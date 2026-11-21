#!/bin/bash
# End-to-end tests for TEXTIFY's OCR, table and clipboard pipeline (headless, never saves files).
# Usage: scripts/run-tests.sh [path/to/Textify-binary]   (default: build/TEXTIFY.app)
set -uo pipefail
cd "$(dirname "$0")/.."

B="${1:-build/TEXTIFY.app/Contents/MacOS/Textify}"
[[ -x "$B" ]] || { echo "Binary not found: $B (run scripts/build-app.sh first)"; exit 1; }
IMG=build/test-images
swift scripts/make-test-images.swift "$IMG" >/dev/null 2>&1

pass=0; fail=0; skip=0
check() { if eval "$2" >/dev/null 2>&1; then pass=$((pass+1)); echo "  ✓ $1"; else fail=$((fail+1)); echo "  ✗ $1"; fi; }
skipped() { skip=$((skip+1)); echo "  – $1 (skipped: $2)"; }

HAS_HEBREW=0; [[ -f "$(brew --prefix 2>/dev/null)/share/tessdata/heb.traineddata" ]] && HAS_HEBREW=1
HAS_TABLES=0; [[ $(sw_vers -productVersion | cut -d. -f1) -ge 26 ]] && HAS_TABLES=1

echo "OCR"
check "English text"            '$B --ocr $IMG/english.png | grep -q "quick brown fox"'
check "paragraph gaps kept"     '[[ $($B --ocr $IMG/multi-paragraph.png | grep -c "^$") -eq 2 ]]'
check "blank image → no text"   '! $B --ocr $IMG/blank.png'
check "unsupported format"      '! $B --ocr Package.swift'
if (( HAS_HEBREW )); then
  check "Hebrew text"           '$B --ocr $IMG/hebrew.png | grep -q "שלום עולם"'
  check "mixed Hebrew/English order" '[[ "$($B --ocr $IMG/mixed.png | grep -v "^$" | sed -n 2p)" == *"פגישה"* ]]'
else
  skipped "Hebrew text" "Tesseract + heb model not installed"
fi

echo "Tables"
if (( HAS_TABLES )); then
  check "gridded table 5×5"     '$B --table $IMG/table-grid.png | grep -q "5 rows × 5 columns"'
  check "borderless table 5×5"  '$B --table $IMG/table-plain.png | grep -q "5 rows × 5 columns"'
  check "merged title row"      '$B --table $IMG/table-merged.png | grep -q "4 rows × 3 columns"'
  (( HAS_HEBREW )) && check "Hebrew RTL table" '$B --table $IMG/table-hebrew.png | grep -q "(RTL)"'
  for f in invoice recipe mixed multi-paragraph english; do
    check "no false table: $f"  "! \$B --table \$IMG/$f.png"
  done
  check "valid .xlsx export"    '$B --table $IMG/table-merged.png --xlsx build/test.xlsx && unzip -tq build/test.xlsx'
else
  skipped "table detection" "needs macOS 26+"
fi

echo "Smart detection"
check "QR link decoded"          '$B --detect $IMG/qr-link.png | grep -q "copy: https://example.com/textify?ref=poster"'
check "Wi-Fi QR → password"      '$B --detect $IMG/qr-wifi.png | grep -q "copy: latte;2026"'
check "English event found"      '$B --detect $IMG/event.png | grep -q "^Event:"'
check "receipt total + VAT"      '$B --detect $IMG/receipt.png | grep -q "Receipt: BLUE BOTTLE COFFEE | \$10.60 · VAT \$0.85"'
check "receipt isn't an event"   '! $B --detect $IMG/receipt.png | grep -q "^Event:"'
for f in table-grid recipe mixed event english; do
  check "no false receipt: $f"   "! \$B --detect \$IMG/$f.png | grep -q '^Receipt:'"
done
if (( HAS_HEBREW )); then
  check "Hebrew event"           '$B --detect $IMG/event-hebrew.png | grep -q "Event: פגישת צוות"'
  check "Hebrew receipt ₪ + VAT" '$B --detect $IMG/receipt-hebrew.png | grep -q "Receipt: קפה לנדוור | ₪32.00 · VAT ₪4.88"'
fi
LEDGER=$(mktemp -d)
TEXTIFY_SAVE_DIR=$LEDGER $B --detect $IMG/receipt.png --log >/dev/null
check "ledger skips duplicates"  'TEXTIFY_SAVE_DIR=$LEDGER $B --detect $IMG/receipt.png --log | grep -q "Already in" && [[ $(wc -l < $LEDGER/Expenses.csv) -eq 2 ]]'
rm -rf "$LEDGER"
check "valid .ics"               '$B --detect $IMG/event.png --ics build/test.ics && grep -q "^DTSTART:.*Z" build/test.ics && grep -q "END:VCALENDAR" build/test.ics'

echo "Clipboard"
setclip() { osascript -e "set the clipboard to (read (POSIX file \"$PWD/$1\") as «class PNGf»)"; }
saved_clip=$(mktemp); pbpaste > "$saved_clip" 2>/dev/null
setclip $IMG/english.png;  $B --ocr-clipboard --no-save >/dev/null
check "image → text on clipboard" 'pbpaste | grep -q "quick brown fox"'
setclip $IMG/blank.png;    $B --ocr-clipboard --no-save >/dev/null 2>&1
check "no text → clipboard untouched" 'osascript -e "clipboard info" | grep -q PNGf'
setclip $IMG/qr-link.png;  $B --ocr-clipboard --no-save >/dev/null
check "QR code → link on clipboard" '[[ "$(pbpaste)" == "https://example.com/textify?ref=poster" ]]'
if (( HAS_TABLES )); then
  setclip $IMG/table-grid.png; $B --ocr-clipboard --no-save >/dev/null
  check "table → tab-separated cells" 'osascript -l JavaScript -e "ObjC.import(\"AppKit\"); \$.NSPasteboard.generalPasteboard.stringForType(\"public.utf8-tab-separated-values-text\").js" | grep -q "Laptop Pro	North"'
fi
pbcopy < "$saved_clip"; rm -f "$saved_clip"

echo; echo "passed $pass, failed $fail, skipped $skip"
(( fail == 0 ))
