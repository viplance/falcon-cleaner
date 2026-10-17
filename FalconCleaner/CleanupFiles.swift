import Foundation

/// A denied metadata lookup must never be mistaken for an already deleted file.
nonisolated enum CleanupFiles {
    static func uniqueTargets(_ urls: [URL]) -> [URL] {
        var seen = Set<String>()
        let unique = urls.filter { seen.insert($0.standardizedFileURL.path).inserted }
        return unique.filter { url in
            !unique.contains { other in
                url.standardizedFileURL.path.hasPrefix(other.standardizedFileURL.path + "/")
            }
        }
    }

    static func exists(_ url: URL) throws -> Bool {
        do {
            _ = try FileManager.default.attributesOfItem(atPath: url.path)
            return true
        } catch let error as NSError {
            if error.domain == NSCocoaErrorDomain, error.code == NSFileReadNoSuchFileError { return false }
            throw error
        }
    }

    static func moveToTrash(_ targets: [URL], using trash: (URL) throws -> Void) throws {
        var failures: [String] = []
        for url in targets {
            do {
                if try exists(url) { try trash(url) }
                if try exists(url) {
                    throw NSError(domain: "FalconCleaner", code: 1, userInfo: [
                        NSLocalizedDescriptionKey: "The item is still in its original location."
                    ])
                }
            } catch {
                failures.append("\(url.path): \(error.localizedDescription)")
            }
        }
        if !failures.isEmpty {
            throw NSError(domain: "FalconCleaner", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Some items could not be moved to the Trash. Items already moved can be restored from the Trash.\n\n" + failures.joined(separator: "\n\n")
            ])
        }
    }
}
