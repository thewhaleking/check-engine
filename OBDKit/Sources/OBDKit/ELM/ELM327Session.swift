import Foundation

/// Serializes commands to an ELM327 adapter over any `OBDTransport` and parses replies.
public actor ELM327Session {
    public struct AdapterInfo: Sendable, Equatable {
        public var version: String
    }
    public struct ProtocolInfo: Sendable, Equatable {
        public var number: String
        public var name: String
    }

    private let transport: any OBDTransport
    public nonisolated let traffic: AsyncStream<TrafficEvent>
    private nonisolated let trafficContinuation: AsyncStream<TrafficEvent>.Continuation
    private var isOpen = false
    private var needsBusSearch = true
    public private(set) var adapterInfo: AdapterInfo?

    public init(transport: any OBDTransport) {
        self.transport = transport
        (traffic, trafficContinuation) = AsyncStream.makeStream(of: TrafficEvent.self, bufferingPolicy: .bufferingNewest(1000))
    }

    public var connected: Bool { isOpen }

    /// Opens the transport, resets the adapter and applies the standard configuration.
    public func connect() async throws -> AdapterInfo {
        try await transport.open()
        isOpen = true
        await transport.flushInput()
        emit(.info, "Resetting adapter")
        // Clones may print garbage or respond slowly to the first ATZ (an OBDLink SX clone takes
        // about 3.8 s to print its banner); a failure here is not fatal.
        _ = try? await command("ATZ", timeout: .seconds(6))
        // The same clone answers "?" to the first command after its banner, regardless of
        // delay, so give it a moment and retry each setup command once before giving up on it.
        try? await Task.sleep(for: .milliseconds(300))
        await transport.flushInput()
        for cmd in ["ATE0", "ATL0", "ATH0", "ATSP0", "ATAT1"] {
            if case .unknownCommand = try await setupCommand(cmd) {
                emit(.info, "\(cmd) not supported by this adapter")
            }
        }
        needsBusSearch = true
        let reply = try await setupCommand("ATI")
        guard case .lines(let lines) = reply, let version = lines.last else {
            throw ELMError.unexpectedResponse("ATI → \(reply)")
        }
        let info = AdapterInfo(version: version)
        adapterInfo = info
        return info
    }

    public func disconnect() async {
        guard isOpen else { return }
        isOpen = false
        await transport.close()
        emit(.info, "Disconnected")
        trafficContinuation.finish()
    }

    /// Sends one command and reads until the ">" prompt.
    /// A setup command with one retry. Measured on an FTDI "OBDlinkSX" clone: about one AT
    /// command in fifty gets no reply at all, and a similar share is answered with "?" even
    /// though the command is valid. One lost reply should not fail the connection.
    private func setupCommand(_ cmd: String, timeout: Duration = .seconds(2)) async throws -> ELMResponse {
        let first: ELMResponse?
        do {
            first = try await command(cmd, timeout: timeout)
        } catch ELMError.timeout {
            first = nil
        }
        if let first, first != .unknownCommand { return first }
        emit(.info, "Retrying \(cmd)")
        await transport.flushInput()
        return try await command(cmd, timeout: timeout)
    }

    public func command(_ text: String, timeout: Duration = .seconds(2)) async throws -> ELMResponse {
        guard isOpen else { throw ELMError.notConnected }
        try await transport.write(Array((text + "\r").utf8))
        emit(.tx, text)
        var lines: [String] = []
        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        while true {
            let remaining = deadline - clock.now
            guard remaining > .zero else {
                emit(.error, "Timeout waiting for \(text)")
                throw ELMError.timeout(text)
            }
            let line: String?
            do {
                line = try await transport.readLine(timeout: remaining)
            } catch TransportError.timeout {
                emit(.error, "Timeout waiting for \(text)")
                throw ELMError.timeout(text)
            }
            guard let line else { throw TransportError.closed }
            if !line.isEmpty { emit(.rx, line) }
            lines.append(line)
            if line.hasSuffix(">") { break }
        }
        return ELMResponseParser.parse(lines, echoOf: text)
    }

    /// Sends an OBD request and returns the frames whose first bytes match the expected
    /// positive response (mode | 0x40, then pid if given). One frame per responding ECU.
    public func request(mode: UInt8, pid: UInt8? = nil, timeout: Duration = .seconds(5)) async throws -> [[UInt8]] {
        var text = String(format: "%02X", mode)
        if let pid { text += String(format: "%02X", pid) }
        let effective = needsBusSearch ? max(timeout, .seconds(12)) : timeout
        // Same retry as setup: a dropped or "?"-answered read would otherwise end live polling.
        let reply = try await setupCommand(text, timeout: effective)
        switch reply {
        case .data(let frames):
            needsBusSearch = false
            let expected = mode | 0x40
            let good = frames.filter { f in
                guard f.first == expected else { return false }
                guard let pid else { return true }
                return f.count > 1 && f[1] == pid
            }
            if good.isEmpty {
                if let neg = frames.first(where: { $0.count >= 3 && $0[0] == 0x7F }) {
                    throw ELMError.negativeResponse(mode: neg[1], code: neg[2])
                }
                throw ELMError.unexpectedResponse(frames.map { Hex.string($0) }.joined(separator: " / "))
            }
            return good
        case .noData: needsBusSearch = false; throw ELMError.noData
        case .unableToConnect: throw ELMError.unableToConnect
        case .stopped: throw ELMError.stopped
        case .unknownCommand: throw ELMError.unknownCommand(text)
        case .busError(let s): throw ELMError.busError(s)
        case .ok: throw ELMError.unexpectedResponse("OK")
        case .lines(let l): throw ELMError.unexpectedResponse(l.joined(separator: " | "))
        }
    }

    /// ATDPN / ATDP. Meaningful only after the first successful OBD request.
    public func describeProtocol() async throws -> ProtocolInfo {
        let number = try await textReply("ATDPN")
        let name = try await textReply("ATDP")
        return ProtocolInfo(number: number, name: name)
    }

    /// ATRV, e.g. "12.6V".
    public func batteryVoltage() async throws -> Double {
        let text = try await textReply("ATRV")
        let digits = text.filter { $0.isNumber || $0 == "." }
        guard let v = Double(digits) else { throw ELMError.unexpectedResponse(text) }
        return v
    }

    private func textReply(_ cmd: String) async throws -> String {
        let reply = try await command(cmd, timeout: .seconds(2))
        guard case .lines(let lines) = reply, let last = lines.last else {
            throw ELMError.unexpectedResponse("\(cmd) → \(reply)")
        }
        return last
    }

    private func emit(_ kind: TrafficEvent.Kind, _ text: String) {
        trafficContinuation.yield(TrafficEvent(kind: kind, text: text))
    }
}
