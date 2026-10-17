import Foundation

/// Run with: xcrun swiftc FalconCleaner/CleanupFiles.swift Tests/CleanupFilesRegression.swift -o /tmp/falcon-cleanup-tests && /tmp/falcon-cleanup-tests
@main
struct CleanupFilesRegression {
    static func main() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }

        func check(_ condition: Bool) { precondition(condition) }

        func fixture(_ name: String) throws -> URL {
            let url = root.appendingPathComponent(name)
            try Data("fixture".utf8).write(to: url)
            return url
        }
        func expectFailure(_ operation: () throws -> Void) throws -> String {
            do { try operation() } catch { return error.localizedDescription }
            fatalError("Expected cleanup to fail")
        }

        let app = try fixture("Example.app")
        let related = try fixture("Example.plist")
        let missing = root.appendingPathComponent("missing")
        check(try !CleanupFiles.exists(missing))
#if APPSTORE
        check(SandboxFileAccess.contains(root.appendingPathComponent("child"), in: root))
        check(!SandboxFileAccess.contains(URL(fileURLWithPath: root.path + "-neighbor"), in: root))
#endif
        let parent = root.appendingPathComponent("Folder")
        let child = parent.appendingPathComponent("child")
        let neighbor = root.appendingPathComponent("Folder2")
        check(CleanupFiles.uniqueTargets([parent, child, parent, neighbor]) == [parent, neighbor])

        // A successful API return without deletion must never remove the UI row.
        let unchanged = try expectFailure {
            try CleanupFiles.moveToTrash([app], using: { _ in })
        }
        check(unchanged.contains(app.path))

        // A related-file failure must be surfaced even after the bundle is removed.
        let partial = try expectFailure {
            try CleanupFiles.moveToTrash([app, related], using: { url in
                if url == related { throw CocoaError(.fileWriteNoPermission) }
                try fm.removeItem(at: url)
            })
        }
        check(try !CleanupFiles.exists(app))
        check(try CleanupFiles.exists(related))
        check(partial.contains(related.path))
        // Retrying a partially completed cleanup skips the absent bundle.
        try CleanupFiles.moveToTrash([app, related], using: { try fm.removeItem(at: $0) })

        let locked = root.appendingPathComponent("locked")
        try fm.createDirectory(at: locked, withIntermediateDirectories: true)
        let protected = locked.appendingPathComponent("file")
        try Data().write(to: protected)
        try fm.setAttributes([.posixPermissions: 0], ofItemAtPath: locked.path)
        defer { try? fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: locked.path) }
        let denied = try expectFailure {
            _ = try CleanupFiles.exists(protected)
        }
        check(!denied.isEmpty)

        // lstat semantics include a dangling symlink itself in cleanup.
        let link = root.appendingPathComponent("Broken.app")
        try fm.createSymbolicLink(at: link, withDestinationURL: missing)
        check(try CleanupFiles.exists(link))
        try CleanupFiles.moveToTrash([link], using: { try fm.removeItem(at: $0) })
        check(try !CleanupFiles.exists(link))
        print("Cleanup regression checks passed")
    }
}
