import Foundation

/// Writes a ZIP archive with stored (uncompressed) entries.
struct ZipWriter {
    private struct Entry {
        let name: String
        let crc: UInt32
        let size: UInt32
        let offset: UInt32
    }

    private var body = Data()
    private var entries: [Entry] = []

    init() {}

    mutating func add(_ name: String, _ content: Data) {
        let nameBytes = Data(name.utf8)
        let crc = Self.crc32(content)
        let offset = UInt32(body.count)
        var h = Data()
        h.append(le32(0x0403_4B50))          // local file header signature
        h.append(le16(20))                   // version needed
        h.append(le16(0x0800))               // flags: UTF-8 names
        h.append(le16(0))                    // method: stored
        h.append(le16(0)); h.append(le16(0)) // time, date
        h.append(le32(crc))
        h.append(le32(UInt32(content.count)))
        h.append(le32(UInt32(content.count)))
        h.append(le16(UInt16(nameBytes.count)))
        h.append(le16(0))                    // extra length
        h.append(nameBytes)
        body.append(h)
        body.append(content)
        entries.append(Entry(name: name, crc: crc, size: UInt32(content.count), offset: offset))
    }

    func finish() -> Data {
        var central = Data()
        for e in entries {
            let nameBytes = Data(e.name.utf8)
            central.append(le32(0x0201_4B50))
            central.append(le16(20)); central.append(le16(20))
            central.append(le16(0x0800))
            central.append(le16(0))
            central.append(le16(0)); central.append(le16(0))
            central.append(le32(e.crc))
            central.append(le32(e.size)); central.append(le32(e.size))
            central.append(le16(UInt16(nameBytes.count)))
            central.append(le16(0)); central.append(le16(0)); central.append(le16(0))
            central.append(le16(0))
            central.append(le32(0))
            central.append(le32(e.offset))
            central.append(nameBytes)
        }
        var end = Data()
        end.append(le32(0x0605_4B50))
        end.append(le16(0)); end.append(le16(0))
        end.append(le16(UInt16(entries.count))); end.append(le16(UInt16(entries.count)))
        end.append(le32(UInt32(central.count)))
        end.append(le32(UInt32(body.count)))
        end.append(le16(0))
        return body + central + end
    }

    private func le16(_ v: UInt16) -> Data { var x = v.littleEndian; return Data(bytes: &x, count: 2) }
    private func le32(_ v: UInt32) -> Data { var x = v.littleEndian; return Data(bytes: &x, count: 4) }

    private static let table: [UInt32] = (0..<256).map { i -> UInt32 in
        var c = UInt32(i)
        for _ in 0..<8 { c = (c & 1) != 0 ? 0xEDB8_8320 ^ (c >> 1) : c >> 1 }
        return c
    }

    static func crc32(_ data: Data) -> UInt32 {
        var c: UInt32 = 0xFFFF_FFFF
        for b in data { c = table[Int((c ^ UInt32(b)) & 0xFF)] ^ (c >> 8) }
        return c ^ 0xFFFF_FFFF
    }
}
