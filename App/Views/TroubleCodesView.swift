import OBDKit
import SwiftUI

struct TroubleCodesView: View {
    @Environment(AppModel.self) private var app
    @State private var confirmClear = false

    var body: some View {
        let model = app.troubleCodes
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button {
                    Task { await read() }
                } label: {
                    Label("Read Codes", systemImage: "arrow.down.doc")
                }
                .disabled(!app.connection.vehicleReady || model.isBusy)

                Button(role: .destructive) {
                    confirmClear = true
                } label: {
                    Label("Clear Codes…", systemImage: "trash")
                }
                .disabled(!app.connection.vehicleReady || model.isBusy)

                if model.isBusy { ProgressView().controlSize(.small) }
                Spacer()
                if let mil = model.mil {
                    Label(mil.milOn ? "Check Engine light ON" : "Check Engine light off",
                          systemImage: mil.milOn ? "engine.combustion.fill" : "engine.combustion")
                        .foregroundStyle(mil.milOn ? .orange : .secondary)
                }
                if let t = model.lastRead {
                    Text("Read \(t, style: .time)").font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(12)
            Divider()

            if !app.connection.vehicleReady {
                ContentUnavailableView("Not Connected", systemImage: "exclamationmark.triangle",
                                       description: Text("Connect to a vehicle to read trouble codes."))
            } else if model.lastRead == nil {
                ContentUnavailableView("No Data Yet", systemImage: "doc.text.magnifyingglass",
                                       description: Text("Press Read Codes to query stored, pending and permanent codes."))
            } else if model.total == 0 {
                ContentUnavailableView("No Trouble Codes", systemImage: "checkmark.seal",
                                       description: Text("The vehicle reported no stored, pending or permanent codes."))
            } else {
                List {
                    ForEach(DTCKind.allCases) { kind in
                        let list = model.codes[kind] ?? []
                        Section("\(kind.title) (\(list.count))") {
                            if list.isEmpty {
                                Text("None").foregroundStyle(.secondary)
                            }
                            ForEach(list) { dtc in
                                HStack(alignment: .firstTextBaseline) {
                                    Text(dtc.code).font(.body.monospaced().bold()).frame(width: 70, alignment: .leading)
                                    Text(dtc.summary ?? "No description available").foregroundStyle(dtc.summary == nil ? .secondary : .primary)
                                    Spacer()
                                    Text(Hex.string(dtc.bytes)).font(.caption.monospaced()).foregroundStyle(.tertiary)
                                }
                                .textSelection(.enabled)
                            }
                        }
                    }
                }
            }

            if let error = model.error {
                Divider()
                Label(error, systemImage: "exclamationmark.circle")
                    .foregroundStyle(.red).font(.caption)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
            }
        }
        .confirmationDialog("Clear all trouble codes?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Clear Codes", role: .destructive) { Task { await clear() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This sends Mode 04. It erases stored codes, freeze frame data and readiness monitors. Do this with the engine off and ignition on.")
        }
    }

    private func read() async {
        guard let client = app.client else { return }
        await app.pausingPolling { await app.troubleCodes.read(client: client) }
    }

    private func clear() async {
        guard let client = app.client else { return }
        await app.pausingPolling { await app.troubleCodes.clear(client: client) }
    }
}
