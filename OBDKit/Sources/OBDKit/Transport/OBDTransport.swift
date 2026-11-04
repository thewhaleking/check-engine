import Foundation

public enum TransportError: Error, Sendable, Equatable, LocalizedError {
    case notOpen
    case openFailed(errno: Int32, path: String)
    case timeout
    case io(errno: Int32)
    case closed

    public var errorDescription: String? {
        switch self {
        case .notOpen: return "Port is not open"
        case .openFailed(let e, let p): return "Cannot open \(p): \(String(cString: strerror(e)))"
        case .timeout: return "Read timed out"
        case .io(let e): return "I/O error: \(String(cString: strerror(e)))"
        case .closed: return "Port closed"
        }
    }
}

/// A byte-oriented, half-duplex link to an ELM327-style adapter.
public protocol OBDTransport: Sendable {
    func open() async throws
    func close() async
    func write(_ bytes: [UInt8]) async throws
    /// Returns the next CR-terminated line (CR removed, LF dropped), or a trailing
    /// fragment that ends in the ">" prompt. Throws `TransportError.timeout` if nothing
    /// arrives within `timeout`. Returns nil on end of stream.
    func readLine(timeout: Duration) async throws -> String?
    func flushInput() async
}
