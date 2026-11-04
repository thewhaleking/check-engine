import Foundation

/// Appends one CSV row per `LiveSample`. Buffered; flushes every second or 20 rows.
public actor CSVLogger {
    public let url: URL
    public let columns: [PIDDescriptor]
    public let includeVoltage: Bool
    public private(set) var rowCount = 0

    private let handle: FileHandle
    private var pending = ""
    private var pendingRows = 0
    private var lastFlush = ContinuousClock.now
    private let style = Date.ISO8601FormatStyle(includingFractionalSeconds: true, timeZone: .current)

    public init(url: URL, columns: [PIDDescriptor], includeVoltage: Bool) throws {
        self.url = url
        self.columns = columns
        self.includeVoltage = includeVoltage
        guard FileManager.default.createFile(atPath: url.path, contents: nil) else {
            throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: url.path])
        }
        handle = try FileHandle(forWritingTo: url)
        var header = ["timestamp", "unix_time"] + columns.map { Self.csvField("\($0.name) (\($0.unit))") }
        if includeVoltage { header.append("Battery (V)") }
        try handle.write(contentsOf: Data((header.joined(separator: ",") + "\n").utf8))
    }

    public func append(_ sample: LiveSample) throws {
        var fields = [sample.time.formatted(style), String(format: "%.3f", sample.time.timeIntervalSince1970)]
        for c in columns { fields.append(sample.values[c.pid].map(Self.format) ?? "") }
        if includeVoltage { fields.append(sample.voltage.map(Self.format) ?? "") }
        pending += fields.joined(separator: ",") + "\n"
        pendingRows += 1
        rowCount += 1
        if pendingRows >= 20 || ContinuousClock.now - lastFlush >= .seconds(1) { try flush() }
    }

    public func flush() throws {
        guard !pending.isEmpty else { return }
        try handle.write(contentsOf: Data(pending.utf8))
        pending = ""
        pendingRows = 0
        lastFlush = .now
    }

    public func close() throws {
        try flush()
        try handle.close()
    }

    static func format(_ v: Double) -> String {
        var s = String(format: "%.2f", v)
        while s.hasSuffix("0") { s.removeLast() }
        if s.hasSuffix(".") { s.removeLast() }
        return s
    }

    static func csvField(_ s: String) -> String {
        s.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" }) ? "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : s
    }
}
