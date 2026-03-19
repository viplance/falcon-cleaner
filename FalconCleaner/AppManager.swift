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
        // 1. Stop app/service if running
        if app.type == .brew {
            if let serviceName = app.brewServiceName {
                progressMessage("Stopping brew service \(serviceName)...")
                await stopBrewService(serviceName)
            }
        } else if isAppRunning(bundleIdentifier: app.bundleIdentifier) {
            _ = await stopApp(bundleIdentifier: app.bundleIdentifier)
        }
        
        // 2. Prepare paths by clearing immutable flags (unlocking)
        unlockPath(app.path)
        for fileURL in app.relatedFiles {
            unlockPath(fileURL)
        }
        
        // 3. Perform Type-Specific Cleanup
        if app.type == .brew {
            await uninstallBrewFormula(app.name)
        }
        
        var failedURLs: [URL] = []
        
        // 4. Attempt standard trash for the main path (if it still exists after brew uninstall)
        if fileManager.fileExists(atPath: app.path.path) {
            do {
                try fileManager.trashItem(at: app.path, resultingItemURL: nil)
            } catch {
                print("Trash failed for \(app.name), staging for AppleScript: \(error)")
                failedURLs.append(app.path)
            }
        }
        
        // 5. Attempt standard trash for related files
        for fileURL in app.relatedFiles {
            if fileManager.fileExists(atPath: fileURL.path) {
                do {
                    try fileManager.trashItem(at: fileURL, resultingItemURL: nil)
                } catch {
                    print("Standard trash failed for related file \(fileURL.lastPathComponent), staging for AppleScript")
                    failedURLs.append(fileURL)
                }
            }
        }
        
        // 6. AppleScript Fallback for all failed items
        if !failedURLs.isEmpty {
            if !moveWithAppleScript(urls: failedURLs) {
                print("AppleScript batch fallback failed for \(app.name)")
            }
        }
        
        // 7. Final Verification
        if fileManager.fileExists(atPath: app.path.path) {
            throw NSError(domain: "FalconCleaner", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to remove \(app.name)."])
        }
    }
    
    private func stopBrewService(_ name: String) async {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["brew", "services", "stop", name]
        try? process.run()
        process.waitUntilExit()
    }
    
    private func uninstallBrewFormula(_ name: String) async {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["brew", "uninstall", "--force", name]
        try? process.run()
        process.waitUntilExit()
    }
    
    private func progressMessage(_ message: String) {
        // This is a placeholder for potential progress reporting
        print(message)
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
    
    private func moveWithAppleScript(urls: [URL]) -> Bool {
        let pathStrings = urls.map { "\"\($0.path.replacingOccurrences(of: "\"", with: "\\\""))\"" }.joined(separator: ", ")
        
        // We convert the POSIX paths to a list of Finder items (aliases/POSIX files)
        // and delete them all in a single command. This triggers ONLY ONE password prompt.
        let scriptSource = """
        set posixPaths to {\(pathStrings)}
        tell application "Finder"
            if not running then
                launch
                delay 1
            end if
            set itemAliases to {}
            repeat with aPath in posixPaths
                try
                    -- Using 'as alias' on a POSIX file string within a try block
                    set theItem to POSIX file aPath as alias
                    set end of itemAliases to theItem
                on error
                    try
                        -- Fallback for items that Finder is picky about
                        set theItem to (aPath as POSIX file)
                        set end of itemAliases to theItem
                    on error errMsg
                        log "Could not resolve path: " & aPath & " Error: " & errMsg
                    end try
                end error
            end repeat
            
            if (count of itemAliases) is 0 then return false
            
            try
                delete itemAliases
                return true
            on error errMsg number errNum
                -- If we got here, the delete command itself failed (e.g. User Cancelled)
                log "Finder delete error: " & errMsg & " (" & errNum & ")"
                return false
            end try
        end tell
        """
        
        if let script = NSAppleScript(source: scriptSource) {
            var error: NSDictionary?
            let result = script.executeAndReturnError(&error)
            
            if error == nil {
                return result.booleanValue
            } else {
                print("AppleScript execution error: \(String(describing: error))")
            }
        }
        return false
    }
}
