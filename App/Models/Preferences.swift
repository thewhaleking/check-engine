import Foundation
import OBDKit

/// Thin UserDefaults wrapper for settings that outlive a launch.
enum Preferences {
    private static var d: UserDefaults { .standard }

    static var lastPort: String? {
        get { d.string(forKey: "lastPort") }
        set { d.set(newValue, forKey: "lastPort") }
    }
    static var baud: String {
        get { d.string(forKey: "baud") ?? BaudChoice.b38400.rawValue }
        set { d.set(newValue, forKey: "baud") }
    }
    static var useSimulator: Bool {
        get { d.object(forKey: "useSimulator") as? Bool ?? true }
        set { d.set(newValue, forKey: "useSimulator") }
    }
    static var pollIntervalMs: Int {
        get { let v = d.integer(forKey: "pollIntervalMs"); return v == 0 ? 500 : v }
        set { d.set(newValue, forKey: "pollIntervalMs") }
    }
    static var includeVoltage: Bool {
        get { d.object(forKey: "includeVoltage") as? Bool ?? true }
        set { d.set(newValue, forKey: "includeVoltage") }
    }
    static var selectedPIDs: [PID] {
        get {
            guard let raw = d.stringArray(forKey: "selectedPIDs") else { return PIDRegistry.defaultSelection }
            return raw.compactMap { s in
                guard s.count == 4, let m = UInt8(s.prefix(2), radix: 16), let p = UInt8(s.suffix(2), radix: 16) else { return nil }
                return PID(mode: m, id: p)
            }
        }
        set { d.set(newValue.map(\.command), forKey: "selectedPIDs") }
    }
    static var consoleVisible: Bool {
        get { d.object(forKey: "consoleVisible") as? Bool ?? true }
        set { d.set(newValue, forKey: "consoleVisible") }
    }
}

enum BaudChoice: String, CaseIterable, Identifiable {
    case auto, b9600, b38400, b115200, b1000000
    var id: String { rawValue }
    var rate: Int? {
        switch self {
        case .auto: return nil
        case .b9600: return 9600
        case .b38400: return 38400
        case .b115200: return 115200
        case .b1000000: return 1_000_000
        }
    }
    var label: String { rate.map { "\($0)" } ?? "Auto" }
}
