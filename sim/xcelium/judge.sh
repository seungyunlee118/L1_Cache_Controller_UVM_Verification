# Sourced by regress.sh and the Makefile: the single pass/fail rule for a run.
#
#   judge <log> [xrun exit code]   ->  prints "PASS -" or "FAIL <reason>"
#
# A run passes only if it reached the scoreboard report, UVM_ERROR and
# UVM_FATAL are both 0 (SVA failures report through uvm_report_error, so they
# count), and the simulator printed no *E/*F other than KNOWN_SIM_ERRORS. The
# reason is the ID of the earliest UVM_ERROR (FATAL:<id> for a UVM_FATAL), or
# SIM:<code> for a simulator message.
#
# xrun's own exit code is not used: on the lab host it is 1 for every run,
# because of the IMPDLL message below. Only 124 (killed by `timeout`) counts.

# The lab host has no glibc-devel, so xmelab cannot link the DPI export stub
# (_sv_export.so) and xmsim reports IMPDLL. Only UVM's interactive Tcl helpers
# and C-side error reporting use those exports, so batch results are
# unaffected. Any other *E/*F fails the run.
KNOWN_SIM_ERRORS="IMPDLL"

judge() {
    local log=$1 rc=${2:-0} id
    [ "$rc" -eq 124 ] && { echo "FAIL WALL_TIMEOUT"; return; }

    id=$(sed -nE -e 's/^UVM_ERROR .* @ [0-9]+: [^ ]+ \[([^]]+)\].*/\1/p' \
                 -e 's/^UVM_FATAL .* @ [0-9]+: [^ ]+ \[([^]]+)\].*/FATAL:\1/p' "$log" | head -1)
    [ -n "$id" ] && { echo "FAIL $id"; return; }

    id=$(grep -oE "\*[EF],[A-Z0-9_]+" "$log" | sed 's/^\*[EF],//' \
         | grep -vxE "${KNOWN_SIM_ERRORS// /|}" | head -1)
    [ -n "$id" ] && { echo "FAIL SIM:$id"; return; }

    grep -q "SCOREBOARD SUMMARY" "$log"            || { echo "FAIL NO_REPORT"; return; }
    grep -qE "^UVM_ERROR :[[:space:]]+0$" "$log"  || { echo "FAIL NO_SUMMARY"; return; }
    grep -qE "^UVM_FATAL :[[:space:]]+0$" "$log"  || { echo "FAIL NO_SUMMARY"; return; }
    echo "PASS -"
}
