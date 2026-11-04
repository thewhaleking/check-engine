import Foundation
import OBDKit

@MainActor @Observable
final class TroubleCodesModel {
    private(set) var codes: [DTCKind: [DTC]] = [:]
    private(set) var mil: OBDClient.MILStatus?
    private(set) var lastRead: Date?
    private(set) var isBusy = false
    private(set) var error: String?
    private(set) var lastClearSucceeded: Bool?

    func read(client: OBDClient) async {
        isBusy = true; error = nil; lastClearSucceeded = nil
        defer { isBusy = false }
        var result: [DTCKind: [DTC]] = [:]
        do {
            mil = try? await client.milStatus()
            for kind in DTCKind.allCases {
                do {
                    result[kind] = try await client.readDTCs(kind: kind)
                } catch ELMError.unexpectedResponse, ELMError.negativeResponse, ELMError.busError {
                    result[kind] = []   // Many ECUs do not support Mode 0A; treat as none.
                }
            }
            codes = result
            lastRead = Date()
        } catch {
            self.error = error.localizedDescription
        }
    }

    func clear(client: OBDClient) async {
        isBusy = true; error = nil
        defer { isBusy = false }
        do {
            try await client.clearDTCs()
            lastClearSucceeded = true
        } catch {
            lastClearSucceeded = false
            self.error = error.localizedDescription
            return
        }
        await read(client: client)
        lastClearSucceeded = true
    }

    var total: Int { codes.values.reduce(0) { $0 + $1.count } }
}
