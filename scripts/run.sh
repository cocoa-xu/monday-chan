#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
scripts/build.sh
open dist/MondayChan.app --args --data "$PWD/data" "$@"
