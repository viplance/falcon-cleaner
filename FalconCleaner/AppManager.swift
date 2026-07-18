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
    
    func cleanup(app: AppInfo, permanently: Bool = false) async throws {
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

        // 2b. Unload any associated launch agents/daemons so their jobs stop before
        // we remove the plists (covers both the Startup category and startup items
        // bundled with a standard app's related files).
        for fileURL in ([app.path] + app.relatedFiles) where isLaunchItemPlist(fileURL) {
            unloadLaunchItem(fileURL)
        }
        
        // 3. Perform Type-Specific Cleanup
        if app.type == .brew {
            await uninstallBrewFormula(app.name)
        }
        
        var failedURLs: [URL] = []

        // 4 & 5. Remove the main path and related files.
        // When `permanently` is set we delete outright (skipping the Trash); otherwise
        // we move to the Trash. Only existing paths are touched (brew uninstall may have
        // already removed the bundle).
        var targets: [URL] = []
        if fileManager.fileExists(atPath: app.path.path) {
            targets.append(app.path)
        }
        for fileURL in app.relatedFiles where fileManager.fileExists(atPath: fileURL.path) {
            targets.append(fileURL)
        }

        for url in targets {
            do {
                if permanently {
                    try fileManager.removeItem(at: url)
                } else {
                    try fileManager.trashItem(at: url, resultingItemURL: nil)
                }
            } catch {
                print("\(permanently ? "Delete" : "Trash") failed for \(url.lastPathComponent), staging for fallback: \(error)")
                failedURLs.append(url)
            }
        }

        // 6. Fallback for items that failed the standard removal (typically root-owned
        // bundles like /Applications/zoom.us.app or launch daemons under /Library).
        if !failedURLs.isEmpty {
            if permanently {
                if !privilegedRemove(urls: failedURLs) {
                    print("Privileged removal failed/cancelled for \(app.name)")
                }
            } else if !moveWithAppleScript(urls: failedURLs) {
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
    
    private func isLaunchItemPlist(_ url: URL) -> Bool {
        let path = url.path
        return url.pathExtension == "plist"
            && (path.contains("/LaunchAgents/") || path.contains("/LaunchDaemons/"))
    }

    private func unloadLaunchItem(_ url: URL) {
        // Best-effort: stop the running job. User agents unload without privileges;
        // system daemons may not, but removing the plist still prevents next-boot launch.
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["unload", url.path]
        try? process.run()
        process.waitUntilExit()
    }

    private func privilegedRemove(urls: [URL]) -> Bool {
        // Permanently remove root-owned items the current user cannot delete directly.
        // All paths are removed in a single `rm -rf`, so the admin prompt appears once.
        guard !urls.isEmpty else { return true }

        let quotedPaths = urls
            .map { "'" + $0.path.replacingOccurrences(of: "'", with: "'\\''") + "'" }
            .joined(separator: " ")
        let shellCommand = "/bin/rm -rf " + quotedPaths

        // Escape for embedding inside an AppleScript double-quoted string.
        let escaped = shellCommand
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let source = "do shell script \"\(escaped)\" with administrator privileges"

        guard let script = NSAppleScript(source: source) else { return false }
        var error: NSDictionary?
        script.executeAndReturnError(&error)
        if let error = error {
            print("Privileged removal error: \(error)")
            return false
        }
        return true
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
