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
    
    let totalSize: Int64
    
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
