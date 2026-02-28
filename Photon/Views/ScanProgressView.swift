import SwiftUI

/// Displays scan progress with animated indicators
struct ScanProgressView: View {
    let phase: String
    let message: String
    let progress: Double? // nil = indeterminate
    let photosProcessed: Int
    let totalPhotos: Int

    @State private var animateGlow = false

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            // Animated icon
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.1))
                    .frame(width: 140, height: 140)
                    .scaleEffect(animateGlow ? 1.1 : 1.0)

                Circle()
                    .fill(Color.accentColor.opacity(0.2))
                    .frame(width: 100, height: 100)

                Image(systemName: phaseIcon)
                    .font(.system(size: 40))
                    .foregroundStyle(Color.accentColor)
                    .symbolEffect(.pulse, isActive: true)
            }
            .animation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true), value: animateGlow)
            .onAppear { animateGlow = true }

            // Phase label
            VStack(spacing: 8) {
                Text(phase)
                    .font(.title2)
                    .fontWeight(.semibold)

                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            // Progress bar
            if let progress {
                VStack(spacing: 8) {
                    ProgressView(value: progress)
                        .tint(Color.accentColor)
                        .scaleEffect(y: 2)
                        .padding(.horizontal, 40)

                    Text("\(Int(progress * 100))%")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            } else {
                ProgressView()
                    .scaleEffect(1.2)
            }

            // Stats
            HStack(spacing: 32) {
                StatView(value: "\(totalPhotos)", label: "Total Photos")
                StatView(value: "\(photosProcessed)", label: "Processed")
            }
            .padding(.top, 8)

            Spacer()
            Spacer()
        }
        .padding()
    }

    private var phaseIcon: String {
        switch phase {
        case "Preparing": return "sparkles"
        case "Loading Photos": return "photo.stack"
        case "Analyzing": return "brain"
        case "Detecting Blur": return "aqi.medium"
        case "Finding Patterns": return "rectangle.3.group"
        default: return "sparkles"
        }
    }
}

struct StatView: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title3)
                .fontWeight(.semibold)
                .monospacedDigit()
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    ScanProgressView(
        phase: "Analyzing",
        message: "Analyzing photos... 1,234/5,678",
        progress: 0.45,
        photosProcessed: 1234,
        totalPhotos: 5678
    )
}
