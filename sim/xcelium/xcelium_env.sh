# Sourced by the Makefile and scripts. Puts Xcelium on PATH if it is not there
# already. Point XCELIUM_HOME at another install to override the lab default.
if ! command -v xrun >/dev/null 2>&1; then
    XCELIUM_HOME=${XCELIUM_HOME:-/usr/local/cadence/XCELIUM2409}
    export PATH="$XCELIUM_HOME/tools.lnx86/bin:$PATH"
fi
if ! command -v xrun >/dev/null 2>&1; then
    echo "xcelium_env.sh: xrun not found - set XCELIUM_HOME" >&2
    return 1 2>/dev/null || exit 1
fi
