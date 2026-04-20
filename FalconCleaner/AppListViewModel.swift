import Foundation
import SwiftUI
import Combine

enum AppCategory: String, CaseIterable, Identifiable {
    case all = "All"
    case standard = "Applications"
    case brew = "Brew"
    case startup = "Startup"
    var id: String { self.rawValue }
}

@MainActor
class AppListViewModel: ObservableObject {
    @Published var apps: [AppInfo] = []
    @Published var selectedApps: Set<UUID> = []
    @Published var isScanning: Bool = false
    @Published var isCleaning: Bool = false
    @Published var progressMessage: String = ""
    @Published var searchText: String = ""
    @Published var selectedCategory: AppCategory = .all
    
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
        }
        
        if searchText.isEmpty {
            return categoryApps
        }
        return categoryApps.filter { $0.name.localizedCaseInsensitiveContains(searchText) || ($0.bundleIdentifier?.localizedCaseInsensitiveContains(searchText) ?? false) }
    }
    
    func scan() async {
        isScanning = true
        progressMessage = "Scanning for applications..."
        apps = await AppScanner.shared.scanInstalledApps()
        isScanning = false
        progressMessage = ""
    }
    
    func cleanupSelected() async {
        isCleaning = true
        let appsToCleanup = apps.filter { selectedApps.contains($0.id) }
        
        for app in appsToCleanup {
            progressMessage = "Cleaning up \(app.name)..."
            do {
                try await AppManager.shared.cleanup(app: app)
                apps.removeAll { $0.id == app.id }
                selectedApps.remove(app.id)
            } catch {
                print("Failed to clean up \(app.name): \(error)")
            }
        }
        
        isCleaning = false
        progressMessage = "Cleanup finished!"
        try? await Task.sleep(nanoseconds: 2_000_000_000)
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
