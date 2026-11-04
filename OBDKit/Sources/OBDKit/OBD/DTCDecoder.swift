import Foundation

public enum DTCDecoder {
    /// Decodes the payload after the mode byte of a 43/47/4A response.
    /// CAN responses carry a leading count byte (odd payload length);
    /// K-line responses are padded to three codes with 00 00.
    public static func decode(payload: [UInt8]) -> [DTC] {
        var bytes = payload
        if bytes.count % 2 == 1 { bytes.removeFirst() }
        var out: [DTC] = []
        var i = 0
        while i + 1 < bytes.count {
            let a = bytes[i], b = bytes[i + 1]
            i += 2
            if a == 0, b == 0 { continue }
            out.append(DTC(a, b))
        }
        return out
    }

    /// Decodes all frames from a DTC request, dropping duplicates across ECUs.
    public static func decode(frames: [[UInt8]], mode: UInt8) -> [DTC] {
        var seen = Set<String>()
        var out: [DTC] = []
        for frame in frames where frame.first == mode | 0x40 {
            for dtc in decode(payload: Array(frame.dropFirst())) where seen.insert(dtc.code).inserted {
                out.append(dtc)
            }
        }
        return out
    }
}
