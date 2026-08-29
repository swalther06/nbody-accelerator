# N-Body Gravity Accelerator

A special-purpose hardware accelerator for N-body gravitational simulation, written in SystemVerilog and validated bit-exactly against a fixed-point C model, in turn validated against a float64 physics reference. Conservation of energy is the ground truth for correctness.

The goal is not to beat a GPU on raw throughput. It is to get close **at a fraction of the cost and power** - to win on performance-per-dollar and performance-per-watt, where dedicated silicon beats general-purpose hardware. 

**Status:** datapath complete and validated end to end. Float64 golden model, bit-level C model, and RTL all agree; the RTL synthesizes through Design Compiler against four standard-cell libraries. This project will be run on FPGA for physical, tangible results, and implemented on an ASIC to maximize performance.

ASIC: Physical implementation flow in progress, using mflowgen. Parameter configurations will be explored once a full run has been completed for 10 pipes and 1 lane (explained later)

FPGA: No progress yet

---

## Driving principle: reptitive arithemetic operations

Hardware efficiency comes from doing **one uniform kernel** as a deep pipeline and pushing work through it nearly every cycle. Point-mass gravity is one of the most homogeneous workloads in physics, with every particle pair undergoing the same acceleration calculation.

This idea drove every decision in this project: which physics, which integrator, the memory layout, the parallelization scheme, where `G` lives, and how the inverse-power unit was built.

Some hardware design-choice optmizations:

- **`G = 1`.** Gravitational constant scales the result, but doesn't change any trajectories. To avoid an additional multiplication, it is excluded from each particle's acceleration calculation. 
- **"Exists" is mass = 0.** Padding (extra, unreal particles) slots get zero mass, so they exert zero force through the `× m_j` factor.
- **Softening `ε²`** makes the self-term exactly zero with a nonzero denominator, so `j == i` needs no special case either.
- **No use of Newton's 3rd Law** Pair reuse halves the arithmetic but wrecks the clean streaming accumulator. Can be explored for optimization purposes for large workloads, but removing this makes the hardware cleaner.

## The kernel

```
a_i = Σ_{j≠i}  m_j · (r_j - r_i) / ( |r_j - r_i|² + ε² )^(3/2)
```

Integration is **leapfrog kick–drift–kick**, chosen because energy oscillates in a bounded band rather than drifting secularly. Acceleration is evaluated once per step at the new positions and carried across the step boundary, with one seed evaluation `a₀` before the loop.

Energy conservation is the project's single most sensitive bug detector and its end-to-end validation gate, as mentioned before.

## Architecture

Each timestep is three phases separated by barriers: **drift → force → kick**. Only the force phase is O(N²); the other two are O(N) and negligible. All hardware budget goes into the force phase.

The barrier rule is **read-all-before-write-any**: every acceleration depends on every other body's *current* position, so all accelerations are computed from one frozen position set before any state is updated.

Parallelism lives on two independent, asymmetric axes:

| Parameter | Axis |
| --- | --- |
| `NUMPIPES` | Parallelism in the state calculation of individual particles |
| `NUMLANES` | Inter-pipe acceleration calculation parallelization |

Total interactions per cycle is `NUMPIPES × NUMLANES`; time scales as `N² / (NUMPIPES × NUMLANES)`. 

The optimization is large `NUMPIPES`, small `NUMLANES` - increasing `NUMPIPES` provides higher throughput per area than increasing `NUMLANES`, and there is no strict upper bound to increasing these parameters. Under area constraints, the number of pipes is the first knob to tune, then lanes to fill any unused area to achieve higher throughput.

Summation never becomes a flat N-wide adder. It is an **accumulator register** (sum over time, indifferent to `N`) plus a **logarithmic-depth reduction tree** for the parallel lanes (sum over space, sized at design time). `N` appears only as a loop bound.

## Numerics: fixed point, and the hard part

All arithmetic is **fixed-point** scaled integers, applied throughout the entire accelerator. 

| Format | Width | Used for |
| --- | --- | --- |
| Q20 | int32 / `word_t` | positions, velocities, masses, accelerations |
| Q40 | int64 / `dword_t` | squared distance (`denom`), products before shift-back |
| Q28 | int64 / `dword_t` | the rsqrt seed/Newton domain |

The rules: adds need matching formats; multiplies add fractional bits (Q20×Q20 = Q40) and must be shifted back **between** chained multiplies or even int64 overflows; and the shift amount is always "however many bits land you in the format the next consumer expects."

**The inverse-power unit.** The kernel needs `(r²+ε²)^-1.5`. The decomposition is `s^-1.5 = rsqrt(s)³` - one inverse square root, then two multiplies. No divider.

`rsqrt` is **LUT seed + Newton–Raphson refinement**, using the division-free step `y' = y·(1.5 − 0.5·a·y²)`. Two subtleties make it work:

- **Normalize, then index.** A table over the full Q40 dynamic range would need ~2⁴⁰ entries. Instead a priority encoder finds the MSB: its position is the exponent (a shift), and the `LUTBITS` bits below it are the mantissa (the table index). Refining in the normalized domain also guarantees convergence regardless of input magnitude.
- **The `[1,4)` / even-exponent subtlety.** `rsqrt` halves the exponent, so the correction `2^(−k/2)` requires `k` even. Normalizing in 2-bit steps forces that and lands the value in `[1,4)` so the **parity of `k` becomes the high index bit** and the table is `2 × 2^LUTBITS` entries.

A 4-bit LUT with 2 Newton iterations reaches roughly 10⁻⁸ accuracy across the range, both parities, determined experimentally by sweeping over a range of values and comparing their real vs. calculated square roots.

Multiplication is a **radix-4 Booth multiplier with a 4:2 compressor reduction tree, with 2 compressors per stage** (`rad4_booth_reduction_multiplier.sv`, `compressor_4_2_tree.sv`), so the multipliers are part of the design rather than inferred. This architecture was chosen to minimize the number of pipeline stages per multiplication while keeping it parameterizable. Additionally, there is little slack per pipline stage of this configuration.

## Verification: three layers, one dimension at a time

Hardware is not translated line-by-line from software. It is re-conceived through models, each validated against the previous, changing exactly one dimension at a time so that any wrong result has exactly one suspect.

| Layer | Numerical fidelity | Timing fidelity | Authority on |
| --- | --- | --- | --- |
| `modeling/float64_model.py` | float64 truth | none | Is the physics right? |
| `modeling/bitlevel_model.c` | exact hardware bits | none | Is the precision enough? |
| `rtl/` | exact hardware bits | exact cycles | Does the circuit work? |

Because both the C model and the RTL operate on fixed-width integers with identical shift and truncation rules, the comparison is **exact integer equality** Every acceleration, position update, and velocity kick matches the oracle bit for bit, across every orbit configuration.

`modeling/reference_sim.c` is a separate artifact: a plain double-precision O(N²) software implementation used as the *performance* baseline, not the correctness oracle. In this project, it is treated as an "optimal" software implementation of the n-body problem (written for speed, compiled with -O3).

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
  pos_module.sv / vel_module.sv   drift and kick phases
  accel_module.sv                 force phase, batching over NUMLANES
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

More orbits will likely be added in the future for larger workloads and cool configurations.

## Roadmap

1. **FPGA bring-up.** Timing closure, resource utilization, real I/O. First stage that meets physical constraints — deliberately quarantined here by the layered design.
2. **Display pipeline.** The deliberate deviation from GRAPE: fold display on-chip for a self-contained appliance that needs no host. Requires an HDMI/VGA framebuffer, coordinate-to-pixel projection, and a simple rendering pass (point sprites or trails). Trades a little homogeneity for standalone operation.
3. **Performance characterization.** Run at target clock on real hardware, measure interactions/second, and compare against GPU baselines on perf/$ and perf/W. Climb the N-ladder: small configs for correctness, then N=1000+ for throughput.
4. **Barnes–Hut (future).** Past N ≈ 10⁴ the O(N²) kernel hits a wall. Tree traversal gets to O(N log N) but reintroduces branching and irregular memory access - exactly the heterogeneity this design avoids. An architectural decision, not a near-term task.

## Verification discipline (carried forward)

- Every RTL block gets a testbench that diffs bit-for-bit against the corresponding C function. Integer arithmetic means exact equality, not "close."
- Build the instrument before the thing it measures. Every silent bug in this project's history — the energy climb, twice — was found by **measurement**: the energy check and the rsqrt sweep. None was found by reading code. Floating-point error is ~1e-15 and random; real bugs are large and systematic.
- Pipelining, retiming, and critical-path concerns live in RTL and are modeled cycle-accurately by the simulator. They never enter the value models.
- SystemVerilog computes a product in the operand width and truncates *before* the shift, so `(y*y) >> SEEDFRAC` on 64-bit operands silently loses the high bits. Every product goes to a wider (`qword_t`) temporary first. Types are signed — positions go negative, and `>>>` on a signed type sign-extends, which the negative-exponent shifts require.

## North star

This project independently re-derived the **GRAPE** architecture (GRAvity PipE, University of Tokyo): a pure force-evaluation coprocessor that won Gordon Bell prizes by doing one uniform kernel and exiling everything heterogeneous — integration, tree traversal, I/O — to a host. GRAPE-on-FPGA already exists in the PROGRAPE line, so a GRAPE-style force engine on reconfigurable hardware is a validated path. The deviation here is folding the display on-chip, trading a little homogeneity for needing no host computer at all.