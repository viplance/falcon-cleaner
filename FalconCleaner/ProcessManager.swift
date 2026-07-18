import Foundation
import Darwin

/// Terminates processes by pid, escalating to admin privileges for root-owned ones.
final class ProcessManager {
    static let shared = ProcessManager()
    private init() {}

    /// Sends SIGKILL to each pid directly. Returns the pids that require elevated
    /// privileges (EPERM); already-gone processes (ESRCH) are treated as success.
    func kill(pids: [Int32]) -> [Int32] {
        var needPrivileged: [Int32] = []
        for pid in pids {
            if Darwin.kill(pid, SIGKILL) != 0 && errno == EPERM {
                needPrivileged.append(pid)
            }
        }
        return needPrivileged
    }

    /// Kills the given pids via a single admin authorization prompt.
    @discardableResult
    func privilegedKill(pids: [Int32]) -> Bool {
        guard !pids.isEmpty else { return true }
        let list = pids.map(String.init).joined(separator: " ")
        let source = "do shell script \"/bin/kill -9 \(list)\" with administrator privileges"

        guard let script = NSAppleScript(source: source) else { return false }
        var error: NSDictionary?
        script.executeAndReturnError(&error)
        if let error = error {
            print("Privileged kill error: \(error)")
            return false
        }
        return true
    }
}
