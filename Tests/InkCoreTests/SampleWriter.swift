import Testing
import Foundation
import CoreGraphics
@testable import InkCore

/// Writes fixture photos to `$INKLIFT_SAMPLES_DIR` for manual runs of the CLI.
/// Skipped unless the variable is set.
struct SampleWriter {
    @Test func writeSamples() throws {
        guard let dir = ProcessInfo.processInfo.environment["INKLIFT_SAMPLES_DIR"] else { return }
        let url = URL(fileURLWithPath: dir)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try ImageFile.savePNG(Fixture.handwriting("Hello notes", noise: 10), to: url.appendingPathComponent("hello.png"))
        try ImageFile.savePNG(Fixture.handwriting("Meeting 17 Oct: ship InkLift", size: 1400, fontSize: 80, noise: 12), to: url.appendingPathComponent("meeting.png"))
        try ImageFile.savePNG(Fixture.cross(), to: url.appendingPathComponent("cross.png"))
        try ImageFile.savePNG(Fixture.circle(), to: url.appendingPathComponent("circle.png"))
    }
}
