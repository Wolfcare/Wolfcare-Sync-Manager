import SwiftUI

/// An at-a-glance summary card (icon, title, one-line status) — inspired by
/// Carbon Copy Cloner's Source/Destination/Automation card row, so a task's
/// whole configuration is visible without clicking through tabs.
struct SummaryCard: View {
    let icon: String
    let title: String
    let detail: String
    var detailColor: Color = Theme.gray2
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 26))
                    .foregroundStyle(Theme.gray2)
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.highlight2)
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(detailColor)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .padding(.horizontal, 8)
            .background(Theme.charcoalDeep, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(.white.opacity(0.06), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

/// Shown once a run finishes (succeeded, failed, or stopped) — a completion
/// summary in the style of CCC's post-run banner, replacing a bare status line.
struct CompletionBanner: View {
    let summary: BackupStore.RunSummary
    let onViewLog: () -> Void
    let onDismiss: () -> Void

    private var icon: String {
        switch summary.outcome {
        case .succeeded: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.triangle.fill"
        case .stopped: return "stop.circle.fill"
        }
    }

    private var iconColor: Color {
        switch summary.outcome {
        case .succeeded: return .green
        case .failed: return .red
        case .stopped: return .orange
        }
    }

    private var headline: String {
        switch summary.outcome {
        case .succeeded: return "The backup completed successfully."
        case .failed: return "The backup did not complete successfully."
        case .stopped: return "The backup was stopped."
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 22))
                .foregroundStyle(iconColor)

            VStack(alignment: .leading, spacing: 4) {
                Text(headline)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.highlight2)
                Text("Completed at \(Self.timeFormatter.string(from: summary.date)) · Took \(Self.durationString(summary.duration)) · Transferred \(Self.byteFormatter.string(fromByteCount: summary.bytesTransferred))")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.gray2)
            }

            Spacer(minLength: 8)

            Button("View Log", action: onViewLog)
                .buttonStyle(.chrome)

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .foregroundStyle(Theme.gray2)
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .frame(maxWidth: 480, alignment: .leading)
        .background(Theme.charcoalDeep, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(.white.opacity(0.06), lineWidth: 1))
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    private static let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter
    }()

    private static func durationString(_ duration: TimeInterval) -> String {
        let totalSeconds = Int(duration.rounded())
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        if minutes >= 60 {
            return String(format: "%dh %dm", minutes / 60, minutes % 60)
        } else if minutes > 0 {
            return String(format: "%dm %ds", minutes, seconds)
        }
        return String(format: "%ds", seconds)
    }
}
