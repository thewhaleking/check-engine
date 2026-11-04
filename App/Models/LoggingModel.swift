import AppKit
import Foundation
import OBDKit
import UniformTypeIdentifiers

@MainActor @Observable
final class LoggingModel {
    private(set) var isLogging = false
    private(set) var fileURL: URL?
    private(set) var rowCount = 0
    private(set) var error: String?

    private var continuation: AsyncStream<LiveSample>.Continuation?
    private var task: Task<Void, Never>?

    /// Asks for a destination, then logs every appended sample until `stop()`.
    func start(columns: [PIDDescriptor], includeVoltage: Bool) {
        guard !isLogging else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "obd-log-\(Self.stamp()).csv"
        panel.title = "Save OBD Log"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let logger: CSVLogger
        do {
            logger = try CSVLogger(url: url, columns: columns, includeVoltage: includeVoltage)
        } catch {
            self.error = error.localizedDescription
            return
        }
        let (stream, cont) = AsyncStream.makeStream(of: LiveSample.self, bufferingPolicy: .unbounded)
        continuation = cont
        fileURL = url
        rowCount = 0
        error = nil
        isLogging = true
        task = Task { [weak self] in
            for await sample in stream {
                do {
                    try await logger.append(sample)
                    self?.rowCount = await logger.rowCount
                } catch {
                    self?.error = error.localizedDescription
                    break
                }
            }
            do { try await logger.close() } catch { self?.error = error.localizedDescription }
            self?.isLogging = false
            self?.continuation = nil
        }
    }

    func append(_ sample: LiveSample) {
        continuation?.yield(sample)
    }

    func stop() {
        continuation?.finish()
    }

    func revealInFinder() {
        guard let fileURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([fileURL])
    }

    private static func stamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f.string(from: Date())
    }
}
