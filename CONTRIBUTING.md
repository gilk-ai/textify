# Contributing to TEXTIFY

Thanks for helping! TEXTIFY is meant to stay small: it does one thing (screenshot → text on the clipboard), and does it fast.

## Ground rules

- **Privacy first.** No networking, no analytics, no logging of extracted text. Images stay in memory.
- **Native first.** Prefer Apple frameworks. The only third-party piece is the optional, locally installed Tesseract engine for Hebrew.
- **Keep it simple.** Before opening a large PR, open an issue to discuss whether the feature fits.

## Development

```bash
swift build                      # with Xcode installed
scripts/build-app.sh             # builds build/TEXTIFY.app (handles the Command Line Tools SDK quirk)
swift scripts/make-test-images.swift build/test-images
.build/debug/Textify --ocr build/test-images/english.png
```

Before submitting, please check:

1. `scripts/build-app.sh` builds without warnings from `Sources/`.
2. Run `--ocr` on the generated test images (English, Hebrew, mixed, multi-paragraph, blank) and check the output reads correctly.
3. For UI changes, attach before/after screenshots. The snapshot mode in the README renders each state without Screen Recording permission.

## Code layout

See the "Layout" section of the README. OCR, clipboard and UI live in separate files. Keep it that way.
