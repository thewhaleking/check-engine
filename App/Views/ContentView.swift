import OBDKit
import SwiftUI

enum AppSection: String, CaseIterable, Identifiable {
    case liveData, troubleCodes, vehicleInfo
    var id: String { rawValue }
    var title: String {
        switch self {
        case .liveData: return "Live Data"
        case .troubleCodes: return "Trouble Codes"
        case .vehicleInfo: return "Vehicle Info"
        }
    }
    var icon: String {
        switch self {
        case .liveData: return "gauge.with.dots.needle.50percent"
        case .troubleCodes: return "exclamationmark.triangle"
        case .vehicleInfo: return "car"
        }
    }
}

struct ContentView: View {
    @Environment(AppModel.self) private var app
    @State private var section: AppSection = .liveData

    var body: some View {
        NavigationSplitView {
            List(AppSection.allCases, selection: $section) { s in
                Label(s.title, systemImage: s.icon).tag(s)
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 190, max: 240)
        } detail: {
            VStack(spacing: 0) {
                ConnectionBar()
                Divider()
                detail
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                if app.console.isVisible {
                    Divider()
                    ConsoleView()
                        .frame(height: 190)
                }
            }
            .navigationTitle(section.title)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    app.console.isVisible.toggle()
                } label: {
                    Label("Console", systemImage: "terminal")
                }
                .help(app.console.isVisible ? "Hide console" : "Show console")
            }
        }
        .frame(minWidth: 860, minHeight: 540)
        .task { await autoconnectIfRequested() }
    }

    /// Developer convenience: `OBDII --autoconnect [--simulate] [--poll]` connects on launch.
    private func autoconnectIfRequested() async {
        let args = CommandLine.arguments
        guard args.contains("--autoconnect") else { return }
        if args.contains("--simulate") { app.connection.useSimulator = true }
        await app.connect()
        if args.contains("--poll"), let client = app.client, app.connection.vehicleReady {
            app.liveData.start(client: client)
        }
        // `--smoke <seconds>`: headless self-check. Prints state to stdout and exits 0 on success.
        if let i = args.firstIndex(of: "--smoke"), i + 1 < args.count, let seconds = Int(args[i + 1]) {
            try? await Task.sleep(for: .seconds(seconds))
            var ok = true
            func line(_ label: String, _ value: String) { print("\(label): \(value)") }
            line("state", "\(app.connection.state)")
            line("adapter", app.connection.adapterVersion ?? "nil")
            line("protocol", app.connection.protocolName ?? "nil")
            line("supportedPIDs", "\(app.connection.supportedPIDs.count)")
            line("samples", "\(app.liveData.sampleCount)")
            if let s = app.liveData.latest {
                line("latest", s.values.sorted { $0.key < $1.key }.map { "\($0.key.command)=\(ValueTile.format($0.value))" }.joined(separator: " ") + " V=\(s.voltage ?? 0)")
            }
            line("pollError", app.liveData.error ?? "none")
            if let client = app.client {
                await app.pausingPolling { await app.troubleCodes.read(client: client) }
                line("dtcs", DTCKind.allCases.map { "\($0.rawValue)=\((app.troubleCodes.codes[$0] ?? []).map(\.code).joined(separator: "/"))" }.joined(separator: " "))
                line("mil", "\(String(describing: app.troubleCodes.mil))")
                await app.pausingPolling { await app.vehicleInfo.load(client: client, adapterVersion: app.connection.adapterVersion, protocolName: app.connection.protocolName) }
                line("vin", app.vehicleInfo.info.vin ?? "nil")
                line("calIDs", app.vehicleInfo.info.calibrationIDs.joined(separator: ","))
                await app.pausingPolling { await app.troubleCodes.clear(client: client) }
                line("afterClear", "\(app.troubleCodes.total) codes, mil=\(String(describing: app.troubleCodes.mil?.milOn))")
                line("pollingResumed", "\(app.liveData.isPolling)")
                ok = app.connection.vehicleReady && app.liveData.sampleCount > 0 && app.vehicleInfo.info.vin != nil && app.liveData.isPolling
            } else { ok = false }
            line("console", "\(app.console.events.count) events")
            await app.disconnect()
            print(ok ? "SMOKE OK" : "SMOKE FAILED")
            exit(ok ? 0 : 1)
        }
    }

    @ViewBuilder private var detail: some View {
        switch section {
        case .liveData: LiveDataView()
        case .troubleCodes: TroubleCodesView()
        case .vehicleInfo: VehicleInfoView()
        }
    }
}
