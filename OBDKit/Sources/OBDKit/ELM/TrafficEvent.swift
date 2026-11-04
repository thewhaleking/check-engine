import Foundation

public struct TrafficEvent: Sendable, Identifiable {
    public enum Kind: Sendable { case tx, rx, info, error }
    public let id: UUID
    public let time: Date
    public let kind: Kind
    public let text: String

    public init(kind: Kind, text: String, time: Date = Date()) {
        self.id = UUID()
        self.time = time
        self.kind = kind
        self.text = text
    }
}
