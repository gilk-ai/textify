#!/bin/bash
# One-step setup on a Mac: check prerequisites, build, install to /Applications, apply settings, test.
#
#   scripts/setup.sh                       build + install + test (English OCR)
#   scripts/setup.sh --hebrew              also install Tesseract for Hebrew (needs Homebrew)
#   scripts/setup.sh --profile product-manager
#   scripts/setup.sh --settings "autoSaveEnabled=1 autoSaveMode=newFile"
#   scripts/setup.sh --check               only check prerequisites; change nothing
set -uo pipefail
cd "$(dirname "$0")/.."

HEBREW=0; CHECK_ONLY=0; SETTINGS=""; PROFILE=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --hebrew) HEBREW=1 ;;
    --check) CHECK_ONLY=1 ;;
    --profile) PROFILE="${2:-}"; shift ;;
    --settings) SETTINGS="${2:-}"; shift ;;
    *) echo "Unknown option: $1"; exit 2 ;;
  esac
  shift
done

[[ -z "$PROFILE" || "$PROFILE" == "product-manager" ]] || {
  echo "Unknown profile: $PROFILE (available: product-manager)"
  exit 2
}

ok()   { echo "  ✓ $*"; }
warn() { echo "  ! $*"; }
die()  { echo "  ✗ $*"; exit 1; }

echo "Checking this Mac"
major=$(sw_vers -productVersion | cut -d. -f1)
(( major >= 14 )) || die "macOS 14 or later is required (this Mac has $(sw_vers -productVersion))."
ok "macOS $(sw_vers -productVersion)"

if ! xcode-select -p >/dev/null 2>&1; then
  (( CHECK_ONLY )) && die "Command Line Tools are not installed (run: xcode-select --install)."
  xcode-select --install 2>/dev/null || true
  die "Command Line Tools are not installed. An installer window was opened — finish it, then run this script again. (On a managed Mac, IT may need to install them.)"
fi
ok "Developer tools at $(xcode-select -p)"

# The macOS 27 Command Line Tools SDK ships SwiftUI macros without their compiler plugin,
# so a build needs either Xcode or a macOS 26 SDK (build-app.sh picks it automatically).
CLT=/Library/Developer/CommandLineTools/SDKs
if xcode-select -p | grep -q Xcode.app; then
  ok "Xcode selected"
elif ls -d "$CLT"/MacOSX26*.sdk >/dev/null 2>&1 || (( major < 27 )); then
  ok "Usable SDK found"
else
  die "No macOS 26 SDK in $CLT and Xcode isn't selected. Install Xcode (App Store / IT) or Command Line Tools that include MacOSX26.sdk."
fi
command -v swift >/dev/null || die "swift not found."
ok "$(swift --version 2>/dev/null | head -1)"

if command -v brew >/dev/null; then BREW=1; ok "Homebrew available"; else BREW=0; fi
TESS=$( [[ -x /opt/homebrew/bin/tesseract || -x /usr/local/bin/tesseract ]] && echo 1 || echo 0 )
(( TESS )) && ok "Tesseract installed (Hebrew OCR)" || warn "Tesseract not installed — Hebrew OCR off, English works"

(( CHECK_ONLY )) && { echo "Check passed."; exit 0; }

if (( HEBREW )) && ! (( TESS )); then
  echo "Installing Tesseract for Hebrew"
  if (( BREW )); then
    brew install tesseract tesseract-lang && ok "Tesseract installed" || warn "brew install failed — continuing with English only"
  else
    warn "Homebrew isn't installed (or isn't allowed here). Hebrew needs: brew install tesseract tesseract-lang. Continuing with English only."
  fi
fi

echo "Building and installing"
scripts/build-app.sh --install || die "Build failed (see build/build.log)."

apply_setting() {
  local pair="$1" key value b
  key="${pair%%=*}"; value="${pair#*=}"
  case "$key" in
    autoSaveEnabled|detectEvents|qrCopyContent|logReceipts|saveTablesAsExcel|showInDock|showInMenuBar|hebrewOCREnabled)
      [[ "$value" =~ ^(1|0|true|false|YES|NO)$ ]] || die "$key needs 1 or 0"
      [[ "$value" =~ ^(1|true|YES)$ ]] && b=true || b=false
      defaults write com.textify.app "$key" -bool "$b" || die "could not set $key" ;;
    autoSaveMode)
      [[ "$value" =~ ^(newFile|append)$ ]] || die "autoSaveMode is newFile or append"
      defaults write com.textify.app "$key" -string "$value" || die "could not set $key" ;;
    globalHotKey)
      [[ "$value" =~ ^(cmdShiftV|ctrlOptCmdV|ctrlShiftT|disabled)$ ]] || die "unknown globalHotKey: $value"
      defaults write com.textify.app "$key" -string "$value" || die "could not set $key" ;;
    *) die "Not a TEXTIFY setting: $key" ;;
  esac
  ok "$key = $value"
}

if [[ "$PROFILE" == "product-manager" ]]; then
  echo "Applying product-manager profile"
  for pair in \
    autoSaveEnabled=1 autoSaveMode=append saveTablesAsExcel=1 detectEvents=1 \
    qrCopyContent=0 logReceipts=0 globalHotKey=ctrlOptCmdV showInDock=1 showInMenuBar=1; do
    apply_setting "$pair"
  done
fi

if [[ -n "$SETTINGS" ]]; then
  echo "Applying custom settings"
  for pair in $SETTINGS; do
    apply_setting "$pair"
  done
fi

echo "Testing"
scripts/run-tests.sh | tail -1

open /Applications/TEXTIFY.app
echo "✓ TEXTIFY is installed in /Applications and running (Dock + menu bar)."
