import Foundation
import OBDKit

// obdcli — command-line probe for OBDKit.
//   obdcli ports
//   obdcli probe --port /dev/cu.usbserial-XXXX [--baud 38400|auto] [--poll <seconds>]
//   obdcli sim [--seconds 5]

func usage() -> Never {
    print("""
    usage:
      obdcli ports
      obdcli probe --port <path> [--baud <rate>|auto] [--poll <seconds>]
      obdcli sim [--seconds <n>]
    """)
    exit(2)
}

func option(_ name: String, in args: [String]) -> String? {
    guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
    return args[i + 1]
}

func watchTraffic(_ session: ELM327Session) -> Task<Void, Never> {
    Task.detached {
        for await e in session.traffic {
            let prefix: String
            switch e.kind {
            case .tx: prefix = ">>"
            case .rx: prefix = "<<"
            case .info: prefix = "--"
            case .error: prefix = "!!"
            }
            print("  \(prefix) \(e.text)")
        }
    }
}

/// Connects and polls the default PID selection for `seconds`, one line per sample.
func runPolling(client: OBDClient, seconds: Int) async throws {
    try await client.connect()
    _ = try await client.supportedPIDs()
    print("\nPolling for \(seconds) s...")
    let pids = PIDRegistry.defaultSelection
    let stream = await client.startPolling(pids: pids, includeVoltage: true, interval: .milliseconds(500))
    let deadline = ContinuousClock.now + .seconds(seconds)
    var samples = 0
    for try await sample in stream {
        samples += 1
        let parts = pids.compactMap { pid -> String? in
            guard let d = PIDRegistry.descriptor(for: pid), let v = sample.values[pid] else { return nil }
            return "\(d.shortName)=\(String(format: "%.1f", v))"
        }
        print(parts.joined(separator: "  ") + (sample.voltage.map { "  V=\($0)" } ?? ""))
        if ContinuousClock.now >= deadline { break }
    }
    print("\(samples) samples")
    await client.disconnect()
}

func runProbe(client: OBDClient) async {
    do {
        let info = try await client.connect()
        print("Adapter: \(info.version)")
        if let v = try? await client.batteryVoltage() { print("Battery: \(v) V") }
        let supported = try await client.supportedPIDs()
        if let p = await client.protocolInfo { print("Protocol: \(p.number) \(p.name)") }
        print("Supported PIDs: \(supported.sorted().map(\.command).joined(separator: " "))")
        for pid in [PID.mode01(0x0C), .mode01(0x0D), .mode01(0x05)] {
            guard let d = PIDRegistry.descriptor(for: pid) else { continue }
            if let v = try? await client.read(pid) { print("\(d.name): \(v) \(d.unit)") }
        }
        let mil = try? await client.milStatus()
        print("MIL: \(mil.map { $0.milOn ? "ON" : "off" } ?? "?") (\(mil?.dtcCount ?? 0) codes)")
        for kind in DTCKind.allCases {
            let codes = (try? await client.readDTCs(kind: kind)) ?? []
            print("\(kind.title) DTCs: \(codes.isEmpty ? "none" : codes.map(\.code).joined(separator: ", "))")
        }
        print("VIN: \((try? await client.vin()) ?? nil ?? "unavailable")")
        print("Calibration IDs: \((try? await client.calibrationIDs())?.joined(separator: ", ") ?? "unavailable")")
    } catch {
        print("ERROR: \(error.localizedDescription)")
    }
    await client.disconnect()
}

let args = Array(CommandLine.arguments.dropFirst())
guard let command = args.first else { usage() }

switch command {
case "ports":
    let ports = SerialPortDiscovery.listPorts(includeSystemPorts: true)
    if ports.isEmpty { print("No serial ports found.") }
    for p in ports { print("\(p.path)\(p.isLikelyUSB ? "   (USB)" : "")") }

case "probe":
    guard let port = option("--port", in: args) else { usage() }
    var baud = 38400
    if let b = option("--baud", in: args) {
        if b.lowercased() == "auto" {
            print("Detecting baud rate...")
            guard let found = await BaudDetector.detect(path: port, progress: { print("  trying \($0)") }) else {
                print("No ELM327 reply at any baud rate. Check the cable and that it has power.")
                exit(1)
            }
            baud = found
            print("Adapter answers at \(baud) baud.")
        } else if let n = Int(b) {
            baud = n
        } else { usage() }
    }
    let transport = SerialPortTransport(path: port, baudRate: baud)
    let client = OBDClient(transport: transport)
    let watcher = watchTraffic(client.session)
    await runProbe(client: client)
    watcher.cancel()
    if let n = option("--poll", in: args).flatMap(Int.init) {
        try await runPolling(client: client, seconds: n)
    }

case "sim":
    let seconds = Int(option("--seconds", in: args) ?? "5") ?? 5
    let transport = SimulatedELM327Transport()
    let client = OBDClient(transport: transport)
    let watcher = watchTraffic(client.session)
    await runProbe(client: client)
    watcher.cancel()
    try await runPolling(client: client, seconds: seconds)

default:
    usage()
}
