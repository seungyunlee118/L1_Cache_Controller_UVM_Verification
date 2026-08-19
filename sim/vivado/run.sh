#!/usr/bin/env bash
# Linux/macOS counterpart of run.bat.
#   ./run.sh                            -> default test, seed 1
#   ./run.sh l1_cache_stress_test       -> pick a test
#   ./run.sh l1_cache_stress_test 42    -> pick a test and a seed
set -euo pipefail
cd "$(dirname "$0")"
exec make run TEST="${1:-l1_cache_random_test}" SEED="${2:-1}"
