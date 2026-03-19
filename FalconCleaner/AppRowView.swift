import SwiftUI

struct AppRowView: View {
    let app: AppInfo
    let isSelected: Bool
    let toggleSelection: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            Toggle("", isOn: Binding(
                get: { isSelected },
                set: { _ in toggleSelection() }
            ))
            .toggleStyle(CheckboxToggleStyle())
            .labelsHidden()
            
            if let icon = app.icon {
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
                Text(app.name)
                    .font(.headline)
                
                Text(app.bundleIdentifier ?? "Unknown bundle ID")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 2) {
                Text(ByteCountFormatter.string(fromByteCount: app.totalSize, countStyle: .file))
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                if app.isSystemApp {
                    Text("System App")
                        .font(.system(size: 10, weight: .bold))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(Color.yellow.opacity(0.2))
                        .foregroundColor(.yellow)
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
