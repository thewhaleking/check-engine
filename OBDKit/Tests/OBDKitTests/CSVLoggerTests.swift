import Foundation
import Testing
@testable import OBDKit

@Suite struct CSVLoggerTests {
    @Test func writesHeaderAndRows() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("obdkit-\(UUID().uuidString).csv")
        defer { try? FileManager.default.removeItem(at: url) }
        let cols = [PIDRegistry.descriptor(for: .mode01(0x0C))!, PIDRegistry.descriptor(for: .mode01(0x05))!]
        let logger = try CSVLogger(url: url, columns: cols, includeVoltage: true)
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        try await logger.append(LiveSample(time: t0, values: [.mode01(0x0C): 1726, .mode01(0x05): 83.5], voltage: 14.1))
        try await logger.append(LiveSample(time: t0.addingTimeInterval(0.5), values: [.mode01(0x0C): 1800.25], voltage: nil))
        try await logger.close()
        let text = try String(contentsOf: url, encoding: .utf8)
        let lines = text.split(separator: "\n").map(String.init)
        #expect(lines.count == 3)
        #expect(lines[0] == "timestamp,unix_time,Engine RPM (rpm),Coolant Temperature (°C),Battery (V)")
        #expect(lines[1].hasSuffix(",1700000000.000,1726,83.5,14.1"))
        #expect(lines[2].hasSuffix(",1700000000.500,1800.25,,"))
        #expect(await logger.rowCount == 2)
        #expect(text.hasSuffix("\n"))
    }
}
