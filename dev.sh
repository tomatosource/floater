#!/bin/bash
# Rebuild and relaunch Floater, restoring the last image, position and size
# (the new instance closes the running one). Use this instead of a fresh launch while developing.
set -euo pipefail
cd "$(dirname "$0")"
./build.sh
open -n build/Floater.app --args --restore
