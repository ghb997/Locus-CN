import Foundation

/// Invalidates queued writes synchronously. The serial barrier clears AFTER an
/// already-running native call; cancelling a Swift task alone cannot do that.
final class LocationCommandQueue: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.chrismack.locus.location", qos: .userInitiated)
    private let lock = NSLock()
    private var generation = UUID()

    func beginSession() -> UUID {
        lock.lock()
        defer { lock.unlock() }
        generation = UUID()
        return generation
    }

    func isCurrent(_ value: UUID) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return value == generation
    }

    func perform<T>(generation: UUID, cancelled: T, operation: @escaping () -> T, completion: @escaping (T) -> Void) {
        queue.async {
            guard self.isCurrent(generation) else {
                completion(cancelled)
                return
            }
            completion(operation())
        }
    }

    func barrier<T>(operation: @escaping () -> T, completion: @escaping (T) -> Void) {
        queue.async { completion(operation()) }
    }
}
