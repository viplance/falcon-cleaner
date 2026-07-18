import Foundation
import SwiftUI
import Combine

enum AppCategory: String, CaseIterable, Identifiable {
    case all = "All"
    case standard = "Applications"
    case brew = "Brew"
    case startup = "Startup"
    case processes = "Processes"
    case disk = "Disk"
    var id: String { self.rawValue }
}

enum SortOption: String, CaseIterable, Identifiable {
    case size = "Size"
    case name = "Name"
    var id: String { self.rawValue }
}

@MainActor
class AppListViewModel: ObservableObject {
    @Published var apps: [AppInfo] = []
    @Published var selectedApps: Set<UUID> = []
    @Published var isScanning: Bool = false
    @Published var hasScanned: Bool = false
    @Published var isCleaning: Bool = false
    @Published var progressMessage: String = ""
    @Published var searchText: String = ""
    @Published var selectedCategory: AppCategory = .all
    @Published var sortOption: SortOption = .size

    var filteredApps: [AppInfo] {
        let categoryApps: [AppInfo]
        switch selectedCategory {
        case .all:
            categoryApps = apps
        case .standard:
            categoryApps = apps.filter { $0.type == .standard }
        case .brew:
            categoryApps = apps.filter { $0.type == .brew }
        case .startup:
            categoryApps = apps.filter { $0.type == .startup }
        case .processes:
            categoryApps = [] // handled by a dedicated Processes view, not the app list
        case .disk:
            categoryApps = [] // handled by a dedicated Disk browser, not the app list
        }

        let searchedApps: [AppInfo]
        if searchText.isEmpty {
            searchedApps = categoryApps
        } else {
            searchedApps = categoryApps.filter { $0.name.localizedCaseInsensitiveContains(searchText) || ($0.bundleIdentifier?.localizedCaseInsensitiveContains(searchText) ?? false) }
        }

        return sorted(searchedApps)
    }

    private func sorted(_ apps: [AppInfo]) -> [AppInfo] {
        // Startup items have no meaningful size, so they are always sorted by name.
        let option: SortOption = selectedCategory == .startup ? .name : sortOption
        switch option {
        case .size:
            // Largest to smallest; tie-break by name for stable ordering.
            return apps.sorted {
                $0.totalSize != $1.totalSize
                    ? $0.totalSize > $1.totalSize
                    : $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
        case .name:
            return apps.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
    }
    
    func scan() async {
        isScanning = true
        progressMessage = "Scanning for applications..."
        // Task.detached guarantees the whole scan (incl. its heavy synchronous prologue)
        // runs off the main thread, so the UI never freezes.
        apps = await Task.detached { await AppScanner.shared.scanInstalledApps() }.value
        // Prefetch Homebrew descriptions once so hovering a package is instant.
        BrewInspector.shared.prefetchAll(apps.filter { $0.type == .brew }.map { $0.name })
        isScanning = false
        hasScanned = true
        progressMessage = ""
    }
    
    func cleanupSelected() async {
        isCleaning = true
        let appsToCleanup = apps.filter { selectedApps.contains($0.id) }
        var failed: [String] = []

        for app in appsToCleanup {
            progressMessage = "Cleaning up \(app.name)..."
            do {
                try await AppManager.shared.cleanup(app: app, permanently: true)
                apps.removeAll { $0.id == app.id }
                selectedApps.remove(app.id)
            } catch {
                failed.append(app.name)
                print("Failed to clean up \(app.name): \(error)")
            }
        }

        isCleaning = false
        progressMessage = failed.isEmpty
            ? "Cleanup finished!"
            : "Could not remove: \(failed.joined(separator: ", "))"
        try? await Task.sleep(nanoseconds: 3_000_000_000)
        progressMessage = ""
    }
    
    func toggleSelection(for id: UUID) {
        if selectedApps.contains(id) {
            selectedApps.remove(id)
        } else {
            selectedApps.insert(id)
        }
    }
    
    func selectAll() {
        selectedApps = Set(filteredApps.map { $0.id })
    }
    
    func deselectAll() {
        selectedApps.removeAll()
    }
    
    var diskUsageInfo: String {
        let fileURL = URL(fileURLWithPath: "/")
        do {
            let values = try fileURL.resourceValues(forKeys: [.volumeAvailableCapacityKey, .volumeTotalCapacityKey])
            if let capacity = values.volumeTotalCapacity, let available = values.volumeAvailableCapacity {
                let used = capacity - available
                let usedGB = Double(used) / 1_000_000_000.0
                let totalGB = Double(capacity) / 1_000_000_000.0
                return String(format: "Disk usage: %.1f from %.0f GB", usedGB, totalGB)
            }
        } catch {
            print("Error retrieving capacity: \(error.localizedDescription)")
        }
        return ""
    }
}
