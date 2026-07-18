import SwiftUI

struct DiskRowView: View {
    let entry: DiskEntry
    let isSelected: Bool
    let isCalculatingSize: Bool
    let toggleSelection: () -> Void
    let open: () -> Void

    /// Byte size to show: a file's own size, or a folder's computed recursive size.
    private var sizeValue: Int64? {
        entry.isDirectory ? entry.folderSize : entry.size
    }

    var body: some View {
        HStack(spacing: 12) {
            Toggle("", isOn: Binding(
                get: { isSelected },
                set: { _ in toggleSelection() }
            ))
            .toggleStyle(CheckboxToggleStyle())
            .labelsHidden()

            Image(nsImage: DiskIconProvider.icon(for: entry))
                .resizable()
                .frame(width: 28, height: 28)

            Text(entry.name)
                .font(.body)
                .lineLimit(1)
                .truncationMode(.middle)

            if entry.isDirectory {
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Items column — folders only.
            Text(entry.isDirectory ? "\(entry.itemCount ?? 0) item\(entry.itemCount == 1 ? "" : "s")" : "")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .frame(width: 80, alignment: .trailing)

            // Size column — files immediately, folders once computed.
            Group {
                if let size = sizeValue {
                    Text(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                } else {
                    if isCalculatingSize {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        // Folder size is queued or not available yet.
                        Text("—")
                            .foregroundColor(.secondary.opacity(0.4))
                    }
                }
            }
            .font(.subheadline)
            .frame(width: 90, alignment: .trailing)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 12)
        .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture {
            if entry.isDirectory { open() }
        }
    }
}
