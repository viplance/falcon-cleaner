import Foundation
import AppKit
import UniformTypeIdentifiers

// nonisolated so the heavy scan (bundle sizes, brew subprocesses, Library lookups) runs off
// the main thread instead of freezing the UI — the project defaults types to @MainActor.
nonisolated final class AppScanner {
    static let shared = AppScanner()
    
    private let fileManager = FileManager.default
    
    func scanInstalledApps() async -> [AppInfo] {
        let appDirs = [
            URL(fileURLWithPath: "/Applications"),
            fileManager.urls(for: .applicationDirectory, in: .userDomainMask).first,
            URL(fileURLWithPath: "/Library/Application Support/Microsoft/MAU2.0")
        ].compactMap { $0 }
        
        var apps: [AppInfo] = []
        
        // 1. Scan Standard Apps
        for dir in appDirs {
            var isDirectory: ObjCBool = false
            if fileManager.fileExists(atPath: dir.path, isDirectory: &isDirectory), isDirectory.boolValue {
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
        }
        
        // 2. Scan Brew Apps & Services
        let brewApps = await scanBrewApps()
        apps.append(contentsOf: brewApps)
        
        // 3. Scan Startup Scripts
        let startupApps = scanStartupScripts()
        apps.append(contentsOf: startupApps)
        
        return apps.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
    
    private func scanBrewApps() async -> [AppInfo] {
        var brewApps: [AppInfo] = []
        let brewPrefix = getBrewPrefix()
        let cellarPath = "\(brewPrefix)/Cellar"
        let cellarURL = URL(fileURLWithPath: cellarPath)
        
        print("Brew scanner checking: \(cellarPath)")
        guard fileManager.fileExists(atPath: cellarPath) else { 
            print("Brew Cellar not found at \(cellarPath)")
            return [] 
        }
        
        // Get services list to match with formulae
        let services = getBrewServices()
        
        do {
            let formulaDirs = try fileManager.contentsOfDirectory(at: cellarURL, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)
            
            for formulaDir in formulaDirs {
                let formulaName = formulaDir.lastPathComponent
                
                // Get the latest version directory
                let versions = try fileManager.contentsOfDirectory(at: formulaDir, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)
                guard let latestVersion = versions.sorted(by: { $0.path.compare($1.path, options: .numeric) == .orderedDescending }).first else { continue }
                
                let bundleSize = allocatedSizeOfDirectory(at: latestVersion)
                let relatedFiles = findRelatedFiles(forName: formulaName, bundleIdentifier: nil)
                let relatedSize = relatedFiles.reduce(0) { $0 + allocatedSizeOfDirectory(at: $1) }
                
                let icon = NSWorkspace.shared.icon(for: .unixExecutable)
                
                let app = AppInfo(
                    name: formulaName,
                    bundleIdentifier: "brew.\(formulaName)",
                    path: formulaDir,
                    icon: icon,
                    bundleSize: bundleSize,
                    isSystemApp: false,
                    type: .brew,
                    brewServiceName: services.contains(formulaName) ? formulaName : nil,
                    relatedFiles: relatedFiles,
                    totalSize: bundleSize + relatedSize
                )
                brewApps.append(app)
            }
        } catch {
            print("Error scanning brew apps: \(error)")
        }
        
        return brewApps
    }
    
    private func scanStartupScripts() -> [AppInfo] {
        var startupApps: [AppInfo] = []
        let paths = [
            URL(fileURLWithPath: "\(NSHomeDirectory())/Library/LaunchAgents"),
            URL(fileURLWithPath: "/Library/LaunchAgents"),
            URL(fileURLWithPath: "/Library/LaunchDaemons")
        ]
        
        for dir in paths {
            var isDirectory: ObjCBool = false
            if fileManager.fileExists(atPath: dir.path, isDirectory: &isDirectory), isDirectory.boolValue {
                do {
                    let contents = try fileManager.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.fileSizeKey], options: .skipsHiddenFiles)
                    for url in contents where url.pathExtension == "plist" {
                        let name = url.deletingPathExtension().lastPathComponent
                        let bundleSize = allocatedSizeOfDirectory(at: url)

                        // The executable this launch item runs (for icon/vendor/description).
                        var programPath: String?
                        if let dict = NSDictionary(contentsOf: url) {
                            programPath = dict["Program"] as? String
                                ?? (dict["ProgramArguments"] as? [String])?.first
                        }

                        // Prefer the parent app's icon when the program lives inside a .app.
                        var icon = NSWorkspace.shared.icon(for: .unixExecutable)
                        if let programPath = programPath {
                            if let range = programPath.range(of: ".app/") {
                                let appPath = String(programPath[..<range.lowerBound]) + ".app"
                                if fileManager.fileExists(atPath: appPath) {
                                    icon = NSWorkspace.shared.icon(forFile: appPath)
                                }
                            } else if fileManager.fileExists(atPath: programPath) {
                                icon = NSWorkspace.shared.icon(forFile: programPath)
                            }
                        }

                        let app = AppInfo(
                            name: name,
                            bundleIdentifier: name,
                            path: url,
                            icon: icon,
                            bundleSize: bundleSize,
                            isSystemApp: false,
                            type: .startup,
                            brewServiceName: nil,
                            relatedFiles: [],
                            totalSize: bundleSize,
                            launchProgramPath: programPath
                        )
                        startupApps.append(app)
                    }
                } catch {
                    print("Error scanning startup dir \(dir.path): \(error)")
                }
            }
        }
        return startupApps
    }
    
    private func getBrewPrefix() -> String {
        // 1. Check Env
        if let envPrefix = ProcessInfo.processInfo.environment["HOMEBREW_PREFIX"] {
            return envPrefix
        }
        
        // 2. Check Common Paths
        let commonPaths = ["/opt/homebrew/bin/brew", "/usr/local/bin/brew", "/usr/bin/brew"]
        for brewPath in commonPaths {
            if fileManager.fileExists(atPath: brewPath) {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: brewPath)
                process.arguments = ["--prefix"]
                let pipe = Pipe()
                process.standardOutput = pipe
                try? process.run()
                process.waitUntilExit()
                
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) {
                    return output
                }
            }
        }
        return "/opt/homebrew" // Default for Apple Silicon
    }
    
    private func getBrewServices() -> [String] {
        let brewBinary = getBrewBinaryPath()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [brewBinary, "services", "list"]
        let pipe = Pipe()
        process.standardOutput = pipe
        try? process.run()
        process.waitUntilExit()
        
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else { return [] }
        
        var services: [String] = []
        let lines = output.components(separatedBy: .newlines)
        for line in lines {
            // Brew services list format: Name Status User File
            // We look for lines that have 'started' or 'error' or 'none' in them
            let parts = line.split(separator: " ", omittingEmptySubsequences: true)
            if parts.count >= 2 {
                let name = String(parts[0])
                let status = String(parts[1])
                // Simple heuristic: if the second word is a known status, the first is the name
                if ["started", "none", "error", "stopped", "scheduled"].contains(status.lowercased()) {
                    services.append(name)
                }
            }
        }
        return services
    }
    
    private func getBrewBinaryPath() -> String {
        let paths = ["/opt/homebrew/bin/brew", "/usr/local/bin/brew", "/usr/bin/brew"]
        for p in paths {
            if fileManager.fileExists(atPath: p) { return p }
        }
        return "brew" // fallback to env
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
        
        var relatedFiles = findRelatedFiles(forName: name, bundleIdentifier: bundleIdentifier)
        // Include associated startup items (LaunchAgents/LaunchDaemons) so they are
        // removed together with the app.
        for startupItem in findRelatedStartupItems(bundleIdentifier: bundleIdentifier, appPath: url)
        where !relatedFiles.contains(startupItem) {
            relatedFiles.append(startupItem)
        }
        let relatedSize = relatedFiles.reduce(0) { $0 + allocatedSizeOfDirectory(at: $1) }

        let category = humanCategory(bundle.object(forInfoDictionaryKey: "LSApplicationCategoryType") as? String)
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let developer = vendorFromCopyright(bundle.object(forInfoDictionaryKey: "NSHumanReadableCopyright") as? String)

        let app = AppInfo(
            name: name,
            bundleIdentifier: bundleIdentifier,
            path: url,
            icon: icon,
            bundleSize: bundleSize,
            isSystemApp: isSystemApp,
            type: .standard,
            brewServiceName: nil,
            relatedFiles: relatedFiles,
            totalSize: bundleSize + relatedSize,
            category: category,
            version: version,
            developer: developer
        )

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
    
    func findRelatedFiles(forName name: String, bundleIdentifier: String?) -> [URL] {
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
            if let bid = bundleIdentifier {
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
            let nameURL = folderURL.appendingPathComponent(name)
            if fileManager.fileExists(atPath: nameURL.path) {
                if !related.contains(nameURL) {
                    related.append(nameURL)
                }
            }
            
            // Search by app name without spaces
            let nameNoSpaces = name.replacingOccurrences(of: " ", with: "")
            let nameNoSpacesURL = folderURL.appendingPathComponent(nameNoSpaces)
            if fileManager.fileExists(atPath: nameNoSpacesURL.path) {
                if !related.contains(nameNoSpacesURL) {
                    related.append(nameNoSpacesURL)
                }
            }
        }
        
        return related
    }

    /// Finds LaunchAgents/LaunchDaemons plists that belong to a given app, matched by
    /// bundle identifier or by a program path that points inside the app bundle.
    func findRelatedStartupItems(bundleIdentifier: String?, appPath: URL) -> [URL] {
        let launchDirs = [
            URL(fileURLWithPath: "\(NSHomeDirectory())/Library/LaunchAgents"),
            URL(fileURLWithPath: "/Library/LaunchAgents"),
            URL(fileURLWithPath: "/Library/LaunchDaemons")
        ]
        let appPathString = appPath.path

        var items: [URL] = []
        for dir in launchDirs {
            guard let contents = try? fileManager.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: nil, options: .skipsHiddenFiles
            ) else { continue }

            for url in contents where url.pathExtension == "plist" {
                let dict = NSDictionary(contentsOf: url)
                if plistBelongsToApp(url, dict: dict, bundleIdentifier: bundleIdentifier, appPathString: appPathString) {
                    items.append(url)
                    // Also remove the privileged helper binary the job launches, if any.
                    for helper in helperExecutables(from: dict) where !items.contains(helper) {
                        items.append(helper)
                    }
                }
            }
        }
        return items
    }

    private func plistBelongsToApp(_ url: URL, dict: NSDictionary?, bundleIdentifier: String?, appPathString: String) -> Bool {
        let label = url.deletingPathExtension().lastPathComponent

        if let bid = bundleIdentifier, !bid.isEmpty {
            // 1. Filename (label) matches the bundle identifier, e.g. "com.foo.Bar.helper.plist".
            if label == bid || label.hasPrefix(bid + ".") {
                return true
            }

            if let dict = dict {
                // 2. AssociatedBundleIdentifiers explicitly lists the app (authoritative).
                if let associated = dict["AssociatedBundleIdentifiers"] as? [String], associated.contains(bid) {
                    return true
                }
                if let associated = dict["AssociatedBundleIdentifiers"] as? String, associated == bid {
                    return true
                }

                // 3. The plist's Label matches the bundle identifier.
                if let plistLabel = dict["Label"] as? String,
                   plistLabel == bid || plistLabel.hasPrefix(bid + ".") {
                    return true
                }
            }
        }

        // 4. Program / ProgramArguments point inside the app bundle (strongest path signal).
        return programPaths(from: dict).contains { $0.hasPrefix(appPathString) }
    }

    private func programPaths(from dict: NSDictionary?) -> [String] {
        guard let dict = dict else { return [] }
        var paths: [String] = []
        if let program = dict["Program"] as? String { paths.append(program) }
        if let args = dict["ProgramArguments"] as? [String] { paths.append(contentsOf: args) }
        return paths
    }

    /// Returns the privileged-helper executables a matched launch item runs, so they can be
    /// removed alongside the plist (e.g. /Library/PrivilegedHelperTools/us.zoom.ZoomDaemon).
    private func helperExecutables(from dict: NSDictionary?) -> [URL] {
        var helpers: [URL] = []
        for path in programPaths(from: dict) where path.hasPrefix("/Library/PrivilegedHelperTools/") {
            let url = URL(fileURLWithPath: path)
            if fileManager.fileExists(atPath: url.path), !helpers.contains(url) {
                helpers.append(url)
            }
        }
        return helpers
    }
}
