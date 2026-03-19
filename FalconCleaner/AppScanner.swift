import Foundation
import AppKit

class AppScanner {
    static let shared = AppScanner()
    
    private let fileManager = FileManager.default
    
    func scanInstalledApps() async -> [AppInfo] {
        let appDirs = [
            URL(fileURLWithPath: "/Applications"),
            fileManager.urls(for: .applicationDirectory, in: .userDomainMask).first
        ].compactMap { $0 }
        
        var apps: [AppInfo] = []
        
        for dir in appDirs {
            do {
                let contents = try fileManager.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isApplicationKey, .fileSizeKey], options: .skipsHiddenFiles)
                for url in contents where url.pathExtension == "app" {
                    if let appInfo = extractAppInfo(from: url) {
                        apps.append(appInfo)
                    }
                }
            } catch {
                print("Error scanning directory \(dir.path): \(error)")
            }
        }
        
        return apps.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
    
    private func extractAppInfo(from url: URL) -> AppInfo? {
        guard let bundle = Bundle(url: url) else { return nil }
        
        let name = bundle.object(forInfoDictionaryKey: "CFBundleName") as? String 
            ?? bundle.object(forInfoDictionaryKey: "CFBundleExecutable") as? String 
            ?? url.deletingPathExtension().lastPathComponent
        
        let bundleIdentifier = bundle.bundleIdentifier
        let isSystemApp = url.path.hasPrefix("/System") || url.path.hasPrefix("/Library/Apple")
        
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        let bundleSize = allocatedSizeOfDirectory(at: url)
        
        var app = AppInfo(
            name: name,
            bundleIdentifier: bundleIdentifier,
            path: url,
            icon: icon,
            bundleSize: bundleSize,
            isSystemApp: isSystemApp
        )
        
        app.relatedFiles = findRelatedFiles(for: app)
        return app
    }

    private func allocatedSizeOfDirectory(at url: URL) -> Int64 {
        var size: Int64 = 0
        let keys: [URLResourceKey] = [.isRegularFileKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey]
        
        guard let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: keys, options: []) else {
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
    
    func findRelatedFiles(for app: AppInfo) -> [URL] {
        var related: [URL] = []
        let libraryFolders = [
            "Application Support",
            "Caches",
            "Preferences",
            "Logs",
            "Containers",
            "Group Containers",
            "Saved Application State",
            "WebKit",
            "Application Scripts",
            "HTTPStorages"
        ]
        
        let homeLibrary = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library")
        
        for folder in libraryFolders {
            let folderURL = homeLibrary.appendingPathComponent(folder)
            
            // Search by bundle identifier
            if let bid = app.bundleIdentifier {
                let bidURL = folderURL.appendingPathComponent(bid)
                if fileManager.fileExists(atPath: bidURL.path) {
                    related.append(bidURL)
                }
                
                // Also search for files starting with bid
                if folder == "Preferences" {
                    let prefFile = folderURL.appendingPathComponent("\(bid).plist")
                    if fileManager.fileExists(atPath: prefFile.path) {
                        related.append(prefFile)
                    }
                }
            }
            
            // Search by app name
            let nameURL = folderURL.appendingPathComponent(app.name)
            if fileManager.fileExists(atPath: nameURL.path) {
                if !related.contains(nameURL) {
                    related.append(nameURL)
                }
            }
            
            // Search by app name without spaces
            let nameNoSpaces = app.name.replacingOccurrences(of: " ", with: "")
            let nameNoSpacesURL = folderURL.appendingPathComponent(nameNoSpaces)
            if fileManager.fileExists(atPath: nameNoSpacesURL.path) {
                if !related.contains(nameNoSpacesURL) {
                    related.append(nameNoSpacesURL)
                }
            }
        }
        
        return related
    }
}
