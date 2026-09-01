import Foundation
import AppKit

enum AppType {
    case standard
    case brew
    case startup
    /// Registered with Launch Services but living outside the standard application
    /// folders (typically a build output or a bundle run once from Downloads).
    /// These appear in Launchpad and Spotlight, so users expect to manage them here.
    case registered
}

struct AppInfo: Identifiable, Hashable {
    let id: UUID = UUID()
    let name: String
    let bundleIdentifier: String?
    let path: URL
    let icon: NSImage?
    let bundleSize: Int64
    let isSystemApp: Bool
    let isBroken: Bool
    var type: AppType
    let brewServiceName: String?
    var relatedFiles: [URL] = []

    let totalSize: Int64

    // Human-facing metadata (from the app bundle's Info.plist), used for the info tooltip.
    var category: String? = nil
    var version: String? = nil
    var developer: String? = nil
    var launchProgramPath: String? = nil   // executable a startup item launches

    /// True when Launch Services still lists the app but its bundle is gone from disk.
    /// Nothing remains to delete, so cleanup only unregisters the stale entry.
    var isDanglingRegistration: Bool = false

    var typeLabel: String {
        if isDanglingRegistration { return "Leftover entry" }
        if isBroken { return "Broken application" }

        switch type {
        case .standard: return isSystemApp ? "System app" : "Application"
        case .brew: return "Homebrew package"
        case .startup: return "Startup item"
        case .registered: return "Application (outside Applications folder)"
        }
    }

    /// Short, human-readable summary shown as a tooltip on the info icon:
    /// role/category, who made it and version — not raw system paths.
    var infoHint: String {
        var lines: [String] = []
        // Role / category (falls back to the item type).
        lines.append(category ?? typeLabel)
        if let developer = developer, !developer.isEmpty {
            lines.append("By \(developer)")
        }
        if let version = version, !version.isEmpty {
            lines.append("Version \(version)")
        }
        if brewServiceName != nil {
            lines.append("Runs as a background service")
        }
        // For apps outside the standard folders the location is the key fact: it explains
        // why the entry exists and lets the user judge whether removing it is safe.
        if type == .registered {
            lines.append(isDanglingRegistration
                ? "Listed by macOS, but the app is no longer on disk"
                : "Located in \(path.deletingLastPathComponent().path)")
        }
        return lines.joined(separator: "\n")
    }

    private func allocatedSizeOfDirectory(at url: URL) -> Int64 {
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), !isDir.boolValue {
            // It's a file
            let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey]
            guard let resourceValues = try? url.resourceValues(forKeys: Set(keys)) else { return 0 }
            return Int64(resourceValues.totalFileAllocatedSize ?? resourceValues.fileAllocatedSize ?? 0)
        }
        
        // It's a directory
        var size: Int64 = 0
        let keys: [URLResourceKey] = [.isRegularFileKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey]
        guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: keys, options: []) else {
            return 0
        }
        
        for case let fileURL as URL in enumerator {
            guard let resourceValues = try? fileURL.resourceValues(forKeys: Set(keys)) else { continue }
            if resourceValues.isRegularFile ?? false {
                size += Int64(resourceValues.totalFileAllocatedSize ?? resourceValues.fileAllocatedSize ?? 0)
            }
        }
        return size
    }
}
