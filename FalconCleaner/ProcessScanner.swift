import Foundation
import AppKit

/// Scans running processes via `top` and enriches them with app icons/names.
final class ProcessScanner {
    static let shared = ProcessScanner()
    private init() {}

    private struct RawProcess {
        let pid: Int32
        let cpu: Double
        let memory: Int64
        let name: String
    }

    struct ScanResult {
        let processes: [SystemProcess]
        let load: SystemLoad
    }

    func scan() async -> ScanResult {
        let output = await runTop()
        let (raw, load) = parse(output)
        let processes = await MainActor.run { attachAppInfo(raw) }
        return ScanResult(processes: processes, load: load)
    }

    // MARK: - Running top

    private func runTop() async -> String {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/top")
                // -l 2: two samples so the second one carries real interval CPU%.
                // -o cpu: pre-sort by CPU. -stats: exactly the columns we parse.
                process.arguments = ["-l", "2", "-o", "cpu", "-stats", "pid,cpu,mem,command"]
                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = Pipe()
                do {
                    try process.run()
                } catch {
                    continuation.resume(returning: "")
                    return
                }
                // Read before waiting to avoid the child blocking on a full pipe buffer.
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                continuation.resume(returning: String(data: data, encoding: .utf8) ?? "")
            }
        }
    }

    // MARK: - Parsing

    private func parse(_ output: String) -> ([RawProcess], SystemLoad) {
        let lines = output.components(separatedBy: .newlines)

        // Keep only the second sample (top's first sample reports since-boot averages).
        let sampleStarts = lines.enumerated()
            .filter { $0.element.hasPrefix("Processes:") }
            .map { $0.offset }
        let sampleStart = sampleStarts.count >= 2 ? sampleStarts[1] : 0

        // The process table begins right after the "PID ... COMMAND" header.
        guard let headerIndex = (sampleStart..<lines.count).first(where: { lines[$0].hasPrefix("PID") }) else {
            return ([], .zero)
        }

        // Overall load comes from the summary lines between the sample start and the table.
        let load = parseLoad(Array(lines[sampleStart..<headerIndex]))

        var result: [RawProcess] = []
        for index in (headerIndex + 1)..<lines.count {
            let line = lines[index].trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            // Columns: pid cpu mem command(may contain spaces, always last).
            let columns = line.split(separator: " ", omittingEmptySubsequences: true)
            guard columns.count >= 4, let pid = Int32(columns[0]) else { continue }
            let cpu = Double(columns[1]) ?? 0
            let memory = parseMemory(String(columns[2]))
            let name = columns[3...].joined(separator: " ")
            if name == "top" { continue } // hide the helper process we just spawned
            result.append(RawProcess(pid: pid, cpu: cpu, memory: memory, name: name))
        }
        return (result, load)
    }

    /// Parses top's "CPU usage:" and "PhysMem:" summary lines.
    private func parseLoad(_ headerLines: [String]) -> SystemLoad {
        var cpuUsed = 0.0
        var memUsed: Int64 = 0
        var memUnused: Int64 = 0

        for line in headerLines {
            if line.hasPrefix("CPU usage:") {
                // e.g. "CPU usage: 10.7% user, 7.30% sys, 82.61% idle"
                let parts = line.components(separatedBy: ",")
                for part in parts where part.contains("idle") {
                    let tokens = part.split(separator: " ")
                    if let idleToken = tokens.first(where: { $0.hasSuffix("%") }),
                       let idle = Double(idleToken.dropLast()) {
                        cpuUsed = max(0, 100 - idle)
                    }
                }
            } else if line.hasPrefix("PhysMem:") {
                // e.g. "PhysMem: 17G used (2324M wired, 2506M compressor), 114M unused."
                let afterLabel = line.dropFirst("PhysMem:".count).trimmingCharacters(in: .whitespaces)
                let tokens = afterLabel.split(separator: " ")
                if let usedToken = tokens.first {
                    memUsed = parseMemory(String(usedToken))
                }
                if let unusedIndex = tokens.firstIndex(where: { $0.contains("unused") }), unusedIndex > 0 {
                    memUnused = parseMemory(String(tokens[unusedIndex - 1]))
                }
            }
        }

        return SystemLoad(cpuUsedPercent: cpuUsed, memoryUsed: memUsed, memoryTotal: memUsed + memUnused)
    }

    /// Converts top's memory strings (e.g. "1334M", "4912K", "2G", "154M-") to bytes.
    private func parseMemory(_ raw: String) -> Int64 {
        var string = raw.trimmingCharacters(in: .whitespaces)
        while let last = string.last, last == "+" || last == "-" { string.removeLast() }
        guard let unit = string.last else { return 0 }

        let multiplier: Double
        switch unit {
        case "B": multiplier = 1
        case "K": multiplier = 1024
        case "M": multiplier = 1024 * 1024
        case "G": multiplier = 1024 * 1024 * 1024
        case "T": multiplier = 1024.0 * 1024 * 1024 * 1024
        default:  multiplier = 1 // no unit suffix → already bytes
        }

        let numberPart = unit.isLetter ? String(string.dropLast()) : string
        let value = Double(numberPart) ?? 0
        return Int64(value * multiplier)
    }

    // MARK: - App enrichment

    @MainActor
    private func attachAppInfo(_ items: [RawProcess]) -> [SystemProcess] {
        var appsByPid: [Int32: NSRunningApplication] = [:]
        for app in NSWorkspace.shared.runningApplications {
            appsByPid[app.processIdentifier] = app
        }

        return items.map { item in
            if let app = appsByPid[item.pid] {
                return SystemProcess(
                    id: item.pid,
                    name: app.localizedName ?? item.name,
                    cpu: item.cpu,
                    memory: item.memory,
                    icon: app.icon,
                    isApp: true
                )
            } else {
                return SystemProcess(
                    id: item.pid,
                    name: item.name,
                    cpu: item.cpu,
                    memory: item.memory,
                    icon: nil,
                    isApp: false
                )
            }
        }
    }
}
