import Foundation

/// Finds applications that Launch Services knows about but that do not live in any of
/// the standard application folders.
///
/// macOS registers an app the first time it is launched or built, wherever it sits, and
/// then shows it in Launchpad and Spotlight forever. A bundle run once from ~/Downloads,
/// or a build product under a project folder, therefore stays visible to the user long
/// after it stops working — while remaining invisible to a scan of /Applications.
///
/// The registration database has no public enumeration API (`LSCopyAllApplicationURLs`
/// was never exported and the LSRegistry SPI is unavailable to sandboxed and hardened
/// builds alike), so the supported `lsregister -dump` output is parsed instead. The tool
/// only reads the database; the scan never mutates it.
nonisolated struct LaunchServicesScanner {

    private static let lsregisterPath =
        "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

    /// A registered bundle plus whether its files are still present.
    struct RegisteredApp {
        let url: URL
        let isDangling: Bool
    }

    /// Directory prefixes whose apps are either already covered by `AppScanner` or are
    /// not user-manageable applications at all.
    private static func excludedPrefixes() -> [String] {
        let home = NSHomeDirectory()
        return [
            // Covered by the standard directory scan.
            "/Applications",
            "\(home)/Applications",
            "/Library/Application Support/Microsoft/MAU2.0",

            // Operating system internals — never user-removable.
            "/System",
            "/Library/Apple",
            "/usr",
            "/bin",
            "/sbin",
            "/private/var",
            "/Library/PrivilegedHelperTools",
            "/Library/Developer/CommandLineTools",
            "/Applications/Xcode.app",

            // OS-managed staging and placeholder caches. These are App Store / TestFlight
            // download stubs and script sandboxes, not installed applications.
            "\(home)/Library/Daemon Containers",
            "\(home)/Library/Application Scripts",
            "\(home)/Library/Containers",
            "\(home)/Library/Group Containers",
            "\(home)/Library/Caches",
            "\(home)/Library/Application Support/Google/GoogleUpdater",

            // Transient build products: rebuilt constantly and meaningless to uninstall.
            "\(home)/Library/Developer/Xcode/DerivedData",
            "\(home)/Library/Developer/CoreSimulator",
            "/Volumes"
        ]
    }

    /// Returns registered applications outside the standard folders.
    ///
    /// Bundles nested inside another `.app`, non-macOS (iOS/simulator) bundles and paths
    /// under `excludedPrefixes()` are filtered out, so the result is limited to
    /// top-level macOS applications the user could plausibly want to remove.
    func scanRegisteredApps() -> [RegisteredApp] {
#if APPSTORE
        // The App Sandbox forbids spawning lsregister and reading bundles outside the
        // container, so this scan cannot run in the App Store build.
        return []
#else
        guard let dump = dumpRegistrationDatabase() else { return [] }

        let excluded = Self.excludedPrefixes()
        var seen = Set<String>()
        var results: [RegisteredApp] = []

        for path in Self.parseBundlePaths(from: dump) {
            guard !seen.contains(path) else { continue }
            seen.insert(path)

            // Helper apps (login items, updaters, XPC UI agents) live inside a parent
            // bundle and are removed with it — listing them separately would be noise.
            guard !Self.isNestedInsideAnotherBundle(path) else { continue }
            guard !excluded.contains(where: { path.hasPrefix($0 + "/") || path == $0 }) else { continue }

            let url = URL(fileURLWithPath: path)
            let exists = FileManager.default.fileExists(atPath: path)

            // An iOS/simulator build has no Contents/MacOS and cannot run on this Mac.
            // Structure is checked rather than Info.plist keys because it holds even for
            // bundles with a missing or malformed plist.
            if exists && !Self.isMacOSApplication(url) { continue }

            results.append(RegisteredApp(url: url, isDangling: !exists))
        }

        return results
#endif
    }

    /// Reads paths from lines of the form `path:    /some/App.app (0x1234)`.
    static func parseBundlePaths(from dump: String) -> [String] {
        var paths: [String] = []

        for line in dump.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("path:") else { continue }

            var value = String(trimmed.dropFirst("path:".count))
                .trimmingCharacters(in: .whitespaces)

            // Each record ends with the database node id, e.g. " (0x14b4)".
            if let idRange = value.range(of: #"\s\(0x[0-9a-fA-F]+\)$"#, options: .regularExpression) {
                value = String(value[..<idRange.lowerBound])
            }
            value = value.trimmingCharacters(in: .whitespaces)

            guard value.hasPrefix("/"), value.hasSuffix(".app") else { continue }
            paths.append(value)
        }

        return paths
    }

    /// True when the bundle sits inside another `.app` (i.e. it is a helper).
    static func isNestedInsideAnotherBundle(_ path: String) -> Bool {
        // Compare against the parent directory so the bundle's own ".app" suffix,
        // which every candidate has, is not mistaken for an enclosing bundle.
        let parent = (path as NSString).deletingLastPathComponent
        return parent.contains(".app/") || parent.hasSuffix(".app")
    }

    /// True for a bundle that can actually run on macOS.
    static func isMacOSApplication(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        let macOSDir = url.appendingPathComponent("Contents/MacOS")
        guard FileManager.default.fileExists(atPath: macOSDir.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return false
        }
        // A stripped or partially copied bundle can have the directory but no binary.
        let contents = try? FileManager.default.contentsOfDirectory(atPath: macOSDir.path)
        return !(contents?.isEmpty ?? true)
    }

    /// Runs `lsregister -dump`. The output is large (tens of MB), so it is drained
    /// concurrently with the process running: waiting first would fill the pipe buffer
    /// and deadlock.
    private func dumpRegistrationDatabase() -> String? {
        guard FileManager.default.fileExists(atPath: Self.lsregisterPath) else { return nil }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: Self.lsregisterPath)
        process.arguments = ["-dump"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            print("lsregister dump failed to start: \(error)")
            return nil
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            print("lsregister dump exited with status \(process.terminationStatus)")
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    /// Removes an app's Launch Services registration so it stops appearing in Launchpad
    /// and Spotlight. Used for entries whose bundle is already gone, where there are no
    /// files left to delete.
    @discardableResult
    static func unregister(url: URL) -> Bool {
#if APPSTORE
        // Prohibited under the App Sandbox, like the other privileged subprocesses.
        return false
#else
        guard FileManager.default.fileExists(atPath: lsregisterPath) else { return false }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: lsregisterPath)
        process.arguments = ["-u", url.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            print("lsregister unregister failed to start: \(error)")
            return false
        }
        process.waitUntilExit()
        return process.terminationStatus == 0
#endif
    }
}
