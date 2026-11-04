import Testing
@testable import OBDKit

@Suite struct PIDDecodeTests {
    @Test func rpm() {
        let d = PIDRegistry.descriptor(for: .mode01(0x0C))!
        #expect(d.value(from: [0x1A, 0xF8]) == 1726)
    }
    @Test func coolant() {
        #expect(PIDRegistry.descriptor(for: .mode01(0x05))!.value(from: [0x7B]) == 83)
    }
    @Test func throttle() {
        let v = PIDRegistry.descriptor(for: .mode01(0x11))!.value(from: [0xFF])!
        #expect(abs(v - 100) < 0.001)
    }
    @Test func maf() {
        #expect(PIDRegistry.descriptor(for: .mode01(0x10))!.value(from: [0x01, 0xF4]) == 5)
    }
    @Test func shortPayloadIsNil() {
        #expect(PIDRegistry.descriptor(for: .mode01(0x0C))!.value(from: [0x1A]) == nil)
    }
    @Test func commandText() {
        #expect(PID.mode01(0x0C).command == "010C")
    }
    @Test func supportedMask() {
        let set = SupportedPIDs.decode(base: 0x00, mask: [0xBE, 0x3E, 0xB8, 0x11])
        let expected: Set<PID> = Set([0x01, 0x03, 0x04, 0x05, 0x06, 0x07, 0x0B, 0x0C, 0x0D, 0x0E, 0x0F, 0x11, 0x13, 0x14, 0x15, 0x1C, 0x20].map(PID.mode01))
        #expect(set == expected)
        #expect(SupportedPIDs.hasNextRange([0xBE, 0x3E, 0xB8, 0x11]))
        #expect(!SupportedPIDs.hasNextRange([0xBE, 0x3E, 0xB8, 0x10]))
    }
    @Test func supportedMaskSecondRange() {
        let set = SupportedPIDs.decode(base: 0x20, mask: [0x80, 0x00, 0x00, 0x01])
        #expect(set == Set([PID.mode01(0x21), PID.mode01(0x40)]))
    }
}
