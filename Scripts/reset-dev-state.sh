#!/bin/zsh
set -euo pipefail

BUNDLE_ID="com.mirr0ch1.babylock"

/usr/bin/pkill -f "/Baby Lock.app/Contents/MacOS/Baby Lock" 2>/dev/null || true
/usr/bin/defaults delete "$BUNDLE_ID" 2>/dev/null || true
/usr/bin/tccutil reset Accessibility "$BUNDLE_ID" 2>/dev/null || true
/usr/bin/tccutil reset ListenEvent "$BUNDLE_ID" 2>/dev/null || true
/usr/bin/killall cfprefsd 2>/dev/null || true

echo "Baby Lock dev state reset"
