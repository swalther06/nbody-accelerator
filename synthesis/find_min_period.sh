#!/usr/bin/env bash
# Damped secant search for the minimum clock period (ns) that still meets
# setup timing (i.e. no VIOLATED slack among "Path Type: max" paths).
#
#
# Path Type: min (hold) violations are deliberately ignored
#
# Usage: synthesis/find_min_period.sh [HIGH] [PRECISION] [DAMPING] [MAX_ITERS]
#   HIGH       starting period (ns) that is assumed to MEET timing. default: 100
#   PRECISION  stop once |slack| <= this, in ns. default: 0.5
#   DAMPING    fraction of slack to subtract each step (0,1]. default: 0.9
#   MAX_ITERS  safety cap on iterations. default: 8
set -uo pipefail

cd "$(dirname "$0")/.."   # repo root

HIGH=${1:-78}
PRECISION=${2:-0.5}
DAMPING=${3:-1.0}
MAX_ITERS=${4:-8}

CLOCK_FILE=synthesis/clock
TIMING_RPT=synthesis/report/accelerator_timing.rpt
LOG=synthesis/logs/find_min_period.log

mkdir -p "$(dirname "$LOG")"
: > "$LOG"

SLACK=""   # set by measure_slack -- bash functions can't return floats

# Runs synthesis at the given period, sets $SLACK to the worst MAX-path slack.
# Returns 0 if MET (slack >= 0), 1 if VIOLATED, 2 on error (run/parse failure).
measure_slack() {
    local period=$1
    echo "$period" > "$CLOCK_FILE"
    echo "=== trying period=${period}ns ===" | tee -a "$LOG"
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

echo "sanity check: HIGH=${HIGH}ns must MEET timing" | tee -a "$LOG"
measure_slack "$HIGH"
rc=$?
if [[ $rc -eq 2 ]]; then
    exit 2
elif [[ $rc -ne 0 ]]; then
    echo "HIGH=${HIGH}ns does not meet timing -- raise HIGH and retry" | tee -a "$LOG"
    exit 1
fi

period=$HIGH
best_met=$period

for ((i = 1; i <= MAX_ITERS; i++)); do
    abs_slack=$(awk -v s="$SLACK" 'BEGIN { print (s < 0) ? -s : s }')
    if awk -v a="$abs_slack" -v p="$PRECISION" 'BEGIN { exit !(a <= p) }'; then
        echo "converged: |slack|=${abs_slack}ns <= precision=${PRECISION}ns" | tee -a "$LOG"
        break
    fi

    next=$(awk -v p="$period" -v s="$SLACK" -v d="$DAMPING" 'BEGIN { printf "%.3f", p - d*s }')
    if awk -v n="$next" 'BEGIN { exit !(n <= 0) }'; then
        echo "  ERROR: next candidate period ${next}ns is non-positive, aborting" | tee -a "$LOG"
        break
    fi

    period=$next
    measure_slack "$period"
    rc=$?
    if [[ $rc -eq 2 ]]; then
        echo "aborting search due to synthesis/report error" | tee -a "$LOG"
        break
    elif [[ $rc -eq 0 ]]; then
        echo "  MET" | tee -a "$LOG"
        best_met=$period
    else
        echo "  VIOLATED" | tee -a "$LOG"
    fi
done

echo "$best_met" > "$CLOCK_FILE"
echo "=== best period found: ${best_met}ns -- regenerating final reports ===" | tee -a "$LOG"
make synth >> "$LOG" 2>&1
echo "done. see $LOG and synthesis/report/" | tee -a "$LOG"
