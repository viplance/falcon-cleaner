import Foundation

/// Session cache of computed folder sizes, validated by the folder's content-modification date.
///
/// Note: a directory's modification date changes only when its *direct* children change
/// (add/remove/rename), not when a file nested deeper is edited. So a cached size can be stale
/// after a deep-nested change — an acceptable trade-off for a size browser, recoverable by
/// recomputing in a later scan.
nonisolated final class FolderSizeCache: @unchecked Sendable {
    static let shared = FolderSizeCache()

    private let lock = NSLock()
    private var cache: [String: (size: Int64, modDate: Date?)] = [:]

    /// Returns the cached size only if the folder's mod date matches what we stored.
    nonisolated func cachedSize(for path: String, modDate: Date?) -> Int64? {
        lock.lock(); defer { lock.unlock() }
        guard let entry = cache[path], entry.modDate == modDate else { return nil }
        return entry.size
    }

    nonisolated func store(_ size: Int64, for path: String, modDate: Date?) {
        lock.lock(); defer { lock.unlock() }
        cache[path] = (size, modDate)
    }
}
