#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_PATH="$("$ROOT_DIR/Scripts/build-debug.sh")"

/usr/bin/pkill -f "/Baby Lock.app/Contents/MacOS/Baby Lock" 2>/dev/null || true
open -n "$APP_PATH"
