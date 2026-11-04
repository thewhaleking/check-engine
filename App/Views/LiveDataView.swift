import OBDKit
import SwiftUI

struct LiveDataView: View {
    @Environment(AppModel.self) private var app
    @State private var showingSelector = false

    private let columns = [GridItem(.adaptive(minimum: 190, maximum: 260), spacing: 12)]

    var body: some View {
        @Bindable var live = app.liveData
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button {
                    if live.isPolling { live.stop() } else if let client = app.client { live.start(client: client) }
                } label: {
                    Label(live.isPolling ? "Stop" : "Start", systemImage: live.isPolling ? "stop.fill" : "play.fill")
                }
                .disabled(!app.connection.vehicleReady)

                Stepper(value: $live.intervalMs, in: 100...5000, step: 100) {
                    Text("Every \(live.intervalMs) ms")
                        .monospacedDigit()
                }
                .disabled(live.isPolling)

                Toggle("Battery", isOn: $live.includeVoltage)
                    .toggleStyle(.checkbox)
                    .disabled(live.isPolling)

                Button("Select PIDs…") { showingSelector = true }
                    .disabled(live.isPolling)

                Spacer()
                LoggingBar()
            }
            .padding(12)

            Divider()

            if !app.connection.vehicleReady {
                ContentUnavailableView(
                    app.connection.isConnected ? "No Vehicle" : "Not Connected",
                    systemImage: "car.side",
                    description: Text(app.connection.isConnected
                        ? (app.connection.vehicleStatus ?? "The adapter is connected but the vehicle did not answer. Turn the ignition on and retry.")
                        : "Choose a port or enable the simulator, then press Connect.")
                )
                if app.connection.isConnected {
                    Button("Retry Vehicle") { Task { await app.connection.probeVehicle() } }
                        .padding(.bottom, 24)
                }
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(live.descriptors) { d in
                            ValueTile(descriptor: d, value: live.latest?.values[d.pid])
                        }
                        if live.includeVoltage {
                            ValueTile(descriptor: Self.batteryDescriptor, value: live.latest?.voltage)
                        }
                    }
                    .padding(12)
                }
                footer
            }
        }
        .sheet(isPresented: $showingSelector) {
            PIDSelectorSheet()
        }
    }

    private var footer: some View {
        HStack {
            if let error = app.liveData.error {
                Label(error, systemImage: "exclamationmark.circle").foregroundStyle(.red)
            } else if app.liveData.isPolling {
                Label("Polling · \(app.liveData.sampleCount) samples", systemImage: "waveform.path.ecg")
                    .foregroundStyle(.secondary)
            } else {
                Text("Stopped").foregroundStyle(.secondary)
            }
            Spacer()
        }
        .font(.caption)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    static let batteryDescriptor = PIDDescriptor(0xFF, name: "Battery Voltage", shortName: "Battery", unit: "V",
                                                 bytes: 0, range: 8...16) { _ in 0 }
}

struct PIDSelectorSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Live Data PIDs")
                .font(.headline)
                .padding()
            Divider()
            List {
                ForEach(PIDRegistry.mode01) { d in
                    let supported = app.connection.supportedPIDs.isEmpty || app.connection.supportedPIDs.contains(d.pid)
                    Toggle(isOn: Binding(
                        get: { app.liveData.selected.contains(d.pid) },
                        set: { _ in app.liveData.toggle(d.pid) }
                    )) {
                        HStack {
                            Text(d.name)
                            Spacer()
                            Text(d.pid.command).font(.caption.monospaced()).foregroundStyle(.secondary)
                            if !supported {
                                Text("not reported").font(.caption).foregroundStyle(.tertiary)
                            }
                        }
                    }
                    .disabled(!supported)
                }
            }
            Divider()
            HStack {
                Button("Defaults") { app.liveData.selected = PIDRegistry.defaultSelection }
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 420, height: 520)
    }
}
