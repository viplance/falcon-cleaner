import SwiftUI

struct ProcessListView: View {
    @StateObject private var viewModel = ProcessListViewModel()
    @State private var showingKillConfirmation = false

    var body: some View {
        VStack(spacing: 0) {
            // Header: search + sort
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search processes...", text: $viewModel.searchText)
                    .textFieldStyle(.plain)

                if !viewModel.searchText.isEmpty {
                    Button(action: { viewModel.searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                Menu {
                    ForEach(ProcessSortOption.allCases) { option in
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

                if viewModel.hasLoaded {
                    Text(viewModel.load.summary)
                        .foregroundColor(.secondary)
                        .font(.subheadline)
                }
            }
            .padding(10)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.8))
            .cornerRadius(8)
            .padding()

            // Content
            ZStack {
                if viewModel.isLoading && !viewModel.hasLoaded {
                    VStack(spacing: 16) {
                        ProgressView()
                        Text("Reading running processes...")
                            .foregroundColor(.secondary)
                    }
                } else if viewModel.visibleProcesses.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "cpu")
                            .resizable()
                            .frame(width: 56, height: 56)
                            .foregroundColor(.secondary.opacity(0.5))
                        Text(viewModel.searchText.isEmpty ? "No processes found" : "No matches for '\(viewModel.searchText)'")
                            .font(.title3)
                            .foregroundColor(.secondary)
                    }
                } else {
                    ScrollView {
                        LazyVStack(spacing: 1) {
                            ForEach(viewModel.visibleProcesses) { process in
                                ProcessRowView(
                                    process: process,
                                    highlight: viewModel.sortOption,
                                    isSelected: viewModel.selectedProcesses.contains(process.pid),
                                    toggleSelection: { viewModel.toggleSelection(for: process.pid) }
                                )
                                Divider().padding(.leading, 56)
                            }
                        }
                        .padding(.top, 8)
                    }
                    .onHover { hovering in
                        viewModel.isHoveringList = hovering
                    }
                }
            }

            Spacer(minLength: 0)

            // Footer
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(viewModel.selectedProcesses.isEmpty
                         ? "\(viewModel.visibleProcesses.count) processes"
                         : "\(viewModel.selectedProcesses.count) selected")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    if viewModel.hasLoaded {
                        Text("Live · refreshes automatically")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                Button("Deselect All") {
                    viewModel.deselectAll()
                }
                .buttonStyle(.link)
                .disabled(viewModel.selectedProcesses.isEmpty || viewModel.isKilling)

                Button(action: { showingKillConfirmation = true }) {
                    Text("Kill")
                        .frame(width: 80)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(.red)
                .disabled(viewModel.selectedProcesses.isEmpty || viewModel.isKilling)
            }
            .padding()
            .background(.ultraThinMaterial)
        }
        .alert("Kill Processes", isPresented: $showingKillConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Kill", role: .destructive) {
                Task { await viewModel.killSelected() }
            }
        } message: {
            Text("Force-quit \(viewModel.selectedProcesses.count) selected process(es)? Unsaved work in those processes will be lost. Root-owned processes will ask for your password.")
        }
        .task {
            // Auto-refresh while the Processes section is visible.
            // Each scan already takes ~1s (top -l 2), then we pause before the next.
            while !Task.isCancelled {
                // Pause updates while the pointer is over the list so rows don't
                // reorder out from under the cursor (keeps the info hint stable).
                if !viewModel.isHoveringList || !viewModel.hasLoaded {
                    await viewModel.refresh()
                }
                try? await Task.sleep(nanoseconds: 3_000_000_000)
            }
        }
    }
}
