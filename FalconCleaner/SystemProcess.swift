import Foundation
import AppKit

/// A single running process/application as shown in the Processes section.
struct SystemProcess: Identifiable, Equatable {
    let id: Int32          // pid
    let name: String
    let cpu: Double        // percent (instantaneous, from top's second sample)
    let memory: Int64      // resident memory in bytes
    let icon: NSImage?
    let isApp: Bool        // true when it maps to a running GUI application

    var pid: Int32 { id }

    static func == (lhs: SystemProcess, rhs: SystemProcess) -> Bool {
        lhs.id == rhs.id && lhs.cpu == rhs.cpu && lhs.memory == rhs.memory && lhs.name == rhs.name
    }
}

/// Overall system load shown in the Processes header (parsed from top's summary lines).
struct SystemLoad: Equatable {
    let cpuUsedPercent: Double   // user + sys (i.e. 100 - idle)
    let memoryUsed: Int64
    let memoryTotal: Int64

    static let zero = SystemLoad(cpuUsedPercent: 0, memoryUsed: 0, memoryTotal: 0)

    var summary: String {
        let used = ByteCountFormatter.string(fromByteCount: memoryUsed, countStyle: .memory)
        let total = ByteCountFormatter.string(fromByteCount: memoryTotal, countStyle: .memory)
        return String(format: "CPU %.0f%%  ·  Memory %@ / %@", cpuUsedPercent, used, total)
    }
}
