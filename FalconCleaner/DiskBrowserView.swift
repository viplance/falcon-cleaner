import SwiftUI

struct DiskBrowserView: View {
    @StateObject private var viewModel = DiskBrowserViewModel()
    // Permanent deletion temporarily disabled; ignore any previously saved preference.
    // @AppStorage(AppSettings.permanentlyDeleteItemsKey) private var permanentlyDeleteItems = false
    @State private var showingDeleteConfirmation = false
    // @State private var pendingPermanentDeletion = false

    private var deletionActionTitle: String {
        // pendingPermanentDeletion ? "Delete Permanently" : "Move to Trash"
        "Move to Trash"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Navigation bar: up, home, breadcrumb path.
            HStack(spacing: 8) {
                Button(action: { viewModel.goUp() }) {
                    Image(systemName: "chevron.up")
                }
                .pointingHandCursor()
                .disabled(!viewModel.canGoUp)
                .help("Up one folder")

                Button(action: { viewModel.goHome() }) {
                    Image(systemName: "house")
                }
                .pointingHandCursor()
                .help("Home folder")

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 2) {
                        ForEach(Array(viewModel.breadcrumbs.enumerated()), id: \.element.url) { index, crumb in
                            if index > 0 {
                                Image(systemName: "chevron.right")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            Button(crumb.name) { viewModel.navigate(to: crumb.url) }
                                .buttonStyle(.link)
                                .lineLimit(1)
                                .pointingHandCursor()
                        }
                    }
                }

                Spacer(minLength: 8)

                Button {
                    viewModel.refresh()
                } label: {
                    Label(viewModel.isRefreshing ? "Refreshing..." : "Refresh", systemImage: "arrow.clockwise")
                }
                .pointingHandCursor()
                .disabled(viewModel.isLoading || viewModel.isDeleting || viewModel.isRefreshing || showingDeleteConfirmation)
                .help("Refresh this folder and recalculate its sizes")

                if viewModel.isCalculatingSizes {
                    ProgressView().controlSize(.small)
                }

                Menu {
                    ForEach(SortOption.allCases) { option in
                        Button {
                            viewModel.sortOption = option
                        } label: {
                            if viewModel.sortOption == option {
                                Label(option.rawValue, systemImage: "checkmark")
                            } else {
                                Text(option.rawValue)
                            }
                        }
                    }
                } label: {
                    Label("Sort: \(viewModel.sortOption.rawValue)", systemImage: "arrow.down")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .pointingHandCursor()
            }
            .padding(10)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.8))
            .cornerRadius(8)
            .padding()

            // Content
            ZStack {
                if viewModel.isLoading {
                    VStack(spacing: 16) {
                        ProgressView()
                        Text("Reading folder…").foregroundColor(.secondary)
                    }
                } else if viewModel.entries.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "folder")
                            .resizable().scaledToFit()
                            .frame(width: 56, height: 56)
                            .foregroundColor(.secondary.opacity(0.5))
                        Text("This folder is empty or not accessible")
                            .font(.title3)
                            .foregroundColor(.secondary)
                    }
                } else {
                    ScrollView {
                        LazyVStack(spacing: 1) {
                            ForEach(viewModel.visibleEntries) { entry in
                                DiskRowView(
                                    entry: entry,
                                    isSelected: viewModel.selected.contains(entry.id),
                                    isCalculatingSize: viewModel.currentSizingFolderID == entry.id,
                                    toggleSelection: { viewModel.toggleSelection(entry.id) },
                                    open: { viewModel.open(entry) }
                                )
                                Divider().padding(.leading, 52)
                            }
                        }
                        .padding(.top, 8)
                    }
                }
            }

            Spacer(minLength: 0)

            // Footer
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(viewModel.selected.isEmpty
                         ? "\(viewModel.entries.count) items"
                         : "\(viewModel.selected.count) selected")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    if !viewModel.statusMessage.isEmpty {
                        Text(viewModel.statusMessage)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                Button("Deselect All") { viewModel.deselectAll() }
                    .buttonStyle(.link)
                    .pointingHandCursor()
                    .disabled(viewModel.selected.isEmpty || viewModel.isDeleting || viewModel.isLoading)

                Button(action: {
                    // pendingPermanentDeletion = permanentlyDeleteItems
                    showingDeleteConfirmation = true
                }) {
                    // Text(permanentlyDeleteItems ? "Delete Permanently" : "Move to Trash")
                    Text("Move to Trash")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(.red)
                .pointingHandCursor()
                .disabled(viewModel.selected.isEmpty || viewModel.isDeleting || viewModel.isLoading || viewModel.isRefreshing)
            }
            .padding()
            .background(.ultraThinMaterial)
        }
        .task { viewModel.load(preservingSelection: true) }
        .onDisappear { viewModel.cancelLoading() }
        .alert(deletionActionTitle, isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button(deletionActionTitle, role: .destructive) {
                // let permanently = pendingPermanentDeletion
                // Task { await viewModel.deleteSelected(permanently: permanently) }
                Task { await viewModel.deleteSelected() }
            }
        } message: {
            /* Permanent deletion temporarily disabled.
            if pendingPermanentDeletion {
                Text("Permanently delete \(viewModel.selected.count) selected item(s), bypassing the Trash? This action cannot be undone.")
            } else {
                Text("Move \(viewModel.selected.count) selected item(s) to the Trash? You can restore them from the Trash if needed.")
            }
            */
            Text("Move \(viewModel.selected.count) selected item(s) to the Trash? You can restore them from the Trash if needed.")
        }
    }
}
