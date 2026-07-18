import Foundation
import SwiftUI
import Combine

enum ProcessSortOption: String, CaseIterable, Identifiable {
    case cpu = "CPU"
    case memory = "Memory"
    var id: String { self.rawValue }
}

@MainActor
final class ProcessListViewModel: ObservableObject {
    @Published var processes: [SystemProcess] = []
    @Published var load: SystemLoad = .zero
    @Published var selectedProcesses: Set<Int32> = []
    @Published var isLoading: Bool = false
    @Published var isKilling: Bool = false
    @Published var isHoveringList: Bool = false
    @Published var hasLoaded: Bool = false
    @Published var sortOption: ProcessSortOption = .cpu
    @Published var searchText: String = ""

    /// Processes after search filtering and sorting (largest load/usage on top).
    var visibleProcesses: [SystemProcess] {
        let filtered: [SystemProcess]
        if searchText.isEmpty {
            filtered = processes
        } else {
            filtered = processes.filter {
                $0.name.localizedCaseInsensitiveContains(searchText) || String($0.pid).contains(searchText)
            }
        }

        switch sortOption {
        case .cpu:
            return filtered.sorted {
                $0.cpu != $1.cpu ? $0.cpu > $1.cpu : $0.memory > $1.memory
            }
        case .memory:
            return filtered.sorted {
                $0.memory != $1.memory ? $0.memory > $1.memory : $0.cpu > $1.cpu
            }
        }
    }

    func refresh() async {
        if !hasLoaded { isLoading = true }
        let result = await ProcessScanner.shared.scan()
        processes = result.processes
        load = result.load
        // Drop selections for processes that no longer exist.
        let alive = Set(processes.map { $0.pid })
        selectedProcesses.formIntersection(alive)
        isLoading = false
        hasLoaded = true
    }

    func toggleSelection(for pid: Int32) {
        if selectedProcesses.contains(pid) {
            selectedProcesses.remove(pid)
        } else {
            selectedProcesses.insert(pid)
        }
    }

    func deselectAll() {
        selectedProcesses.removeAll()
    }

    func killSelected() async {
        let pids = Array(selectedProcesses)
        guard !pids.isEmpty else { return }

        isKilling = true
        // Kill user-owned processes directly; escalate the rest with one admin prompt.
        let needPrivileged = await Task.detached { ProcessManager.shared.kill(pids: pids) }.value
        if !needPrivileged.isEmpty {
            await Task.detached { ProcessManager.shared.privilegedKill(pids: needPrivileged) }.value
        }
        selectedProcesses.removeAll()
        await refresh()
        isKilling = false
    }
}
