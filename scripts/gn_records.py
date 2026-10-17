"""Summarize the records of a .goodnotes page stream (notes/<uuid>) or index.events.pb.

usage: gn_records.py <archive.goodnotes> <member> [max_records] [--full N]
"""
import sys, zipfile, base64
from goodnotes_re.wire import decode_delimited_messages, decode_message, try_decode_message

def short(v, n=40):
    if isinstance(v, bytes):
        try:
            s = v.decode("utf-8")
            if s.isprintable():
                return repr(s[:n])
        except UnicodeDecodeError:
            pass
        tag = ""
        if b"bv41" in v: tag = " <LZ4>"
        if v[:4] == b"%PDF": tag = " <PDF>"
        return f"bytes[{len(v)}]{tag} {v[:12].hex()}"
    return v

def dump(msg, indent, depth=0, maxdepth=3):
    for f in msg.fields:
        v = f.value
        if isinstance(v, bytes) and depth < maxdepth and len(v) > 0:
            inner = try_decode_message(v)
            # treat as nested only if it decodes AND is not a plain uuid/string
            is_text = False
            try:
                s = v.decode("utf-8"); is_text = s.isprintable()
            except UnicodeDecodeError:
                pass
            if inner is not None and not is_text and len(inner.fields) > 0 and all(not isinstance(x.value, bytes) or len(x.value) < 5000 for x in inner.fields):
                print(f"{indent}f{f.number} ({f.wire_type.name.lower()}) msg[{len(v)}] {{")
                dump(inner, indent + "  ", depth + 1, maxdepth)
                print(f"{indent}}}")
                continue
        if f.wire_type.name == "FIXED32":
            import struct
            fl = struct.unpack("<f", struct.pack("<I", v))[0]
            print(f"{indent}f{f.number} (fixed32) {v} = {fl:.4g}")
        elif f.wire_type.name == "FIXED64":
            import struct
            fl = struct.unpack("<d", struct.pack("<Q", v))[0]
            print(f"{indent}f{f.number} (fixed64) {v} = {fl:.6g}")
        else:
            print(f"{indent}f{f.number} ({f.wire_type.name.lower()}) {short(v)}")

def main():
    archive, member = sys.argv[1], sys.argv[2]
    maxr = int(sys.argv[3]) if len(sys.argv) > 3 and not sys.argv[3].startswith("--") else 10**9
    full = None
    if "--full" in sys.argv:
        full = int(sys.argv[sys.argv.index("--full") + 1])
    data = zipfile.ZipFile(archive).read(member)
    msgs = decode_delimited_messages(data)
    print(f"{member}: {len(msgs)} records, {len(data)} bytes")
    for i, m in enumerate(msgs[:maxr]):
        size = sum(len(f.raw) for f in m.fields)
        sig = ",".join(f"f{f.number}{'L' if isinstance(f.value, bytes) else ''}" for f in m.fields)
        print(f"--- record {i} [{size} B] {sig}")
        if full is None or i == full:
            dump(m, "  ", maxdepth=4 if full is not None else 2)

main()
