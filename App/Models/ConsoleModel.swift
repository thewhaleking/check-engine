import Foundation
import OBDKit

@MainActor @Observable
final class ConsoleModel {
    private(set) var events: [TrafficEvent] = []
    var command = ""
    var isVisible = Preferences.consoleVisible {
        didSet { Preferences.consoleVisible = isVisible }
    }

    func append(_ event: TrafficEvent) {
        events.append(event)
        if events.count > 2000 { events.removeFirst(500) }
    }

    func info(_ text: String) { append(TrafficEvent(kind: .info, text: text)) }
    func error(_ text: String) { append(TrafficEvent(kind: .error, text: text)) }

    func clear() { events.removeAll() }

    /// Sends a raw command typed by the user. Replies arrive through the session's traffic stream.
    func send(to client: OBDClient?) async {
        let text = command.trimmingCharacters(in: .whitespacesAndNewlines)
        command = ""
        guard !text.isEmpty else { return }
        guard let client else { error("Not connected"); return }
        do {
            _ = try await client.session.command(text, timeout: .seconds(8))
        } catch {
            self.error(error.localizedDescription)
        }
    }
}
