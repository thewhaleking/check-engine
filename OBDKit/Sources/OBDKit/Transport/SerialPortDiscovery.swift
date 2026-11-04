import Foundation

public struct SerialPortInfo: Identifiable, Hashable, Sendable {
    public let path: String
    public var id: String { path }
    /// Display name, e.g. "usbserial-A50285BI".
    public var name: String { path.replacingOccurrences(of: "/dev/cu.", with: "") }
    /// True for USB serial adapters (usbserial, usbmodem, wchusbserial, SLAB_USBtoUART).
    public var isLikelyUSB: Bool {
        let n = name.lowercased()
        return n.contains("usb") || n.contains("slab") || n.contains("wch")
    }

    public init(path: String) { self.path = path }
}

public enum SerialPortDiscovery {
    static let ignored = ["Bluetooth-Incoming-Port", "debug-console", "wlan-debug"]

    /// All callout devices, USB adapters first.
    public static func listPorts(includeSystemPorts: Bool = false) -> [SerialPortInfo] {
        var g = glob_t()
        defer { globfree(&g) }
        guard glob("/dev/cu.*", 0, nil, &g) == 0 else { return [] }
        var ports: [SerialPortInfo] = []
        for i in 0..<Int(g.gl_matchc) {
            guard let c = g.gl_pathv[i] else { continue }
            let info = SerialPortInfo(path: String(cString: c))
            if !includeSystemPorts, ignored.contains(info.name) { continue }
            ports.append(info)
        }
        return ports.sorted { a, b in
            if a.isLikelyUSB != b.isLikelyUSB { return a.isLikelyUSB }
            return a.name < b.name
        }
    }
}
