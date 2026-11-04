import Foundation

public struct LiveSample: Sendable, Equatable {
    public let time: Date
    public let values: [PID: Double]
    public let voltage: Double?

    public init(time: Date = Date(), values: [PID: Double], voltage: Double? = nil) {
        self.time = time
        self.values = values
        self.voltage = voltage
    }
}
