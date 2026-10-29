#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/build/Debug"
APP_DIR="$BUILD_DIR/Baby Lock.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
MODULE_CACHE_DIR="/private/tmp/babylock-module-cache"

SWIFT_FILES=()
while IFS= read -r file; do
  SWIFT_FILES+=("$file")
done < <(find "$ROOT_DIR/BabyLock" -name '*.swift' -print | sort)

if (( ${#SWIFT_FILES[@]} == 0 )); then
  echo "No Swift files found" >&2
  exit 1
fi

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR" "$MODULE_CACHE_DIR"

swiftc \
  -target "$(uname -m)-apple-macos13.0" \
  -module-cache-path "$MODULE_CACHE_DIR" \
  -g \
  -Onone \
  -D DEBUG \
  -o "$MACOS_DIR/Baby Lock" \
  "${SWIFT_FILES[@]}"

cat > "$CONTENTS_DIR/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>en</string>
	<key>CFBundleDisplayName</key>
	<string>Baby Lock</string>
	<key>CFBundleExecutable</key>
	<string>Baby Lock</string>
	<key>CFBundleIconFile</key>
	<string>AppIcon</string>
	<key>CFBundleIdentifier</key>
	<string>com.mirr0ch1.babylock</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>Baby Lock</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>1.2.2</string>
	<key>CFBundleVersion</key>
	<string>4</string>
	<key>LSApplicationCategoryType</key>
	<string>public.app-category.utilities</string>
	<key>LSMinimumSystemVersion</key>
	<string>13.0</string>
	<key>LSUIElement</key>
	<true/>
	<key>LSMultipleInstancesProhibited</key>
	<true/>
	<key>NSHighResolutionCapable</key>
	<true/>
	<key>NSInputMonitoringUsageDescription</key>
	<string>Baby Lock uses Input Monitoring only to recognize the unlock gesture.</string>
	<key>NSSupportsAutomaticTermination</key>
	<false/>
	<key>NSSupportsSuddenTermination</key>
	<false/>
</dict>
</plist>
PLIST

cp "$ROOT_DIR/BabyLock/Resources/AppIcon.icns" "$RESOURCES_DIR/AppIcon.icns"

for lproj in "$ROOT_DIR"/BabyLock/Resources/*.lproj; do
  cp -R "$lproj" "$RESOURCES_DIR/"
done

echo "$APP_DIR"
