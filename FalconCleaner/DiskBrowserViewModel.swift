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
    @Published var currentSizingFolderID: String?
    @Published var statusMessage = ""

    private let homeURL = FileManager.default.homeDirectoryForCurrentUser
    private var sizeTask: Task<Void, Never>?
    private var sizeScanID = UUID()

    init() {
        currentURL = FileManager.default.homeDirectoryForCurrentUser
    }

    var canGoUp: Bool { currentURL.path != "/" }

    /// Auto-sizing is limited to the user's home subtree. Elsewhere (/, /System, /Users of
    /// other accounts) recursive sizing scans the entire disk via firmlinks and is anyway
    /// permission-limited, so we only show item counts there.
    var isWithinHome: Bool {
        let home = homeURL.path
        return currentURL.path == home || currentURL.path.hasPrefix(home + "/")
    }

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
        sizeScanID = UUID()
        isCalculatingSizes = false
        currentSizingFolderID = nil
        selected.removeAll()
        statusMessage = ""
        isLoading = true
        let url = currentURL
        Task {
            let list = await Task.detached { DiskScanner.shared.listDirectory(url) }.value
            guard url == self.currentURL else { return }  // navigated away meanwhile
            self.entries = list
            self.isLoading = false
            // Auto-size, but only inside the home tree — at the root the firmlinked system
            // volume would make it scan the whole disk and freeze.
            if self.isWithinHome { self.calculateSizes() }
        }
    }

    /// Computes recursive sizes for the folders currently shown automatically in the background.
    /// The task starts after the folder list has had a chance to render, then walks one folder at
    /// a time with throttled I/O in `DiskScanner`.
    func calculateSizes() {
        sizeTask?.cancel()
        sizeScanID = UUID()
        let scanID = sizeScanID
        let folders = entries.filter { $0.isDirectory && $0.folderSize == nil }.map { ($0.id, $0.url) }
        guard !folders.isEmpty else { return }
        isCalculatingSizes = true
        sizeTask = Task.detached(priority: .background) { [weak self] in
            try? await Task.sleep(nanoseconds: 500_000_000)
            if Task.isCancelled { return }
            for (id, url) in folders {
                if Task.isCancelled { break }
                await MainActor.run { [weak self] in
                    guard let self, self.sizeScanID == scanID else { return }
                    self.currentSizingFolderID = id
                }
                let modDate = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
                let size = await DiskScanner.shared.directorySize(url, isCancelled: { Task.isCancelled })
                if Task.isCancelled { break }
                FolderSizeCache.shared.store(size, for: url.path, modDate: modDate)
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    guard self.sizeScanID == scanID else { return }
                    if let index = self.entries.firstIndex(where: { $0.id == id }) {
                        self.entries[index].folderSize = size
                    }
                }
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
            await MainActor.run { [weak self] in
                guard let self, self.sizeScanID == scanID else { return }
                self.isCalculatingSizes = false
                self.currentSizingFolderID = nil
            }
        }
    }

    func cancelSizeCalculation() {
        sizeTask?.cancel()
        sizeScanID = UUID()
        isCalculatingSizes = false
        currentSizingFolderID = nil
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
