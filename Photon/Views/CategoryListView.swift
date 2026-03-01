import SwiftUI

/// Displays the list of detected photo categories sorted by confidence,
/// with collapse logic: within each confidence section, if a signal type
/// has more than `maxVisiblePerSignal` groups, show the top N and collapse the rest.
struct CategoryListView: View {
    @ObservedObject var viewModel: ScanViewModel
    var onRescan: () -> Void = {}
    @State private var showSettings = false

    private var maxVisible: Int {
        viewModel.groupingConfig.maxVisiblePerSignal
    }

    var body: some View {
        List {
            // Summary section
            Section {
                SummaryCard(
                    totalPhotos: viewModel.totalPhotos,
                    categoriesFound: viewModel.categories.count,
                    highConfidenceCount: viewModel.categories.filter { $0.confidence == .high }.count,
                    totalDeletablePhotos: viewModel.categories
                        .filter { $0.confidence >= .medium }
                        .reduce(0) { $0 + $1.photoCount }
                )
            }

            // Session stats banner (shown after first deletion)
            if viewModel.sessionStats.photosDeleted > 0 {
                Section {
                    SessionBanner(stats: viewModel.sessionStats)
                        .accessibilityIdentifier("session_banner")
                }
            }

            // High confidence categories
            let highCategories = viewModel.categories.filter { $0.confidence == .high }
            if !highCategories.isEmpty {
                Section {
                    collapsedRows(for: highCategories)
                } header: {
                    Label("Likely to Delete", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            }

            // Medium confidence categories
            let mediumCategories = viewModel.categories.filter { $0.confidence == .medium }
            if !mediumCategories.isEmpty {
                Section {
                    collapsedRows(for: mediumCategories)
                } header: {
                    Label("Maybe Delete", systemImage: "questionmark.circle.fill")
                        .foregroundStyle(.orange)
                }
            }

            // Low confidence categories
            let lowCategories = viewModel.categories.filter { $0.confidence == .low }
            if !lowCategories.isEmpty {
                Section {
                    collapsedRows(for: lowCategories)
                } header: {
                    Label("Probably Keep", systemImage: "heart.circle.fill")
                        .foregroundStyle(.blue)
                }
            }

            if viewModel.categories.isEmpty {
                Section {
                    VStack(spacing: 12) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 40))
                            .foregroundStyle(Color.accentColor)
                        Text("Your library looks clean!")
                            .font(.headline)
                        Text("We couldn't find obvious groups of photos to suggest for deletion.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                }
            }
        }
        .listStyle(.insetGrouped)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    showSettings = true
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    onRescan()
                } label: {
                    Label("Rescan", systemImage: "arrow.clockwise")
                }
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
    }

    // MARK: - Collapse Logic

    /// Build rows for a confidence section with collapse logic per signal type.
    @ViewBuilder
    private func collapsedRows(for categories: [PhotoCategory]) -> some View {
        let grouped = Dictionary(grouping: categories, by: { $0.groupingSignal })

        // Collect visible rows and collapsed summaries
        let items = buildCollapsedItems(grouped: grouped)

        ForEach(items, id: \.id) { item in
            switch item {
            case .category(let category):
                NavigationLink(destination: CategoryDetailView(
                    category: category,
                    viewModel: viewModel
                )) {
                    CategoryRow(
                        category: category,
                        status: viewModel.categoryStatuses[category.id]
                    )
                }
                .accessibilityIdentifier("category_row_\(category.id)")
            case .collapsed(let signal, let hiddenCategories):
                NavigationLink(destination: CollapsedGroupListView(
                    categories: hiddenCategories,
                    signalName: signal.rawValue,
                    viewModel: viewModel
                )) {
                    CollapsedGroupSummaryRow(
                        signal: signal,
                        categories: hiddenCategories
                    )
                }
            }
        }
    }

    private func buildCollapsedItems(grouped: [GroupingSignal: [PhotoCategory]]) -> [CollapsedItem] {
        var items: [CollapsedItem] = []

        // Sort signal types by best score (show highest-scoring signals first)
        let sortedSignals = grouped.keys.sorted { a, b in
            let bestA = grouped[a]?.first?.score ?? 0
            let bestB = grouped[b]?.first?.score ?? 0
            return bestA > bestB
        }

        for signal in sortedSignals {
            guard let signalCategories = grouped[signal] else { continue }
            // Categories are already sorted by score from ScoringService
            if signalCategories.count <= maxVisible {
                for cat in signalCategories {
                    items.append(.category(cat))
                }
            } else {
                let visible = Array(signalCategories.prefix(maxVisible))
                let hidden = Array(signalCategories.dropFirst(maxVisible))
                for cat in visible {
                    items.append(.category(cat))
                }
                items.append(.collapsed(signal, hidden))
            }
        }

        return items
    }
}

// MARK: - Collapsed Item Model

private enum CollapsedItem {
    case category(PhotoCategory)
    case collapsed(GroupingSignal, [PhotoCategory])

    var id: String {
        switch self {
        case .category(let cat): return cat.id.uuidString
        case .collapsed(let signal, _): return "collapsed-\(signal.rawValue)"
        }
    }
}

// MARK: - Session Banner

struct SessionBanner: View {
    let stats: SessionStats

    var body: some View {
        HStack(spacing: 0) {
            BannerStat(value: "\(stats.photosDeleted)", label: "Deleted", color: .red)
            BannerStat(value: stats.formattedBytesFreed, label: "Freed", color: .green)
            BannerStat(value: "\(stats.categoriesCleaned)", label: "Cleaned", color: .purple)
        }
        .padding(.vertical, 4)
    }
}

private struct BannerStat: View {
    let value: String
    let label: String
    let color: Color

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.subheadline)
                .fontWeight(.bold)
                .monospacedDigit()
                .foregroundStyle(color)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Collapsed Group Summary Row

struct CollapsedGroupSummaryRow: View {
    let signal: GroupingSignal
    let categories: [PhotoCategory]

    private var totalPhotos: Int {
        categories.reduce(0) { $0 + $1.photoCount }
    }

    private var totalSize: Int64 {
        categories.reduce(Int64(0)) { $0 + $1.estimatedSize }
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "chevron.right.circle.fill")
                .foregroundStyle(.secondary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 4) {
                Text("\(categories.count) more \(signal.rawValue.lowercased()) groups")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    Text("\(totalPhotos) photos")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    if totalSize > 0 {
                        Text(ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file))
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Summary Card

struct SummaryCard: View {
    let totalPhotos: Int
    let categoriesFound: Int
    let highConfidenceCount: Int
    let totalDeletablePhotos: Int

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 24) {
                SummaryStatView(
                    value: "\(totalPhotos)",
                    label: "Photos Scanned",
                    icon: "photo.stack",
                    color: .primary
                )

                SummaryStatView(
                    value: "\(categoriesFound)",
                    label: "Groups Found",
                    icon: "rectangle.3.group",
                    color: Color.accentColor
                )

                SummaryStatView(
                    value: "\(totalDeletablePhotos)",
                    label: "To Review",
                    icon: "trash.circle",
                    color: .orange
                )
            }

            if highConfidenceCount > 0 {
                Text("We found \(highConfidenceCount) group\(highConfidenceCount == 1 ? "" : "s") that look like good candidates for cleanup!")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.vertical, 8)
    }
}

struct SummaryStatView: View {
    let value: String
    let label: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
            Text(value)
                .font(.headline)
                .monospacedDigit()
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Category Row

struct CategoryRow: View {
    let category: PhotoCategory
    var status: CategoryStatus? = nil

    var body: some View {
        HStack(spacing: 12) {
            // Signal icon
            Image(systemName: category.groupingSignal.systemImage)
                .foregroundStyle(confidenceColor)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 4) {
                Text(category.label)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .strikethrough(status == .cleaned, color: .secondary)

                HStack(spacing: 8) {
                    // Interaction mode badge
                    HStack(spacing: 3) {
                        Image(systemName: category.interactionMode == .keepBest ? "hand.tap" : "trash")
                            .font(.system(size: 10))
                        Text(category.interactionMode == .keepBest ? "Keep Best" : "Delete All")
                            .font(.caption)
                            .fontWeight(.semibold)
                    }
                    .fixedSize()
                    .foregroundStyle(category.interactionMode == .keepBest ? .blue : .red)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        (category.interactionMode == .keepBest ? Color.blue : Color.red)
                            .opacity(0.15)
                    )
                    .clipShape(Capsule())

                    Text("\(category.photoCount) photos")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    if category.estimatedSize > 0 {
                        Text(category.formattedSize)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }

            Spacer()

            // Status badge
            if status == .cleaned {
                HStack(spacing: 2) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Cleaned")
                        .font(.caption2).fontWeight(.medium).foregroundStyle(.green)
                }
                .font(.caption)
            } else if status == .reviewed {
                HStack(spacing: 2) {
                    Image(systemName: "eye.fill")
                        .foregroundStyle(.secondary)
                    Text("Viewed")
                        .font(.caption2).fontWeight(.medium).foregroundStyle(.secondary)
                }
                .font(.caption)
            }

            // Score badge
            Text("\(Int(category.score * 100))%")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(confidenceColor)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(confidenceColor.opacity(0.1))
                .clipShape(Capsule())
        }
        .padding(.vertical, 4)
        .opacity(status == .cleaned ? 0.5 : (status == .reviewed ? 0.85 : 1.0))
    }

    private var confidenceColor: Color {
        switch category.confidence {
        case .high: return .green
        case .medium: return .orange
        case .low: return .blue
        }
    }
}
