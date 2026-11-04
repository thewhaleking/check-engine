import Foundation

public struct TimeoutError: Error, Sendable, Equatable {}

/// Runs `operation` and throws `TimeoutError` if it does not finish within `duration`.
public func withTimeout<T: Sendable>(
    _ duration: Duration,
    operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await operation() }
        group.addTask {
            try await Task.sleep(for: duration)
            throw TimeoutError()
        }
        guard let result = try await group.next() else { throw TimeoutError() }
        group.cancelAll()
        return result
    }
}
