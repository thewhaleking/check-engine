import OBDKit
import SwiftUI

struct VehicleInfoView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let model = app.vehicleInfo
        VStack(spacing: 0) {
            HStack {
                Button {
                    Task { await load() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(!app.connection.vehicleReady || model.isBusy)
                if model.isBusy { ProgressView().controlSize(.small) }
                Spacer()
                if let t = model.loadedAt {
                    Text("Updated \(t, style: .time)").font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(12)
            Divider()

            if !app.connection.isConnected {
                ContentUnavailableView("Not Connected", systemImage: "car",
                                       description: Text("Connect to an adapter to see vehicle information."))
            } else {
                Form {
                    Section("Vehicle") {
                        row("VIN", model.info.vin ?? placeholder(model))
                        row("Calibration IDs", model.info.calibrationIDs.isEmpty ? placeholder(model) : model.info.calibrationIDs.joined(separator: ", "))
                        row("Battery", model.info.batteryVoltage.map { String(format: "%.1f V", $0) } ?? placeholder(model))
                        row("Supported PIDs", app.connection.supportedPIDs.isEmpty ? "—" : "\(app.connection.supportedPIDs.count)")
                    }
                    Section("Adapter") {
                        row("Firmware", app.connection.adapterVersion ?? "—")
                        row("Protocol", app.connection.protocolName ?? "—")
                        row("Link", app.connection.useSimulator ? "Built-in simulator"
                            : "\(app.connection.selectedPort ?? "?")" + (app.connection.detectedBaud.map { " @ \($0)" } ?? " @ \(app.connection.baud.label)"))
                    }
                    if let error = model.error {
                        Section { Text(error).foregroundStyle(.red).font(.caption) }
                    }
                }
                .formStyle(.grouped)
                .textSelection(.enabled)
            }
        }
        .task(id: app.connection.vehicleReady) {
            if app.connection.vehicleReady, model.loadedAt == nil { await load() }
        }
    }

    private func placeholder(_ model: VehicleInfoModel) -> String {
        model.loadedAt == nil ? "…" : "Unavailable"
    }

    private func row(_ label: String, _ value: String) -> some View {
        LabeledContent(label) {
            Text(value).font(.body.monospaced()).multilineTextAlignment(.trailing)
        }
    }

    private func load() async {
        guard let client = app.client else { return }
        await app.pausingPolling {
            await app.vehicleInfo.load(client: client,
                                       adapterVersion: app.connection.adapterVersion,
                                       protocolName: app.connection.protocolName)
        }
    }
}
