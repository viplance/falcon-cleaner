import AppKit
import Darwin

#if APPSTORE
/// Keep Powerbox grants alive for this session. No access is assumed on the next launch.
@MainActor
final class SandboxFileAccess {
    static let shared = SandboxFileAccess()
    private var directories: [URL] = []

    nonisolated static var userHomeURL: URL {
        // NSHomeDirectory() points at our container in a sandboxed process.
        guard let path = getpwuid(getuid())?.pointee.pw_dir else {
            return FileManager.default.homeDirectoryForCurrentUser
        }
        return URL(fileURLWithPath: String(cString: path), isDirectory: true)
    }

    static var userLibraryURL: URL { userHomeURL.appendingPathComponent("Library", isDirectory: true) }

    func authorize(directory: URL) async throws {
        if directories.contains(where: { Self.contains(directory, in: $0) }) { return }
        let panel = NSOpenPanel()
        panel.title = "Allow Access to \(directory.lastPathComponent)"
        panel.message = "Choose \(directory.path) to let Falcon Cleaner find related files and move selected items to the Trash. Access lasts until you quit the app."
        panel.prompt = "Allow Access"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.showsHiddenFiles = true
        panel.directoryURL = directory

        let response = await withCheckedContinuation { continuation in
            panel.begin { continuation.resume(returning: $0) }
        }
        guard response == .OK, let chosen = panel.url else { throw CancellationError() }
        guard chosen.standardizedFileURL.path == directory.standardizedFileURL.path else {
            throw NSError(domain: "FalconCleaner", code: 3, userInfo: [
                NSLocalizedDescriptionKey: "Access was not granted. Choose the folder \(directory.path) and try again."
            ])
        }
        // The panel grants access even when a separate scope need not be started.
        // Retain the exact returned URL rather than reconstructing it from its path.
        _ = chosen.startAccessingSecurityScopedResource()
        directories.append(chosen)
    }

    nonisolated static func contains(_ url: URL, in directory: URL) -> Bool {
        let path = url.standardizedFileURL.path
        let root = directory.standardizedFileURL.path
        return path == root || path.hasPrefix(root == "/" ? root : root + "/")
    }
}
#endif
