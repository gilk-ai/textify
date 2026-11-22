#!/bin/bash
# Builds TEXTIFY.app into ./build. Pass --install to copy it to /Applications.
set -euo pipefail
cd "$(dirname "$0")/.."

# The macOS 27 SDK in Command Line Tools ships SwiftUI macros without their compiler plugin,
# so prefer the newest SDK that builds without Xcode. Override with SDKROOT=... if needed.
if [[ -z "${SDKROOT:-}" ]]; then
  CLT=/Library/Developer/CommandLineTools/SDKs
  SDK26=$(ls -d "$CLT"/MacOSX26*.sdk 2>/dev/null | sort -V | tail -1)
  if [[ -n "$SDK26" ]] && ! xcode-select -p | grep -q Xcode.app; then
    export SDKROOT="$SDK26"
  fi
fi

echo "→ Compiling (release)…"
# Fail loudly on compile errors (don't silently package a stale binary).
mkdir -p build
status=0
swift build -c release > build/build.log 2>&1 || status=$?
grep -v "search path .* not found" build/build.log || true
if [[ $status -ne 0 ]]; then echo "✗ Build failed (see build/build.log)"; exit 1; fi
BIN="$(swift build -c release --show-bin-path)/Textify"

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
