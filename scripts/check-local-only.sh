#!/bin/bash
# Local-only policy check. TEXTIFY's promise: OCR on-device, no networking, no telemetry, never log extracted text.
# Fails (exit 1) if the code base drifts from that. Runs in CI on every push and inside scripts/run-tests.sh.
#
#   scripts/check-local-only.sh
#
# A rule can be relaxed only by editing this file in a reviewed change: the allowlists below are deliberate.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

CODE=(Sources Package.swift Resources)
problems=0
flag() { problems=$((problems + 1)); echo "  ✗ $1"; [[ -n "${2:-}" ]] && echo "$2" | sed 's/^/      /'; }
ok()   { echo "  ✓ $1"; }

# grep wrapper: prints matches (file:line:text), never fails the script by itself.
find_in() { grep -rnE "$1" "${CODE[@]}" 2>/dev/null || true; }

echo "Local-only policy"

# 1. No networking APIs.
hits=$(find_in 'URLSession|URLRequest|NSURLConnection|NWConnection|NWListener|NWPathMonitor|NWBrowser|^import Network|^import WebKit|WKWebView|CFSocket|CFStream|CFReadStream|getaddrinfo|\bsocket\(|contentsOf: *URL\(string')
[[ -z "$hits" ]] && ok "no networking APIs" || flag "networking APIs found" "$hits"

# 2. No analytics / crash-reporting / telemetry SDKs.
hits=$(find_in 'Firebase|Crashlytics|Sentry|Mixpanel|Amplitude|Segment|TelemetryDeck|AppCenter|Bugsnag|Datadog|PostHog|GoogleAnalytics')
[[ -z "$hits" ]] && ok "no telemetry SDKs" || flag "telemetry SDKs found" "$hits"

# 3. No third-party packages (supply chain: nothing can sneak networking in through a dependency).
hits=$(grep -nE '\.package\(' Package.swift || true)
[[ -z "$hits" ]] && ok "no package dependencies" || flag "Package.swift declares dependencies" "$hits"

# 4. No system logging (it would persist text in the unified log). Console output only in the CLI/debug tools,
#    plus the TEXTIFY_DEBUG lines in OCRService (counts) and EventDetector (lengths, dates, decisions) — never text.
hits=$(find_in 'NSLog\(|os_log|\bLogger\(|^import os(\.log)?$')
[[ -z "$hits" ]] && ok "no system logging" || flag "system logging found" "$hits"
hits=$(grep -rnE '(^|[^A-Za-z_.])(print|debugPrint|dump|fputs)\(' Sources \
       | grep -vE '^Sources/Textify/(CommandLineTools|DebugSnapshots)\.swift:' \
       | grep -vE '^Sources/Textify/OCRService\.swift:[0-9]+: *fputs\("\[debug\] obs=' \
       | grep -vE '^Sources/Textify/EventDetector\.swift:[0-9]+: *if debugging \{ fputs\("\[debug\] event: ' \
       | grep -vE '^Sources/Textify/FileLabeler\.swift:[0-9]+: *fputs\("\[debug\] event: model availability = ' || true)
[[ -z "$hits" ]] && ok "console output only in CLI/debug tools" || flag "console output outside CLI/debug tools" "$hits"

# 5. URL literals: only identifiers that are never fetched — the .xlsx format's XML namespaces and
#    the standard plist DTD declaration.
hits=$(find_in 'https?://' | grep -vE 'https?://schemas\.openxmlformats\.org/|http://www\.apple\.com/DTDs/PropertyList-1\.0\.dtd' || true)
[[ -z "$hits" ]] && ok "no URLs besides file-format identifiers" || flag "URL literals found" "$hits"

# 6. Opening things in other apps happens only on a user's click, in reviewed places:
#    QR links (http/https/mailto/tel only), the .ics file for Calendar, and the save folder.
allowed='^Sources/Textify/(BarcodeDetector|EventDetector|Views/SettingsView)\.swift:'
hits=$(grep -rnE 'NSWorkspace\.shared\.(open|openApplication)' Sources | grep -vE "$allowed" || true)
[[ -z "$hits" ]] && ok "opening URLs/files only from reviewed places" || flag "new NSWorkspace.open call (needs review)" "$hits"
schemes=$(grep -n 'openableSchemes: Set<String> = ' Sources/Textify/BarcodeDetector.swift)
[[ "$schemes" == *'["http", "https", "mailto", "tel"]'* ]] && ok "QR links limited to http/https/mailto/tel" \
  || flag "QR openable schemes changed" "$schemes"

# 7. No network entitlements or App Transport Security exceptions.
hits=$( (grep -rlE 'com\.apple\.security\.network|NSAppTransportSecurity|NSAllowsArbitraryLoads' Resources ./*.entitlements 2>/dev/null) || true)
[[ -z "$hits" ]] && ok "no network entitlements / ATS exceptions" || flag "network entitlement or ATS exception" "$hits"

if (( problems )); then
  echo "Local-only policy: $problems problem(s). TEXTIFY must stay on-device (see README → Privacy)."
  exit 1
fi
echo "Local-only policy: passed"
