import Foundation

/// Writes a `.goodnotes` document. Format notes: docs/goodnotes-format.md.
public struct GoodNotesExporter {
    public enum Error: Swift.Error { case notImplemented }

    public init() {}

    public func write(_ document: InkDocument, to url: URL) throws {
        throw Error.notImplemented
    }
}
