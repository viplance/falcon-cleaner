import Foundation

/// A single file or folder shown in the Disk browser.
struct DiskEntry: Identifiable {
    let url: URL
    let name: String
    let isDirectory: Bool
    let size: Int64?         // byte size for files (nil for folders)
    let itemCount: Int?      // number of immediate items for folders (nil for files)
    var folderSize: Int64? = nil   // recursive folder size, filled in on demand

    var id: String { url.path }
}
