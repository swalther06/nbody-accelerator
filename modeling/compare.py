"""Side-by-side comparison of sim_log/hardware.log and sim_log/software.log.

Both are produced by runs that report the same quantities: one "step" is one
Stormer-Verlet timestep (all N bodies advanced by dt) in both, and pairs/step
counts the same N*(N-1) ordered interactions, so the numbers are directly
comparable. Each log ends with a [metrics] key=value block; only that block is
parsed, so the prose above it can change freely.
"""

import os
import sys

LOG_DIR = os.path.join(os.path.dirname(__file__), "..", "sim_log")


def read_metrics(path):
    """Parse the trailing [metrics] key=value block out of a log."""
    if not os.path.exists(path):
        return None
    out, in_block = {}, False
    with open(path) as f:
        for line in f:
            line = line.strip()
            if line == "[metrics]":
                in_block = True
                continue
            if in_block and "=" in line:
                k, v = line.split("=", 1)
                try:
                    out[k] = float(v)
                except ValueError:
                    out[k] = v
    return out or None


def fmt(x, spec=".3f"):
    return format(x, spec) if isinstance(x, (int, float)) else str(x)


def main():
    hw = read_metrics(os.path.join(LOG_DIR, "hardware.log"))
    sw = read_metrics(os.path.join(LOG_DIR, "software.log"))

    missing = [n for n, m in (("hardware", hw), ("software", sw)) if m is None]
    if missing:
        print(f"missing or unparseable: {', '.join(missing)}")
        print("run 'make hw_metrics' and 'make sw_metrics' first (or 'make compare')")
        return 1

    if hw.get("n") != sw.get("n"):
        print(f"WARNING: N differs -- hardware N={fmt(hw.get('n'),'.0f')}, "
              f"software N={fmt(sw.get('n'),'.0f')}. Speedup below is not meaningful.\n")
    if hw.get("pairs_per_step") != sw.get("pairs_per_step"):
        print("WARNING: pairs/step differs between the two runs.\n")

    print("=== hardware vs software ===")
    print(f"orbit={hw.get('orbit')}  N={fmt(hw.get('n'),'.0f')}  "
          f"steps_hw={fmt(hw.get('steps'),'.0f')} steps_sw={fmt(sw.get('steps'),'.0f')}  "
          f"NUMPIPES={fmt(hw.get('numpipes'),'.0f')} NUMLANES={fmt(hw.get('numlanes'),'.0f')}  "
          f"clk={fmt(hw.get('clk_period_ns'))} ns")
    print()

    rows = [
        ("ns/step",        hw.get("ns_per_step"),  sw.get("ns_per_step"),  sw.get("sym_ns_per_step")),
        ("ns/pair",        hw.get("ns_per_pair"),  sw.get("ns_per_pair"),  sw.get("sym_ns_per_pair")),
        ("pairs/step",     hw.get("pairs_per_step"), sw.get("pairs_per_step"), sw.get("sym_pairs_per_step")),
        ("energy drift %", hw.get("drift_pct"),    sw.get("drift_pct"),    sw.get("drift_pct")),
    ]
    print(f"{'metric':<16}{'hardware':>14}{'software full':>16}{'software sym':>15}")
    for name, h, s_full, s_sym in rows:
        print(f"{name:<16}{fmt(h):>14}{fmt(s_full):>16}{fmt(s_sym):>15}")

    print()
    print(f"{'hardware cycles/step':<26}{fmt(hw.get('cycles_per_step'),'.2f')}")
    print(f"{'hardware cycles/pair':<26}{fmt(hw.get('cycles_per_pair'),'.3f')}")
    print(f"{'hardware occupancy %':<26}{fmt(hw.get('occupancy_pct'),'.1f')}"
          f"   ({fmt(hw.get('pairs_per_step'),'.0f')} useful of "
          f"{fmt(hw.get('slots_per_step'),'.0f')} slots streamed)")

    hw_ns, sw_ns, sym_ns = hw.get("ns_per_step"), sw.get("ns_per_step"), sw.get("sym_ns_per_step")
    if hw_ns:
        print()
        print(f"speedup vs software full N^2 : {sw_ns / hw_ns:.2f}x")
        print(f"speedup vs software symmetric: {sym_ns / hw_ns:.2f}x")
        print()
        print("Wall-clock speedup is dominated by process node: the RTL is synthesized")
        print("for a 0.25um library, so the CPU enjoys roughly an order of magnitude of")
        print("clock advantage. cycles/pair is the process-independent comparison.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
