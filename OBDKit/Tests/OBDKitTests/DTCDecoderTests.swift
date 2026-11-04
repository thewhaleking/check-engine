import Testing
@testable import OBDKit

@Suite struct DTCDecoderTests {
    @Test func canWithCount() {
        let codes = DTCDecoder.decode(payload: [0x02, 0x01, 0x33, 0x02, 0x44]).map(\.code)
        #expect(codes == ["P0133", "P0244"])
    }
    @Test func klinePadded() {
        let codes = DTCDecoder.decode(payload: [0x01, 0x33, 0x00, 0x00, 0x00, 0x00]).map(\.code)
        #expect(codes == ["P0133"])
    }
    @Test func allLetters() {
        #expect(DTC(0x03, 0x01).code == "P0301")
        #expect(DTC(0x43, 0x01).code == "C0301")
        #expect(DTC(0x83, 0x01).code == "B0301")
        #expect(DTC(0xC1, 0x00).code == "U0100")
        #expect(DTC(0x14, 0x20).code == "P1420")
    }
    @Test func roundTripFromText() {
        for c in ["P0301", "P0420", "U0100", "C1234", "B2AFF"] {
            #expect(DTC(code: c)?.code == c)
        }
        #expect(DTC(code: "X0000") == nil)
    }
    @Test func framesAcrossECUs() {
        let codes = DTCDecoder.decode(frames: [[0x43, 0x01, 0x03, 0x01], [0x43, 0x02, 0x03, 0x01, 0x04, 0x20]], mode: 0x03).map(\.code)
        #expect(codes == ["P0301", "P0420"])
    }
    @Test func emptyWhenNoCodes() {
        #expect(DTCDecoder.decode(frames: [[0x43, 0x00]], mode: 0x03).isEmpty)
    }
    @Test func descriptions() {
        #expect(DTC(code: "P0420")!.summary == "Catalyst system efficiency below threshold (bank 1)")
        #expect(DTC(code: "P0304")!.summary == "Cylinder 4 misfire detected")
        #expect(DTC(code: "P1FFF")!.summary == nil)
    }
}
