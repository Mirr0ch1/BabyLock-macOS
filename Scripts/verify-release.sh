#!/bin/bash
set -euo pipefail

if [ "$#" -ne 1 ]; then
  echo "usage: $0 vX.Y.Z" >&2
  exit 2
fi

TAG="$1"
case "$TAG" in
  v*) ;;
  *)
    echo "tag must start with v, for example v1.2.3" >&2
    exit 2
    ;;
esac
VERSION="${TAG#v}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

ORIGIN_URL="$(git remote get-url origin)"
REPO="$(printf '%s' "$ORIGIN_URL" | sed -E 's#^git@github.com:##; s#^ssh://git@github.com/##; s#^https://github.com/##; s#\.git$##')"
if ! [[ "$REPO" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]]; then
  echo "could not determine the GitHub repository from origin: $ORIGIN_URL" >&2
  exit 1
fi

DIST="$ROOT/dist/$TAG"

rm -rf "$DIST"
mkdir -p "$DIST"

gh release download "$TAG" --repo "$REPO" --pattern 'BabyLock-macOS.zip*' --dir "$DIST" --clobber

for file in BabyLock-macOS.zip BabyLock-macOS.zip.sig BabyLock-macOS.zip.sha256; do
  if [ ! -f "$DIST/$file" ]; then
    echo "missing release asset: $file" >&2
    exit 1
  fi
done

if command -v sha256sum >/dev/null 2>&1; then
  (cd "$DIST" && sha256sum -c BabyLock-macOS.zip.sha256)
else
  (cd "$DIST" && shasum -a 256 -c BabyLock-macOS.zip.sha256)
fi

PUBLIC_KEY="$(sed -n 's/.*publicKeyBase64 = "\([^"]*\)".*/\1/p' BabyLock/Managers/UpdateSigning.swift | head -1)"
if [ -z "$PUBLIC_KEY" ]; then
  echo "could not read the pinned Ed25519 public key" >&2
  exit 1
fi

BUILD="$(sed -n 's/.*CURRENT_PROJECT_VERSION = \([0-9]*\);.*/\1/p' BabyLock.xcodeproj/project.pbxproj | head -1)"
if [ -z "$BUILD" ]; then
  echo "could not read CURRENT_PROJECT_VERSION" >&2
  exit 1
fi

PUBLIC_KEY="$PUBLIC_KEY" VERSION="$VERSION" BUILD="$BUILD" DIST="$DIST" python3 - <<'PY'
import base64
import os
import plistlib
import zipfile

try:
    from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PublicKey
except ImportError:
    raise SystemExit("python3 cryptography is required: python3 -m pip install cryptography")

dist = os.environ["DIST"]
version = os.environ["VERSION"]
build = os.environ["BUILD"]
public_key = base64.b64decode(os.environ["PUBLIC_KEY"])

if len(public_key) != 32:
    raise SystemExit(f"pinned public key is {len(public_key)} bytes, expected 32")

with open(os.path.join(dist, "BabyLock-macOS.zip"), "rb") as handle:
    archive = handle.read()
with open(os.path.join(dist, "BabyLock-macOS.zip.sig"), "rb") as handle:
    signature = handle.read()

if len(signature) != 64:
    raise SystemExit(f"signature is {len(signature)} bytes, expected 64")

Ed25519PublicKey.from_public_bytes(public_key).verify(signature, archive)

with zipfile.ZipFile(os.path.join(dist, "BabyLock-macOS.zip")) as bundle:
    info = plistlib.loads(bundle.read("Baby Lock.app/Contents/Info.plist"))

checks = {
    "CFBundleIdentifier": "com.mirr0ch1.babylock",
    "CFBundleShortVersionString": version,
    "CFBundleVersion": build,
    "LSMultipleInstancesProhibited": True,
}
for key, expected in checks.items():
    actual = info.get(key)
    if actual != expected:
        raise SystemExit(f"{key} = {actual!r}, expected {expected!r}")

minimum = info.get("LSMinimumSystemVersion")
if not isinstance(minimum, str) or not minimum:
    raise SystemExit("LSMinimumSystemVersion is missing")

print(f"Ed25519 signature OK; bundle {version} ({build}); min macOS {minimum}")
PY

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
unzip -q "$DIST/BabyLock-macOS.zip" -d "$TMP"

BINARY="$TMP/Baby Lock.app/Contents/MacOS/Baby Lock"
if [ ! -f "$BINARY" ]; then
  echo "release does not contain Baby Lock.app/Contents/MacOS/Baby Lock" >&2
  exit 1
fi

FILE_OUT="$(file "$BINARY")"
printf '%s\n' "$FILE_OUT"

case "$FILE_OUT" in
  *arm64*x86_64*|*x86_64*arm64*) ;;
  *)
    echo "release binary is not universal arm64 + x86_64" >&2
    exit 1
    ;;
esac

echo "Release verified: $(gh release view "$TAG" --repo "$REPO" --json url -q .url)"
