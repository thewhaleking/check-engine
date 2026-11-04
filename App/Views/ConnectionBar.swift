import OBDKit
import SwiftUI

/// Port / baud / simulator controls plus a status line. Sits above the detail area.
struct ConnectionBar: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var connection = app.connection
        HStack(spacing: 12) {
            Toggle("Simulator", isOn: $connection.useSimulator)
                .toggleStyle(.switch)
                .controlSize(.small)
                .disabled(connection.isConnected || connection.isBusy)

            Picker("Port", selection: $connection.selectedPort) {
                if connection.ports.isEmpty {
                    Text("No serial ports").tag(String?.none)
                }
                ForEach(connection.ports) { port in
                    Text(port.name).tag(Optional(port.path))
                }
            }
            .frame(maxWidth: 260)
            .disabled(connection.useSimulator || connection.isConnected || connection.isBusy)

            Button {
                connection.refreshPorts()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help("Rescan serial ports")
            .disabled(connection.useSimulator || connection.isConnected || connection.isBusy)

            Picker("Baud", selection: $connection.baud) {
                ForEach(BaudChoice.allCases) { Text($0.label).tag($0) }
            }
            .frame(width: 140)
            .disabled(connection.useSimulator || connection.isConnected || connection.isBusy)

            Spacer()

            statusView

            Button(connection.isConnected ? "Disconnect" : "Connect") {
                Task { await app.toggleConnection() }
            }
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(connection.isBusy)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private var statusView: some View {
        HStack(spacing: 6) {
            Circle().fill(statusColor).frame(width: 9, height: 9)
            VStack(alignment: .trailing, spacing: 1) {
                Text(statusTitle).font(.callout)
                if let detail = statusDetail {
                    Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
        }
    }

    private var statusColor: Color {
        switch app.connection.state {
        case .disconnected: return .gray
        case .connecting: return .yellow
        case .connected: return app.connection.vehicleReady ? .green : .orange
        case .failed: return .red
        }
    }

    private var statusTitle: String {
        switch app.connection.state {
        case .disconnected: return "Disconnected"
        case .connecting: return "Connecting…"
        case .connected: return app.connection.vehicleReady ? "Connected" : "Adapter only"
        case .failed: return "Failed"
        }
    }

    private var statusDetail: String? {
        let c = app.connection
        switch c.state {
        case .failed(let reason): return reason
        case .connected:
            if let s = c.vehicleStatus { return s }
            var parts: [String] = []
            if let v = c.adapterVersion { parts.append(v) }
            if let p = c.protocolName { parts.append(p) }
            if let b = c.detectedBaud { parts.append("\(b) baud") }
            return parts.isEmpty ? nil : parts.joined(separator: " · ")
        default: return nil
        }
    }
}
