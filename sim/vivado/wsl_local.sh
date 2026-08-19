#!/usr/bin/env bash

set -euo pipefail

# Repo root = two levels above this script (sim/vivado -> repo root).
SRC="$(cd "$(dirname "$0")/../.." && pwd)"
DST="${L1_WSL_DIR:-$HOME/Pipelined_Cache_Cont}"

if [ "$SRC" = "$DST" ]; then
    # Already running from the native copy - just build here.
    cd "$SRC/sim/vivado"
    exec make "$@"
fi

if ! command -v rsync >/dev/null 2>&1; then
    echo "ERROR: rsync not found. Install it:  sudo apt-get install -y rsync" >&2
    exit 1
fi

echo ">> mirroring source (no build artifacts)"
echo "     from: $SRC"
echo "     to:   $DST"
rsync -a --delete \
    --exclude 'xsim.dir/'              \
    --exclude 'xsim.covdb/'            \
    --exclude 'xsim.codeCov/'          \
    --exclude 'xsim_coverage_report/'  \
    --exclude 'work/'                  \
    --exclude 'sim/work/'              \
    --exclude '.Xil/'                  \
    --exclude '.git/'                  \
    --exclude '*.log'                  \
    --exclude '*.pb'                   \
    --exclude '*.jou'                  \
    --exclude '*.wdb'                  \
    --exclude '*.vcd'                  \
    --exclude '*.wlf'                  \
    --exclude '*.backup.*'             \
    "$SRC/" "$DST/"

echo ">> building in $DST/sim/vivado"
cd "$DST/sim/vivado"
exec make "$@"
