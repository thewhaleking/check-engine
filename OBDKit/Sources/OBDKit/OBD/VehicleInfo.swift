import Foundation

public struct VehicleInfo: Sendable, Equatable {
    public var vin: String?
    public var calibrationIDs: [String] = []
    public var elmVersion: String?
    public var protocolName: String?
    public var batteryVoltage: Double?

    public init() {}
}

/// Parsers for Mode 09 responses.
public enum Mode09Parser {
    /// Returns the data bytes for a Mode 09 PID from one or more response frames.
    /// CAN (assembled): one frame `49 <pid> <count> <data...>`.
    /// K-line: several frames `49 <pid> <seq> <4 data bytes>`, ordered by `seq`.
    public static func dataBytes(frames: [[UInt8]], pid: UInt8) -> [UInt8] {
        let matching = frames.filter { $0.count >= 3 && $0[0] == 0x49 && $0[1] == pid }
        guard !matching.isEmpty else { return [] }
        if matching.count == 1, matching[0].count > 7 {
            return Array(matching[0].dropFirst(3))
        }
        return matching.sorted { $0[2] < $1[2] }.flatMap { $0.dropFirst(3) }
    }

    public static func vin(frames: [[UInt8]]) -> String? {
        let bytes = dataBytes(frames: frames, pid: 0x02).filter { $0 != 0 }
        guard bytes.count >= 17 else { return nil }
        let text = String(decoding: bytes.suffix(17), as: UTF8.self)
        return text.allSatisfy { $0.isLetter || $0.isNumber } ? text : nil
    }

    public static func calibrationIDs(frames: [[UInt8]]) -> [String] {
        let bytes = dataBytes(frames: frames, pid: 0x04)
        var ids: [String] = []
        var i = 0
        while i < bytes.count {
            let chunk = bytes[i..<min(i + 16, bytes.count)].filter { $0 != 0 }
            i += 16
            let s = String(decoding: chunk, as: UTF8.self).trimmingCharacters(in: .whitespaces)
            if !s.isEmpty { ids.append(s) }
        }
        return ids
    }
}
