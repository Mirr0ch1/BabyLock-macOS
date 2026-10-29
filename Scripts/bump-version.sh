#!/bin/bash
set -euo pipefail

if [ "$#" -ne 2 ]; then
  echo "usage: $0 <version> <build>" >&2
  echo "example: $0 1.2.3 5" >&2
  exit 2
fi

VERSION="$1"
BUILD="$2"

if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "version must look like 1.2.3" >&2
  exit 2
fi

if ! [[ "$BUILD" =~ ^[0-9]+$ ]]; then
  echo "build must be an integer" >&2
  exit 2
fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

python3 - "$VERSION" "$BUILD" <<'PY'
import re
import sys

version, build = sys.argv[1], sys.argv[2]


def replace(path, pattern, replacement):
    text = open(path, encoding="utf-8").read()
    updated, count = re.subn(pattern, replacement, text)
    if count == 0:
        raise SystemExit(f"pattern not found in {path}: {pattern}")
    open(path, "w", encoding="utf-8").write(updated)


replace(
    "BabyLock.xcodeproj/project.pbxproj",
    r"MARKETING_VERSION = [^;]+;",
    f"MARKETING_VERSION = {version};",
)
replace(
    "BabyLock.xcodeproj/project.pbxproj",
    r"CURRENT_PROJECT_VERSION = [^;]+;",
    f"CURRENT_PROJECT_VERSION = {build};",
)
replace(
    "BabyLock/Views/SettingsView.swift",
    r'\?\? "[0-9]+\.[0-9]+\.[0-9]+"',
    f'?? "{version}"',
)
replace(
    "Scripts/build-debug.sh",
    r"(<key>CFBundleShortVersionString</key>\s*<string>)[^<]+(</string>)",
    rf"\g<1>{version}\g<2>",
)
replace(
    "Scripts/build-debug.sh",
    r"(<key>CFBundleVersion</key>\s*<string>)[^<]+(</string>)",
    rf"\g<1>{build}\g<2>",
)
PY

echo "Bumped to $VERSION ($BUILD)"
git diff --stat
