# N-Body Gravity Accelerator

A special-purpose hardware accelerator for N-body gravitational simulation, written in SystemVerilog and validated bit-exactly against a fixed-point C model, which is in turn validated against a float64 physics reference.

The goal is not to beat a GPU on raw throughput. It is to get close **at a fraction of the cost and power** — to win on performance-per-dollar and performance-per-watt, where dedicated silicon beats general-purpose hardware.

**Status:** datapath complete and validated end to end. Float64 golden model, bit-level C model, and RTL all agree; the RTL synthesizes through Design Compiler against four standard-cell libraries. Not yet mapped to an FPGA, and no display pipeline yet.

---

## The guiding principle: homogeneity of operation

Hardware efficiency comes from doing **one uniform kernel** as a deep pipeline and pushing work through it nearly every cycle. Point-mass gravity is one of the most homogeneous workloads in physics: every pair interaction is the identical kernel, with no branches and no neighbor search. This is why astrophysics got dedicated silicon (GRAPE) decades before most other domains.

That one idea drove every decision in this project — which physics, which integrator, the memory layout, the parallelization scheme, where `G` lives, and how the inverse-power unit was built.

Corollaries visible throughout the code:

- **`G = 1`.** Gravitational constant sets the timescale, not the shape of any trajectory. Working in natural units removes a multiplier from the datapath entirely.
- **"Exists" is mass 0.** Padding slots get zero mass, so they exert zero force through the `× m_j` factor. No `if (exists)` branch in the hot path, and `N` pads freely to a multiple of the lane width.
- **Softening `ε²`** makes the self-term exactly zero, so `j == i` needs no special case either.
- **Newton's third law is deliberately not exploited.** Pair reuse halves the arithmetic but wrecks the clean streaming accumulator. Regularity wins.

## The kernel

```
a_i = Σ_{j≠i}  m_j · (r_j - r_i) / ( |r_j - r_i|² + ε² )^(3/2)
```

The `3/2` is not a typo for "squared." Force magnitude goes as `1/r²`, but force is a *vector*: multiplying by the unit direction `(r_j−r_i)/r` adds one more power of `r`, so the denominator is `r³ = (r²)^1.5` while the numerator keeps the un-normalized displacement. The whole expression still scales as `1/r²`.

Integration is **leapfrog kick–drift–kick**, which is symplectic: energy oscillates in a bounded band rather than drifting secularly. Acceleration is evaluated once per step at the *new* positions and carried across the step boundary, with one seed evaluation `a₀` before the loop.

Energy conservation is the project's single most sensitive bug detector and its end-to-end validation gate.

## Architecture

Each timestep is three phases separated by barriers: **drift → force → kick**. Only the force phase is O(N²); the other two are O(N) and negligible. All hardware budget goes into the force phase.

The barrier rule is **read-all-before-write-any**: every acceleration depends on every other body's *current* position, so all accelerations are computed from one frozen position set before any state is updated.

Parallelism lives on two independent, asymmetric axes — asymmetric because the real bottleneck is **memory bandwidth, not multiplier count**:

| Axis | Parameter | Cost |
| --- | --- | --- |
| Targets — compute several target bodies at once, each with its own accumulator | `NUMPIPES` | **Bandwidth-cheap.** One source broadcasts to every pipe: one read feeds them all. Grow this axis. |
| Sources — process several sources per target per cycle through a reduction tree | `NUMLANES` | **Bandwidth-expensive.** Each lane is another read per cycle. Raise only by adding memory banks. |

Total interactions per cycle is `NUMPIPES × NUMLANES`; time scales as `N² / (NUMPIPES × NUMLANES)`. The optimization is target-parallel with source broadcast: large `NUMPIPES`, small `NUMLANES`.

Summation never becomes a flat N-wide adder. It is an **accumulator register** (sum over time, indifferent to `N`) plus a **logarithmic-depth reduction tree** for the parallel lanes (sum over space, sized at design time). `N` appears only as a loop bound.

## Numerics: fixed point, and the hard part

All arithmetic is fixed-point scaled integers — the scale is permanent, not applied at the end.

| Format | Width | Used for |
| --- | --- | --- |
| Q20 | int32 / `word_t` | positions, velocities, masses, accelerations |
| Q40 | int64 / `dword_t` | squared distance (`denom`), products before shift-back |
| Q28 | int64 / `dword_t` | the rsqrt seed/Newton domain |

The rules: adds need matching formats; multiplies add fractional bits (Q20×Q20 = Q40) and must be shifted back **between** chained multiplies or even int64 overflows; and the shift amount is always "however many bits land you in the format the next consumer expects." `denom` is the deliberate exception — its consumer is the rsqrt unit, which wants Q40, so `dx*dx + dy*dy + dz*dz + EPS_SQUARED` is not shifted at all.

**The inverse-power unit.** The kernel needs `(r²+ε²)^-1.5`. The decomposition is `s^-1.5 = rsqrt(s)³` — one inverse square root, then two multiplies. No divider.

`rsqrt` is **LUT seed + Newton–Raphson refinement**, using the division-free step `y' = y·(1.5 − 0.5·a·y²)`. Two subtleties make it work:

- **Normalize, don't flat-index.** A table over the full Q40 dynamic range would need ~2⁴⁰ entries. Instead a priority encoder finds the MSB: its position is the exponent (a shift), and the `LUTBITS` bits below it are the mantissa (the table index). Refining in the normalized domain also guarantees convergence regardless of input magnitude.
- **The `[1,4)` / even-exponent subtlety.** `rsqrt` halves the exponent, so the correction `2^(−k/2)` requires `k` even. Normalizing in 2-bit steps forces that and lands the value in `[1,4)` — two octaves — so the **parity of `k` becomes the high index bit** and the table is `2 × 2^LUTBITS` entries.

A 4-bit LUT with 2 Newton iterations reaches roughly 10⁻⁸ accuracy across the range, both parities.

Multiplication is a **radix-4 Booth multiplier with a 4:2 compressor reduction tree** (`rad4_booth_reduction_multiplier.sv`, `compressor_4_2_tree.sv`), so the multipliers are part of the design rather than inferred.

## Verification: three layers, one dimension at a time

Hardware is not translated line-by-line from software. It is re-conceived through models, each validated against the previous, changing exactly one dimension at a time so that any wrong result has exactly one suspect.

| Layer | Numerical fidelity | Timing fidelity | Authority on |
| --- | --- | --- | --- |
| `modeling/float64_model.py` | float64 truth | none | Is the physics right? |
| `modeling/bitlevel_model.c` | exact hardware bits | none | Is the precision enough? |
| `rtl/` | exact hardware bits | exact cycles | Does the circuit work? |

The value models deliberately do **not** model pipeline concurrency. Pipelining is a timing property, and the HDL simulator models it for free and more accurately than any hand-written cycle-accurate model in C or Python could.

Because both the C model and the RTL operate on fixed-width integers with identical shift and truncation rules, the comparison is **exact integer equality** — not "close," not "within tolerance." Every acceleration, position update, and velocity kick matches the oracle bit for bit, across every orbit configuration.

`modeling/reference_sim.c` is a separate artifact: a plain double-precision O(N²) software implementation used as the *performance* baseline, not the correctness oracle.

## Repository layout

```
modeling/     float64 reference, bit-level C model, LUT and init generators, comparison + rendering
  float64_model.py        Layer A — physics truth
  bitlevel_model.c/.h     Layer B — bit-exact fixed-point twin
  reference_sim.c/.h      double-precision software performance baseline
  gen_lut.c               emits newton_lut.h (C) and the hex ROM init (RTL)
  gen_st_init.c           emits simulation/st_init.mem for the testbench
  orbits.{py,c,h,csv}     shared orbit registry — the same test vectors feed every layer
  compare.py, render.py   side-by-side metrics; trajectory rendering

rtl/          the design
  accelerator.sv                  top level + control FSM
  integrator.sv                   leapfrog kick–drift–kick sequencing
  pos_module.sv / vel_module.sv   drift and kick phases
  accel_module.sv                 force phase, batching over NUMPIPES
  accel_unit.sv                   one pair interaction
  inv_pwr_3d2_unit.sv             (r²+ε²)^-3/2
  rsqrt_newton_step.sv            one Newton iteration
  newton_lut.sv / .hex            seed ROM ($readmemh — this is how BRAM inits for real)
  accumulator_piplined.sv         streaming accumulator
  compressor_4_2{,_tree}.sv       reduction tree
  rad4_booth_reduction_multiplier.sv
  defs.svh                        parameters and signed typedefs

simulation/   testbenches (VCS)
synthesis/    Design Compiler script, multi-library tech presets, min-period search
sim_log/      last hardware/software benchmark runs
```

## Building and running

Requirements: Python ≥3.14 with [`uv`](https://docs.astral.sh/uv/), `gcc`, Synopsys **VCS** (plus DesignWare simulation models — `accelerator.sv` instantiates `DW_div_pipe`), and Synopsys **Design Compiler** for synthesis. `tmux` for the detached run targets.

```bash
make sync                       # install Python dependencies
make help                       # list targets and available orbit configs

make fm    ORBIT=figure8        # Layer A — float64 model
make blm   ORBIT=figure8        # Layer B — bit-level C model
make lut                        # regenerate the Newton seed table
make st_init ORBIT=figure8      # generate simulation/st_init.mem

make sim   ORBIT=figure8        # run accelerator_tb.sv in VCS (VCD=1 to dump waves)
make mult_tb                    # standalone multiplier check
make accel_unit_tb              # standalone pair-kernel check

make compare N=10 STEPS=500 ORBIT=figure8   # RTL vs software, side by side
make compare_only                            # re-print from existing sim_log/

make synth TECH=nangate45       # Design Compiler; reports land in synthesis/report/
make syn_search                 # bisect for the minimum clock period that meets timing
make render                     # render trajectories
```

**Design knobs** are guarded macros overridable from the build, so nothing has to be edited by hand:

| Knob | Where | Meaning |
| --- | --- | --- |
| `N` | `defs.svh` + `definitions.h` | body count. Must match on both sides — `st_init.mem` is written and read with `N` values per field, so a mismatch silently scrambles state rather than failing loudly. `make compare N=...` sets both. |
| `NUMPIPES` | `defs.svh` | target-parallel width |
| `NUMLANES` | `defs.svh` | source-parallel width |
| `FRACBITS` / `SEEDFRAC` | `defs.svh` | Q-format fractional bits |
| `NEWTONITERS` | `defs.svh` | Newton refinement steps — a loop bound in C, **pipeline depth** in RTL |
| `LUTBITS` | `defs.svh` | seed table mantissa bits |
| `TECH` | `make synth` | `lec25` (TSMC 250nm edu), `nangate45` (open, publishable), `freepdk45`, `n16` (foundry PDK — check its terms before publishing numbers) |

**On benchmark numbers:** `PERIOD` defaults to whatever is in `synthesis/clock`. The testbench's clock is arbitrary, so ns/step and ns/pair are meaningless until a real synthesized period is plugged in. Run `make syn_search` first, then `make compare`. The logs checked into `sim_log/` are sample output, not a matched benchmark pair.

## Orbit configurations

Configs are stored as data — a registry of named scenarios, each carrying its own `dt` because the orbits have wildly different timescales. They are functions rather than static tables so that computed velocities stay live: change a mass and the orbital velocity rescales correctly. The same registry feeds all three layers as shared test vectors.

| Config | Notes |
| --- | --- |
| `figure8` | 3-body Chenciner–Montgomery periodic solution. Magic initial conditions; the strongest validation case. |
| `three_chaotic` | 3 equal masses, asymmetric. Drifts and ejects — real chaos, not a bug, and therefore a poor validator. |
| `four_ring` | 4 masses on a cross orbiting the barycenter. Symmetric rings are genuinely unstable; it breaks up after several orbits. Smaller `dt` delays it but doesn't save it. |
| `two_barycentric` | 2 equal masses, opposite momenta, fixed barycenter. |
| `two_circular` | Heavy + light, `v = √(μ/r)`, barycentric split. |
| `two_elliptical` | Heavy + light at perihelion, `v = √(μ/r)·√(1+e)`. `e` is the shape knob. |
| `solar_system` | Sun (M=100) + 8 planets at NASA mass ratios, circular orbits at AU distances, 2D. Extreme mass hierarchy (~10⁶:1 Sun:Mercury); period ratio Neptune/Mercury = 684.9, matching Kepler exactly. Exercises the pipeline with realistic multi-scale dynamics. |

Note that only *equal* masses produce a figure-8; a heavier body destroys it. Scaling all three masses together scales velocity by `√M` and period by `1/√M`.

## Implementation target: FPGA or ASIC

Both, for different purposes — and the repo is already set up that way.

**ASIC synthesis is the measurement instrument.** `make synth` through Design Compiler gives area, timing, and power for a real standard-cell library, which is what actually substantiates a performance-per-watt claim. `make syn_search` bisects for the minimum period that closes timing. Prefer `TECH=nangate45`: its characterization is clean, it ships wire-load models, and the license permits publishing results. The 250nm educational library is fine for relative comparisons but not for credible absolute power numbers; the 16nm foundry kit has terms attached.

**FPGA is the deployment target.** It is the only path to a working device without six figures of NRE, and it is the only path to the on-chip display — an ASIC would need a custom HDMI PHY, which is a full analog design problem on its own. Expect these changes when mapping:

- **Delete the hand-built multiplier.** `rad4_booth_reduction_multiplier.sv` is the right answer in standard cells and the wrong one in an FPGA, where it lowers into LUT fabric and loses to a hard DSP slice on area, timing, and power. Guard it behind a target macro and infer `*` instead.
- **Replace `DW_div_pipe`.** DesignWare is Synopsys-only; substitute a vendor IP core or an open equivalent.
- **The seed ROM already ports.** `newton_lut.sv` initializes from `newton_lut.hex` via `$readmemh`, which is exactly how BRAM initializes on real hardware.
- **The priority encoder will want pipelining.** It is the longest combinational path in the inverse-power unit and free of charge in the C model, which has no timing.
- **Board sizing.** Artix-7 or Spartan-7 for the Vivado flow, ECP5 for the fully open Yosys/nextpnr toolchain. An iCE40 is almost certainly too small once `NUMPIPES` is more than a couple — the 64-bit Newton pipeline alone is substantial. A display framebuffer will want the board's external DRAM.

**Actual tapeout** is a separate decision from ASIC *synthesis*, and the low-cost shuttle landscape has been unsettled since Efabless shut down in 2025 (chipIgnite continued under ChipFoundry; Tiny Tapeout moved toward other foundry partners). Worth revisiting only after the FPGA version exists and the area numbers say something interesting.

## Roadmap

1. **FPGA bring-up.** Timing closure, resource utilization, real I/O. First stage that meets physical constraints — deliberately quarantined here by the layered design.
2. **Display pipeline.** The deliberate deviation from GRAPE: fold display on-chip for a self-contained appliance that needs no host. Requires an HDMI/VGA framebuffer, coordinate-to-pixel projection, and a simple rendering pass (point sprites or trails). Trades a little homogeneity for standalone operation.
3. **Performance characterization.** Run at target clock on real hardware, measure interactions/second, and compare against GPU baselines on perf/$ and perf/W. Climb the N-ladder: small configs for correctness, then N=1000+ for throughput.
4. **Barnes–Hut (future).** Past N ≈ 10⁴ the O(N²) kernel hits a wall. Tree traversal gets to O(N log N) but reintroduces branching and irregular memory access — exactly the heterogeneity this design avoids. An architectural decision, not a near-term task.

## Verification discipline (carried forward)

- Every RTL block gets a testbench that diffs bit-for-bit against the corresponding C function. Integer arithmetic means exact equality, not "close."
- Build the instrument before the thing it measures. Every silent bug in this project's history — the energy climb, twice — was found by **measurement**: the energy check and the rsqrt sweep. None was found by reading code. Floating-point error is ~1e-15 and random; real bugs are large and systematic.
- Pipelining, retiming, and critical-path concerns live in RTL and are modeled cycle-accurately by the simulator. They never enter the value models.
- SystemVerilog computes a product in the operand width and truncates *before* the shift, so `(y*y) >> SEEDFRAC` on 64-bit operands silently loses the high bits. Every product goes to a wider (`qword_t`) temporary first. Types are signed — positions go negative, and `>>>` on a signed type sign-extends, which the negative-exponent shifts require.

## North star

This project independently re-derived the **GRAPE** architecture (GRAvity PipE, University of Tokyo): a pure force-evaluation coprocessor that won Gordon Bell prizes by doing one uniform kernel and exiling everything heterogeneous — integration, tree traversal, I/O — to a host. GRAPE-on-FPGA already exists in the PROGRAPE line, so a GRAPE-style force engine on reconfigurable hardware is a validated path. The deviation here is folding the display on-chip, trading a little homogeneity for needing no host computer at all.