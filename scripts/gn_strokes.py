"""Dump stroke TPL payloads of a .goodnotes page.

usage: gn_strokes.py <archive> <member> [record_index ...]
"""
import sys, zipfile, struct
from goodnotes_re.wire import decode_delimited_messages, decode_message
from goodnotes_re.compression import decode_apple_lz4
from goodnotes_re.tpl import decode_tpl

def f32(u):
    return struct.unpack("<f", struct.pack("<I", u))[0]

def show(v, depth=0):
    if isinstance(v, (list, tuple)):
        if len(v) > 12 and all(not isinstance(x, (list, tuple)) for x in v):
            return f"[{len(v)} values: {', '.join(str(x) for x in v[:8])} ...]"
        if len(v) > 6 and all(isinstance(x, (list, tuple)) for x in v):
            return f"[{len(v)} tuples: " + ", ".join(show(x, depth+1) for x in v[:4]) + " ...]"
        return "(" + ", ".join(show(x, depth+1) for x in v) + ")"
    if isinstance(v, int) and v > 0x3a000000 and v < 0x4b000000:
        return f"{f32(v):.3f}"
    return str(v)

def main():
    archive, member = sys.argv[1], sys.argv[2]
    wanted = [int(x) for x in sys.argv[3:]]
    data = zipfile.ZipFile(archive).read(member)
    msgs = decode_delimited_messages(data)
    meta = {}
    for i, m in enumerate(msgs):
        f1 = m.by_number(1)
        f16 = m.by_number(16)
        if f1 and isinstance(f1[0].value, bytes) and len(f1[0].value) == 36:
            meta[f1[0].value.decode()] = (i, f16[0].value if f16 else None, bool(m.by_number(3)))
    for i, m in enumerate(msgs):
        if wanted and i not in wanted:
            continue
        f7 = m.by_number(7)
        if not f7 or not isinstance(f7[0].value, bytes):
            continue
        inner = decode_message(f7[0].value)
        uuid = inner.by_number(1)[0].value.decode()
        f2 = inner.by_number(2)
        if not f2:
            continue
        raw = f2[0].value
        if b"bv41" not in raw and b"bv4-" not in raw:
            continue
        payload, consumed = decode_apple_lz4(raw)
        trailer = raw[consumed:]
        t = decode_tpl(payload)
        mi = meta.get(uuid)
        print(f"--- record {i} uuid={uuid} meta_record={mi[0] if mi else None} type16={mi[1] if mi else None} erased={mi[2] if mi else None}")
        print(f"    lz4 raw={len(raw)} tpl={len(payload)} trailer={len(trailer)} trailer_hex={trailer.hex()}")
        print(f"    format: {t.format}")
        for k, v in enumerate(t.values):
            print(f"    v[{k}] = {show(v)}")
        extras = [f"f{f.number}={f.value if not isinstance(f.value, bytes) else f.value[:16].hex()}" for f in inner.fields if f.number not in (1, 2)]
        print("    other fields:", "; ".join(extras))

main()
