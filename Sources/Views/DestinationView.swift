import SwiftUI
import AppKit

struct DestinationView: View {
    @EnvironmentObject private var store: BackupStore

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Destination")
                .font(.title2.bold())

            if let destination = store.destination {
                HStack(spacing: 8) {
                    Circle()
                        .fill(store.isDestinationReachable ? .green : .red)
                        .frame(width: 10, height: 10)
                    Text(destination)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                if !store.isDestinationReachable {
                    Text("Not reachable — is the drive mounted?")
                        .font(.subheadline)
                        .foregroundStyle(.red)
                }
            } else {
                Text("No destination set yet.")
                    .foregroundStyle(.secondary)
            }

            Button {
                chooseDestination()
            } label: {
                Label("Choose Destination…", systemImage: "externaldrive.badge.plus")
            }

            Text("Every backup run copies the contents of each source directory into this destination. Files about to be overwritten are preserved first under .versions/<timestamp>/.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Spacer()
        }
    }

    private func chooseDestination() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.message = "Choose the backup destination root"
        if panel.runModal() == .OK, let url = panel.url {
            store.setDestination(url.path)
        }
    }
}
