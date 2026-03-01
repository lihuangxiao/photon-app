import Foundation
import Photos

actor ScanResultStore {

    private var fileURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("scan_result.json")
    }

    // MARK: - Save

    func save(totalPhotos: Int, categories: [PhotoCategory]) throws {
        let persisted = categories.map { cat in
            PersistedCategory(
                id: cat.id,
                label: cat.label,
                photoIDs: cat.photoIDs,
                confidence: cat.confidence.rawValue,
                score: cat.score,
                photoCount: cat.photoCount,
                estimatedSize: cat.estimatedSize,
                dateRangeStart: cat.dateRange?.lowerBound,
                dateRangeEnd: cat.dateRange?.upperBound,
                dominantType: cat.dominantType.rawValue,
                groupingSignal: cat.groupingSignal.rawValue,
                interactionMode: cat.interactionMode.rawValue,
                cloudReason: cat.cloudReason
            )
        }

        let result = PersistedScanResult(
            scanDate: Date(),
            totalPhotosScanned: totalPhotos,
            categories: persisted
        )

        let data = try JSONEncoder().encode(result)
        try data.write(to: fileURL, options: .atomic)
    }

    // MARK: - Load

    func load() -> (totalPhotos: Int, categories: [PhotoCategory])? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        guard let result = try? JSONDecoder().decode(PersistedScanResult.self, from: data) else { return nil }
        guard !result.categories.isEmpty else { return nil }

        // Collect all photo IDs to validate against PhotoKit in one batch
        let allIDs = result.categories.flatMap { $0.photoIDs }
        let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: allIDs, options: nil)
        var validIDs = Set<String>()
        fetchResult.enumerateObjects { asset, _, _ in
            validIDs.insert(asset.localIdentifier)
        }

        // Rebuild categories, pruning stale IDs
        let categories: [PhotoCategory] = result.categories.compactMap { pc in
            let remaining = pc.photoIDs.filter { validIDs.contains($0) }
            guard !remaining.isEmpty else { return nil }

            let ratio = Double(remaining.count) / Double(pc.photoIDs.count)
            let adjustedSize = Int64(Double(pc.estimatedSize) * ratio)

            guard let confidence = PhotoCategory.ConfidenceLevel(rawValue: pc.confidence),
                  let dominantType = PhotoCategory.DominantType(rawValue: pc.dominantType),
                  let groupingSignal = GroupingSignal(rawValue: pc.groupingSignal),
                  let interactionMode = InteractionMode(rawValue: pc.interactionMode) else {
                return nil
            }

            var dateRange: ClosedRange<Date>?
            if let start = pc.dateRangeStart, let end = pc.dateRangeEnd {
                dateRange = start...end
            }

            return PhotoCategory(
                id: pc.id,
                label: pc.label,
                photoIDs: remaining,
                confidence: confidence,
                score: pc.score,
                photoCount: remaining.count,
                estimatedSize: adjustedSize,
                dateRange: dateRange,
                dominantType: dominantType,
                groupingSignal: groupingSignal,
                interactionMode: interactionMode,
                cloudReason: pc.cloudReason
            )
        }

        guard !categories.isEmpty else { return nil }
        return (result.totalPhotosScanned, categories)
    }

    // MARK: - Clear

    func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}
