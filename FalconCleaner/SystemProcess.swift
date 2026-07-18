import Foundation
import AppKit

/// A single running process/application as shown in the Processes section.
struct SystemProcess: Identifiable, Equatable {
    let id: Int32          // pid
    let name: String
    let cpu: Double        // percent of the whole machine (normalized across all cores)
    let coreCPU: Double    // percent of a single core (top's raw %CPU, can exceed 100%)
    let memory: Int64      // resident memory in bytes
    let icon: NSImage?
    let isApp: Bool        // true when it maps to a running GUI application
    var category: String? = nil
    var developer: String? = nil
    var executablePath: String? = nil

    var pid: Int32 { id }

    /// Base summary for the info tooltip. Vendor/enclosing app are resolved lazily in the
    /// hint view; CPU/memory live in the columns, so they are not repeated here.
    var infoHint: String {
        var lines: [String] = []
        lines.append(isApp ? (category ?? "Application") : "Background process")
        if let developer = developer, !developer.isEmpty {
            lines.append("By \(developer)")
        }
        return lines.joined(separator: "\n")
    }

    static func == (lhs: SystemProcess, rhs: SystemProcess) -> Bool {
        lhs.id == rhs.id && lhs.cpu == rhs.cpu && lhs.memory == rhs.memory && lhs.name == rhs.name
    }
}

/// Overall system load shown in the Processes header (parsed from top's summary lines).
struct SystemLoad: Equatable {
    let cpuUsedPercent: Double   // user + sys (i.e. 100 - idle)
    let memoryUsed: Int64
    let memoryTotal: Int64
    let coreCount: Int

    static let zero = SystemLoad(cpuUsedPercent: 0, memoryUsed: 0, memoryTotal: 0, coreCount: 0)

    var summary: String {
        let used = ByteCountFormatter.string(fromByteCount: memoryUsed, countStyle: .memory)
        let total = ByteCountFormatter.string(fromByteCount: memoryTotal, countStyle: .memory)
        let cpuPart = coreCount > 0
            ? String(format: "CPU %.0f%% of %d cores", cpuUsedPercent, coreCount)
            : String(format: "CPU %.0f%%", cpuUsedPercent)
        return "\(cpuPart)  ·  Memory \(used) / \(total)"
    }
}
