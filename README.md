# InkLift

Photograph a page of handwritten notes. Get a GoodNotes document with the handwriting as
real, editable ink.

```
photo -> find page (Vision) -> flatten -> binarize (Sauvola) -> thin (Zhang-Suen)
      -> trace centerlines -> smooth -> strokes -> .goodnotes (or PDF)
```

- `Sources/InkCore` -- the pipeline and exporters. Pure Swift, Apple frameworks only.
- `Sources/inklift` -- macOS CLI for testing on photos.
- `App/` -- iPadOS SwiftUI app (xcodegen spec), PencilKit preview, share sheet.
- `docs/goodnotes-format.md` -- what the writer puts in a `.goodnotes` file and why.

See `PLAN.md` for status and run instructions.

The `.goodnotes` template and dump scripts build on
[parser-for-goodnotes](https://github.com/Kaih1825/parser-for-goodnotes) (MIT). Not
affiliated with Goodnotes Limited.
