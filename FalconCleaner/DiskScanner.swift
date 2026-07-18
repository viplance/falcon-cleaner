import Foundation

/// Lists directory contents for the Disk browser — current level only, no recursion.
final class DiskScanner {
    static let shared = DiskScanner()
    private let fileManager = FileManager.default

    /// Immediate contents of a directory (hidden files skipped), folders first then alphabetical.
    /// Files carry their byte size; folders carry the count of their immediate items. Nothing is
    /// traversed recursively, so this is fast and bounded regardless of how large the tree is.
    func listDirectory(_ url: URL) -> [DiskEntry] {
        let keys: [URLResourceKey] = [.isDirectoryKey, .fileSizeKey, .totalFileAllocatedSizeKey, .contentModificationDateKey]
        guard let contents = try? fileManager.contentsOfDirectory(
            at: url, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]
        ) else { return [] }

        var entries: [DiskEntry] = []
        for itemURL in contents {
            let values = try? itemURL.resourceValues(forKeys: Set(keys))
            let isDirectory = values?.isDirectory ?? false

            if isDirectory {
                // Immediate item count (shown in its own column) + a cached recursive size if
                // the folder's mod date is unchanged.
                let modDate = values?.contentModificationDate
                let cachedSize = FolderSizeCache.shared.cachedSize(for: itemURL.path, modDate: modDate)
                let count = (try? fileManager.contentsOfDirectory(
                    at: itemURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
                ))?.count
                entries.append(DiskEntry(url: itemURL, name: itemURL.lastPathComponent,
                                         isDirectory: true, size: nil, itemCount: count,
                                         folderSize: cachedSize))
            } else {
                let fileSize = Int64(values?.totalFileAllocatedSize ?? values?.fileSize ?? 0)
                entries.append(DiskEntry(url: itemURL, name: itemURL.lastPathComponent,
                                         isDirectory: false, size: fileSize, itemCount: nil))
            }
        }

        return entries.sorted { lhs, rhs in
            if lhs.isDirectory != rhs.isDirectory { return lhs.isDirectory }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    /// Recursive allocated size of a directory, computed only on demand. Each iteration runs
    /// inside an `autoreleasepool` so transient URLs/resource values don't pile up (that was the
    /// out-of-memory cause), and a hard file cap guards against runaway/cloud trees.
    func directorySize(_ url: URL, isCancelled: () -> Bool = { false }) -> Int64 {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey]
        // Count everything the way Finder's "Get Info" does: include hidden files (e.g.
        // ~/.orbstack, ~/.docker, caches) and the contents of packages/.app bundles. Skipping
        // them badly under-reports folder sizes.
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: Array(keys),
            options: []
        ) else { return 0 }

        var size: Int64 = 0
        var counter = 0
        let maxFiles = 3_000_000
        var stop = false
        while !stop {
            autoreleasepool {
                guard let fileURL = enumerator.nextObject() as? URL else { stop = true; return }
                counter += 1
                if counter > maxFiles || (counter & 0x1FFF == 0 && isCancelled()) {
                    stop = true
                    return
                }
                if let values = try? fileURL.resourceValues(forKeys: keys),
                   values.isRegularFile ?? false {
                    size += Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
                }
            }
        }
        return size
    }
}
