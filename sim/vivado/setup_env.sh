# ============================================================================
#  Put the Vivado xsim tools (xvlog / xelab / xsim / xcrg) on PATH.
#
#  SOURCE this file, do not execute it:  source ./setup_env.sh
#  It is sourced automatically by the Makefile and the run/regress scripts.
#
#  Resolution order:
#    1. If xvlog is already on PATH (you ran settings64.sh yourself), do nothing.
#    2. Else source "$VIVADO_ROOT/settings64.sh".
#    3. Else try a few common Linux install locations.
#
#  Override the version/location with:
#    export VIVADO_ROOT=/opt/Xilinx/Vivado/2025.2
# ============================================================================

if ! command -v xvlog >/dev/null 2>&1; then

    _candidates=(
        "$VIVADO_ROOT"
        /tools/Xilinx/Vivado/2025.2
        /opt/Xilinx/Vivado/2025.2
        /opt/Xilinx/2025.2/Vivado
        "$HOME/Xilinx/Vivado/2025.2"
        /tools/Xilinx/Vivado/2026.1
        /opt/Xilinx/Vivado/2026.1
    )

    _found=""
    for _c in "${_candidates[@]}"; do
        if [ -n "$_c" ] && [ -f "$_c/settings64.sh" ]; then
            _found="$_c"
            break
        fi
    done

    if [ -n "$_found" ]; then
        # shellcheck disable=SC1091
        source "$_found/settings64.sh"
    else
        echo "ERROR: Vivado xsim tools not found." >&2
        echo "  xvlog is not on PATH and no settings64.sh was found in:" >&2
        printf '    %s\n' "${_candidates[@]}" >&2
        echo "  Fix it one of two ways:" >&2
        echo "    export VIVADO_ROOT=/your/path/to/Vivado/<version>" >&2
        echo "    # or just source Vivado yourself first:" >&2
        echo "    source /your/path/to/Vivado/<version>/settings64.sh" >&2
        return 1 2>/dev/null || exit 1
    fi
fi

# Sanity: the precompiled UVM 1.2 library must exist for -L uvm to work.
if ! command -v xvlog >/dev/null 2>&1; then
    echo "ERROR: xvlog still not on PATH after sourcing Vivado." >&2
    return 1 2>/dev/null || exit 1
fi
