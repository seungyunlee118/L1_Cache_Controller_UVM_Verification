#!/usr/bin/env bash
# Linux/macOS counterpart of regress.bat.
# Runs every test x seed and prints a merged functional-coverage score.
set -euo pipefail
cd "$(dirname "$0")"
exec make regress
