"""Prototype .goodnotes writer (template based).

usage: gn_write_proto.py <template.goodnotes> <strokes.json> <out.goodnotes> [--stored|--lz4]

strokes.json is the inklift `-o x.json` output (InkDocument). Only the first page is used.
The template's notes/<uuid> stream is replaced by our strokes written as type-24 ballpoint
records. Everything else in the template is kept as-is.
"""
import json, struct, sys, uuid, zipfile, random, time, io

# --- protobuf wire -----------------------------------------------------------

def varint(n: int) -> bytes:
    out = bytearray()
    while True:
        b = n & 0x7F
        n >>= 7
        if n:
            out.append(b | 0x80)
        else:
            out.append(b)
            return bytes(out)

def key(field: int, wt: int) -> bytes:
    return varint((field << 3) | wt)

def f_varint(field: int, n: int) -> bytes:
    return key(field, 0) + varint(n)

def f_bytes(field: int, b: bytes) -> bytes:
    return key(field, 2) + varint(len(b)) + b

def f_str(field: int, s: str) -> bytes:
    return f_bytes(field, s.encode("utf-8"))

def f_fixed32f(field: int, x: float) -> bytes:
    return key(field, 5) + struct.pack("<f", x)

def record(msg: bytes) -> bytes:
    return varint(len(msg)) + msg

# --- TPL ---------------------------------------------------------------------

def fbits(x: float) -> int:
    return struct.unpack("<I", struct.pack("<f", x))[0]

def tpl_ballpoint(width: float, points: list[tuple[float, float]]) -> bytes:
    """vuA(v)A(S(uu))A(S(uuuu))vA(f) with points chained two per tuple."""
    fmt = b"vuA(v)A(S(uu))A(S(uuuu))vA(f)\0"
    body = bytearray()
    body += struct.pack("<H", 2)                 # v0: version
    body += struct.pack("<I", fbits(width))      # v1: width (float bits)
    # pairs after the start point
    rest = points[1:]
    if len(rest) % 2 == 1:
        rest = rest + [rest[-1]]
    quads = [(rest[i][0], rest[i][1], rest[i + 1][0], rest[i + 1][1]) for i in range(0, len(rest), 2)]
    flags = [0] + [1] * len(quads)               # v2: pen down flags, one per quad + 1
    body += struct.pack("<I", len(flags)) + b"".join(struct.pack("<H", f) for f in flags)
    body += struct.pack("<I", 1) + struct.pack("<II", fbits(points[0][0]), fbits(points[0][1]))  # v3
    body += struct.pack("<I", len(quads))
    for q in quads:
        body += struct.pack("<IIII", *(fbits(c) for c in q))                                    # v4
    body += struct.pack("<H", 1)                 # v5
    body += struct.pack("<I", 0)                 # v6: A(f) empty
    size = 8 + len(fmt) + len(body)
    return b"tpl\0" + struct.pack("<I", size) + fmt + bytes(body)

# --- Apple framed LZ4 --------------------------------------------------------

def lz4_block_compress(src: bytes) -> bytes:
    """Minimal LZ4 block encoder (greedy hash match). Valid LZ4 block format."""
    n = len(src)
    out = bytearray()
    MINMATCH = 4
    table = {}
    anchor = 0
    i = 0
    def emit(lit_start, lit_end, match_len, offset):
        lit_len = lit_end - lit_start
        tok_l = 15 if lit_len >= 15 else lit_len
        if match_len is None:
            out.append(tok_l << 4)
        else:
            ml = match_len - MINMATCH
            tok_m = 15 if ml >= 15 else ml
            out.append((tok_l << 4) | tok_m)
        if lit_len >= 15:
            r = lit_len - 15
            while r >= 255:
                out.append(255); r -= 255
            out.append(r)
        out.extend(src[lit_start:lit_end])
        if match_len is not None:
            out.extend(struct.pack("<H", offset))
            ml = match_len - MINMATCH
            if ml >= 15:
                r = ml - 15
                while r >= 255:
                    out.append(255); r -= 255
                out.append(r)
    # last 5 bytes must be literals; last match must start 12 bytes before end
    limit = n - 12
    while i < limit:
        h = src[i:i + 4]
        cand = table.get(h)
        table[h] = i
        if cand is not None and i - cand <= 0xFFFF and src[cand:cand + 4] == h:
            # extend
            m = 4
            while i + m < n - 5 and src[cand + m] == src[i + m]:
                m += 1
            emit(anchor, i, m, i - cand)
            i += m
            anchor = i
            continue
        i += 1
    emit(anchor, n, None, 0)
    return bytes(out)

def apple_lz4(payload: bytes, stored: bool) -> bytes:
    if stored:
        return b"bv4-" + struct.pack("<II", len(payload), len(payload)) + payload + b"bv4$"
    comp = lz4_block_compress(payload)
    return b"bv41" + struct.pack("<II", len(payload), len(comp)) + comp + b"bv4$"

# --- records -----------------------------------------------------------------

DEVICE_ID = 1184897455800006800   # copied from template (f8 / f14 constants)
APP_BUILD = 5381
TYPE_BALLPOINT = 24

def stroke_records(points_gn, width_gn, color, counter, stored):
    sid = str(uuid.uuid4()).upper()
    pen_uuid = str(uuid.uuid4()).upper()
    rnd = random.getrandbits(32)
    ts = int(time.time() * 1000)
    meta = (
        f_str(1, sid)
        + f_bytes(2, f_varint(1, 2) + f_varint(2, rnd))
        + f_str(6, pen_uuid)
        + f_varint(8, DEVICE_ID)
        + f_varint(9, counter)
        + f_varint(14, APP_BUILD)
        + f_varint(16, TYPE_BALLPOINT)
    )
    tpl = tpl_ballpoint(width_gn, points_gn)
    data = apple_lz4(tpl, stored)
    rgba = f_fixed32f(1, color[0]) + f_fixed32f(2, color[1]) + f_fixed32f(3, color[2]) + f_fixed32f(4, color[3])
    inner = (
        f_str(1, sid)
        + f_bytes(2, data)
        + f_bytes(4, rgba)
        + f_bytes(6, b"")
        + f_bytes(7, f_bytes(1, f_varint(1, counter) + f_varint(2, ts)))
        + f_bytes(9, b"")
        + f_bytes(15, f_varint(1, 2) + f_varint(2, rnd))
        + f_bytes(20, b"")
        + f_varint(21, TYPE_BALLPOINT)
    )
    stroke = f_bytes(7, inner)
    return record(meta) + record(stroke)

GN_PER_PT = 132.0 / 72.0

def main():
    template, strokes_json, out = sys.argv[1], sys.argv[2], sys.argv[3]
    stored = "--lz4" not in sys.argv
    doc = json.load(open(strokes_json))
    page = doc["pages"][0]
    pw, ph = page["size"]["width"], page["size"]["height"]

    zin = zipfile.ZipFile(template)
    names = zin.namelist()
    note_member = next(n for n in names if n.startswith("notes/"))

    # Template page size in GN units (from the PDF MediaBox we know: 455.04 x 588.45 pt).
    tpl_w_pt, tpl_h_pt = 455.04, 588.45
    scale = min(tpl_w_pt / pw, tpl_h_pt / ph)
    offx = (tpl_w_pt - pw * scale) / 2
    offy = (tpl_h_pt - ph * scale) / 2

    stream = bytearray()
    counter = 3653600
    for s in page["strokes"]:
        pts = [((offx + p["x"] * scale) * GN_PER_PT, (offy + p["y"] * scale) * GN_PER_PT) for p in s["points"]]
        if len(pts) == 1:
            pts = [pts[0], (pts[0][0] + 0.01, pts[0][1] + 0.01)]
        width = sum(p["width"] for p in s["points"]) / len(s["points"]) * scale * GN_PER_PT
        c = s["color"]
        counter += 1
        stream += stroke_records(pts, max(0.5, width), (c["r"], c["g"], c["b"], c["a"]), counter, stored)

    zout = zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED)
    for n in names:
        info = zin.getinfo(n)
        if n == note_member:
            zout.writestr(n, bytes(stream))
        else:
            zout.writestr(info, zin.read(n))
    zout.close()
    print(f"wrote {out}: {len(page['strokes'])} strokes, {len(stream)} bytes note stream, lz4={'stored' if stored else 'compressed'}")

main()
