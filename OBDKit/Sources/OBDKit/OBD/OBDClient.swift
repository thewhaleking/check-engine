import Foundation

/// Typed OBD-II API on top of an `ELM327Session`. All calls are serialized by the actor,
/// which matches the half-duplex nature of the adapter.
public actor OBDClient {
    public nonisolated let session: ELM327Session
    public private(set) var adapterInfo: ELM327Session.AdapterInfo?
    public private(set) var protocolInfo: ELM327Session.ProtocolInfo?
    private var supportedCache: Set<PID>?
    private var pollTask: Task<Void, Never>?

    public init(session: ELM327Session) {
        self.session = session
    }

    public init(transport: any OBDTransport) {
        self.session = ELM327Session(transport: transport)
    }

    /// Connects to the adapter only. Call `supportedPIDs()` to reach the vehicle.
    @discardableResult
    public func connect() async throws -> ELM327Session.AdapterInfo {
        let info = try await session.connect()
        adapterInfo = info
        supportedCache = nil
        protocolInfo = nil
        return info
    }

    public func disconnect() async {
        stopPolling()
        await session.disconnect()
        adapterInfo = nil
        protocolInfo = nil
        supportedCache = nil
    }

    /// Walks 0100, 0120, ... and caches the result. The first call performs the bus search.
    public func supportedPIDs() async throws -> Set<PID> {
        if let supportedCache { return supportedCache }
        var set = Set<PID>()
        var base: UInt8 = 0x00
        while true {
            let frames: [[UInt8]]
            do {
                frames = try await session.request(mode: 0x01, pid: base)
            } catch ELMError.noData where base > 0 {
                break
            }
            var next = false
            for frame in frames {
                let mask = Array(frame.dropFirst(2))
                set.formUnion(SupportedPIDs.decode(base: base, mask: mask))
                if SupportedPIDs.hasNextRange(mask) { next = true }
            }
            guard next, base < 0xE0 else { break }
            base += 0x20
        }
        supportedCache = set
        if protocolInfo == nil { protocolInfo = try? await session.describeProtocol() }
        return set
    }

    /// Raw payload bytes (after "41 <pid>") from the first responding ECU.
    public func readRaw(_ pid: PID) async throws -> [UInt8] {
        let frames = try await session.request(mode: pid.mode, pid: pid.id)
        return Array(frames[0].dropFirst(2))
    }

    public func read(_ pid: PID) async throws -> Double {
        guard let descriptor = PIDRegistry.descriptor(for: pid) else {
            throw ELMError.unexpectedResponse("No decoder for \(pid)")
        }
        let payload = try await readRaw(pid)
        guard let value = descriptor.value(from: payload) else {
            throw ELMError.unexpectedResponse("\(pid): short payload \(Hex.string(payload))")
        }
        return value
    }

    public struct MILStatus: Sendable, Equatable {
        public var milOn: Bool
        public var dtcCount: Int
    }

    public func milStatus() async throws -> MILStatus {
        let payload = try await readRaw(.mode01(0x01))
        guard let a = payload.first else { throw ELMError.unexpectedResponse("0101: empty") }
        return MILStatus(milOn: a & 0x80 != 0, dtcCount: Int(a & 0x7F))
    }

    public func readDTCs(kind: DTCKind) async throws -> [DTC] {
        do {
            let frames = try await session.request(mode: kind.mode)
            return DTCDecoder.decode(frames: frames, mode: kind.mode)
        } catch ELMError.noData {
            return []
        }
    }

    public func clearDTCs() async throws {
        let reply = try await session.command("04", timeout: .seconds(5))
        switch reply {
        case .ok: return
        case .data(let frames) where frames.contains(where: { $0.first == 0x44 }): return
        case .data(let frames):
            if let neg = frames.first(where: { $0.count >= 3 && $0[0] == 0x7F }) {
                throw ELMError.negativeResponse(mode: neg[1], code: neg[2])
            }
            throw ELMError.unexpectedResponse(frames.map { Hex.string($0) }.joined(separator: " / "))
        case .noData: throw ELMError.noData
        case .unableToConnect: throw ELMError.unableToConnect
        case .stopped: throw ELMError.stopped
        case .unknownCommand: throw ELMError.unknownCommand("04")
        case .busError(let s): throw ELMError.busError(s)
        case .lines(let l): throw ELMError.unexpectedResponse(l.joined(separator: " | "))
        }
    }

    public func vin() async throws -> String? {
        do {
            let frames = try await session.request(mode: 0x09, pid: 0x02)
            return Mode09Parser.vin(frames: frames)
        } catch ELMError.noData {
            return nil
        }
    }

    public func calibrationIDs() async throws -> [String] {
        do {
            let frames = try await session.request(mode: 0x09, pid: 0x04)
            return Mode09Parser.calibrationIDs(frames: frames)
        } catch ELMError.noData {
            return []
        }
    }

    public func batteryVoltage() async throws -> Double {
        try await session.batteryVoltage()
    }

    // MARK: Polling

    public var isPolling: Bool { pollTask != nil }

    /// Reads `pids` in a loop. Each cycle yields one `LiveSample`. PIDs that return
    /// NO DATA are omitted from that sample. The stream ends with an error after a
    /// transport failure or three consecutive cycles with no data at all.
    public func startPolling(pids: [PID], includeVoltage: Bool, interval: Duration) -> AsyncThrowingStream<LiveSample, Error> {
        stopPolling()
        let (stream, continuation) = AsyncThrowingStream.makeStream(of: LiveSample.self)
        let task = Task { [self] in
            let clock = ContinuousClock()
            var emptyCycles = 0
            var lastError: Error?
            while !Task.isCancelled {
                let start = clock.now
                var values: [PID: Double] = [:]
                do {
                    for pid in pids {
                        if Task.isCancelled { break }
                        do {
                            values[pid] = try await read(pid)
                        } catch let error as ELMError {
                            switch error {
                            case .noData, .busError, .stopped, .unexpectedResponse, .negativeResponse:
                                lastError = error
                            default:
                                throw error
                            }
                        }
                    }
                    if Task.isCancelled { break }
                    let voltage = includeVoltage ? try? await session.batteryVoltage() : nil
                    continuation.yield(LiveSample(values: values, voltage: voltage))
                } catch {
                    continuation.finish(throwing: error)
                    return
                }
                emptyCycles = values.isEmpty && !pids.isEmpty ? emptyCycles + 1 : 0
                if emptyCycles >= 3 {
                    continuation.finish(throwing: lastError ?? ELMError.noData)
                    return
                }
                let elapsed = clock.now - start
                if elapsed < interval { try? await Task.sleep(for: interval - elapsed) }
            }
            continuation.finish()
        }
        pollTask = task
        continuation.onTermination = { _ in task.cancel() }
        return stream
    }

    public func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }
}
