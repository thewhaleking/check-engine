import Foundation

public enum DTCKind: String, Sendable, CaseIterable, Identifiable {
    case stored, pending, permanent
    public var id: String { rawValue }

    public var mode: UInt8 {
        switch self {
        case .stored: return 0x03
        case .pending: return 0x07
        case .permanent: return 0x0A
        }
    }

    public var title: String {
        switch self {
        case .stored: return "Stored"
        case .pending: return "Pending"
        case .permanent: return "Permanent"
        }
    }
}

public struct DTC: Hashable, Codable, Sendable, Identifiable, CustomStringConvertible {
    public let code: String
    public let bytes: [UInt8]
    public var id: String { code }
    public var description: String { code }

    public init(code: String, bytes: [UInt8]) {
        self.code = code
        self.bytes = bytes
    }

    /// Builds a DTC from its two raw bytes.
    public init(_ a: UInt8, _ b: UInt8) {
        let letters: [Character] = ["P", "C", "B", "U"]
        let letter = letters[Int(a >> 6)]
        let d1 = (a >> 4) & 0x03
        let d2 = a & 0x0F
        self.code = "\(letter)\(d1)" + String(format: "%X%02X", d2, b)
        self.bytes = [a, b]
    }

    /// Builds a DTC from text such as "P0301". Returns nil if malformed.
    public init?(code: String) {
        let c = code.uppercased()
        guard c.count == 5, let letter = c.first,
              let prefix = ["P": 0, "C": 1, "B": 2, "U": 3][String(letter)],
              let d1 = Int(String(c[c.index(c.startIndex, offsetBy: 1)])), d1 < 4,
              let rest = Int(c.dropFirst(2), radix: 16) else { return nil }
        let a = UInt8(prefix << 6 | d1 << 4 | (rest >> 8))
        let b = UInt8(rest & 0xFF)
        self.init(a, b)
    }

    public var summary: String? { DTCDescriptions.lookup(code) }
}
