import SwiftUI

/// Info icon for a process: shows base info instantly and enriches it on hover with the
/// code-signature vendor, enclosing app and executable path (loaded lazily, cached).
struct ProcessInfoHint: View {
    let process: SystemProcess
    @State private var isHovering = false
    @State private var details: ProcessDetails?

    var body: some View {
        Image(systemName: "info.circle")
            .font(.caption)
            .foregroundColor(isHovering ? .primary : .secondary)
            .contentShape(Rectangle())
            .onHover { isHovering = $0 }
            .popover(isPresented: $isHovering, arrowEdge: .bottom) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(process.infoHint)
                        .font(.callout)

                    // Vendor from the signature is most useful for background processes
                    // (apps already show their developer in the base info).
                    if !process.isApp, let signer = details?.signer, !signer.isEmpty {
                        Text("By \(signer)").font(.callout)
                    }
                    if !process.isApp, let app = details?.enclosingApp {
                        Text("Part of \(app)").font(.callout)
                    }
                }
                .padding(12)
                .fixedSize()
                .task(id: process.executablePath) {
                    if let path = process.executablePath {
                        details = await ProcessInspector.shared.detailsAsync(forPath: path)
                    }
                }
            }
    }
}
