import Testing
@testable import OBDKit

@Suite struct VehicleInfoTests {
    @Test func vinFromKLineFrames() {
        let vinBytes = Array("WVWZZZ1JZXW000001".utf8)
        var frames: [[UInt8]] = [[0x49, 0x02, 0x01, 0x00, 0x00, 0x00, vinBytes[0]]]
        var i = 1
        var seq: UInt8 = 2
        while i < 17 {
            frames.append([0x49, 0x02, seq] + Array(vinBytes[i..<i + 4]))
            i += 4; seq += 1
        }
        #expect(Mode09Parser.vin(frames: frames.shuffled()) == "WVWZZZ1JZXW000001")
    }
    @Test func vinFromCANFrame() {
        let frame: [UInt8] = [0x49, 0x02, 0x01] + Array("1HGCM82633A004352".utf8)
        #expect(Mode09Parser.vin(frames: [frame]) == "1HGCM82633A004352")
    }
    @Test func calibrationIDs() {
        var data = Array("SIM-CAL-0001".utf8); data += [UInt8](repeating: 0, count: 16 - data.count)
        var data2 = Array("ABC123".utf8); data2 += [UInt8](repeating: 0, count: 16 - data2.count)
        let frame: [UInt8] = [0x49, 0x04, 0x02] + data + data2
        #expect(Mode09Parser.calibrationIDs(frames: [frame]) == ["SIM-CAL-0001", "ABC123"])
    }
    @Test func missing() {
        #expect(Mode09Parser.vin(frames: []) == nil)
        #expect(Mode09Parser.vin(frames: [[0x49, 0x02, 0x01, 0x41]]) == nil)
    }
}
