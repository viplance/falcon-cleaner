import SwiftUI

struct DiskBrowserView: View {
    @StateObject private var viewModel = DiskBrowserViewModel()
    @AppStorage(AppSettings.permanentlyDeleteItemsKey) private var permanentlyDeleteItems = false
    @State private var showingDeleteConfirmation = false
    @State private var pendingPermanentDeletion = false

    private var deletionActionTitle: String {
        pendingPermanentDeletion ? "Delete Permanently" : "Move to Trash"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Navigation bar: up, home, breadcrumb path.
            HStack(spacing: 8) {
                Button(action: { viewModel.goUp() }) {
                    Image(systemName: "chevron.up")
                }
                .disabled(!viewModel.canGoUp)
                .help("Up one folder")

                Button(action: { viewModel.goHome() }) {
                    Image(systemName: "house")
                }
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
                        }
                    }
                }

                Spacer(minLength: 8)

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
                    .disabled(viewModel.selected.isEmpty || viewModel.isDeleting)

                Button(action: {
                    pendingPermanentDeletion = permanentlyDeleteItems
                    showingDeleteConfirmation = true
                }) {
                    Text(permanentlyDeleteItems ? "Delete Permanently" : "Move to Trash")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(.red)
                .disabled(viewModel.selected.isEmpty || viewModel.isDeleting)
            }
            .padding()
            .background(.ultraThinMaterial)
        }
        .task { if viewModel.entries.isEmpty { viewModel.load() } }
        .onDisappear { viewModel.cancelSizeCalculation() }
        .alert(deletionActionTitle, isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button(deletionActionTitle, role: .destructive) {
                let permanently = pendingPermanentDeletion
                Task { await viewModel.deleteSelected(permanently: permanently) }
            }
        } message: {
            if pendingPermanentDeletion {
                Text("Permanently delete \(viewModel.selected.count) selected item(s), bypassing the Trash? This action cannot be undone.")
            } else {
                Text("Move \(viewModel.selected.count) selected item(s) to the Trash? You can restore them from the Trash if needed.")
            }
        }
    }
}
