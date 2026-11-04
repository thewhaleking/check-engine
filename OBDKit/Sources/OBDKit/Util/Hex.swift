import Foundation

public enum Hex {
    /// Parses a hex string such as "41 0C 1A F8" or "410C1AF8" into bytes.
    /// Returns nil if the string contains a non-hex character or an odd number of digits.
    public static func bytes(from text: String) -> [UInt8]? {
        var out: [UInt8] = []
        var pending: UInt8? = nil
        for ch in text.utf8 {
            let v: UInt8
            switch ch {
            case UInt8(ascii: "0")...UInt8(ascii: "9"): v = ch - UInt8(ascii: "0")
            case UInt8(ascii: "a")...UInt8(ascii: "f"): v = ch - UInt8(ascii: "a") + 10
            case UInt8(ascii: "A")...UInt8(ascii: "F"): v = ch - UInt8(ascii: "A") + 10
            case UInt8(ascii: " "), UInt8(ascii: "\t"): continue
            default: return nil
            }
            if let hi = pending {
                out.append(hi << 4 | v)
                pending = nil
            } else {
                pending = v
            }
        }
        return pending == nil ? out : nil
    }

    /// True if every non-space character is a hex digit and there is at least one digit.
    public static func isHex(_ text: String) -> Bool {
        let t = text.replacingOccurrences(of: " ", with: "")
        return !t.isEmpty && t.utf8.allSatisfy { Hex.isHexDigit($0) }
    }

    static func isHexDigit(_ c: UInt8) -> Bool {
        switch c {
        case UInt8(ascii: "0")...UInt8(ascii: "9"),
             UInt8(ascii: "a")...UInt8(ascii: "f"),
             UInt8(ascii: "A")...UInt8(ascii: "F"): return true
        default: return false
        }
    }

    public static func string(_ bytes: [UInt8], separator: String = " ") -> String {
        bytes.map { String(format: "%02X", $0) }.joined(separator: separator)
    }
}
