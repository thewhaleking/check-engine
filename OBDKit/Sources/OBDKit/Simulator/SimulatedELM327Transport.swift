import Foundation

/// An in-process transport that talks to `ELM327Emulator`, for tests and the app's simulator mode.
public actor SimulatedELM327Transport: OBDTransport {
    private var emulator: ELM327Emulator
    private let latency: Duration
    private var buffer = LineBuffer()
    private var pending: [UInt8] = []
    private var isOpen = false

    public init(vehicle: SimulatedVehicle = SimulatedVehicle(), latency: Duration = .milliseconds(20)) {
        self.emulator = ELM327Emulator(vehicle: vehicle)
        self.latency = latency
    }

    public var vehicle: SimulatedVehicle { emulator.vehicle }
    public func setVehicle(_ v: SimulatedVehicle) { emulator.vehicle = v }

    public func open() async throws { isOpen = true }
    public func close() async { isOpen = false; buffer.clear(); pending.removeAll() }
    public func flushInput() async { buffer.clear() }

    public func write(_ bytes: [UInt8]) async throws {
        guard isOpen else { throw TransportError.notOpen }
        for b in bytes {
            if b == 0x0D {
                let command = String(decoding: pending, as: UTF8.self)
                pending.removeAll()
                if latency > .zero { try await Task.sleep(for: latency) }
                let reply = emulator.handle(command)
                buffer.append(Array(reply.utf8))
            } else {
                pending.append(b)
            }
        }
    }

    public func readLine(timeout: Duration) async throws -> String? {
        guard isOpen else { throw TransportError.notOpen }
        if let line = buffer.nextLine() { return line }
        try await Task.sleep(for: timeout)
        if let line = buffer.nextLine() { return line }
        throw TransportError.timeout
    }
}
