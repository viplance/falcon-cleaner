import Foundation
import AppKit

class AppManager {
    static let shared = AppManager()
    
    private let fileManager = FileManager.default
    private let workspace = NSWorkspace.shared
    
    func isAppRunning(bundleIdentifier: String?) -> Bool {
        guard let bid = bundleIdentifier else { return false }
        return workspace.runningApplications.contains { $0.bundleIdentifier == bid }
    }
    
    func stopApp(bundleIdentifier: String?) async -> Bool {
        guard let bid = bundleIdentifier else { return true }
        let runningApps = workspace.runningApplications.filter { $0.bundleIdentifier == bid }
        
        for app in runningApps {
            app.terminate()
        }
        
        // Wait for termination
        var retries = 0
        while retries < 10 {
            if workspace.runningApplications.allSatisfy({ $0.bundleIdentifier != bid }) {
                return true
            }
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s
            retries += 1
        }
        
        // Force terminate if still running
        for app in runningApps {
            app.forceTerminate()
        }
        
        return true
    }
    
    func cleanup(app: AppInfo) async throws {
        // 1. Stop app if running
        if isAppRunning(bundleIdentifier: app.bundleIdentifier) {
            _ = await stopApp(bundleIdentifier: app.bundleIdentifier)
        }
        
        // 2. Move app to Trash
        try fileManager.trashItem(at: app.path, resultingItemURL: nil)
        
        // 3. Move related files to Trash
        for fileURL in app.relatedFiles {
            if fileManager.fileExists(atPath: fileURL.path) {
                try? fileManager.trashItem(at: fileURL, resultingItemURL: nil)
            }
        }
    }
}
