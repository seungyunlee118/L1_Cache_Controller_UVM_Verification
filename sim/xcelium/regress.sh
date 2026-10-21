#!/usr/bin/env bash
# ============================================================================
#  L1 cache UVM regression - Cadence Xcelium
#
#    ./regress.sh                         # 11 tests x 4 seeds, 4 runs at a time
#    ./regress.sh -s "1 2 3 4 5"          # other seeds
#    ./regress.sh -t "l1_cache_be_test"   # a subset of tests
#    ./regress.sh -x C                    # X-propagation build (-xprop C or F)
#    ./regress.sh -k -j 1                 # stop at the first failing run
#
#  Builds once into <out>/xcelium.d, then runs every test/seed from that
#  snapshot. A run PASSES only if
#    * it reached the scoreboard report (the test really finished),
#    * UVM_ERROR and UVM_FATAL are both 0 (SVA failures report through
#      uvm_report_error, so they are counted here too), and
#    * the simulator printed no *E / *F message other than the known IMPDLL
#  (the rule lives in judge.sh, shared with `make run`).
#
#  Results: <out>/results.txt, one line per run:
#    <test> <seed> PASS|FAIL <reason> <funccov> <fsmcov> <wall_s>
# ============================================================================
set -u
cd "$(dirname "$0")"
source ./xcelium_env.sh || exit 1
source ./judge.sh

ALL_TESTS="l1_cache_smoke_test l1_cache_random_test l1_cache_thrash_test
           l1_cache_eviction_test l1_cache_b2b_test l1_cache_line_test
           l1_cache_be_test l1_cache_stress_test l1_cache_passive_test
           l1_cache_reset_test l1_cache_reset_async_test"

TESTS=$ALL_TESTS
SEEDS="1 7 42 999"
XPROP=""
FILELIST="files.f"
OUT="regress"
JOBS=4
STOP_ON_FAIL=0
WALL_LIMIT=600        # seconds per run - backstop if the UVM timeout never fires
QUIET=0

usage() { sed -n '3,20p' "$0"; exit 1; }

while getopts "t:s:x:f:o:j:kqh" opt; do
    case $opt in
        t) TESTS=$OPTARG ;;
        s) SEEDS=$OPTARG ;;
        x) XPROP=$OPTARG ;;
        f) FILELIST=$OPTARG ;;
        o) OUT=$OPTARG ;;
        j) JOBS=$OPTARG ;;
        k) STOP_ON_FAIL=1 ;;
        q) QUIET=1 ;;
        *) usage ;;
    esac
done

say() { [ "$QUIET" -eq 1 ] || echo "$@"; }

if [ "$STOP_ON_FAIL" -eq 1 ] && [ "$JOBS" -gt 1 ]; then
    say "-k stops at the first failing run, so runs go one at a time (-j 1)"
    JOBS=1
fi

# Every xrun writes xrun.history/xrun.key/... into its working directory, so
# the build runs inside $OUT and each simulation in its own $OUT/runs/<run>/.
# Parallel runs (and parallel mutate.py regressions) then never share a file.
# Paths are made absolute first; files.f is read with -F so its relative paths
# resolve against the filelist's own directory.
HERE=$(pwd)
FILELIST="$(cd "$(dirname "$FILELIST")" && pwd)/$(basename "$FILELIST")"
mkdir -p "$OUT"
OUT=$(cd "$OUT" && pwd)
rm -rf "$OUT/logs" "$OUT/runs" "$OUT/results.txt"
mkdir -p "$OUT/logs" "$OUT/runs"

# ---- build -----------------------------------------------------------------
XPROP_OPT=""
[ -n "$XPROP" ] && XPROP_OPT="-xprop $XPROP"

say "==================== BUILD ($(basename "$FILELIST")${XPROP:+, xprop $XPROP}) ===================="
if ! (cd "$OUT" && xrun -F "$HERE/xrun.args" -F "$FILELIST" $XPROP_OPT \
          -xmlibdirname xcelium.d -elaborate -l build.log >/dev/null 2>&1); then
    say "BUILD FAILED - see $OUT/build.log"
    grep -E "\*[EF]," "$OUT/build.log" | head -5
    echo "BUILD_FAILED" > "$OUT/results.txt"
    exit 2
fi

# ---- one run ---------------------------------------------------------------
run_one() {
    local t=$1 s=$2 log="$OUT/logs/${1}_${2}.log" dir="$OUT/runs/${1}_${2}" rc t0 verdict fc fsm
    t0=$(date +%s)
    mkdir -p "$dir"
    (cd "$dir" && timeout "$WALL_LIMIT" xrun -F "$HERE/xrun_run.args" -R \
        -xmlibdirname "$OUT/xcelium.d" -covworkdir cov_work -covtest "${t}_${s}" \
        -svseed "$s" +UVM_TESTNAME="$t" -l "$log" >/dev/null 2>&1)
    rc=$?
    verdict=$(judge "$log" "$rc")
    fc=$(grep -oE "FUNCCOV=[0-9.]+" "$log" | head -1 | cut -d= -f2)
    fsm=$(grep -oE "cache_fsm covergroup: [0-9.]+" "$log" | head -1 | awk '{print $3}')
    echo "$t $s $verdict ${fc:--} ${fsm:--} $(( $(date +%s) - t0 ))" > "$OUT/logs/${t}_${s}.res"
}

# ---- run everything --------------------------------------------------------
say "==================== REGRESSION ===================="
failed=0
for t in $TESTS; do
    for s in $SEEDS; do
        if [ "$JOBS" -le 1 ]; then
            run_one "$t" "$s"
            if [ "$STOP_ON_FAIL" -eq 1 ] && grep -q " FAIL " "$OUT/logs/${t}_${s}.res"; then
                break 2
            fi
        else
            while [ "$(jobs -rp | wc -l)" -ge "$JOBS" ]; do wait -n; done
            run_one "$t" "$s" &
        fi
    done
done
wait

# Collect in a stable order.
for t in $TESTS; do
    for s in $SEEDS; do
        [ -f "$OUT/logs/${t}_${s}.res" ] && cat "$OUT/logs/${t}_${s}.res" >> "$OUT/results.txt"
    done
done

if [ "$QUIET" -eq 0 ]; then
    printf "  %-4s  %-28s %-5s %-6s %-8s %-7s %s\n" "" "test" "seed" "time" "funccov" "fsmcov" "reason"
    while read -r t s v r fc fsm w; do
        printf "  %-4s  %-28s %-5s %4ss  %7s%% %6s%%  %s\n" \
            "$( [ "$v" = PASS ] && echo pass || echo FAIL)" "$t" "$s" "$w" "$fc" "$fsm" \
            "$( [ "$r" = - ] && echo "" || echo "$r")"
    done < "$OUT/results.txt"
fi

total=$(wc -l < "$OUT/results.txt")
failed=$(grep -c " FAIL " "$OUT/results.txt")

say "===================================================="
say "  runs: $total   pass: $((total - failed))   fail: $failed"

# Without IMC the UCDs cannot be merged here, but the merged score is at least
# the best single run - so a best run of 100% means the merged score is 100%.
best_fc=$(awk '$5 != "-" {print $5}' "$OUT/results.txt" | sort -g | tail -1)
best_fsm=$(awk '$6 != "-" {print $6}' "$OUT/results.txt" | sort -g | tail -1)
say "  cache_ops  best single run : ${best_fc:--}%"
say "  cache_fsm  best single run : ${best_fsm:--}%"
say "  (merged >= best run; UCDs for IMC: $OUT/runs/*/cov_work)"

sva=$(cat "$OUT"/logs/*.log 2>/dev/null | grep -h "^\[SVA COVER\]" | \
      awk '{for (i=3;i<=NF;i++){split($i,kv,"="); n[kv[1]]+=kv[2]}}
           END {for (k in n) printf "%s=%d ", k, n[k]}')
say "  SVA cover hits (all runs)  : ${sva:-none}"
say "===================================================="

if [ "$failed" -ne 0 ]; then
    say "REGRESSION FAILED"
    exit 1
fi
say "REGRESSION PASSED"
exit 0
