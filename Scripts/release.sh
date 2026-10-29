#!/bin/bash
set -euo pipefail

ASSUME_YES=0
if [ "${1:-}" = "--yes" ]; then
  ASSUME_YES=1
  shift
fi

if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
  echo "usage: $0 [--yes] <version> [release-notes.md]" >&2
  echo "example: $0 1.2.3 dist/release-notes-1.2.3.md" >&2
  exit 2
fi

VERSION="$1"
NOTES="${2:-}"
TAG="v$VERSION"

if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "version must look like 1.2.3 (stable releases only)" >&2
  exit 2
fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

ORIGIN_URL="$(git remote get-url origin)"
REPO="$(printf '%s' "$ORIGIN_URL" | sed -E 's#^git@github.com:##; s#^ssh://git@github.com/##; s#^https://github.com/##; s#\.git$##')"
if ! [[ "$REPO" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]]; then
  echo "could not determine the GitHub repository from origin: $ORIGIN_URL" >&2
  exit 1
fi

mkdir -p "$ROOT/dist"

if [ -n "$(git status --porcelain --untracked-files=no)" ]; then
  echo "working tree has tracked changes; commit or stash them first" >&2
  git status --short
  exit 1
fi

if [ "$(git branch --show-current)" != "main" ]; then
  echo "release must be cut from main" >&2
  exit 1
fi

git fetch --quiet origin main
if [ "$(git rev-parse HEAD)" != "$(git rev-parse origin/main)" ]; then
  echo "local main is not at origin/main; push or pull first" >&2
  exit 1
fi

if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
  echo "local tag $TAG already exists" >&2
  exit 1
fi

if [ -n "$(git ls-remote --tags origin "refs/tags/$TAG")" ]; then
  echo "remote tag $TAG already exists" >&2
  exit 1
fi

if gh release view "$TAG" --repo "$REPO" >/dev/null 2>&1; then
  echo "release $TAG already exists" >&2
  exit 1
fi

if [ -n "$NOTES" ] && [ ! -f "$NOTES" ]; then
  echo "release notes file not found: $NOTES" >&2
  exit 1
fi

python3 - "$VERSION" <<'PY'
import re
import sys

version = sys.argv[1]


def first(path, pattern):
    match = re.search(pattern, open(path, encoding="utf-8").read())
    return match.group(1) if match else None


project = "BabyLock.xcodeproj/project.pbxproj"
marketing = first(project, r"MARKETING_VERSION = ([^;]+);")
build = first(project, r"CURRENT_PROJECT_VERSION = ([^;]+);")
debug_version = first("Scripts/build-debug.sh", r"<key>CFBundleShortVersionString</key>\s*<string>([^<]+)</string>")
debug_build = first("Scripts/build-debug.sh", r"<key>CFBundleVersion</key>\s*<string>([^<]+)</string>")
fallback = first("BabyLock/Views/SettingsView.swift", r'\?\? "([0-9]+\.[0-9]+\.[0-9]+)"')

values = {
    "project MARKETING_VERSION": marketing,
    "project CURRENT_PROJECT_VERSION": build,
    "debug CFBundleShortVersionString": debug_version,
    "debug CFBundleVersion": debug_build,
    "SettingsView fallback": fallback,
}
for name, value in values.items():
    print(f"{name}: {value}")

if marketing != version or debug_version != version or fallback != version:
    raise SystemExit(f"version mismatch: expected {version}")

if build != debug_build or not build or not build.isdigit():
    raise SystemExit("build number mismatch between project and debug script")
PY

BUILD="$(sed -n 's/.*CURRENT_PROJECT_VERSION = \([0-9]*\);.*/\1/p' BabyLock.xcodeproj/project.pbxproj | head -1)"
PREVIOUS_TAG="$(git describe --tags --abbrev=0 2>/dev/null || true)"
if [ -n "$PREVIOUS_TAG" ]; then
  PREVIOUS_VERSION="${PREVIOUS_TAG#v}"
  python3 - "$PREVIOUS_VERSION" "$VERSION" <<'PY'
import sys

def parse(value):
    return tuple(int(part) for part in value.split("."))

previous, current = sys.argv[1], sys.argv[2]
try:
    if parse(current) <= parse(previous):
        raise SystemExit(f"version {current} must be greater than {previous}")
except ValueError:
    # A non-semver historical tag should not block a release.
    pass
PY

  PREVIOUS_BUILD="$(git show "$PREVIOUS_TAG:BabyLock.xcodeproj/project.pbxproj" | sed -n 's/.*CURRENT_PROJECT_VERSION = \([0-9]*\);.*/\1/p' | head -1)"
  if [ -n "$PREVIOUS_BUILD" ] && [ "$BUILD" -le "$PREVIOUS_BUILD" ]; then
    echo "build $BUILD must be greater than the build in $PREVIOUS_TAG ($PREVIOUS_BUILD)" >&2
    exit 1
  fi
fi

LAST_MAIN="$(gh run list --repo "$REPO" --workflow=build.yml --branch main --limit 1 --json status,conclusion,headSha -q '.[0] | [.status, (.conclusion // ""), .headSha] | @tsv')"
LAST_MAIN_STATUS="$(printf '%s' "$LAST_MAIN" | awk '{print $1}')"
LAST_MAIN_CONCLUSION="$(printf '%s' "$LAST_MAIN" | awk '{print $2}')"
LAST_MAIN_SHA="$(printf '%s' "$LAST_MAIN" | awk '{print $3}')"
HEAD_SHA="$(git rev-parse HEAD)"
if [ "$LAST_MAIN_STATUS" != "completed" ] || [ "$LAST_MAIN_CONCLUSION" != "success" ] || [ "$LAST_MAIN_SHA" != "$HEAD_SHA" ]; then
  echo "latest main build is not a successful build of $HEAD_SHA" >&2
  echo "status=$LAST_MAIN_STATUS conclusion=$LAST_MAIN_CONCLUSION head=$LAST_MAIN_SHA" >&2
  echo "wait for the main build to finish, then run this script again" >&2
  exit 1
fi

if [ "$ASSUME_YES" -ne 1 ]; then
  echo "About to tag and publish $TAG from $(git rev-parse --short HEAD)."
  read -r -p "Continue? [y/N] " answer
  case "$answer" in
    y|Y) ;;
    *) echo "aborted" >&2; exit 1 ;;
  esac
fi

git tag -a "$TAG" -m "Baby Lock $VERSION"
git push origin "$TAG"

echo "Waiting for the tag build..."
RUN_ID=""
TRIES=0
while [ "$TRIES" -lt 60 ]; do
  RUN_ID="$(gh run list --repo "$REPO" --workflow=build.yml --limit 20 \
    --json databaseId,event,headBranch -q ".[] | select(.event == \"push\" and .headBranch == \"$TAG\") | .databaseId" | head -1)"
  if [ -n "$RUN_ID" ]; then
    break
  fi
  TRIES=$((TRIES + 1))
  sleep 5
done

if [ -z "$RUN_ID" ]; then
  echo "could not find the workflow run for $TAG" >&2
  exit 1
fi

gh run watch "$RUN_ID" --repo "$REPO" --exit-status

"$ROOT/Scripts/verify-release.sh" "$TAG"

if [ -n "$NOTES" ]; then
  gh release edit "$TAG" --repo "$REPO" --title "Baby Lock $VERSION" --notes-file "$NOTES"
fi

echo "Release ready: $(gh release view "$TAG" --repo "$REPO" --json url -q .url)"
echo "Artifacts: $ROOT/dist/$TAG"
