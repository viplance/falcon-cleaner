import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = AppListViewModel()
    @State private var showingConfirmation = false
    
    var body: some View {
        NavigationSplitView {
            List(AppCategory.allCases, selection: $viewModel.selectedCategory) { category in
                NavigationLink(value: category) {
                    Label(
                        category.rawValue,
                        systemImage: {
                            switch category {
                            case .all: return "circle.grid.2x2.fill"
                            case .standard: return "app.fill"
                            case .brew: return "terminal"
                            case .startup: return "bolt.fill"
                            case .processes: return "cpu"
                            case .disk: return "internaldrive"
                            }
                        }()
                    )
                    // Indent the sub-categories that "All" aggregates.
                    .padding(.leading, (category == .standard || category == .brew || category == .startup) ? 16 : 0)
                }
            }
            .listStyle(.sidebar)
            .navigationTitle("Falcon Cleaner")
            .navigationSplitViewColumnWidth(min: 180, ideal: 185)
        } detail: {
            if viewModel.selectedCategory == .processes {
                ProcessListView()
            } else if viewModel.selectedCategory == .disk {
                DiskBrowserView()
            } else {
            VStack(spacing: 0) {
                // Header / Search Bar
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("Search applications...", text: $viewModel.searchText)
                        .textFieldStyle(.plain)
                    
                    if !viewModel.searchText.isEmpty {
                        Button(action: { viewModel.searchText = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    
                    Spacer()

                    if viewModel.selectedCategory != .startup {
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

                    Text(viewModel.diskUsageInfo)
                        .foregroundColor(.secondary)
                        .font(.subheadline)
                }
                .padding(10)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.8))
                .cornerRadius(8)
                .padding()
                
                // Content
                ZStack {
                    if viewModel.isScanning || !viewModel.hasScanned {
                        VStack(spacing: 16) {
                            ProgressView()
                            Text("Scanning your Mac for apps...")
                                .foregroundColor(.secondary)
                        }
                    } else if viewModel.filteredApps.isEmpty {
                        VStack(spacing: 16) {
                            Image(systemName: "sun.max.fill")
                                .resizable()
                                .frame(width: 64, height: 64)
                                .foregroundColor(.secondary.opacity(0.5))
                            Text(viewModel.searchText.isEmpty ? "No applications found" : "No matches for '\(viewModel.searchText)'")
                                .font(.title3)
                                .foregroundColor(.secondary)
                        }
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 1) {
                                ForEach(viewModel.filteredApps) { app in
                                    AppRowView(
                                        app: app,
                                        isSelected: viewModel.selectedApps.contains(app.id),
                                        toggleSelection: { viewModel.toggleSelection(for: app.id) }
                                    )
                                    Divider().padding(.leading, 64)
                                }
                            }
                            .padding(.top, 8)
                        }
                    }
                    
                    if viewModel.isCleaning {
                        Color(NSColor.windowBackgroundColor).opacity(0.7)
                            .edgesIgnoringSafeArea(.all)
                        
                        VStack(spacing: 20) {
                            ProgressView()
                                .scaleEffect(1.5)
                            Text(viewModel.progressMessage)
                                .font(.headline)
                        }
                        .padding(40)
                        .background(.ultraThinMaterial)
                        .cornerRadius(16)
                        .shadow(radius: 20)
                    }
                }
                
                Spacer(minLength: 0)
                
                // Footer
                HStack {
                    VStack(alignment: .leading) {
                        Text("\(viewModel.selectedApps.count) selected")
                            .font(.subheadline)
                        Text(viewModel.progressMessage)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()

                    Button("Deselect All") {
                        viewModel.deselectAll()
                    }
                    .buttonStyle(.link)
                    .disabled(viewModel.selectedApps.isEmpty || viewModel.isCleaning)

                    Button(action: { showingConfirmation = true }) {
                        Text("Clean Up")
                            .frame(width: 100)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .tint(.blue)
                    .disabled(viewModel.selectedApps.isEmpty || viewModel.isCleaning)
                }
                .padding()
                .background(.ultraThinMaterial)
            }
            }
        }
        .task {
            CPUAlertMonitor.shared.start()
            await viewModel.scan()
        }
        .alert("Confirm Clean Up", isPresented: $showingConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete Permanently", role: .destructive) {
                Task {
                    await viewModel.cleanupSelected()
                }
            }
        } message: {
            let totalSelected = viewModel.apps.filter { viewModel.selectedApps.contains($0.id) }.count
            Text("This will permanently delete \(totalSelected) applications and their related files, bypassing the Trash. This action cannot be undone.")
        }
    }
}
