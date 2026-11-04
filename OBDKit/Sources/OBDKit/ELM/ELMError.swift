import Foundation

public enum ELMError: Error, Sendable, Equatable {
    case notConnected
    case noData
    case unableToConnect
    case stopped
    case unknownCommand(String)
    case busError(String)
    case timeout(String)
    /// ECU replied 7F <mode> <nrc>.
    case negativeResponse(mode: UInt8, code: UInt8)
    case unexpectedResponse(String)
}

extension ELMError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .notConnected: return "Not connected"
        case .noData: return "No data from vehicle"
        case .unableToConnect: return "Unable to connect to vehicle"
        case .stopped: return "Command interrupted"
        case .unknownCommand(let c): return "Adapter did not understand: \(c)"
        case .busError(let s): return "Bus error: \(s)"
        case .timeout(let c): return "Timeout waiting for reply to \(c)"
        case .negativeResponse(let m, let c):
            return String(format: "ECU rejected mode %02X (NRC %02X)", m, c)
        case .unexpectedResponse(let s): return "Unexpected response: \(s)"
        }
    }
}
