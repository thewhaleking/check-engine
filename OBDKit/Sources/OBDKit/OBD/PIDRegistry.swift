import Foundation

public enum PIDRegistry {
    private static func a(_ b: [UInt8]) -> Double { Double(b[0]) }
    private static func ab(_ b: [UInt8]) -> Double { Double(b[0]) * 256 + Double(b[1]) }

    public static let mode01: [PIDDescriptor] = [
        PIDDescriptor(0x04, name: "Engine Load", shortName: "Load", unit: "%", bytes: 1, range: 0...100) { a($0) * 100 / 255 },
        PIDDescriptor(0x05, name: "Coolant Temperature", shortName: "Coolant", unit: "°C", bytes: 1, range: -40...215) { a($0) - 40 },
        PIDDescriptor(0x0A, name: "Fuel Pressure", shortName: "Fuel Press", unit: "kPa", bytes: 1, range: 0...765) { a($0) * 3 },
        PIDDescriptor(0x0B, name: "Intake Manifold Pressure", shortName: "MAP", unit: "kPa", bytes: 1, range: 0...255) { a($0) },
        PIDDescriptor(0x0C, name: "Engine RPM", shortName: "RPM", unit: "rpm", bytes: 2, range: 0...8000) { ab($0) / 4 },
        PIDDescriptor(0x0D, name: "Vehicle Speed", shortName: "Speed", unit: "km/h", bytes: 1, range: 0...255) { a($0) },
        PIDDescriptor(0x0E, name: "Timing Advance", shortName: "Timing", unit: "°", bytes: 1, range: -64...63.5) { a($0) / 2 - 64 },
        PIDDescriptor(0x0F, name: "Intake Air Temperature", shortName: "IAT", unit: "°C", bytes: 1, range: -40...215) { a($0) - 40 },
        PIDDescriptor(0x10, name: "Mass Air Flow", shortName: "MAF", unit: "g/s", bytes: 2, range: 0...655.35) { ab($0) / 100 },
        PIDDescriptor(0x11, name: "Throttle Position", shortName: "Throttle", unit: "%", bytes: 1, range: 0...100) { a($0) * 100 / 255 },
        PIDDescriptor(0x1F, name: "Run Time Since Start", shortName: "Run Time", unit: "s", bytes: 2, range: 0...65535) { ab($0) },
        PIDDescriptor(0x21, name: "Distance With MIL On", shortName: "MIL Dist", unit: "km", bytes: 2, range: 0...65535) { ab($0) },
        PIDDescriptor(0x2F, name: "Fuel Level", shortName: "Fuel", unit: "%", bytes: 1, range: 0...100) { a($0) * 100 / 255 },
        PIDDescriptor(0x33, name: "Barometric Pressure", shortName: "Baro", unit: "kPa", bytes: 1, range: 0...255) { a($0) },
        PIDDescriptor(0x42, name: "Control Module Voltage", shortName: "ECU Volt", unit: "V", bytes: 2, range: 0...65.535) { ab($0) / 1000 },
        PIDDescriptor(0x46, name: "Ambient Air Temperature", shortName: "Ambient", unit: "°C", bytes: 1, range: -40...215) { a($0) - 40 },
        PIDDescriptor(0x5C, name: "Engine Oil Temperature", shortName: "Oil Temp", unit: "°C", bytes: 1, range: -40...210) { a($0) - 40 },
        PIDDescriptor(0x5E, name: "Engine Fuel Rate", shortName: "Fuel Rate", unit: "L/h", bytes: 2, range: 0...3276.75) { ab($0) / 20 },
    ]

    private static let byPID: [PID: PIDDescriptor] = Dictionary(uniqueKeysWithValues: mode01.map { ($0.pid, $0) })

    public static func descriptor(for pid: PID) -> PIDDescriptor? { byPID[pid] }

    /// A sensible default dashboard selection.
    public static let defaultSelection: [PID] = [0x0C, 0x0D, 0x05, 0x04, 0x11, 0x0F].map(PID.mode01)
}
