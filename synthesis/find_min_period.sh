#!/usr/bin/env bash
# Binary search for the minimum clock period (ns) that still meets setup
# timing (i.e. no VIOLATED slack among "Path Type: max" paths).
#
# Why bisection rather than a slack-driven secant step: Design Compiler stops
# optimizing as soon as the constraint is satisfied, so a run that MEETS reports
# slack ~= 0.00 regardless of how much headroom the netlist really has. A step of
# (period - damping*slack) therefore lands back on the same period and stalls,
# and an "|slack| <= precision" convergence test declares victory at the very
# first MET point without ever probing lower. Slack only carries information
# when it is NEGATIVE; on the MET side the single trustworthy bit is
# MET vs VIOLATED, which is what bisection consumes.
#
# Negative slack IS used, but only to place the initial bracket: if a probe at
# period P misses by slack s < 0, no period below P-s can work either, so P-s is
# a sound lower bound to start bisecting from instead of blindly shrinking.
#
# Path Type: min (hold) violations are deliberately ignored.
#
# Usage: synthesis/find_min_period.sh [HIGH] [PRECISION] [LOW] [MAX_ITERS]
#   HIGH       starting period (ns) assumed to MEET timing. default: 2.5
#   PRECISION  stop once (HIGH-LOW) <= this, in ns. default: 0.05
#   LOW        period (ns) known to VIOLATE. default: auto-discovered by
#              shrinking down from HIGH until a run violates
#   MAX_ITERS  safety cap on total synthesis runs. default: 12
set -uo pipefail

cd "$(dirname "$0")/.."   # repo root

HIGH=${1:-2.5}
PRECISION=${2:-0.05}
LOW=${3:-}
MAX_ITERS=${4:-12}

CLOCK_FILE=synthesis/clock
TIMING_RPT=synthesis/report/accelerator_timing.rpt
LOG=synthesis/logs/find_min_period.log

SHRINK=0.75    # bracket-discovery step: probe*SHRINK until something violates
FLOOR=0.10     # never probe below this period (ns); guards a runaway search

mkdir -p "$(dirname "$LOG")"
: > "$LOG"

SLACK=""       # set by measure_slack -- bash functions can't return floats
RUNS=0         # synthesis runs consumed, capped by MAX_ITERS

# float helpers (bash has no float arithmetic). fmt EVALUATES an expression, so
# it interpolates into the awk program body -- passing it via -v would assign
# the string "2.5 * 0.75" and awk would silently read just its numeric prefix.
fmt()  { awk "BEGIN { printf \"%.3f\", ($1) }"; }
flt()  { awk -v a="$1" -v b="$2" 'BEGIN { exit !(a+0 <  b+0) }'; }   # a <  b
fle()  { awk -v a="$1" -v b="$2" 'BEGIN { exit !(a+0 <= b+0) }'; }   # a <= b

# Runs synthesis at the given period, sets $SLACK to the worst MAX-path slack.
# Returns 0 if MET (slack >= 0), 1 if VIOLATED, 2 on error (run/parse failure).
measure_slack() {
    local period=$1
    RUNS=$((RUNS + 1))
    echo "$period" > "$CLOCK_FILE"
    echo "=== run ${RUNS}/${MAX_ITERS}: trying period=${period}ns ===" | tee -a "$LOG"

    # FMP_FAKE_MIN models DC for a logic-only test of this search: it reports
    # the true violation when short, and pins slack at exactly 0 when met --
    # the saturation that breaks a secant step. Unset in real runs.
    if [[ -n "${FMP_FAKE_MIN:-}" ]]; then
        SLACK=$(awk -v p="$period" -v m="$FMP_FAKE_MIN" \
                    'BEGIN { s = p - m; printf "%.4f", (s > 0 ? 0 : s) }')
        echo "  worst max-path slack: ${SLACK} ns (simulated)" | tee -a "$LOG"
        awk -v s="$SLACK" 'BEGIN { exit (s+0 < 0) ? 1 : 0 }'
        return $?
    fi

    if ! make synth >> "$LOG" 2>&1; then
        echo "  ERROR: synthesis run failed, see $LOG" | tee -a "$LOG"
        return 2
    fi
    if [[ ! -f "$TIMING_RPT" ]]; then
        echo "  ERROR: $TIMING_RPT not found" | tee -a "$LOG"
        return 2
    fi

    local worst
    worst=$(awk '
        /Path Type: max/ { in_max=1; next }
        /Path Type: min/ { in_max=0; next }
        in_max && /slack \(/ {
            val = $NF
            if (min == "" || val+0 < min) min = val+0
        }
        END { print (min == "" ? "NA" : min) }
    ' "$TIMING_RPT")

    echo "  worst max-path slack: ${worst} ns" | tee -a "$LOG"
    if [[ "$worst" == "NA" ]]; then
        echo "  ERROR: no max-path slack found in report" | tee -a "$LOG"
        return 2
    fi

    SLACK=$worst
    awk -v s="$worst" 'BEGIN { exit (s+0 < 0) ? 1 : 0 }'
}

# --- establish the upper (MET) end of the bracket ---------------------------
echo "sanity check: HIGH=${HIGH}ns must MEET timing" | tee -a "$LOG"
measure_slack "$HIGH"
rc=$?
if [[ $rc -eq 2 ]]; then
    exit 2
elif [[ $rc -ne 0 ]]; then
    echo "HIGH=${HIGH}ns does not meet timing -- raise HIGH and retry" | tee -a "$LOG"
    exit 1
fi
best_met=$HIGH

# --- establish the lower (VIOLATED) end -------------------------------------
# Caller-supplied LOW is trusted as violating and not spent a run on.
if [[ -z "$LOW" ]]; then
    probe=$HIGH
    while true; do
        if [[ $RUNS -ge $MAX_ITERS ]]; then
            echo "hit MAX_ITERS=${MAX_ITERS} before bracketing a violation" | tee -a "$LOG"
            break
        fi
        probe=$(fmt "$probe * $SHRINK")
        if fle "$probe" "$FLOOR"; then
            echo "reached FLOOR=${FLOOR}ns without violating; design is faster than this search resolves" | tee -a "$LOG"
            best_met=$probe
            break
        fi

        measure_slack "$probe"
        rc=$?
        if [[ $rc -eq 2 ]]; then
            echo "aborting search due to synthesis/report error" | tee -a "$LOG"
            break
        elif [[ $rc -eq 0 ]]; then
            echo "  MET -- new best, keep descending" | tee -a "$LOG"
            best_met=$probe
            HIGH=$probe
        else
            # slack is real on this side: nothing below probe-slack can pass
            LOW=$(fmt "$probe - $SLACK")
            if fle "$HIGH" "$LOW"; then LOW=$probe; fi   # keep LOW < HIGH
            echo "  VIOLATED -- bracket is [${LOW}, ${HIGH}]" | tee -a "$LOG"
            break
        fi
    done
fi

# --- bisect -----------------------------------------------------------------
if [[ -n "$LOW" ]]; then
    while [[ $RUNS -lt $MAX_ITERS ]]; do
        width=$(fmt "$HIGH - $LOW")
        if fle "$width" "$PRECISION"; then
            echo "converged: bracket width ${width}ns <= precision=${PRECISION}ns" | tee -a "$LOG"
            break
        fi

        mid=$(fmt "($HIGH + $LOW) / 2")
        # guard against the midpoint rounding onto an endpoint
        if fle "$mid" "$LOW" || fle "$HIGH" "$mid"; then
            echo "midpoint collapsed onto a bracket end; stopping" | tee -a "$LOG"
            break
        fi

        measure_slack "$mid"
        rc=$?
        if [[ $rc -eq 2 ]]; then
            echo "aborting search due to synthesis/report error" | tee -a "$LOG"
            break
        elif [[ $rc -eq 0 ]]; then
            echo "  MET -- searching lower" | tee -a "$LOG"
            best_met=$mid
            HIGH=$mid
        else
            echo "  VIOLATED -- searching higher" | tee -a "$LOG"
            LOW=$mid
        fi
    done
    if [[ $RUNS -ge $MAX_ITERS ]]; then
        echo "stopped at MAX_ITERS=${MAX_ITERS} runs" | tee -a "$LOG"
    fi
fi

echo "$best_met" > "$CLOCK_FILE"
echo "=== best period found: ${best_met}ns (in ${RUNS} synthesis runs) ===" | tee -a "$LOG"
echo "done. see $LOG -- synthesis/report/ reflects whichever period was tried last, not necessarily ${best_met}ns; rerun 'make synth' if you need reports for the best period specifically" | tee -a "$LOG"
