import Foundation
import OBDKit

@MainActor @Observable
final class ConnectionModel {
    enum State: Equatable {
        case disconnected, connecting, connected
        case failed(String)
    }

    var ports: [SerialPortInfo] = []
    var selectedPort: String? = Preferences.lastPort {
        didSet { Preferences.lastPort = selectedPort }
    }
    var baud: BaudChoice = BaudChoice(rawValue: Preferences.baud) ?? .b38400 {
        didSet { Preferences.baud = baud.rawValue }
    }
    var useSimulator = Preferences.useSimulator {
        didSet { Preferences.useSimulator = useSimulator }
    }

    private(set) var state: State = .disconnected
    private(set) var adapterVersion: String?
    private(set) var protocolName: String?
    private(set) var detectedBaud: Int?
    /// Nil when the vehicle answered; otherwise a short reason (searching, unable to connect...).
    private(set) var vehicleStatus: String?
    private(set) var vehicleReady = false
    private(set) var supportedPIDs: Set<PID> = []
    private(set) var client: OBDClient?

    let console: ConsoleModel
    private var trafficTask: Task<Void, Never>?

    init(console: ConsoleModel) {
        self.console = console
        refreshPorts()
    }

    var isConnected: Bool { state == .connected }
    var isBusy: Bool { state == .connecting }

    func refreshPorts() {
        ports = SerialPortDiscovery.listPorts()
        if selectedPort == nil || !ports.contains(where: { $0.path == selectedPort }) {
            selectedPort = ports.first(where: \.isLikelyUSB)?.path ?? selectedPort
        }
    }

    func connect() async {
        guard state != .connecting else { return }
        state = .connecting
        adapterVersion = nil; protocolName = nil; detectedBaud = nil
        vehicleStatus = nil; vehicleReady = false; supportedPIDs = []

        let transport: any OBDTransport
        if useSimulator {
            transport = SimulatedELM327Transport(latency: .milliseconds(30))
            console.info("Using built-in simulator")
        } else {
            guard let path = selectedPort else { state = .failed("Select a serial port"); return }
            var rate = baud.rate
            if rate == nil {
                console.info("Detecting baud rate on \(path)…")
                let console = self.console
                let found = await BaudDetector.detect(path: path) { b in
                    Task { @MainActor in console.info("Trying \(b) baud") }
                }
                guard let found else {
                    state = .failed("No ELM327 reply at any baud rate")
                    return
                }
                rate = found
                detectedBaud = found
                console.info("Adapter answers at \(found) baud")
            }
            transport = SerialPortTransport(path: path, baudRate: rate!)
        }

        let client = OBDClient(transport: transport)
        self.client = client
        let console = self.console
        trafficTask = Task {
            for await event in client.session.traffic { console.append(event) }
        }
        do {
            let info = try await client.connect()
            adapterVersion = info.version
            state = .connected
        } catch {
            state = .failed(error.localizedDescription)
            await client.disconnect()
            self.client = nil
            return
        }
        await probeVehicle()
    }

    /// Runs the supported-PID walk, which performs the bus search. Safe to call again later.
    func probeVehicle() async {
        guard let client else { return }
        vehicleStatus = "Searching for vehicle…"
        do {
            supportedPIDs = try await client.supportedPIDs()
            protocolName = await client.protocolInfo?.name
            vehicleStatus = nil
            vehicleReady = true
        } catch {
            vehicleStatus = error.localizedDescription
            vehicleReady = false
        }
    }

    func disconnect() async {
        guard let client else { state = .disconnected; return }
        await client.disconnect()
        self.client = nil
        trafficTask?.cancel()
        trafficTask = nil
        state = .disconnected
        vehicleReady = false
        vehicleStatus = nil
    }
}
