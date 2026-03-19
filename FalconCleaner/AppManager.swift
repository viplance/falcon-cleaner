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
        
        // 2. Prepare paths by clearing immutable flags (unlocking)
        // This helps with "Kern Failure (0x5)" and "Access Denied" for locked files
        unlockPath(app.path)
        for fileURL in app.relatedFiles {
            unlockPath(fileURL)
        }
        
        // 3. Move app to Trash
        do {
            try fileManager.trashItem(at: app.path, resultingItemURL: nil)
        } catch {
            print("Standard trash failed for \(app.name), trying AppleScript fallback: \(error)")
            if !moveWithAppleScript(url: app.path) {
                print("AppleScript fallback failed for \(app.name)")
                throw error
            }
        }
        
        // 4. Verification: Check if the app bundle still exists
        // If the user cancelled the password prompt, the script might return false OR the command might simply not have had an effect.
        if fileManager.fileExists(atPath: app.path.path) {
            throw NSError(domain: "FalconCleaner", code: 1, userInfo: [NSLocalizedDescriptionKey: "User cancelled or operation failed to move \(app.name) to Trash."])
        }
        
        // 4. Move related files to Trash
        for fileURL in app.relatedFiles {
            if fileManager.fileExists(atPath: fileURL.path) {
                do {
                    try fileManager.trashItem(at: fileURL, resultingItemURL: nil)
                } catch {
                    print("Standard trash failed for related file \(fileURL.lastPathComponent), trying AppleScript fallback")
                    _ = moveWithAppleScript(url: fileURL)
                }
            }
        }
    }
    
    private func unlockPath(_ url: URL) {
        // Use chflags to clear uchg (user immutable) and uappnd (user append-only)
        // We do this recursively for directories
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/chflags")
        process.arguments = ["-R", "nouchg,nouappnd", url.path]
        try? process.run()
        process.waitUntilExit()
    }
    
    private func moveWithAppleScript(url: URL) -> Bool {
        let escapedPath = url.path.replacingOccurrences(of: "\"", with: "\\\"")
        
        // We use a more explicit Finder command that handles POSIX paths as aliases
        // This often triggers the permission dialog more reliably than the raw 'delete POSIX file' command
        let scriptSource = """
        set posixPath to "\(escapedPath)"
        tell application "Finder"
            if not running then
                launch
                delay 1 -- Give Finder a moment to initialize
            end if
            try
                set theItem to POSIX file posixPath as alias
                delete theItem
                return true
            on error errMsg number errNum
                log "Finder error: " & errMsg & " (" & errNum & ")"
                return false
            end try
        end tell
        """
        
        if let script = NSAppleScript(source: scriptSource) {
            var error: NSDictionary?
            let result = script.executeAndReturnError(&error)
            
            if error == nil {
                // Check the boolean return value from the script itself
                return result.booleanValue
            } else {
                print("AppleScript execution error: \(String(describing: error))")
            }
        }
        return false
    }
}
