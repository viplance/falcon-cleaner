import Foundation
import SwiftUI
import Combine

@MainActor
final class DiskBrowserViewModel: ObservableObject {
    @Published var currentURL: URL
    @Published var entries: [DiskEntry] = []
    @Published var sortOption: SortOption = .size
    @Published var selected: Set<String> = []

    /// Entries sorted by the chosen option (folders' sizes fill in as they are computed).
    var visibleEntries: [DiskEntry] {
        switch sortOption {
        case .size:
            return entries.sorted {
                let a = sortKey($0), b = sortKey($1)
                return a != b ? a > b : $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
        case .name:
            return entries.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
    }

    private func sortKey(_ entry: DiskEntry) -> Int64 {
        if let folderSize = entry.folderSize { return folderSize }
        if let size = entry.size { return size }
        return -1   // folder size not computed yet — keep at the bottom until it arrives
    }
    @Published var isLoading = false
    @Published var isDeleting = false
    @Published var isCalculatingSizes = false
    @Published var statusMessage = ""

    private let homeURL = FileManager.default.homeDirectoryForCurrentUser
    private var sizeTask: Task<Void, Never>?

    init() {
        currentURL = FileManager.default.homeDirectoryForCurrentUser
    }

    var canGoUp: Bool { currentURL.path != "/" }

    /// Path components from root to the current folder, for the breadcrumb bar.
    /// Built from `pathComponents` (finite) — a previous while-loop version could spin
    /// forever on some URLs, blowing up memory and hanging the UI.
    var breadcrumbs: [(name: String, url: URL)] {
        let components = currentURL.standardizedFileURL.pathComponents  // ["/", "Users", "me", …]
        var result: [(name: String, url: URL)] = []
        var url = URL(fileURLWithPath: "/")
        for (index, component) in components.enumerated() {
            if index == 0 {
                result.append(("Macintosh HD", url))
            } else {
                url.appendPathComponent(component)
                result.append((component, url))
            }
        }
        return result
    }

    func load() {
        sizeTask?.cancel()
        isCalculatingSizes = false
        selected.removeAll()
        statusMessage = ""
        isLoading = true
        let url = currentURL
        Task {
            let list = await Task.detached { DiskScanner.shared.listDirectory(url) }.value
            guard url == self.currentURL else { return }  // navigated away meanwhile
            self.entries = list
            self.isLoading = false
            self.calculateSizes()   // start sizing automatically
        }
    }

    /// Computes recursive sizes for the folders currently shown — on demand only, in the
    /// background, one folder at a time, cancelled when navigating away.
    func calculateSizes() {
        let folders = entries.filter { $0.isDirectory && $0.folderSize == nil }.map { ($0.id, $0.url) }
        guard !folders.isEmpty else { return }
        isCalculatingSizes = true
        sizeTask = Task.detached(priority: .utility) { [weak self] in
            for (id, url) in folders {
                if Task.isCancelled { break }
                let modDate = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
                let size = DiskScanner.shared.directorySize(url, isCancelled: { Task.isCancelled })
                if Task.isCancelled { break }
                FolderSizeCache.shared.store(size, for: url.path, modDate: modDate)
                await MainActor.run {
                    guard let self else { return }
                    if let index = self.entries.firstIndex(where: { $0.id == id }) {
                        self.entries[index].folderSize = size
                    }
                }
            }
            await MainActor.run { self?.isCalculatingSizes = false }
        }
    }

    func cancelSizeCalculation() {
        sizeTask?.cancel()
        isCalculatingSizes = false
    }

    func open(_ entry: DiskEntry) {
        guard entry.isDirectory else { return }
        navigate(to: entry.url)
    }

    func navigate(to url: URL) {
        currentURL = url
        load()
    }

    func goUp() {
        guard canGoUp else { return }
        navigate(to: currentURL.deletingLastPathComponent())
    }

    func goHome() {
        navigate(to: homeURL)
    }

    func toggleSelection(_ id: String) {
        if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
    }

    func deselectAll() {
        selected.removeAll()
    }

    func deleteSelected() async {
        let targets = entries.filter { selected.contains($0.id) }
        guard !targets.isEmpty else { return }
        isDeleting = true
        var failed: [String] = []
        for entry in targets {
            do {
                try FileManager.default.trashItem(at: entry.url, resultingItemURL: nil)
            } catch {
                failed.append(entry.name)
            }
        }
        isDeleting = false
        statusMessage = failed.isEmpty ? "" : "Could not move to Trash: \(failed.joined(separator: ", "))"
        load()
    }
}
