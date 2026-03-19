import Foundation
import AppKit

struct AppInfo: Identifiable, Hashable {
    let id: UUID = UUID()
    let name: String
    let bundleIdentifier: String?
    let path: URL
    let icon: NSImage?
    let bundleSize: Int64
    let isSystemApp: Bool
    var relatedFiles: [URL] = []
    
    var totalSize: Int64 {
        let relatedSize = relatedFiles.reduce(0) { $0 + Int64((try? $1.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0) }
        return bundleSize + relatedSize
    }
}
