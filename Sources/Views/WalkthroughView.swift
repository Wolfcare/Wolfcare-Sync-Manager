import SwiftUI

private struct WalkthroughStep {
    let icon: String
    let title: String
    let body: String
}

private let walkthroughSteps: [WalkthroughStep] = [
    .init(
        icon: "folder.badge.plus",
        title: "Add Sources",
        body: "Create a sync task with the + button, then add one or more folders under its Sources tab — those are the folders that get backed up."
    ),
    .init(
        icon: "externaldrive.fill",
        title: "Choose a Destination",
        body: "Point the task at an external drive or folder. Imitor keeps it in sync using rsync under the hood."
    ),
    .init(
        icon: "clock.fill",
        title: "Set a Schedule",
        body: "Run hourly, daily, weekly, or on an interval. Imitor keeps syncing on schedule in the menu bar, even with the window closed."
    ),
    .init(
        icon: "arrow.triangle.2.circlepath",
        title: "Sync, Pause, Stop",
        body: "Run tasks individually or all at once from the sidebar. Any sync can be paused or stopped mid-transfer without losing progress."
    ),
    .init(
        icon: "doc.text",
        title: "Check the Activity Log",
        body: "The Activity Log in the sidebar keeps a running record of every sync, so you can always see what happened and why."
    ),
]

struct WalkthroughView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("showWalkthroughOnLaunch") private var showOnLaunch: Bool = true
    @State private var stepIndex = 0

    private let steps = walkthroughSteps

    var body: some View {
        VStack(spacing: 22) {
            ImitorIcon(isAnimating: false)
                .frame(width: 60, height: 60)

            VStack(spacing: 10) {
                Image(systemName: steps[stepIndex].icon)
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(Theme.highlight2)
                Text(steps[stepIndex].title)
                    .font(.title3.bold())
                    .foregroundStyle(Theme.highlight2)
                Text(steps[stepIndex].body)
                    .font(.callout)
                    .foregroundStyle(Theme.gray2)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: 340)
            .frame(minHeight: 140, alignment: .top)

            HStack(spacing: 6) {
                ForEach(steps.indices, id: \.self) { index in
                    Circle()
                        .fill(index == stepIndex ? Theme.highlight2 : Theme.dark1)
                        .frame(width: 6, height: 6)
                }
            }

            Divider().overlay(.white.opacity(0.08))

            HStack {
                Toggle("Show this when the app opens", isOn: $showOnLaunch)
                    .toggleStyle(.checkbox)
                    .font(.caption)
                    .foregroundStyle(Theme.gray2)

                Spacer()

                if stepIndex > 0 {
                    Button("Back") { stepIndex -= 1 }
                        .buttonStyle(.chrome)
                }
                Button(stepIndex == steps.count - 1 ? "Done" : "Next") {
                    if stepIndex == steps.count - 1 {
                        dismiss()
                    } else {
                        stepIndex += 1
                    }
                }
                .buttonStyle(.chrome)
            }
        }
        .padding(28)
        .frame(width: 440)
        .background(Theme.charcoalBase)
    }
}
