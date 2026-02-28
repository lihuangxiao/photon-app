import SwiftUI

/// Full-screen celebration shown at the end of a cleanup session
struct SessionSummaryView: View {
    let stats: SessionStats
    let totalPhotos: Int
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            // Celebration icon
            Image(systemName: "sparkles")
                .font(.system(size: 64))
                .foregroundStyle(.yellow.gradient)

            Text("Cleanup Complete!")
                .font(.largeTitle)
                .fontWeight(.bold)

            // Stats grid
            VStack(spacing: 20) {
                HStack(spacing: 32) {
                    StatBubble(
                        value: "\(totalPhotos)",
                        label: "Reviewed",
                        icon: "eye",
                        color: .blue
                    )
                    StatBubble(
                        value: "\(stats.photosDeleted)",
                        label: "Deleted",
                        icon: "trash",
                        color: .red
                    )
                    .accessibilityIdentifier("summary_deleted_count")
                }
                HStack(spacing: 32) {
                    StatBubble(
                        value: stats.formattedBytesFreed,
                        label: "Freed",
                        icon: "externaldrive",
                        color: .green
                    )
                    StatBubble(
                        value: "\(stats.categoriesCleaned)",
                        label: "Cleaned",
                        icon: "checkmark.circle",
                        color: .purple
                    )
                }
            }
            .padding(.horizontal)

            // Recovery reminder
            VStack(spacing: 8) {
                Label("Photos stay in Recently Deleted for 30 days", systemImage: "clock.arrow.circlepath")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("Come back anytime to clean up more!")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 8)

            Spacer()

            Button(action: onDismiss) {
                Text("Done")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
            }
            .accessibilityIdentifier("summary_done")
            .buttonStyle(.borderedProminent)
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
    }
}

// MARK: - Stat Bubble

private struct StatBubble: View {
    let value: String
    let label: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)
            Text(value)
                .font(.title3)
                .fontWeight(.bold)
                .monospacedDigit()
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(color.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
