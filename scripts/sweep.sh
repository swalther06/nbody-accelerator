#!/usr/bin/env bash
# Sweep N x NUMPIPES x NUMLANES and report speedup, area, and timing closure
# for every configuration.
#
# The clock is fixed at 400 MHz (2.5 ns), so period is NOT searched -- each
# config is synthesized against that constraint and reported as MET or VIOLATED.
# A config that violates is not viable regardless of how good its cycle count
# looks, so the timing column gates the rest of the row.
#
# Cost warning: simulation is ~30-60s per config but synthesis is ~10min, so
# synthesis dominates. SYNTH=0 gives a fast cycles-and-speedup-only sweep.
#
# Usage (all optional, shown with defaults):
#   N_LIST="10 20" PIPES_LIST="1 5 10" LANES_LIST="1 4" \
#   STEPS=100 PERIOD=2.5 ORBIT=figure8 SYNTH=1 scripts/sweep.sh
set -uo pipefail

cd "$(dirname "$0")/.."   # repo root

N_LIST=${N_LIST:-"10 20"}
PIPES_LIST=${PIPES_LIST:-"1 5 10"}
LANES_LIST=${LANES_LIST:-"1 4"}
STEPS=${STEPS:-100}
PERIOD=${PERIOD:-2.5}          # 400 MHz -- fixed, not searched
ORBIT=${ORBIT:-figure8}
SYNTH=${SYNTH:-1}

OUT=sweep_results
CSV=$OUT/sweep.csv
LOG=$OUT/sweep.log
mkdir -p "$OUT"
: > "$LOG"

CLOCK_FILE=synthesis/clock
CLOCK_BAK=$OUT/.clock.bak
[[ -f $CLOCK_FILE ]] && cp "$CLOCK_FILE" "$CLOCK_BAK"

restore_clock() {
    [[ -f $CLOCK_BAK ]] && cp "$CLOCK_BAK" "$CLOCK_FILE"
}
trap restore_clock EXIT

echo "n,pipes,lanes,accel_units,cycles_per_step,cycles_per_pair,occupancy_pct,hw_ns_per_step,sw_ns_per_step,sw_sym_ns_per_step,speedup_full,speedup_sym,area,slack_ns,timing" > "$CSV"

# pull "key=value" out of a [metrics] block
metric() { grep -E "^$2=" "$1" 2>/dev/null | tail -1 | cut -d= -f2; }

say() { echo "$@" | tee -a "$LOG"; }

say "sweep: N=[$N_LIST] PIPES=[$PIPES_LIST] LANES=[$LANES_LIST]"
say "steps=$STEPS  period=${PERIOD}ns (400 MHz)  orbit=$ORBIT  synth=$SYNTH"
say ""

total=0; done_n=0
for n in $N_LIST; do for p in $PIPES_LIST; do for l in $LANES_LIST; do
    [[ $p -gt $n ]] && continue
    total=$((total + 1))
done; done; done
say "$total configurations to run"
say ""

for n in $N_LIST; do
  for p in $PIPES_LIST; do
    for l in $LANES_LIST; do

      # NUMPIPES beyond N only pads the body count and wastes work (N_PAD1
      # rounds up to a multiple of NUMPIPES), so those points are skipped.
      if [[ $p -gt $n ]]; then
          say "skip N=$n pipes=$p lanes=$l  (pipes > N just pads the body count)"
          continue
      fi

      done_n=$((done_n + 1))
      tag="N${n}_P${p}_L${l}"
      say "=== [$done_n/$total] N=$n NUMPIPES=$p NUMLANES=$l ==="

      # ---- software baseline ----
      if ! make sw_metrics N="$n" STEPS="$STEPS" ORBIT="$ORBIT" >> "$LOG" 2>&1; then
          say "  ERROR: software run failed, see $LOG"; continue
      fi

      # ---- RTL simulation ----
      if ! make hw_metrics N="$n" PIPES="$p" LANES="$l" STEPS="$STEPS" \
                           ORBIT="$ORBIT" PERIOD="$PERIOD" >> "$LOG" 2>&1; then
          say "  ERROR: RTL run failed, see $LOG"; continue
      fi

      cp sim_log/hardware.log "$OUT/hardware_$tag.log" 2>/dev/null
      cp sim_log/software.log "$OUT/software_$tag.log" 2>/dev/null

      cyc=$(metric sim_log/hardware.log cycles_per_step)
      cpp=$(metric sim_log/hardware.log cycles_per_pair)
      occ=$(metric sim_log/hardware.log occupancy_pct)
      hw_ns=$(metric sim_log/hardware.log ns_per_step)
      sw_ns=$(metric sim_log/software.log ns_per_step)
      sw_sym=$(metric sim_log/software.log sym_ns_per_step)

      sp_full=$(awk -v a="${sw_ns:-0}" -v b="${hw_ns:-0}" 'BEGIN{printf "%.3f", (b>0)?a/b:0}')
      sp_sym=$(awk  -v a="${sw_sym:-0}" -v b="${hw_ns:-0}" 'BEGIN{printf "%.3f", (b>0)?a/b:0}')

      # ---- synthesis: area + timing closure at the fixed 400 MHz ----
      area="NA"; slack="NA"; timing="skipped"
      if [[ "$SYNTH" != "0" ]]; then
          echo "$PERIOD" > "$CLOCK_FILE"
          if make synth N="$n" PIPES="$p" LANES="$l" >> "$LOG" 2>&1; then
              area=$(grep -E "^Total cell area" synthesis/report/accelerator_area.rpt 2>/dev/null \
                     | tail -1 | awk '{print $NF}')
              slack=$(awk '
                  /Path Type: max/ { in_max=1; next }
                  /Path Type: min/ { in_max=0; next }
                  in_max && /slack \(/ { v=$NF; if (m=="" || v+0 < m) m=v+0 }
                  END { print (m=="" ? "NA" : m) }
              ' synthesis/report/accelerator_timing.rpt 2>/dev/null)
              timing=$(awk -v s="${slack:-0}" 'BEGIN{print (s+0 < 0) ? "VIOLATED" : "MET"}')
              cp synthesis/report/accelerator_area.rpt   "$OUT/area_$tag.rpt"   2>/dev/null
              cp synthesis/report/accelerator_timing.rpt "$OUT/timing_$tag.rpt" 2>/dev/null
          else
              say "  ERROR: synthesis failed, see $LOG"
              timing="ERROR"
          fi
      fi

      echo "$n,$p,$l,$((p*l)),${cyc:-NA},${cpp:-NA},${occ:-NA},${hw_ns:-NA},${sw_ns:-NA},${sw_sym:-NA},$sp_full,$sp_sym,${area:-NA},${slack:-NA},$timing" >> "$CSV"

      say "  cycles/step=${cyc:-NA}  cycles/pair=${cpp:-NA}  speedup=${sp_full}x  area=${area:-NA}  timing=$timing"
      say ""
    done
  done
done

restore_clock

say "=== sweep complete: $CSV ==="
say ""
if command -v column >/dev/null 2>&1; then
    column -s, -t "$CSV" | tee -a "$LOG"
else
    cat "$CSV" | tee -a "$LOG"
fi
