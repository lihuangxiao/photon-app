import Foundation

/// Multi-signal scoring algorithm that assigns deletion confidence to photo categories.
/// Updated for the multi-signal grouping pipeline — each signal type gets appropriate base scoring,
/// with existing sub-signals (age, temporal density, recency) as modifiers.
class ScoringService {

    struct Weights {
        var clusterSize: Double = 0.20
        var temporalDensity: Double = 0.15
        var age: Double = 0.10
        var visualHomogeneity: Double = 0.10
        var recencyPenalty: Double = 0.10
    }

    private let weights: Weights

    init(weights: Weights = Weights()) {
        self.weights = weights
    }

    /// Score categories produced by GroupingPipeline.
    /// Each category already has a groupingSignal — we apply signal-specific base scoring
    /// plus modifier sub-signals.
    func scoreCategories(
        categories: [PhotoCategory],
        allAssets: [PhotoAsset]
    ) -> [PhotoCategory] {
        let assetMap = Dictionary(uniqueKeysWithValues: allAssets.map { ($0.id, $0) })

        return categories.map { category in
            let assets = category.photoIDs.compactMap { assetMap[$0] }
            guard !assets.isEmpty else { return category }

            let score = computeScore(for: assets, signal: category.groupingSignal)
            let confidence = confidenceLevel(from: score)

            return PhotoCategory(
                id: category.id,
                label: category.label,
                photoIDs: category.photoIDs,
                confidence: confidence,
                score: score,
                photoCount: category.photoCount,
                estimatedSize: category.estimatedSize,
                dateRange: category.dateRange,
                dominantType: category.dominantType,
                groupingSignal: category.groupingSignal,
                interactionMode: category.interactionMode,
                cloudReason: category.cloudReason
            )
        }
        .sorted { $0.score > $1.score }
    }

    // MARK: - Score Computation

    private func computeScore(for assets: [PhotoAsset], signal: GroupingSignal) -> Double {
        // Base score from signal type
        let baseScore = signalBaseScore(signal: signal, count: assets.count)

        // Modifier sub-signals
        let sizeModifier = clusterSizeModifier(count: assets.count)
        let temporalModifier = temporalDensitySignal(assets)
        let ageModifier = ageSignal(assets)
        let homogeneityModifier = visualHomogeneitySignal(assets)
        let recencyModifier = recencyPenaltySignal(assets)

        // Base score contributes ~35%, modifiers contribute the rest
        let modifierSum =
            sizeModifier * weights.clusterSize +
            temporalModifier * weights.temporalDensity +
            ageModifier * weights.age +
            homogeneityModifier * weights.visualHomogeneity -
            recencyModifier * weights.recencyPenalty

        let final = baseScore * 0.65 + modifierSum * 0.35
        return min(max(final, 0.0), 1.0)
    }

    /// Signal-specific base scoring — wider spread for near-duplicates based on group size
    private func signalBaseScore(signal: GroupingSignal, count: Int) -> Double {
        switch signal {
        case .burst:
            return 0.85
        case .nearDuplicate:
            // Wide spread so large groups clearly separate from small ones
            if count >= 20 { return 0.90 }
            if count >= 12 { return 0.80 }
            if count >= 8 { return 0.65 }
            if count >= 5 { return 0.50 }
            return 0.35 // Small groups: low priority, "review later"
        case .screenshot:
            if count >= 20 { return 0.80 }
            if count >= 10 { return 0.70 }
            return 0.60
        case .blur:
            return 0.85
        case .trip:
            return 0.30
        case .video:
            return 0.70
        case .screenRecording:
            return 0.85
        case .livePhoto:
            return 0.30
        case .oldPhoto:
            return 0.25
        case .dark:
            return 0.80
        case .document:
            return 0.45
        case .savedImage:
            return 0.50
        case .ai:
            return 0.50
        }
    }

    /// Larger groups get a small bonus
    private func clusterSizeModifier(count: Int) -> Double {
        switch count {
        case 0...2: return 0.1
        case 3...5: return 0.3
        case 6...10: return 0.5
        case 11...20: return 0.7
        case 21...50: return 0.85
        default: return 1.0
        }
    }

    /// Many similar photos taken in a short time = likely burst/spam behavior
    private func temporalDensitySignal(_ assets: [PhotoAsset]) -> Double {
        let dates = assets.compactMap { $0.creationDate }.sorted()
        guard dates.count >= 2 else { return 0.0 }

        let totalSpan = dates.last!.timeIntervalSince(dates.first!)
        guard totalSpan > 0 else { return 1.0 }

        let averageInterval = totalSpan / Double(dates.count - 1)

        if averageInterval < 60 { return 1.0 }
        if averageInterval < 300 { return 0.8 }
        if averageInterval < 3600 { return 0.5 }
        if averageInterval < 86400 { return 0.3 }
        return 0.1
    }

    /// Older photos are slightly more likely to be deletable
    private func ageSignal(_ assets: [PhotoAsset]) -> Double {
        let avgAge = assets.compactMap { $0.creationDate }
            .map { Date().timeIntervalSince($0) / 86400 }
            .reduce(0.0, +) / max(Double(assets.count), 1.0)

        if avgAge > 365 { return 0.8 }
        if avgAge > 180 { return 0.6 }
        if avgAge > 90 { return 0.4 }
        if avgAge > 30 { return 0.2 }
        return 0.1
    }

    /// How visually similar are photos within the cluster
    private func visualHomogeneitySignal(_ assets: [PhotoAsset]) -> Double {
        let embeddings = assets.compactMap { $0.embedding }
        guard embeddings.count >= 2 else { return 0.5 }

        var totalSimilarity: Float = 0
        var pairCount = 0

        for i in 0..<min(embeddings.count, 20) {
            for j in (i + 1)..<min(embeddings.count, 20) {
                totalSimilarity += cosineSimilarity(embeddings[i], embeddings[j])
                pairCount += 1
            }
        }

        guard pairCount > 0 else { return 0.5 }
        return Double(totalSimilarity / Float(pairCount))
    }

    /// Very recent photos get a penalty
    private func recencyPenaltySignal(_ assets: [PhotoAsset]) -> Double {
        let minAge = assets.compactMap { $0.creationDate }
            .map { Date().timeIntervalSince($0) / 86400 }
            .min() ?? 365

        if minAge < 1 { return 1.0 }
        if minAge < 3 { return 0.7 }
        if minAge < 7 { return 0.4 }
        if minAge < 14 { return 0.2 }
        return 0.0
    }

    // MARK: - Helpers

    private func confidenceLevel(from score: Double) -> PhotoCategory.ConfidenceLevel {
        if score >= 0.65 { return .high }
        if score >= 0.40 { return .medium }
        return .low
    }

    private func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dot: Float = 0, normA: Float = 0, normB: Float = 0
        for i in 0..<a.count {
            dot += a[i] * b[i]
            normA += a[i] * a[i]
            normB += b[i] * b[i]
        }
        let denom = sqrt(normA) * sqrt(normB)
        return denom > 0 ? dot / denom : 0
    }
}
