import Foundation
import OBDKit

@MainActor @Observable
final class AppModel {
    let console = ConsoleModel()
    let connection: ConnectionModel
    let liveData = LiveDataModel()
    let troubleCodes = TroubleCodesModel()
    let vehicleInfo = VehicleInfoModel()
    let logging = LoggingModel()

    init() {
        connection = ConnectionModel(console: console)
        let logging = self.logging
        liveData.onSample = { sample in logging.append(sample) }
    }

    var client: OBDClient? { connection.client }

    func connect() async {
        await connection.connect()
    }

    func disconnect() async {
        liveData.stop()
        logging.stop()
        vehicleInfo.reset()
        await connection.disconnect()
    }

    func toggleConnection() async {
        if connection.isConnected { await disconnect() } else { await connect() }
    }

    /// Suspends live polling around a one-off request so it does not wait behind a full poll cycle.
    func pausingPolling<T: Sendable>(_ body: () async -> T) async -> T {
        let wasPolling = liveData.isPolling
        if wasPolling { await liveData.stopAndWait() }
        let result = await body()
        if wasPolling, let client { liveData.start(client: client) }
        return result
    }
}
