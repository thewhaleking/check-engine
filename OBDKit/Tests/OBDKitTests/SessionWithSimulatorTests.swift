import Foundation
import Testing
@testable import OBDKit

@Suite struct SessionWithSimulatorTests {
    @Test func connectAndRequest() async throws {
        let transport = SimulatedELM327Transport(latency: .zero)
        let session = ELM327Session(transport: transport)
        let info = try await session.connect()
        #expect(info.version == "ELM327 v1.5")
        let frames = try await session.request(mode: 0x01, pid: 0x00)
        #expect(frames.count == 1)
        #expect(frames[0].prefix(2) == [0x41, 0x00])
        let proto = try await session.describeProtocol()
        #expect(proto.number == "A6")
        #expect(proto.name.contains("CAN"))
        let v = try await session.batteryVoltage()
        #expect(v > 13 && v < 15)
        await session.disconnect()
    }
    @Test func noDataAndUnknown() async throws {
        let session = ELM327Session(transport: SimulatedELM327Transport(latency: .zero))
        _ = try await session.connect()
        await #expect(throws: ELMError.noData) { _ = try await session.request(mode: 0x01, pid: 0x5A) }
        let reply = try await session.command("ATXYZ")
        #expect(reply == .unknownCommand)
    }
    @Test func unableToConnect() async throws {
        var vehicle = SimulatedVehicle(); vehicle.ecuPresent = false
        let session = ELM327Session(transport: SimulatedELM327Transport(vehicle: vehicle, latency: .zero))
        _ = try await session.connect()
        await #expect(throws: ELMError.unableToConnect) { _ = try await session.request(mode: 0x01, pid: 0x00) }
    }
    @Test func trafficIsEmitted() async throws {
        let session = ELM327Session(transport: SimulatedELM327Transport(latency: .zero))
        _ = try await session.connect()
        await session.disconnect()
        var tx: [String] = []
        for await e in session.traffic where e.kind == .tx { tx.append(e.text) }
        #expect(tx.first == "ATZ")
        #expect(tx.contains("ATI"))
    }
    @Test func notConnected() async {
        let session = ELM327Session(transport: SimulatedELM327Transport(latency: .zero))
        await #expect(throws: ELMError.notConnected) { _ = try await session.command("ATI") }
    }
}
