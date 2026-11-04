import SwiftUI

struct LoggingBar: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        HStack(spacing: 8) {
            if app.logging.isLogging {
                Label("\(app.logging.rowCount) rows", systemImage: "record.circle")
                    .foregroundStyle(.red)
                    .monospacedDigit()
                if let url = app.logging.fileURL {
                    Button(url.lastPathComponent) { app.logging.revealInFinder() }
                        .buttonStyle(.link)
                        .lineLimit(1)
                }
                Button("Stop Log") { app.logging.stop() }
            } else {
                Button {
                    app.logging.start(columns: app.liveData.descriptors, includeVoltage: app.liveData.includeVoltage)
                } label: {
                    Label("Log to CSV…", systemImage: "square.and.arrow.down")
                }
                .disabled(!app.connection.vehicleReady || app.liveData.descriptors.isEmpty)
                .help("Writes one row per poll cycle. Start polling to collect data.")
            }
            if let error = app.logging.error {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange).help(error)
            }
        }
    }
}
