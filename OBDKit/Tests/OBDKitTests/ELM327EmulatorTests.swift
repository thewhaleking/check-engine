import Foundation
import Testing
@testable import OBDKit

@Suite struct ELM327EmulatorTests {
    @Test func resetAndEcho() {
        var e = ELM327Emulator()
        let r = e.handle("ATZ")
        #expect(r.hasPrefix("ATZ\r\n"))
        #expect(r.contains("ELM327 v1.5"))
        #expect(r.hasSuffix("\r\n>"))
        _ = e.handle("ATE0"); _ = e.handle("ATL0")
        #expect(e.handle("ATI") == "ELM327 v1.5\r\r>")
    }
    @Test func searchingThenData() {
        var e = ELM327Emulator()
        _ = e.handle("ATE0"); _ = e.handle("ATL0")
        let first = e.handle("0100")
        #expect(first.hasPrefix("SEARCHING...\r41 00 "))
        let second = e.handle("0100")
        #expect(second.hasPrefix("41 00 "))
        #expect(e.handle("ATDPN") == "A6\r\r>")
    }
    @Test func rpmRoundTrip() {
        let start = Date()
        var e = ELM327Emulator(startTime: start)
        _ = e.handle("ATE0"); _ = e.handle("ATL0")
        let r = e.handle("010C", now: start)
        let lines = r.split(separator: "\r").map(String.init)
        guard case .data(let frames) = ELMResponseParser.parse(lines) else { Issue.record("no data"); return }
        let value = PIDRegistry.descriptor(for: .mode01(0x0C))!.value(from: Array(frames[0].dropFirst(2)))!
        let expected = SimulatedVehicle().value(for: 0x0C, at: 0)!
        #expect(abs(value - expected) < 0.5)
    }
    @Test func unsupportedPID() {
        var e = ELM327Emulator()
        _ = e.handle("ATE0"); _ = e.handle("ATL0"); _ = e.handle("0100")
        #expect(e.handle("015A") == "NO DATA\r\r>")
    }
    @Test func dtcsAndClear() {
        var e = ELM327Emulator()
        _ = e.handle("ATE0"); _ = e.handle("ATL0"); _ = e.handle("0100")
        #expect(e.handle("03") == "43 02 03 01 04 20\r\r>")
        #expect(e.handle("07") == "47 01 01 71\r\r>")
        #expect(e.handle("04") == "44\r\r>")
        #expect(e.handle("03") == "43 00\r\r>")
    }
    @Test func vinMultiFrame() {
        var e = ELM327Emulator()
        _ = e.handle("ATE0"); _ = e.handle("ATL0"); _ = e.handle("0100")
        let lines = e.handle("0902").split(separator: "\r").map(String.init)
        #expect(lines[0] == "014")
        #expect(lines[1] == "0: 49 02 01 57 56 57")
        guard case .data(let frames) = ELMResponseParser.parse(lines) else { Issue.record("no data"); return }
        #expect(Mode09Parser.vin(frames: frames) == "WVWZZZ1JZXW000001")
    }
    @Test func unknownAT() {
        var e = ELM327Emulator()
        _ = e.handle("ATE0"); _ = e.handle("ATL0")
        #expect(e.handle("ATXYZ") == "?\r\r>")
    }
    @Test func maskRoundTrip() {
        let supported: Set<UInt8> = [0x01, 0x0C, 0x0D, 0x20, 0x21, 0x5E]
        let m0 = SupportedPIDs.mask(base: 0x00, supported: supported)
        #expect(SupportedPIDs.decode(base: 0x00, mask: m0).map(\.id).sorted() == [0x01, 0x0C, 0x0D, 0x20])
        #expect(SupportedPIDs.hasNextRange(m0))
        let m20 = SupportedPIDs.mask(base: 0x20, supported: supported)
        #expect(SupportedPIDs.decode(base: 0x20, mask: m20).map(\.id).sorted() == [0x21, 0x40])
        let m40 = SupportedPIDs.mask(base: 0x40, supported: supported)
        #expect(SupportedPIDs.decode(base: 0x40, mask: m40).map(\.id).sorted() == [0x5E])
        #expect(!SupportedPIDs.hasNextRange(m40))
    }
}
