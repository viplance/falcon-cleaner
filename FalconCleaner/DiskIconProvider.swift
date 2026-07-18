import AppKit
import UniformTypeIdentifiers

/// Fast, main-thread icons for the Disk browser. Uses one shared folder icon and per-file-type
/// icons cached by extension — avoids a slow LaunchServices lookup for every individual file.
@MainActor
enum DiskIconProvider {
    private static let folderIcon = NSWorkspace.shared.icon(for: .folder)
    private static let genericIcon = NSWorkspace.shared.icon(for: .data)
    private static var byExtension: [String: NSImage] = [:]

    static func icon(for entry: DiskEntry) -> NSImage {
        if entry.isDirectory { return folderIcon }

        let ext = entry.url.pathExtension.lowercased()
        if ext.isEmpty { return genericIcon }
        if let cached = byExtension[ext] { return cached }

        let type = UTType(filenameExtension: ext) ?? .data
        let icon = NSWorkspace.shared.icon(for: type)
        byExtension[ext] = icon
        return icon
    }
}
