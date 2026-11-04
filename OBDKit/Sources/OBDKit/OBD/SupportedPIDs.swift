import Foundation

public enum SupportedPIDs {
    /// Decodes the 4-byte bitmask returned by PID `base` (0x00, 0x20, 0x40, ...).
    /// Bit 7 of byte 0 is PID base+1; bit 0 of byte 3 is PID base+0x20.
    public static func decode(base: UInt8, mask: [UInt8], mode: UInt8 = 0x01) -> Set<PID> {
        var out = Set<PID>()
        for (byteIndex, byte) in mask.prefix(4).enumerated() {
            for bit in 0..<8 where byte & (0x80 >> bit) != 0 {
                let offset = byteIndex * 8 + bit + 1
                let id = Int(base) + offset
                if id <= 0xFF { out.insert(PID(mode: mode, id: UInt8(id))) }
            }
        }
        return out
    }

    /// True if the mask says the next range (base+0x20) is supported.
    public static func hasNextRange(_ mask: [UInt8]) -> Bool {
        mask.count >= 4 && mask[3] & 0x01 != 0
    }
}
