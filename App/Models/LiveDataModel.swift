import Foundation
import OBDKit

@MainActor @Observable
final class LiveDataModel {
    var selected: [PID] = Preferences.selectedPIDs {
        didSet { Preferences.selectedPIDs = selected }
    }
    var intervalMs: Int = Preferences.pollIntervalMs {
        didSet { Preferences.pollIntervalMs = intervalMs }
    }
    var includeVoltage: Bool = Preferences.includeVoltage {
        didSet { Preferences.includeVoltage = includeVoltage }
    }
    private(set) var latest: LiveSample?
    private(set) var isPolling = false
    private(set) var error: String?
    private(set) var sampleCount = 0

    /// Called on the main actor for every sample (used by CSV logging).
    var onSample: (@MainActor (LiveSample) -> Void)?

    private var task: Task<Void, Never>?
    private weak var client: OBDClient?

    var descriptors: [PIDDescriptor] { selected.compactMap(PIDRegistry.descriptor(for:)) }

    func start(client: OBDClient) {
        stop()
        guard !selected.isEmpty else { error = "Select at least one PID"; return }
        self.client = client
        isPolling = true
        error = nil
        let pids = selected
        let voltage = includeVoltage
        let interval = Duration.milliseconds(max(100, intervalMs))
        task = Task { [weak self] in
            let stream = await client.startPolling(pids: pids, includeVoltage: voltage, interval: interval)
            do {
                for try await sample in stream {
                    guard let self, !Task.isCancelled else { break }
                    latest = sample
                    sampleCount += 1
                    onSample?(sample)
                }
            } catch {
                self?.error = error.localizedDescription
            }
            self?.isPolling = false
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        isPolling = false
        if let client { Task { await client.stopPolling() } }
    }

    /// Stops and waits until the poll loop has exited, so another request can go first.
    func stopAndWait() async {
        let t = task
        stop()
        _ = await t?.value
    }

    func toggle(_ pid: PID) {
        if let i = selected.firstIndex(of: pid) { selected.remove(at: i) } else { selected.append(pid); selected.sort() }
    }
}
