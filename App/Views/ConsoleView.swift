import OBDKit
import SwiftUI

/// Raw adapter traffic plus a command line for manual AT/OBD commands.
struct ConsoleView: View {
    @Environment(AppModel.self) private var app
    @FocusState private var focused: Bool

    private static let time: Date.FormatStyle = .dateTime.hour().minute().second().secondFraction(.fractional(3))

    var body: some View {
        @Bindable var console = app.console
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(console.events) { e in
                            HStack(alignment: .top, spacing: 8) {
                                Text(e.time, format: Self.time).foregroundStyle(.tertiary)
                                Text(prefix(e.kind)).foregroundStyle(color(e.kind)).frame(width: 18)
                                Text(e.text).foregroundStyle(color(e.kind)).textSelection(.enabled)
                            }
                            .id(e.id)
                        }
                    }
                    .font(.system(.caption, design: .monospaced))
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .onChange(of: console.events.count) {
                    if let last = console.events.last { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
            Divider()
            HStack(spacing: 8) {
                Text(">").font(.system(.body, design: .monospaced)).foregroundStyle(.secondary)
                TextField("AT or OBD command, e.g. ATRV or 010C", text: $console.command)
                    .textFieldStyle(.plain)
                    .font(.system(.body, design: .monospaced))
                    .focused($focused)
                    .onSubmit { Task { await console.send(to: app.client) } }
                    .disabled(!app.connection.isConnected)
                Button("Send") { Task { await console.send(to: app.client) } }
                    .disabled(!app.connection.isConnected || console.command.isEmpty)
                Button("Clear") { console.clear() }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
        .background(.background)
    }

    private func prefix(_ k: TrafficEvent.Kind) -> String {
        switch k {
        case .tx: return ">>"
        case .rx: return "<<"
        case .info: return "--"
        case .error: return "!!"
        }
    }

    private func color(_ k: TrafficEvent.Kind) -> Color {
        switch k {
        case .tx: return .blue
        case .rx: return .primary
        case .info: return .secondary
        case .error: return .red
        }
    }
}
