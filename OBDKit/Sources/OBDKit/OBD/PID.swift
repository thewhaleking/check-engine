import Foundation

public struct PID: Hashable, Codable, Sendable, Comparable, CustomStringConvertible {
    public let mode: UInt8
    public let id: UInt8

    public init(mode: UInt8, id: UInt8) {
        self.mode = mode
        self.id = id
    }

    public static func mode01(_ id: UInt8) -> PID { PID(mode: 0x01, id: id) }

    /// Command text as sent to the ELM327, e.g. "010C".
    public var command: String { String(format: "%02X%02X", mode, id) }
    public var description: String { command }

    public static func < (lhs: PID, rhs: PID) -> Bool {
        (lhs.mode, lhs.id) < (rhs.mode, rhs.id)
    }
}

public struct PIDDescriptor: Identifiable, Sendable {
    public let pid: PID
    public var id: PID { pid }
    public let name: String
    public let shortName: String
    public let unit: String
    public let byteCount: Int
    public let range: ClosedRange<Double>
    public let decode: @Sendable ([UInt8]) -> Double

    public init(_ id: UInt8, name: String, shortName: String, unit: String, bytes: Int,
                range: ClosedRange<Double>, decode: @escaping @Sendable ([UInt8]) -> Double) {
        self.pid = .mode01(id)
        self.name = name
        self.shortName = shortName
        self.unit = unit
        self.byteCount = bytes
        self.range = range
        self.decode = decode
    }

    /// Decodes a Mode 01 response payload (bytes after "41 <pid>"). Returns nil if too short.
    public func value(from payload: [UInt8]) -> Double? {
        guard payload.count >= byteCount else { return nil }
        return decode(Array(payload.prefix(byteCount)))
    }
}
