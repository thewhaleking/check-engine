import Foundation
import Testing
@testable import OBDKit

@Suite struct OBDClientTests {
    func makeClient(_ vehicle: SimulatedVehicle = SimulatedVehicle()) async throws -> (OBDClient, SimulatedELM327Transport) {
        let transport = SimulatedELM327Transport(vehicle: vehicle, latency: .zero)
        let client = OBDClient(transport: transport)
        try await client.connect()
        return (client, transport)
    }

    @Test func supportedPIDs() async throws {
        let (client, _) = try await makeClient()
        let set = try await client.supportedPIDs()
        #expect(set.map(\.id).filter { $0 % 0x20 != 0 }.sorted() == SimulatedVehicle().supportedPIDs.sorted())
        #expect(set.contains(.mode01(0x20)) && set.contains(.mode01(0x40)))
        let proto = await client.protocolInfo
        #expect(proto?.number == "A6")
    }
    @Test func readValues() async throws {
        let (client, _) = try await makeClient()
        let rpm = try await client.read(.mode01(0x0C))
        #expect(rpm >= 800 && rpm <= 3000)
        let coolant = try await client.read(.mode01(0x05))
        #expect(coolant >= 20 && coolant <= 90)
        await #expect(throws: ELMError.noData) { _ = try await client.read(.mode01(0x0A)) }
    }
    @Test func dtcLifecycle() async throws {
        let (client, _) = try await makeClient()
        let stored = try await client.readDTCs(kind: .stored)
        #expect(stored.map(\.code) == ["P0301", "P0420"])
        #expect(try await client.readDTCs(kind: .pending).map(\.code) == ["P0171"])
        #expect(try await client.readDTCs(kind: .permanent).isEmpty)
        let mil = try await client.milStatus()
        #expect(mil == OBDClient.MILStatus(milOn: true, dtcCount: 2))
        try await client.clearDTCs()
        #expect(try await client.readDTCs(kind: .stored).isEmpty)
        #expect(try await client.milStatus().milOn == false)
    }
    @Test func vehicleInfo() async throws {
        let (client, _) = try await makeClient()
        #expect(try await client.vin() == "WVWZZZ1JZXW000001")
        #expect(try await client.calibrationIDs() == ["SIM-CAL-0001"])
    }
    @Test func polling() async throws {
        let (client, _) = try await makeClient()
        let pids: [PID] = [.mode01(0x0C), .mode01(0x0D), .mode01(0x0A)]
        let stream = await client.startPolling(pids: pids, includeVoltage: true, interval: .milliseconds(10))
        var samples: [LiveSample] = []
        for try await s in stream {
            samples.append(s)
            if samples.count == 3 { break }
        }
        #expect(samples.count == 3)
        #expect(samples[0].values[.mode01(0x0C)] != nil)
        #expect(samples[0].values[.mode01(0x0A)] == nil)   // unsupported -> omitted
        #expect(samples[0].voltage != nil)
        await client.stopPolling()
        #expect(await client.isPolling == false)
    }
    @Test func pollingEndsOnTransportFailure() async throws {
        let (client, transport) = try await makeClient()
        let stream = await client.startPolling(pids: [.mode01(0x0C)], includeVoltage: false, interval: .milliseconds(5))
        var count = 0
        var failed = false
        do {
            for try await _ in stream {
                count += 1
                if count == 2 { await transport.close() }
            }
        } catch {
            failed = true
        }
        #expect(failed)
        #expect(count >= 2)
    }
}
