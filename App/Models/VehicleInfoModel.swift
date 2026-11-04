import Foundation
import OBDKit

@MainActor @Observable
final class VehicleInfoModel {
    private(set) var info = VehicleInfo()
    private(set) var isBusy = false
    private(set) var error: String?
    private(set) var loadedAt: Date?

    func load(client: OBDClient, adapterVersion: String?, protocolName: String?) async {
        isBusy = true; error = nil
        defer { isBusy = false }
        var next = VehicleInfo()
        next.elmVersion = adapterVersion
        next.protocolName = protocolName
        next.batteryVoltage = try? await client.batteryVoltage()
        do {
            next.vin = try await client.vin()
        } catch {
            self.error = "VIN: \(error.localizedDescription)"
        }
        do {
            next.calibrationIDs = try await client.calibrationIDs()
        } catch {
            self.error = (self.error.map { $0 + "\n" } ?? "") + "Calibration ID: \(error.localizedDescription)"
        }
        info = next
        loadedAt = Date()
    }

    func reset() { info = VehicleInfo(); loadedAt = nil; error = nil }
}
