import Foundation
import Testing
@testable import OBDKit

/// A pseudo-terminal pair: the test holds the master, the transport opens the slave path.
final class PTY: @unchecked Sendable {
    let master: Int32
    let slavePath: String
    init() throws {
        master = posix_openpt(O_RDWR | O_NOCTTY)
        guard master >= 0, grantpt(master) == 0, unlockpt(master) == 0, let name = ptsname(master) else {
            throw TransportError.io(errno: errno)
        }
        slavePath = String(cString: name)
    }
    func send(_ s: String) { let b = Array(s.utf8); _ = b.withUnsafeBufferPointer { Darwin.write(master, $0.baseAddress, $0.count) } }
    func receive(max: Int = 256) -> String {
        var buf = [UInt8](repeating: 0, count: max)
        var fds = [pollfd(fd: master, events: Int16(POLLIN), revents: 0)]
        guard poll(&fds, 1, 1000) > 0 else { return "" }
        let n = read(master, &buf, max)
        return n > 0 ? String(decoding: buf[..<n], as: UTF8.self) : ""
    }
    deinit { Darwin.close(master) }
}

@Suite struct SerialPortTransportTests {
    @Test func openMissingPathFails() async {
        let t = SerialPortTransport(path: "/dev/cu.does-not-exist", baudRate: 38400)
        await #expect(throws: TransportError.openFailed(errno: ENOENT, path: "/dev/cu.does-not-exist")) { try await t.open() }
    }

    @Test func readBeforeOpenFails() async {
        let t = SerialPortTransport(path: "/dev/null")
        await #expect(throws: TransportError.notOpen) { _ = try await t.readLine(timeout: .milliseconds(10)) }
    }

    @Test func loopbackThroughPTY() async throws {
        let pty = try PTY()
        let t = SerialPortTransport(path: pty.slavePath, baudRate: 38400)
        try await t.open()
        try await t.write(Array("ATZ\r".utf8))
        #expect(pty.receive() == "ATZ\r")
        pty.send("41 0C 1A F8\r\r>")
        #expect(try await t.readLine(timeout: .seconds(1)) == "41 0C 1A F8")
        #expect(try await t.readLine(timeout: .seconds(1)) == "")
        #expect(try await t.readLine(timeout: .seconds(1)) == ">")
        await #expect(throws: TransportError.timeout) { _ = try await t.readLine(timeout: .milliseconds(50)) }
        await t.close()
        #expect(await t.isOpen == false)
    }

    @Test func sessionOverPTY() async throws {
        let pty = try PTY()
        let session = ELM327Session(transport: SerialPortTransport(path: pty.slavePath))
        // Script the adapter side with the emulator.
        let responder = Task.detached {
            var emu = ELM327Emulator()
            var pending = ""
            while !Task.isCancelled {
                let chunk = pty.receive()
                if chunk.isEmpty { continue }
                for ch in chunk {
                    if ch == "\r" { pty.send(emu.handle(pending)); pending = "" } else { pending.append(ch) }
                }
            }
        }
        let info = try await session.connect()
        #expect(info.version == "ELM327 v1.5")
        let frames = try await session.request(mode: 0x01, pid: 0x0C)
        #expect(frames[0].prefix(2) == [0x41, 0x0C])
        responder.cancel()
        await session.disconnect()
    }

    @Test func closeWakesPendingRead() async throws {
        let pty = try PTY()
        let t = SerialPortTransport(path: pty.slavePath)
        try await t.open()
        let reader = Task { try await t.readLine(timeout: .seconds(10)) }
        try await Task.sleep(for: .milliseconds(100))
        let clock = ContinuousClock()
        let start = clock.now
        await t.close()
        let result = try await reader.value
        #expect(result == nil)
        #expect(clock.now - start < .seconds(1))
    }
}
