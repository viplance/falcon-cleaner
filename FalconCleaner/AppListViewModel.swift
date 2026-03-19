import Foundation
import SwiftUI
import Combine

@MainActor
class AppListViewModel: ObservableObject {
    @Published var apps: [AppInfo] = []
    @Published var selectedApps: Set<UUID> = []
    @Published var isScanning: Bool = false
    @Published var isCleaning: Bool = false
    @Published var progressMessage: String = ""
    @Published var searchText: String = ""
    
    var filteredApps: [AppInfo] {
        if searchText.isEmpty {
            return apps
        }
        return apps.filter { $0.name.localizedCaseInsensitiveContains(searchText) || ($0.bundleIdentifier?.localizedCaseInsensitiveContains(searchText) ?? false) }
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
}
