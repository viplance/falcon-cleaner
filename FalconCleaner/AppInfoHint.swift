import SwiftUI

/// Info icon for an app row. Shows a human-readable summary that depends on the item type:
/// standard apps show role/developer/version; Homebrew packages lazily load `brew desc`;
/// startup items lazily resolve the vendor and owning app of the executable they launch.
struct AppInfoHint: View {
    let app: AppInfo
    @State private var isHovering = false
    @State private var brewDescription: String?
    @State private var brewLoaded = false
    @State private var startupDetails: ProcessDetails?

    var body: some View {
        Image(systemName: "info.circle")
            .font(.caption)
            .foregroundColor(isHovering ? .primary : .secondary)
            .contentShape(Rectangle())
            .onHover { isHovering = $0 }
            .popover(isPresented: $isHovering, arrowEdge: .bottom) {
                VStack(alignment: .leading, spacing: 4) {
                    content
                }
                .padding(12)
                .fixedSize()
                .task(id: app.id) { await load() }
            }
    }

    @ViewBuilder
    private var content: some View {
        switch app.type {
        case .standard:
            Text(app.infoHint).font(.callout)

        case .brew:
            if let description = brewDescription, !description.isEmpty {
                // Cap width so long descriptions wrap instead of stretching the popover.
                Text(description).font(.callout).frame(maxWidth: 320, alignment: .leading)
            } else if brewLoaded {
                Text("Homebrew package · no description available")
                    .font(.callout).foregroundColor(.secondary)
            } else {
                Text("Loading…").font(.callout).foregroundColor(.secondary)
            }

        case .startup:
            let hasVendor = (startupDetails?.signer?.isEmpty == false)
            let hasApp = (startupDetails?.enclosingApp != nil)
            if let signer = startupDetails?.signer, !signer.isEmpty {
                Text("By \(signer)").font(.callout)
            }
            if let owner = startupDetails?.enclosingApp {
                Text("Part of \(owner)").font(.callout)
            }
            Text("Launches automatically at startup")
                .font(hasVendor || hasApp ? .caption : .callout)
                .foregroundColor(.secondary)
        }
    }

    private func load() async {
        switch app.type {
        case .brew:
            brewDescription = await BrewInspector.shared.descriptionAsync(for: app.name)
            brewLoaded = true
        case .startup:
            if let path = app.launchProgramPath {
                startupDetails = await ProcessInspector.shared.detailsAsync(forPath: path)
            }
        case .standard:
            break
        }
    }
}
