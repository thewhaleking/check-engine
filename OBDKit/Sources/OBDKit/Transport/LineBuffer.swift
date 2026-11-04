import Foundation

/// Accumulates bytes and splits them into ELM327 lines.
struct LineBuffer: Sendable {
    private var bytes: [UInt8] = []

    mutating func append(_ new: [UInt8]) { bytes.append(contentsOf: new) }
    mutating func append(_ new: UnsafeBufferPointer<UInt8>) { bytes.append(contentsOf: new) }

    var isEmpty: Bool { bytes.isEmpty }

    mutating func clear() { bytes.removeAll() }

    /// Next complete line, or the trailing prompt fragment, or nil.
    mutating func nextLine() -> String? {
        if let i = bytes.firstIndex(of: 0x0D) {
            let line = Array(bytes[..<i])
            bytes.removeFirst(i + 1)
            return decode(line)
        }
        if bytes.last == UInt8(ascii: ">") {
            let line = bytes
            bytes.removeAll()
            return decode(line)
        }
        return nil
    }

    private func decode(_ raw: [UInt8]) -> String {
        let cleaned = raw.filter { $0 != 0x0A && $0 != 0 }
        return String(decoding: cleaned, as: UTF8.self)
    }
}
