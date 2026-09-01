import SwiftUI

struct AppRowView: View {
    let app: AppInfo
    let isSelected: Bool
    let toggleSelection: () -> Void

    /// Secondary line under the app name. Apps outside the standard folders show where
    /// they live, since that is what explains their presence in the list.
    private var subtitle: String {
        if app.isDanglingRegistration { return "Listed by macOS · app no longer on disk" }
        if app.isBroken { return "Broken application entry" }
        if app.type == .registered { return app.path.deletingLastPathComponent().path }
        return app.bundleIdentifier ?? "Unknown bundle ID"
    }


    var body: some View {
        HStack(spacing: 12) {
            Toggle("", isOn: Binding(
                get: { isSelected },
                set: { _ in toggleSelection() }
            ))
            .toggleStyle(CheckboxToggleStyle())
            .labelsHidden()
            
            if app.type == .brew {
                Image(systemName: "mug.fill")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 26, height: 26)
                    .frame(width: 40, height: 40)
                    .foregroundColor(.brown)
            } else if let icon = app.icon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 40, height: 40)
            } else {
                Image(systemName: "app.fill")
                    .resizable()
                    .frame(width: 40, height: 40)
                    .foregroundColor(.secondary)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(app.name)
                        .font(.headline)
                        .lineLimit(1)

                    AppInfoHint(app: app)
                }

                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 2) {
                // Startup items have no meaningful size (always zero), and a dangling
                // registration has no files left at all, so hide the size for both.
                if app.type != .startup && !app.isDanglingRegistration {
                    Text(ByteCountFormatter.string(fromByteCount: app.totalSize, countStyle: .file))
                        .font(.subheadline)
                        .fontWeight(.medium)
                }

                if app.isSystemApp {
                    Text("System App")
                        .font(.system(size: 10, weight: .bold))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(Color.yellow.opacity(0.2))
                        .foregroundColor(.yellow)
                        .cornerRadius(4)
                } else if app.isDanglingRegistration {
                    Text("Leftover")
                        .font(.system(size: 10, weight: .bold))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(Color.orange.opacity(0.15))
                        .foregroundColor(.orange)
                        .cornerRadius(4)
                } else if app.isBroken {
                    Text("Broken")
                        .font(.system(size: 10, weight: .bold))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(Color.red.opacity(0.15))
                        .foregroundColor(.red)
                        .cornerRadius(4)
                }
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture {
            toggleSelection()
        }
    }
}
