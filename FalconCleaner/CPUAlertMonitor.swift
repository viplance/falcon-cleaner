import Foundation
import UserNotifications

/// Watches processes in the background and posts a system notification when one stays in the
/// "red" zone (pegging a CPU core) for longer than a sustained window. Runs independently of
/// whichever section is on screen.
@MainActor
final class CPUAlertMonitor {
    static let shared = CPUAlertMonitor()

    private let redThreshold: Double = 80          // per-core %, matches the red highlight
    private let sustainedFor: TimeInterval = 600   // 10 minutes
    private let interval: TimeInterval = 60        // poll cadence

    private var redSince: [Int32: Date] = [:]      // pid -> when it first went red (continuously)
    private var notified: Set<Int32> = []          // pids already alerted this episode
    private var task: Task<Void, Never>?

    func start() {
        guard task == nil else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        task = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                await self.tick()
                try? await Task.sleep(nanoseconds: UInt64(self.interval * 1_000_000_000))
            }
        }
    }

    private func tick() async {
        let processes = await ProcessScanner.shared.scan().processes
        let now = Date()
        var currentlyRed: Set<Int32> = []

        for process in processes where process.coreCPU >= redThreshold {
            currentlyRed.insert(process.pid)
            if let since = redSince[process.pid] {
                if now.timeIntervalSince(since) >= sustainedFor, !notified.contains(process.pid) {
                    notify(process: process)
                    notified.insert(process.pid)
                }
            } else {
                redSince[process.pid] = now
            }
        }

        // Reset processes that cooled down or exited so a later spike alerts again.
        for pid in Array(redSince.keys) where !currentlyRed.contains(pid) {
            redSince.removeValue(forKey: pid)
            notified.remove(pid)
        }
    }

    private func notify(process: SystemProcess) {
        let content = UNMutableNotificationContent()
        content.title = "High CPU usage"
        content.body = "\(process.name) has been using a full CPU core for over 10 minutes "
            + "(\(Int(process.coreCPU.rounded()))% of one core)."
        content.sound = .default
        let request = UNNotificationRequest(identifier: "cpu-alert-\(process.pid)",
                                            content: content,
                                            trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
