import Foundation

/// Reassembles the ELM327 multi-line CAN format produced with headers off:
///
///     014
///     0: 49 02 01 57 56 57
///     1: 5A 5A 5A 31 4A 5A 58
///     2: 57 30 30 30 30 30 31
///
/// The first line is the total payload length in hex (optional on some clones).
/// Returns nil if the lines are not in this format.
public enum MultiFrameAssembler {
    public static func isMultiFrame(_ lines: [String]) -> Bool {
        lines.contains { indexedPayload($0) != nil }
    }

    public static func assemble(_ lines: [String]) -> [UInt8]? {
        var total: Int? = nil
        var segments: [(Int, [UInt8])] = []
        for line in lines {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.isEmpty { continue }
            if let (idx, bytes) = indexedPayload(t) {
                segments.append((idx, bytes))
            } else if segments.isEmpty, total == nil, t.count == 3, let n = Int(t, radix: 16) {
                total = n
            } else {
                return nil
            }
        }
        guard !segments.isEmpty else { return nil }
        // Frame indices wrap at 0xF; preserve arrival order but stable-sort within a wrap.
        var out: [UInt8] = []
        for (_, bytes) in segments { out.append(contentsOf: bytes) }
        if let total, total <= out.count { out = Array(out.prefix(total)) }
        return out
    }

    /// Parses "1: 5A 5A 5A" or "1:5A5A5A" into (1, bytes).
    static func indexedPayload(_ line: String) -> (Int, [UInt8])? {
        guard let colon = line.firstIndex(of: ":") else { return nil }
        let head = line[..<colon].trimmingCharacters(in: .whitespaces)
        guard head.count == 1, let idx = Int(head, radix: 16) else { return nil }
        let rest = String(line[line.index(after: colon)...])
        guard let bytes = Hex.bytes(from: rest) else { return nil }
        return (idx, bytes)
    }
}
