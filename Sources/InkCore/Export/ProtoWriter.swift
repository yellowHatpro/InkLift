import Foundation

/// Protobuf wire-format encoder. Only what the GoodNotes writer needs.
struct ProtoWriter {
    private(set) var data = Data()

    init() {}

    static func varint(_ value: UInt64) -> Data {
        var v = value
        var out = Data()
        while true {
            let byte = UInt8(v & 0x7F)
            v >>= 7
            if v == 0 {
                out.append(byte)
                return out
            }
            out.append(byte | 0x80)
        }
    }

    private mutating func key(_ field: Int, wireType: UInt64) {
        data.append(Self.varint(UInt64(field) << 3 | wireType))
    }

    mutating func varint(_ field: Int, _ value: UInt64) {
        key(field, wireType: 0)
        data.append(Self.varint(value))
    }

    mutating func bytes(_ field: Int, _ value: Data) {
        key(field, wireType: 2)
        data.append(Self.varint(UInt64(value.count)))
        data.append(value)
    }

    mutating func string(_ field: Int, _ value: String) {
        bytes(field, Data(value.utf8))
    }

    mutating func message(_ field: Int, _ inner: ProtoWriter) {
        bytes(field, inner.data)
    }

    mutating func fixed32(_ field: Int, _ value: Float) {
        key(field, wireType: 5)
        var bits = value.bitPattern.littleEndian
        data.append(Data(bytes: &bits, count: 4))
    }

    /// Varint length prefix followed by the message. Streams are sequences of these.
    func record() -> Data {
        Self.varint(UInt64(data.count)) + data
    }
}
