import Testing
@testable import OBDKit

@Suite struct HexTests {
    @Test func parsesSpacedAndPacked() {
        #expect(Hex.bytes(from: "41 0C 1A F8") == [0x41, 0x0C, 0x1A, 0xF8])
        #expect(Hex.bytes(from: "410c1af8") == [0x41, 0x0C, 0x1A, 0xF8])
    }
    @Test func rejectsGarbage() {
        #expect(Hex.bytes(from: "NO DATA") == nil)
        #expect(Hex.bytes(from: "41 0") == nil)
    }
    @Test func formats() {
        #expect(Hex.string([0x41, 0x0C]) == "41 0C")
    }
}
