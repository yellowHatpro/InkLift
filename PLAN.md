# InkLift -- handwriting photo to GoodNotes

Take a photo of handwritten notes on an iPad. Get a GoodNotes document with the
handwriting as ink.

## Definition of done

- Phase A: a photo becomes a vector PDF. The PDF opens in Goodnotes.app and shows the
  handwriting. Ink is flat (not editable).
- Phase B: a photo becomes a `.goodnotes` file. The file opens in Goodnotes.app and the
  strokes are editable with the pen tools.

## Steps

| # | Step | Status | Evidence |
|---|------|--------|----------|
| 1 | `InkCore` package: rectify -> binarize -> skeletonize -> trace -> smooth -> `Stroke` | done fe093f8 | `scripts/test.sh`: 13 tests pass |
| 2 | `PDFExporter`: strokes -> vector PDF | done fe093f8 | `docs/evidence/2026-10-17-pdf-in-goodnotes.png` (Goodnotes 7.1.18 for Mac showing samples/meeting.pdf) |
| 3 | iPad app (SwiftUI, PhotosPicker/camera, PencilKit preview, share sheet) | written, not built | sources parse; this Mac has only Command Line Tools (no iOS SDK). Build in Xcode: `cd App && xcodegen && open InkLift.xcodeproj` |
| 4 | `GoodNotesExporter`: write `.goodnotes` with native ink | done | opens in Goodnotes 7.1.18, strokes render as ink on the template page: `docs/evidence/2026-10-17-goodnotes-native-ink-swift.png`; reference parser decodes all strokes. Editability (lasso/erase) still to be confirmed by hand |

## Layout

```
Package.swift            SwiftPM: InkCore (lib), inklift (CLI for Mac testing), InkCoreTests
Sources/InkCore/Model    Stroke, Page, InkDocument
Sources/InkCore/Pipeline Rectifier, Binarizer, Skeletonizer, Tracer, Smoother, InkPipeline
Sources/InkCore/Export   PDFExporter, GoodNotesExporter
Sources/inklift          CLI: inklift <photo> -o out.pdf|out.goodnotes
Tests/InkCoreTests       synthetic fixtures + pipeline assertions
App/InkLift              iPadOS app sources (Xcode project generated with xcodegen or by hand)
docs/                    format notes from reverse engineering
```

## Decisions

- Native Swift. Vision for document detection, CoreGraphics for PDF, PencilKit for preview.
- Core is a SwiftPM package that builds on macOS with Command Line Tools, so every
  pipeline step is testable here without Xcode.
- `.goodnotes` write side: reference the read-side parser
  https://github.com/Kaih1825/parser-for-goodnotes, confirm with rea against
  /Applications/Goodnotes.app (7.1.18). Time-boxed; findings go in docs/goodnotes-format.md.

## Run (Mac, Command Line Tools are enough)

```
swift build -c release
./scripts/test.sh                                   # 19 tests
.build/release/inklift photo.jpg -o notes.goodnotes # editable ink
.build/release/inklift photo.jpg -o notes.pdf       # flat PDF
.build/release/inklift photo.jpg -o x.pdf --debug-dir dbg   # writes 1-rectified 2-binary 3-skeleton 4-strokes PNGs
open -a Goodnotes notes.goodnotes
```

## Run (iPad app, needs Xcode)

```
brew install xcodegen          # done on this Mac
cd App && xcodegen generate && open InkLift.xcodeproj
```
Select your team under Signing, pick an iPad (or iPad simulator), Run. In the app: choose or
take a photo, check the PencilKit preview, Share as GoodNotes, open in Goodnotes.
