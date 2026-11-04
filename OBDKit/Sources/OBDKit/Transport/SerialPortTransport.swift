import Foundation

/// POSIX serial port transport. Blocking calls run on a private dispatch queue so the
/// actor (and the cooperative thread pool) never blocks; `close()` wakes a pending read
/// through a self-pipe.
public actor SerialPortTransport: OBDTransport {
    public let path: String
    public let baudRate: Int

    private var fd: Int32 = -1
    private var wakeRead: Int32 = -1
    private var wakeWrite: Int32 = -1
    private var buffer = LineBuffer()
    private let queue = DispatchQueue(label: "OBDKit.SerialPortTransport")

    public init(path: String, baudRate: Int = 38400) {
        self.path = path
        self.baudRate = baudRate
    }

    public var isOpen: Bool { fd >= 0 }

    public func open() async throws {
        guard fd < 0 else { return }
        let path = self.path, baud = self.baudRate
        let newFD: Int32 = try await withCheckedThrowingContinuation { cont in
            queue.async { cont.resume(with: Result { try Self.openPort(path: path, baud: baud) }) }
        }
        var p: [Int32] = [-1, -1]
        guard pipe(&p) == 0 else {
            Darwin.close(newFD)
            throw TransportError.io(errno: errno)
        }
        fd = newFD
        wakeRead = p[0]
        wakeWrite = p[1]
        buffer.clear()
    }

    public func close() async {
        guard fd >= 0 else { return }
        var one: UInt8 = 1
        _ = Darwin.write(wakeWrite, &one, 1)
        let (f, r, w) = (fd, wakeRead, wakeWrite)
        fd = -1; wakeRead = -1; wakeWrite = -1
        buffer.clear()
        // Runs after any in-flight poll/read block on the serial queue has returned.
        await withCheckedContinuation { cont in
            queue.async {
                Darwin.close(f); Darwin.close(r); Darwin.close(w)
                cont.resume()
            }
        }
    }

    public func flushInput() async {
        buffer.clear()
        guard fd >= 0 else { return }
        let f = fd
        await withCheckedContinuation { cont in
            queue.async { tcflush(f, TCIFLUSH); cont.resume() }
        }
    }

    public func write(_ bytes: [UInt8]) async throws {
        guard fd >= 0 else { throw TransportError.notOpen }
        let f = fd
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            queue.async {
                var offset = 0
                while offset < bytes.count {
                    let n = bytes[offset...].withUnsafeBufferPointer { Darwin.write(f, $0.baseAddress, $0.count) }
                    if n < 0 {
                        if errno == EINTR { continue }
                        cont.resume(throwing: TransportError.io(errno: errno)); return
                    }
                    offset += n
                }
                cont.resume()
            }
        }
    }

    public func readLine(timeout: Duration) async throws -> String? {
        guard fd >= 0 else { throw TransportError.notOpen }
        if let line = buffer.nextLine() { return line }
        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        while true {
            guard fd >= 0 else { return nil }
            let remaining = deadline - clock.now
            guard remaining > .zero else { throw TransportError.timeout }
            let ms = Int32(clamping: max(1, remaining.components.seconds * 1000 + remaining.components.attoseconds / 1_000_000_000_000_000))
            guard let chunk = try await readChunk(fd: fd, wake: wakeRead, timeoutMs: ms) else { return nil }
            buffer.append(chunk)
            if let line = buffer.nextLine() { return line }
        }
    }

    /// Returns bytes read ([] on poll timeout) or nil when the port closed or was woken for close.
    private nonisolated func readChunk(fd: Int32, wake: Int32, timeoutMs: Int32) async throws -> [UInt8]? {
        try await withCheckedThrowingContinuation { cont in
            queue.async {
                var fds = [pollfd(fd: fd, events: Int16(POLLIN), revents: 0),
                           pollfd(fd: wake, events: Int16(POLLIN), revents: 0)]
                let n = poll(&fds, 2, timeoutMs)
                if n < 0 {
                    if errno == EINTR { cont.resume(returning: []) } else { cont.resume(throwing: TransportError.io(errno: errno)) }
                    return
                }
                if n == 0 { cont.resume(returning: []); return }
                if fds[1].revents != 0 { cont.resume(returning: nil); return }
                if fds[0].revents & Int16(POLLNVAL) != 0 { cont.resume(returning: nil); return }
                var buf = [UInt8](repeating: 0, count: 4096)
                let r = read(fd, &buf, buf.count)
                if r < 0 {
                    if errno == EAGAIN || errno == EINTR { cont.resume(returning: []) } else { cont.resume(throwing: TransportError.io(errno: errno)) }
                } else if r == 0 {
                    cont.resume(returning: nil)
                } else {
                    cont.resume(returning: Array(buf[..<r]))
                }
            }
        }
    }

    // MARK: termios

    private static func openPort(path: String, baud: Int) throws -> Int32 {
        let fd = Darwin.open(path, O_RDWR | O_NOCTTY | O_NONBLOCK)
        guard fd >= 0 else { throw TransportError.openFailed(errno: errno, path: path) }
        func fail() -> TransportError { let e = errno; Darwin.close(fd); return .openFailed(errno: e, path: path) }
        guard ioctl(fd, TIOCEXCL) != -1 else { throw fail() }
        let flags = fcntl(fd, F_GETFL)
        guard flags != -1, fcntl(fd, F_SETFL, flags & ~O_NONBLOCK) != -1 else { throw fail() }
        var tty = termios()
        guard tcgetattr(fd, &tty) == 0 else { throw fail() }
        cfmakeraw(&tty)
        tty.c_cflag |= tcflag_t(CLOCAL | CREAD)
        tty.c_cflag &= ~tcflag_t(CSIZE)
        tty.c_cflag |= tcflag_t(CS8)
        tty.c_cflag &= ~tcflag_t(PARENB | CSTOPB | CRTSCTS)
        withUnsafeMutablePointer(to: &tty.c_cc) {
            $0.withMemoryRebound(to: cc_t.self, capacity: Int(NCCS)) { cc in
                cc[Int(VMIN)] = 0
                cc[Int(VTIME)] = 0
            }
        }
        if cfsetspeed(&tty, speed_t(baud)) == 0, tcsetattr(fd, TCSANOW, &tty) == 0 {
            // Standard rate accepted by termios.
        } else {
            // Non-standard rate (e.g. 1 Mbps on an OBDLink SX). macOS termios rejects it,
            // but the serial driver accepts any rate through IOSSIOSPEED after tcsetattr.
            guard cfsetspeed(&tty, speed_t(B9600)) == 0, tcsetattr(fd, TCSANOW, &tty) == 0 else { throw fail() }
            var speed = speed_t(baud)
            guard ioctl(fd, IOSSIOSPEED, &speed) == 0 else { throw fail() }
        }
        tcflush(fd, TCIOFLUSH)
        return fd
    }

    /// `IOSSIOSPEED` from <IOKit/serial/ioss.h>: `_IOW('T', 2, speed_t)`. The macro does not
    /// import into Swift, so the value is spelled out.
    private static let IOSSIOSPEED: UInt = 0x8004_5402
}

public enum BaudDetector {
    public static let candidates = [38400, 9600, 115200, 1_000_000, 57600, 19200, 2400]

    /// Tries each baud rate until the adapter answers ATI with something containing "ELM".
    public static func detect(path: String, candidates: [Int] = candidates,
                              perAttempt: Duration = .milliseconds(1500),
                              progress: (@Sendable (Int) -> Void)? = nil) async -> Int? {
        for baud in candidates {
            progress?(baud)
            let t = SerialPortTransport(path: path, baudRate: baud)
            guard (try? await t.open()) != nil else { continue }
            defer { Task { await t.close() } }
            await t.flushInput()
            // A lone CR clears any partial command; then ask for the version string twice,
            // because some clones drop or reject a command now and then.
            guard (try? await t.write(Array("\rATI\rATI\r".utf8))) != nil else { await t.close(); continue }
            let clock = ContinuousClock()
            let deadline = clock.now + perAttempt
            var found = false
            while clock.now < deadline, !found {
                guard let line = try? await t.readLine(timeout: deadline - clock.now) else { break }
                if line.uppercased().contains("ELM") { found = true }
            }
            await t.close()
            if found { return baud }
        }
        return nil
    }
}
