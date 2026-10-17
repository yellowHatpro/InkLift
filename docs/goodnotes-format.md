# .goodnotes format notes (write side)

What InkLift writes, and where each fact came from. Verified against Goodnotes 7.1.18
for Mac on 2026-10-17: files written by `GoodNotesExporter` open and render as native ink
(`evidence/2026-10-17-goodnotes-native-ink-swift.png`).

Sources:
- Read-side parser and wiki: https://github.com/Kaih1825/parser-for-goodnotes (MIT).
  Its `web/assets/ex2.goodnotes` sample supplied the template's index and event records.
- Our own dumps: `scripts/gn_records.py`, `scripts/gn_strokes.py` (need the parser's venv).

## Container

ZIP archive. Members in the template document:

| Member | Content | InkLift |
|---|---|---|
| `schema.pb` | protobuf, field 1 varint = 25 | copied |
| `index.notes.pb` | f1 page uuid, f2 `notes/<uuid>` | copied |
| `index.attachments.pb` | f1 attachment uuid, f2 `attachments/<uuid>` | copied |
| `index.search.pb` | uuid -> `search/<uuid>` map | copied |
| `index.events.pb` | event log: document create (f30, title), attachment add (f6), page add (f2, page size 834.2 x 1079 GN units), template (f54), ... | copied |
| `attachments/<uuid>` | background PDF, MediaBox 455.04 x 588.45 pt | our own dot grid, `scripts/make-template-pdf.swift` (verified: Goodnotes imports it) |
| `search/<page uuid>` | handwriting search index | 5-byte stub `04 10 01 1a 00` |
| `notes/<page uuid>` | stroke stream | written |
| `thumbnail.jpg` | page preview | rendered from strokes |
| `document.info.pb` | empty | empty |

The ZIP uses stored entries. Goodnotes accepts that.

## Coordinates

GN units per PDF point = 132 / 72. The template page is 455.04 x 588.45 pt, so 834.24 x
1078.8 GN units, which matches the page-size pair in the page-add event (834.2, 1079).
Origin top-left, y down.

## Stroke stream `notes/<uuid>`

Sequence of varint-length-prefixed protobuf records. Each stroke is two records:

Metadata record:
```
f1  string  stroke uuid
f2  msg     { f1 varint 2, f2 varint random32 }      clock / version stamp
f6  string  uuid                                     pen / layer id
f8  varint  1184897455800006800                      device tag (copied)
f9  varint  counter                                  increments per stroke
f14 varint  5381                                     app tag (copied)
f16 varint  24                                       element type: 24 = ballpoint
```

Stroke record:
```
f7 msg {
  f1  string  stroke uuid (same as above)
  f2  bytes   Apple framed LZ4 (bv41 ... bv4$) of a TPL image
  f4  msg     { f1..f4 fixed32 } RGBA 0..1
  f6  bytes   empty
  f7  msg     { f1 msg { f1 varint counter, f2 varint unix-ms } }
  f9  bytes   empty
  f15 msg     same clock as metadata f2
  f20 bytes   empty
  f21 varint  24
}
```

Erased strokes carry `f3 varint 1` in the metadata record; InkLift never writes it.

## TPL image (ballpoint)

Format string `vuA(v)A(S(uu))A(S(uuuu))vA(f)`, little-endian:

| value | type | content |
|---|---|---|
| v0 | u16 | 2 |
| v1 | u32 | pen width, float32 bits, GN units |
| v2 | A(u16) | pen-down flags: `[0, 1, 1, ...]`, length = quads + 1 |
| v3 | A(S(u32,u32)) | one start point (x, y) as float32 bits |
| v4 | A(S(u32 x4)) | (x1, y1, x2, y2): two points per tuple, chained |
| v5 | u16 | 1 |
| v6 | A(f64) | empty |

Header: `tpl\0`, u32 total image size, format string, `\0`, body.

The LZ4 wrapper is what `NSData.compressed(using: .lz4)` produces (verified: output
begins `bv41` and ends `bv4$`, and the reference parser decodes it).

## Not done

- Multiple pages: the template has one page. More pages need new page uuids in
  `index.notes.pb`, `index.search.pb` and page-add events in `index.events.pb`.
- Document title: lives in the events log (f30/f31). Goodnotes names the imported
  document after the file name, so InkLift leaves it.
- Pressure: ballpoint has a single width. Pressure-carrying formats (11-tuple) exist but
  are not needed for photo-traced ink.
