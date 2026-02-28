import SwiftUI

/// Debug panel for tuning grouping parameters and inspecting results
struct DebugView: View {
    @ObservedObject var viewModel: ScanViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var config: GroupingConfig
    @State private var isReclustering = false

    init(viewModel: ScanViewModel) {
        self.viewModel = viewModel
        self._config = State(initialValue: viewModel.groupingConfig)
    }

    var body: some View {
        NavigationStack {
            List {
                // Statistics
                Section("Statistics") {
                    StatRow(label: "Total photos scanned", value: "\(viewModel.totalPhotos)")
                    StatRow(label: "Total groups", value: "\(viewModel.categories.count)")
                    StatRow(label: "Photos in groups", value: "\(photosInGroups)")
                    StatRow(label: "Ungrouped photos", value: "\(viewModel.totalPhotos - uniquePhotosInGroups)")
                    StatRow(label: "Photos in multiple groups", value: "\(photosInMultipleGroups)")

                    // Per-signal breakdown
                    ForEach(GroupingSignal.allCases, id: \.self) { signal in
                        let groups = viewModel.categories.filter { $0.groupingSignal == signal }
                        if !groups.isEmpty {
                            let totalPhotos = groups.reduce(0) { $0 + $1.photoCount }
                            StatRow(
                                label: signal.rawValue,
                                value: "\(groups.count) groups, \(totalPhotos) photos"
                            )
                        }
                    }

                    if let largest = viewModel.categories.max(by: { $0.photoCount < $1.photoCount }) {
                        StatRow(label: "Largest group", value: "\(largest.photoCount) photos (\(largest.groupingSignal.rawValue))")
                    }
                }

                // Near-Duplicate Parameters
                Section("Near-Duplicate Detection") {
                    VStack(alignment: .leading) {
                        Text("Epsilon: \(config.nearDuplicateEpsilon, specifier: "%.2f")")
                            .font(.caption)
                        Slider(value: $config.nearDuplicateEpsilon, in: 0.05...0.30, step: 0.01)
                    }
                    Stepper("Min points: \(config.nearDuplicateMinPoints)", value: $config.nearDuplicateMinPoints, in: 2...10)
                    Stepper("Max group size: \(config.nearDuplicateMaxGroupSize)", value: $config.nearDuplicateMaxGroupSize, in: 10...200, step: 10)
                }

                // Global
                Section("Global Filters") {
                    Stepper("Min group size: \(config.minGroupSize)", value: $config.minGroupSize, in: 2...10)
                }

                // Screenshot Parameters
                Section("Screenshot Clustering") {
                    VStack(alignment: .leading) {
                        Text("Epsilon: \(config.screenshotEpsilon, specifier: "%.2f")")
                            .font(.caption)
                        Slider(value: $config.screenshotEpsilon, in: 0.10...0.50, step: 0.01)
                    }
                    Stepper("Min points: \(config.screenshotMinPoints)", value: $config.screenshotMinPoints, in: 2...10)
                }

                // Blur Parameters
                Section("Blur Detection") {
                    VStack(alignment: .leading) {
                        Text("Very blurry threshold: \(config.veryBlurryThreshold, specifier: "%.0f")")
                            .font(.caption)
                        Slider(value: $config.veryBlurryThreshold, in: 10...200, step: 5)
                    }
                    VStack(alignment: .leading) {
                        Text("Somewhat blurry threshold: \(config.somewhatBlurryThreshold, specifier: "%.0f")")
                            .font(.caption)
                        Slider(value: $config.somewhatBlurryThreshold, in: 50...500, step: 10)
                    }
                }

                // Trip Parameters
                Section("Trip Detection") {
                    VStack(alignment: .leading) {
                        Text("Distance from home: \(config.tripDistanceThresholdKm, specifier: "%.0f") km")
                            .font(.caption)
                        Slider(value: $config.tripDistanceThresholdKm, in: 10...200, step: 5)
                    }
                    VStack(alignment: .leading) {
                        Text("Trip merge radius: \(config.tripLocationGridKm, specifier: "%.0f") km")
                            .font(.caption)
                        Slider(value: $config.tripLocationGridKm, in: 10...200, step: 10)
                    }
                    Stepper("Min photos per trip: \(config.minPhotosPerTrip)", value: $config.minPhotosPerTrip, in: 3...20)
                }

                // Video Parameters
                Section("Video Detection") {
                    Stepper("Large video threshold: \(config.largeVideoThresholdMB) MB", value: $config.largeVideoThresholdMB, in: 25...500, step: 25)
                }

                // Live Photo Parameters
                Section("Live Photo Detection") {
                    Stepper("Min live photos: \(config.livePhotoMinCount)", value: $config.livePhotoMinCount, in: 3...50)
                }

                // Old Photo Parameters
                Section("Old Photo Detection") {
                    Stepper("Age threshold: \(config.oldPhotoAgeDays) days", value: $config.oldPhotoAgeDays, in: 180...1825, step: 90)
                }

                // Dark Photo Parameters
                Section("Dark Photo Detection") {
                    VStack(alignment: .leading) {
                        Text("Very dark threshold: \(config.veryDarkBrightnessThreshold, specifier: "%.0f")")
                            .font(.caption)
                        Slider(value: $config.veryDarkBrightnessThreshold, in: 5...50, step: 5)
                    }
                    VStack(alignment: .leading) {
                        Text("Dark threshold: \(config.darkBrightnessThreshold, specifier: "%.0f")")
                            .font(.caption)
                        Slider(value: $config.darkBrightnessThreshold, in: 20...80, step: 5)
                    }
                }

                // Saved Image Parameters
                Section("Saved Image Detection") {
                    let fileSizeKB = config.savedImageMaxFileSize / 1000
                    Stepper("Max file size: \(fileSizeKB) KB", value: $config.savedImageMaxFileSize, in: 100_000...2_000_000, step: 100_000)
                }

                // Collapse UX
                Section("Collapse UX") {
                    Stepper("Max visible per signal: \(config.maxVisiblePerSignal)", value: $config.maxVisiblePerSignal, in: 1...10)
                }

                // Re-cluster button
                Section {
                    Button {
                        Task {
                            isReclustering = true
                            await viewModel.rerunGrouping(with: config)
                            isReclustering = false
                        }
                    } label: {
                        HStack {
                            if isReclustering {
                                ProgressView()
                                    .padding(.trailing, 4)
                            }
                            Text(isReclustering ? "Re-clustering..." : "Re-cluster with New Parameters")
                                .fontWeight(.medium)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .disabled(isReclustering)
                }

                // Group list
                Section("Groups (\(viewModel.categories.count))") {
                    ForEach(viewModel.categories) { category in
                        NavigationLink(destination: CategoryDetailView(
                            category: category,
                            viewModel: viewModel
                        )) {
                            HStack {
                                Image(systemName: category.groupingSignal.systemImage)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 24)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(category.label)
                                        .font(.caption)
                                        .lineLimit(1)
                                    Text("\(category.groupingSignal.rawValue) · Score: \(Int(category.score * 100))%")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Debug Mode")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    // MARK: - Computed stats

    private var photosInGroups: Int {
        viewModel.categories.reduce(0) { $0 + $1.photoCount }
    }

    private var uniquePhotosInGroups: Int {
        var allIDs = Set<String>()
        for category in viewModel.categories {
            allIDs.formUnion(category.photoIDs)
        }
        return allIDs.count
    }

    private var photosInMultipleGroups: Int {
        var counts: [String: Int] = [:]
        for category in viewModel.categories {
            for id in category.photoIDs {
                counts[id, default: 0] += 1
            }
        }
        return counts.values.filter { $0 > 1 }.count
    }
}

// MARK: - Helper views

private struct StatRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.caption)
                .fontWeight(.medium)
                .monospacedDigit()
        }
    }
}
