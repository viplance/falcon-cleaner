import SwiftUI

enum AppSettings {
    static let permanentlyDeleteItemsKey = "permanentlyDeleteItems"
}

struct SettingsView: View {
    // Permanent deletion temporarily disabled.
    // @AppStorage(AppSettings.permanentlyDeleteItemsKey) private var permanentlyDeleteItems = false
    // @State private var showingPermanentDeletionWarning = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Deletion")
                .font(.headline)

            /* Permanent deletion temporarily disabled.
            Toggle("Permanently delete items instead of moving them to Trash", isOn: Binding(
                get: { permanentlyDeleteItems },
                set: { enabled in
                    if enabled {
                        showingPermanentDeletionWarning = true
                    } else {
                        permanentlyDeleteItems = false
                    }
                }
            ))
            .toggleStyle(.checkbox)

            Label {
                Text("Permanent deletion bypasses the Trash and cannot be undone. Removing applications and their related files can erase saved data and affect other applications. This applies to app cleanup and files deleted in Disk.")
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
            .font(.callout)
            */

            // Text("Leave this option off to move items to the Trash. Homebrew packages are always uninstalled directly and cannot be restored from the Trash.")
            Text("Applications and related files, and items removed in Disk, are moved to the Trash. Homebrew packages are uninstalled directly and cannot be restored from the Trash.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(24)
        .frame(width: 480)
        /* Permanent deletion temporarily disabled.
        .alert("Enable Permanent Deletion?", isPresented: $showingPermanentDeletionWarning) {
            Button("Cancel", role: .cancel) { }
            Button("Enable Permanent Deletion", role: .destructive) {
                permanentlyDeleteItems = true
            }
        } message: {
            Text("Deleted applications, related files, and items deleted in Disk will bypass the Trash. This can permanently erase saved data and cannot be undone.")
        }
        */
    }
}
