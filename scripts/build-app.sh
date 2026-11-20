#!/bin/bash
# Builds TEXTIFY.app into ./build. Pass --install to copy it to /Applications.
set -euo pipefail
cd "$(dirname "$0")/.."

# The macOS 27 SDK in Command Line Tools ships SwiftUI macros without their compiler plugin,
# so prefer the newest SDK that builds without Xcode. Override with SDKROOT=... if needed.
if [[ -z "${SDKROOT:-}" ]]; then
  CLT=/Library/Developer/CommandLineTools/SDKs
  if [[ -d "$CLT/MacOSX26.sdk" ]] && ! xcode-select -p | grep -q Xcode.app; then
    export SDKROOT="$CLT/MacOSX26.sdk"
  fi
fi

echo "→ Compiling (release)…"
swift build -c release 2>&1 | grep -v "search path .* not found" || true
BIN="$(swift build -c release --show-bin-path)/Textify"
[[ -x "$BIN" ]] || { echo "Build failed"; exit 1; }

APP=build/TEXTIFY.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Textify"
cp Resources/Info.plist "$APP/Contents/Info.plist"

echo "→ Generating icon…"
ICONSET=build/AppIcon.iconset
rm -rf "$ICONSET"
swift scripts/make-icon.swift "$ICONSET" >/dev/null
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

echo "→ Signing (ad-hoc)…"
codesign --force --deep --sign - "$APP"

echo "✓ Built $APP"
if [[ "${1:-}" == "--install" ]]; then
  pkill -x Textify 2>/dev/null || true
  rm -rf /Applications/TEXTIFY.app
  cp -R "$APP" /Applications/
  echo "✓ Installed to /Applications/TEXTIFY.app"
fi
