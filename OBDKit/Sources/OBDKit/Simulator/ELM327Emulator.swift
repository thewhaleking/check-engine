import Foundation

/// A pure ELM327 state machine: feed it one command line, get back the exact text an
/// adapter would print (including echo and the trailing prompt).
public struct ELM327Emulator: Sendable {
    public static let version = "ELM327 v1.5"

    public var vehicle: SimulatedVehicle
    public private(set) var echo = true
    public private(set) var linefeed = true
    public private(set) var spaces = true
    public private(set) var headers = false
    public private(set) var protocolSetting = "0"
    public private(set) var protocolSearched = false
    private let startTime: Date
    private var lastCommand = ""

    public init(vehicle: SimulatedVehicle = SimulatedVehicle(), startTime: Date = Date()) {
        self.vehicle = vehicle
        self.startTime = startTime
    }

    public mutating func reset() {
        echo = true; linefeed = true; spaces = true; headers = false
        protocolSetting = "0"; protocolSearched = false
    }

    public mutating func handle(_ raw: String, now: Date = Date()) -> String {
        let eol = linefeed ? "\r\n" : "\r"
        var out = echo ? raw + eol : ""
        var cmd = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if cmd.isEmpty { cmd = lastCommand } else { lastCommand = cmd }
        let lines = cmd.hasPrefix("AT") ? handleAT(String(cmd.dropFirst(2)).replacingOccurrences(of: " ", with: ""), now: now)
                                        : handleOBD(cmd, now: now)
        for line in lines { out += line + eol }
        out += eol + ">"
        return out
    }

    // MARK: AT commands

    private mutating func handleAT(_ c: String, now: Date) -> [String] {
        switch c {
        case "Z": reset(); return ["", Self.version]
        case "WS": return ["", Self.version]
        case "I": return [Self.version]
        case "@1": return ["OBDII to RS232 Interpreter"]
        case "E0": echo = false; return ["OK"]
        case "E1": echo = true; return ["OK"]
        case "L0": linefeed = false; return ["OK"]
        case "L1": linefeed = true; return ["OK"]
        case "S0": spaces = false; return ["OK"]
        case "S1": spaces = true; return ["OK"]
        case "H0": headers = false; return ["OK"]
        case "H1": headers = true; return ["OK"]
        case "D": reset(); return ["OK"]
        case "DPN": return [protocolSearched ? "A6" : "A0"]
        case "DP": return [protocolSearched ? "AUTO, ISO 15765-4 (CAN 11/500)" : "AUTO"]
        case "RV": return [String(format: "%.1fV", vehicle.voltage(at: now.timeIntervalSince(startTime)))]
        default:
            if c.hasPrefix("SP") { protocolSetting = String(c.dropFirst(2)); protocolSearched = false; return ["OK"] }
            if c.hasPrefix("AT") || c.hasPrefix("ST") || c.hasPrefix("CAF") || c.hasPrefix("M") { return ["OK"] }
            return ["?"]
        }
    }

    // MARK: OBD requests

    private mutating func handleOBD(_ c: String, now: Date) -> [String] {
        guard let bytes = Hex.bytes(from: c), !bytes.isEmpty else { return ["?"] }
        var prefix: [String] = []
        if !protocolSearched {
            prefix.append("SEARCHING...")
            guard vehicle.ecuPresent else { return prefix + ["UNABLE TO CONNECT"] }
            protocolSearched = true
        } else if !vehicle.ecuPresent {
            return ["NO DATA"]
        }
        let t = now.timeIntervalSince(startTime)
        let mode = bytes[0]
        let pid: UInt8? = bytes.count > 1 ? bytes[1] : nil
        let reply: [String]
        switch mode {
        case 0x01:
            guard let pid else { return prefix + ["?"] }
            reply = mode01(pid, t: t)
        case 0x03: reply = dtcReply(0x43, vehicle.storedDTCs)
        case 0x07: reply = dtcReply(0x47, vehicle.pendingDTCs)
        case 0x0A: reply = dtcReply(0x4A, vehicle.permanentDTCs)
        case 0x04:
            vehicle.storedDTCs = []; vehicle.pendingDTCs = []
            reply = [format([0x44])]
        case 0x09:
            guard let pid else { return prefix + ["?"] }
            reply = mode09(pid)
        default: reply = ["NO DATA"]
        }
        return prefix + reply
    }

    private func mode01(_ pid: UInt8, t: TimeInterval) -> [String] {
        if pid % 0x20 == 0 {
            let mask = SupportedPIDs.mask(base: pid, supported: vehicle.supportedPIDs)
            return mask == [0, 0, 0, 0] && pid != 0 ? ["NO DATA"] : [format([0x41, pid] + mask)]
        }
        if pid == 0x01 {
            let a = UInt8(min(vehicle.storedDTCs.count, 127)) | (vehicle.milOn ? 0x80 : 0)
            return [format([0x41, 0x01, a, 0x07, 0xE5, 0x00])]
        }
        guard let value = vehicle.value(for: pid, at: t), let encoded = Self.encode(pid: pid, value: value) else {
            return ["NO DATA"]
        }
        return [format([0x41, pid] + encoded)]
    }

    private func dtcReply(_ responseMode: UInt8, _ codes: [DTC]) -> [String] {
        var bytes: [UInt8] = [responseMode, UInt8(codes.count)]
        for c in codes { bytes += c.bytes }
        return [format(bytes)]
    }

    private func mode09(_ pid: UInt8) -> [String] {
        switch pid {
        case 0x00: return [format([0x49, 0x00, 0x50, 0x00, 0x00, 0x00])]
        case 0x02: return multiFrame([0x49, 0x02, 0x01] + Array(vehicle.vin.utf8))
        case 0x04:
            var data: [UInt8] = [0x49, 0x04, UInt8(vehicle.calibrationIDs.count)]
            for id in vehicle.calibrationIDs {
                var b = Array(id.utf8.prefix(16)); b += [UInt8](repeating: 0, count: 16 - b.count); data += b
            }
            return multiFrame(data)
        default: return ["NO DATA"]
        }
    }

    /// ELM327 CAN multi-frame display format (headers off).
    private func multiFrame(_ payload: [UInt8]) -> [String] {
        var lines = [String(format: "%03X", payload.count)]
        var rest = payload[...]
        var index = 0
        var take = 6
        while !rest.isEmpty {
            let chunk = Array(rest.prefix(take)); rest = rest.dropFirst(take)
            lines.append(String(format: "%X:", index & 0xF) + (spaces ? " " : "") + format(chunk))
            index += 1; take = 7
        }
        return lines
    }

    private func format(_ bytes: [UInt8]) -> String { Hex.string(bytes, separator: spaces ? " " : "") }

    /// Inverse of the PIDRegistry decode formulas.
    static func encode(pid: UInt8, value v: Double) -> [UInt8]? {
        func b1(_ x: Double) -> [UInt8] { [UInt8(max(0, min(255, x.rounded())))] }
        func b2(_ x: Double) -> [UInt8] { let n = Int(max(0, min(65535, x.rounded()))); return [UInt8(n >> 8), UInt8(n & 0xFF)] }
        switch pid {
        case 0x04, 0x11, 0x2F: return b1(v * 255 / 100)
        case 0x05, 0x0F, 0x46, 0x5C: return b1(v + 40)
        case 0x0A: return b1(v / 3)
        case 0x0B, 0x0D, 0x33: return b1(v)
        case 0x0E: return b1((v + 64) * 2)
        case 0x0C: return b2(v * 4)
        case 0x10: return b2(v * 100)
        case 0x1F, 0x21: return b2(v)
        case 0x42: return b2(v * 1000)
        case 0x5E: return b2(v * 20)
        default: return nil
        }
    }
}

extension SupportedPIDs {
    /// Builds the 4-byte bitmask for PID `base` from a set of supported Mode 01 PIDs.
    public static func mask(base: UInt8, supported: Set<UInt8>) -> [UInt8] {
        var mask: [UInt8] = [0, 0, 0, 0]
        for id in supported where id > base && Int(id) <= Int(base) + 0x20 {
            let offset = Int(id) - Int(base) - 1
            mask[offset / 8] |= 0x80 >> (offset % 8)
        }
        if supported.contains(where: { Int($0) > Int(base) + 0x20 }) { mask[3] |= 0x01 }
        return mask
    }
}
