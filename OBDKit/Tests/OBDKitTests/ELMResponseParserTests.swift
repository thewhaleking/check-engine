import Testing
@testable import OBDKit

@Suite struct ELMResponseParserTests {
    @Test func singleFrame() {
        #expect(ELMResponseParser.parse(["41 0C 1A F8", ">"], echoOf: "010C") == .data(frames: [[0x41, 0x0C, 0x1A, 0xF8]]))
    }
    @Test func removesEchoAndSearching() {
        let r = ELMResponseParser.parse(["0100", "SEARCHING...", "41 00 BE 3E B8 11", ">"], echoOf: "0100")
        #expect(r == .data(frames: [[0x41, 0x00, 0xBE, 0x3E, 0xB8, 0x11]]))
    }
    @Test func multipleECUs() {
        let r = ELMResponseParser.parse(["41 00 BE 3E B8 11", "41 00 80 00 00 00"], echoOf: nil)
        #expect(r == .data(frames: [[0x41, 0x00, 0xBE, 0x3E, 0xB8, 0x11], [0x41, 0x00, 0x80, 0, 0, 0]]))
    }
    /// Real replies captured from an FTDI "OBDlinkSX" clone (ELM327 v1.4b) on 2026-11-04.
    @Test func searchingJoinedToResult() {
        #expect(ELMResponseParser.parse(["0100", "SEARCHING...NO DATA", ">"], echoOf: "0100") == .noData)
        #expect(ELMResponseParser.parse(["SEARCHING...UNABLE TO CONNECT"]) == .unableToConnect)
        let r = ELMResponseParser.parse(["SEARCHING...41 00 BE 3E B8 11"], echoOf: "0100")
        #expect(r == .data(frames: [[0x41, 0x00, 0xBE, 0x3E, 0xB8, 0x11]]))
        #expect(ELMResponseParser.parse(["ELM327 v1.4b", ">"], echoOf: "ATI") == .lines(["ELM327 v1.4b"]))
    }
    @Test func statusWords() {
        #expect(ELMResponseParser.parse(["NO DATA"]) == .noData)
        #expect(ELMResponseParser.parse(["SEARCHING...", "UNABLE TO CONNECT"]) == .unableToConnect)
        #expect(ELMResponseParser.parse(["STOPPED"]) == .stopped)
        #expect(ELMResponseParser.parse(["?"]) == .unknownCommand)
        #expect(ELMResponseParser.parse(["OK"]) == .ok)
        #expect(ELMResponseParser.parse(["CAN ERROR"]) == .busError("CAN ERROR"))
        #expect(ELMResponseParser.parse(["BUFFER FULL"]) == .busError("BUFFER FULL"))
    }
    @Test func textLines() {
        #expect(ELMResponseParser.parse(["ATZ", "", "ELM327 v1.5", ">"], echoOf: "ATZ") == .lines(["ELM327 v1.5"]))
        #expect(ELMResponseParser.parse(["12.6V"]) == .lines(["12.6V"]))
        #expect(ELMResponseParser.parse(["A6"], echoOf: "ATDPN") == .lines(["A6"]))  // looks like hex
    }
    @Test func multiFrameVIN() {
        let lines = ["014", "0: 49 02 01 57 56 57", "1: 5A 5A 5A 31 4A 5A 58", "2: 57 30 30 30 30 30 31"]
        guard case .data(let frames) = ELMResponseParser.parse(lines, echoOf: "0902") else {
            Issue.record("expected data"); return
        }
        #expect(frames.count == 1)
        #expect(frames[0].count == 20)
        #expect(Mode09Parser.vin(frames: frames) == "WVWZZZ1JZXW000001")
    }
    @Test func multiFrameWithoutSpaces() {
        let lines = ["014", "0:490201575657", "1:5A5A5A314A5A58", "2:57303030303031"]
        guard case .data(let frames) = ELMResponseParser.parse(lines) else { Issue.record("expected data"); return }
        #expect(Mode09Parser.vin(frames: frames) == "WVWZZZ1JZXW000001")
    }
    @Test func negativeResponseIsData() {
        #expect(ELMResponseParser.parse(["7F 01 12"]) == .data(frames: [[0x7F, 0x01, 0x12]]))
    }
    @Test func emptyIsEmptyLines() {
        #expect(ELMResponseParser.parse([">"]) == .lines([]))
    }
}
