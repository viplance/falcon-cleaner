import Foundation

/// Fetches Homebrew formula descriptions. All installed formulae are prefetched once in a
/// single `brew info` call (fast, avoids per-hover brew launches); hovers read the cache.
/// Formulae brew refuses to read (untrusted taps) fall back to parsing the formula .rb file.
@MainActor
final class BrewInspector {
    static let shared = BrewInspector()

    private var cache: [String: String] = [:]   // formula -> desc ("" means "looked up, none")
    private var prefetchTask: Task<Void, Never>?

    /// Kicks off a one-shot batch load of descriptions for the given installed formulae.
    func prefetchAll(_ formulae: [String]) {
        guard prefetchTask == nil, !formulae.isEmpty else { return }
        prefetchTask = Task { [formulae] in
            let map = await Task.detached { Self.fetchAllInstalled() }.value
            for (name, desc) in map where cache[name] == nil {
                cache[name] = desc
            }
            // For formulae brew didn't describe (e.g. untrusted taps), read the .rb directly.
            let missing = formulae.filter { (cache[$0] ?? "").isEmpty }
            if !missing.isEmpty {
                let extra = await Task.detached { Self.descriptionsFromFormulaFiles(missing) }.value
                for (name, desc) in extra { cache[name] = desc }
            }
            // Mark anything still unknown so we don't retry it.
            for formula in formulae where cache[formula] == nil {
                cache[formula] = ""
            }
        }
    }

    /// Description for a formula. Waits for the batch prefetch if it is in flight, then
    /// falls back to an individual lookup only if still unknown.
    func descriptionAsync(for formula: String) async -> String? {
        if let cached = cache[formula] { return cached.isEmpty ? nil : cached }
        if let task = prefetchTask {
            await task.value
            if let cached = cache[formula] { return cached.isEmpty ? nil : cached }
        }
        let desc = await Task.detached { Self.fetchOne(formula) }.value
        cache[formula] = desc ?? ""
        return desc
    }

    // MARK: - brew invocation

    private nonisolated static func brewBinaryPath() -> String? {
        ["/opt/homebrew/bin/brew", "/usr/local/bin/brew", "/usr/bin/brew"]
            .first { FileManager.default.fileExists(atPath: $0) }
    }

    private nonisolated static func run(_ arguments: [String]) -> Data? {
        guard let brew = brewBinaryPath() else { return nil }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: brew)
        process.arguments = arguments
        // brew requires HOME; ensure it is set regardless of the app's launch environment.
        var env = ProcessInfo.processInfo.environment
        if env["HOME"] == nil { env["HOME"] = NSHomeDirectory() }
        process.environment = env
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
        } catch {
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return process.terminationStatus == 0 ? data : nil
    }

    /// One call returning descriptions for every installed formula (name and full_name).
    private nonisolated static func fetchAllInstalled() -> [String: String] {
        guard let data = run(["info", "--json=v2", "--installed"]),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let formulae = root["formulae"] as? [[String: Any]] else { return [:] }

        var map: [String: String] = [:]
        for formula in formulae {
            let desc = (formula["desc"] as? String) ?? ""
            if let name = formula["name"] as? String { map[name] = desc }
            if let fullName = formula["full_name"] as? String { map[fullName] = desc }
        }
        return map
    }

    private nonisolated static func fetchOne(_ formula: String) -> String? {
        if let data = run(["desc", formula]), let output = String(data: data, encoding: .utf8) {
            for line in output.components(separatedBy: .newlines) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("\(formula): ") {
                    return String(trimmed.dropFirst(formula.count + 2))
                }
            }
        }
        return descriptionsFromFormulaFiles([formula])[formula]
    }

    // MARK: - Reading desc straight from the formula .rb (bypasses brew's tap trust check)

    private nonisolated static func descriptionsFromFormulaFiles(_ formulae: [String]) -> [String: String] {
        guard let brew = brewBinaryPath() else { return [:] }
        let prefix = URL(fileURLWithPath: brew).deletingLastPathComponent().deletingLastPathComponent()
        let tapsDir = prefix.appendingPathComponent("Library/Taps")
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(at: tapsDir, includingPropertiesForKeys: nil) else { return [:] }

        // Map "<formula>.rb" -> formula so we can match while walking the taps once.
        let targets = Dictionary(formulae.map { ("\($0).rb", $0) }, uniquingKeysWith: { first, _ in first })
        var result: [String: String] = [:]

        for case let url as URL in enumerator {
            // homebrew-core is huge and its formulae come from the trusted JSON already.
            if url.lastPathComponent == "homebrew-core" { enumerator.skipDescendants(); continue }
            if let formula = targets[url.lastPathComponent], result[formula] == nil,
               let content = try? String(contentsOf: url, encoding: .utf8),
               let desc = descLine(in: content) {
                result[formula] = desc
                if result.count == targets.count { break }
            }
        }
        return result
    }

    private nonisolated static func descLine(in content: String) -> String? {
        guard let range = content.range(of: #"desc\s+"([^"]*)""#, options: .regularExpression) else { return nil }
        let matched = content[range]
        guard let firstQuote = matched.firstIndex(of: "\"") else { return nil }
        let afterFirst = matched.index(after: firstQuote)
        guard let secondQuote = matched[afterFirst...].firstIndex(of: "\"") else { return nil }
        let desc = String(matched[afterFirst..<secondQuote])
        return desc.isEmpty ? nil : desc
    }
}
