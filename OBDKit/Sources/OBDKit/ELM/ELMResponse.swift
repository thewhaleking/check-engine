import Foundation

public enum ELMResponse: Sendable, Equatable {
    case ok
    case noData
    case unableToConnect
    case stopped
    case unknownCommand
    case busError(String)
    /// Non-hex text lines (AT replies such as "ELM327 v1.5", "12.6V", "A6").
    case lines([String])
    /// One byte array per responding ECU (or one assembled multi-frame message).
    case data(frames: [[UInt8]])

    public var isError: Bool {
        switch self {
        case .noData, .unableToConnect, .stopped, .unknownCommand, .busError: return true
        default: return false
        }
    }
}

public enum ELMResponseParser {
    static let busErrorPrefixes = [
        "CAN ERROR", "BUS BUSY", "BUS ERROR", "DATA ERROR", "<DATA ERROR", "BUFFER FULL",
        "LV RESET", "FB ERROR", "ACT ALERT", "<RX ERROR", "ERR",
    ]
    static let infoPrefixes = ["SEARCHING", "BUS INIT"]

    /// Parses the raw lines received between a command and the next prompt.
    public static func parse(_ raw: [String], echoOf command: String? = nil) -> ELMResponse {
        let normalizedCommand = command.map { normalize($0) }
        var lines: [String] = []
        for var line in raw {
            line = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.hasSuffix(">") { line = String(line.dropLast()).trimmingCharacters(in: .whitespaces) }
            if line.isEmpty { continue }
            if let normalizedCommand, normalize(line) == normalizedCommand { continue } // echo
            // Some adapters print "SEARCHING..." and the result on one line, e.g. "SEARCHING...NO DATA".
            if let prefix = infoPrefixes.first(where: { line.uppercased().hasPrefix($0) }) {
                var rest = line.dropFirst(prefix.count)
                while rest.first == "." { rest = rest.dropFirst() }
                line = rest.trimmingCharacters(in: .whitespaces)
                if line.isEmpty { continue }
            }
            lines.append(line)
        }
        guard !lines.isEmpty else { return .lines([]) }

        for line in lines {
            let upper = line.uppercased()
            if upper == "NO DATA" { return .noData }
            if upper == "UNABLE TO CONNECT" { return .unableToConnect }
            if upper == "STOPPED" { return .stopped }
            if upper == "?" { return .unknownCommand }
            if busErrorPrefixes.contains(where: { upper.hasPrefix($0) }) { return .busError(line) }
        }
        if lines.count == 1, lines[0].uppercased() == "OK" { return .ok }
        // Replies to AT commands are text, even when they look like hex ("A6" from ATDPN).
        if let normalizedCommand, normalizedCommand.hasPrefix("AT") { return .lines(lines) }

        if MultiFrameAssembler.isMultiFrame(lines) {
            if let bytes = MultiFrameAssembler.assemble(lines) { return .data(frames: [bytes]) }
            return .lines(lines)
        }
        var frames: [[UInt8]] = []
        for line in lines {
            guard let bytes = Hex.bytes(from: line), !bytes.isEmpty else { return .lines(lines) }
            frames.append(bytes)
        }
        return .data(frames: frames)
    }

    static func normalize(_ s: String) -> String {
        s.uppercased().replacingOccurrences(of: " ", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
