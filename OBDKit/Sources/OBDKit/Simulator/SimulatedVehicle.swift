import Foundation

/// A deterministic, time-varying vehicle model used by the ELM327 emulator.
public struct SimulatedVehicle: Sendable, Equatable {
    public var vin = "WVWZZZ1JZXW000001"
    public var calibrationIDs = ["SIM-CAL-0001"]
    public var storedDTCs: [DTC] = [DTC(code: "P0301")!, DTC(code: "P0420")!]
    public var pendingDTCs: [DTC] = [DTC(code: "P0171")!]
    public var permanentDTCs: [DTC] = []
    public var supportedPIDs: Set<UInt8> = [
        0x01, 0x04, 0x05, 0x0B, 0x0C, 0x0D, 0x0E, 0x0F, 0x10, 0x11,
        0x1F, 0x21, 0x2F, 0x33, 0x42, 0x46, 0x5C, 0x5E,
    ]
    /// When false, OBD requests answer UNABLE TO CONNECT (ignition off / not plugged in).
    public var ecuPresent = true

    public init() {}

    public var milOn: Bool { !storedDTCs.isEmpty }

    public func voltage(at t: TimeInterval) -> Double {
        14.0 + 0.2 * sin(t / 3)
    }

    /// Physical value for a Mode 01 PID at vehicle time `t` (seconds since start).
    public func value(for id: UInt8, at t: TimeInterval) -> Double? {
        guard supportedPIDs.contains(id) else { return nil }
        let wave = (1 + sin(t / 8)) / 2              // 0...1, 50 s period
        let rpm = 800 + 2200 * wave                  // 800...3000
        let load = 20 + 40 * wave                    // 20...60 %
        let coolant = 20 + 70 * (1 - exp(-t / 90))   // warms to 90 °C
        switch id {
        case 0x04: return load
        case 0x05: return coolant
        case 0x0B: return 30 + load                  // kPa
        case 0x0C: return rpm
        case 0x0D: return max(0, (rpm - 800) / 2200 * 110)
        case 0x0E: return 10 + load / 5
        case 0x0F: return 25 + 5 * wave
        case 0x10: return rpm / 100 * (0.5 + load / 100)
        case 0x11: return 12 + 60 * wave
        case 0x1F: return t
        case 0x21: return milOn ? 12 : 0
        case 0x2F: return max(0, 62 - t / 600)
        case 0x33: return 101
        case 0x42: return voltage(at: t)
        case 0x46: return 22
        case 0x5C: return coolant + 5
        case 0x5E: return 0.8 + load / 10
        default: return nil
        }
    }
}
