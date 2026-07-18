import SwiftUI

struct ProcessRowView: View {
    let process: SystemProcess
    let highlight: ProcessSortOption
    let isSelected: Bool
    let toggleSelection: () -> Void

    private var cpuColor: Color {
        switch process.cpu {
        case 50...: return .red
        case 20..<50: return .orange
        default: return .primary
        }
    }

    private var memoryText: String {
        ByteCountFormatter.string(fromByteCount: process.memory, countStyle: .memory)
    }

    var body: some View {
        HStack(spacing: 12) {
            Toggle("", isOn: Binding(
                get: { isSelected },
                set: { _ in toggleSelection() }
            ))
            .toggleStyle(CheckboxToggleStyle())
            .labelsHidden()

            if let icon = process.icon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 32, height: 32)
            } else {
                Image(systemName: "gearshape.2.fill")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 24, height: 24)
                    .frame(width: 32, height: 32)
                    .foregroundColor(.secondary)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(process.name)
                        .font(.headline)
                        .lineLimit(1)

                    ProcessInfoHint(process: process)
                }
                Text("PID \(process.pid)\(process.isApp ? " · App" : "")")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            HStack(spacing: 20) {
                // CPU
                VStack(alignment: .trailing, spacing: 2) {
                    Text(String(format: "%.1f%%", process.cpu))
                        .font(.subheadline)
                        .fontWeight(highlight == .cpu ? .bold : .medium)
                        .foregroundColor(cpuColor)
                    Text("CPU")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.secondary)
                }
                .frame(width: 70, alignment: .trailing)

                // Memory
                VStack(alignment: .trailing, spacing: 2) {
                    Text(memoryText)
                        .font(.subheadline)
                        .fontWeight(highlight == .memory ? .bold : .medium)
                    Text("Memory")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.secondary)
                }
                .frame(width: 80, alignment: .trailing)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 12)
        .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture {
            toggleSelection()
        }
    }
}
