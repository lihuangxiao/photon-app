import Foundation
import Accelerate
import CoreLocation

/// Tunable parameters for all grouping signals
struct GroupingConfig {
    // Near-duplicate detection
    var nearDuplicateEpsilon: Float = 0.10   // tight — only truly similar photos
    var nearDuplicateMinPoints: Int = 5       // need at least 5 to form a group
    var nearDuplicateMaxGroupSize: Int = 50   // cap — larger groups are DBSCAN chain artifacts

    // Screenshot sub-clustering
    var screenshotEpsilon: Float = 0.25
    var screenshotMinPoints: Int = 3

    // Blur thresholds
    var veryBlurryThreshold: Float = 50
    var somewhatBlurryThreshold: Float = 150

    // Trip detection
    var tripDistanceThresholdKm: Double = 50
    var tripLocationGridKm: Double = 50       // merge photos within this radius into same trip
    var minPhotosWithLocationForTrips: Int = 10
    var minPhotosPerTrip: Int = 5

    // Video detection
    var largeVideoThresholdMB: Int = 100

    // Live photo detection
    var livePhotoMinCount: Int = 10

    // Old photo detection
    var oldPhotoAgeDays: Int = 730 // 2 years

    // Dark photo detection
    var darkBrightnessThreshold: Float = 40
    var veryDarkBrightnessThreshold: Float = 25

    // Document detection
    var documentConfidenceThreshold: Float = 0.8

    // Saved image detection
    var savedImageMaxFileSize: Int64 = 500_000 // 500KB

    // Collapse UX
    var maxVisiblePerSignal: Int = 3

    // Global
    var minGroupSize: Int = 3
}

/// Multi-signal grouping pipeline. Replaces the single-DBSCAN ClusteringService.
/// Near-duplicate groups are exclusive — photos in them don't appear in other groups.
class GroupingPipeline {

    private var config: GroupingConfig

    init(config: GroupingConfig = GroupingConfig()) {
        self.config = config
    }

    func updateConfig(_ config: GroupingConfig) {
        self.config = config
    }

    /// Run all grouping signals and return unified list of groups.
    /// Near-duplicate groups are exclusive — photos claimed by them are excluded from other signals.
    func runAllSignals(assets: [PhotoAsset]) -> [PhotoCategory] {
        // Run near-duplicates first — they claim photos exclusively
        let nearDupeGroups = detectNearDuplicates(assets: assets)
        var claimedIDs = Set<String>()
        for group in nearDupeGroups {
            claimedIDs.formUnion(group.photoIDs)
        }

        // Run other signals, excluding photos already claimed by near-duplicates
        let burstGroups = detectBursts(assets: assets, excludeIDs: claimedIDs)
        let screenshotGroups = detectScreenshotClusters(assets: assets, excludeIDs: claimedIDs)
        let blurGroups = detectBlurGroups(assets: assets, excludeIDs: claimedIDs)
        let tripGroups = detectTrips(assets: assets, excludeIDs: claimedIDs)
        let videoGroups = detectVideos(assets: assets, excludeIDs: claimedIDs)
        let screenRecordingGroups = detectScreenRecordings(assets: assets, excludeIDs: claimedIDs)
        let livePhotoGroups = detectLivePhotos(assets: assets, excludeIDs: claimedIDs)
        let oldPhotoGroups = detectOldPhotos(assets: assets, excludeIDs: claimedIDs)
        let darkGroups = detectDarkPhotos(assets: assets, excludeIDs: claimedIDs)
        let documentGroups = detectDocuments(assets: assets, excludeIDs: claimedIDs)
        let savedImageGroups = detectSavedImages(assets: assets, excludeIDs: claimedIDs)

        var allGroups: [PhotoCategory] = []
        allGroups.append(contentsOf: burstGroups)
        allGroups.append(contentsOf: nearDupeGroups)
        allGroups.append(contentsOf: screenshotGroups)
        allGroups.append(contentsOf: blurGroups)
        allGroups.append(contentsOf: tripGroups)
        allGroups.append(contentsOf: videoGroups)
        allGroups.append(contentsOf: screenRecordingGroups)
        allGroups.append(contentsOf: livePhotoGroups)
        allGroups.append(contentsOf: oldPhotoGroups)
        allGroups.append(contentsOf: darkGroups)
        allGroups.append(contentsOf: documentGroups)
        allGroups.append(contentsOf: savedImageGroups)

        // Filter out groups smaller than the minimum
        let minSize = config.minGroupSize
        let beforeFilter = allGroups.count
        allGroups = allGroups.filter { $0.photoCount >= minSize }

        print("[Photon] Grouping complete: \(allGroups.count) groups (filtered \(beforeFilter - allGroups.count) small) " +
              "— bursts: \(burstGroups.count), near-dupes: \(nearDupeGroups.count), " +
              "screenshots: \(screenshotGroups.count), blur: \(blurGroups.count), " +
              "trips: \(tripGroups.count), videos: \(videoGroups.count), " +
              "screen-rec: \(screenRecordingGroups.count), live: \(livePhotoGroups.count), " +
              "old: \(oldPhotoGroups.count), dark: \(darkGroups.count), " +
              "docs: \(documentGroups.count), saved: \(savedImageGroups.count), " +
              "near-dupe claimed \(claimedIDs.count) photos exclusively")

        return allGroups
    }

    // MARK: - Signal 1: Near-Duplicate Detection

    private func detectNearDuplicates(assets: [PhotoAsset]) -> [PhotoCategory] {
        let candidates = assets.enumerated().filter { _, asset in
            !asset.isScreenshot && asset.embedding != nil && asset.mediaType == .image
        }

        guard candidates.count >= config.nearDuplicateMinPoints else { return [] }

        let indices = candidates.map { $0.offset }
        let vectors = candidates.map { $0.element.embedding! }
        let normalized = normalizeVectors(vectors)

        let clusters = dbscan(
            vectors: normalized,
            epsilon: config.nearDuplicateEpsilon,
            minPoints: config.nearDuplicateMinPoints
        )

        let maxSize = config.nearDuplicateMaxGroupSize
        return clusters.compactMap { clusterLocalIndices in
            let assetIndices = clusterLocalIndices.map { indices[$0] }
            let groupAssets = assetIndices.map { assets[$0] }
            guard groupAssets.count >= config.nearDuplicateMinPoints else { return nil }

            if groupAssets.count > maxSize {
                print("[Photon] Dropping near-duplicate mega-cluster of \(groupAssets.count) photos")
                return nil
            }

            let dateRange = computeDateRange(groupAssets)
            let totalSize = groupAssets.reduce(Int64(0)) { $0 + $1.fileSize }

            return PhotoCategory(
                id: UUID(),
                label: "\(groupAssets.count) near-duplicate photos",
                photoIDs: groupAssets.map { $0.id },
                confidence: .high,
                score: 0.0,
                photoCount: groupAssets.count,
                estimatedSize: totalSize,
                dateRange: dateRange,
                dominantType: .similarPhotos,
                groupingSignal: .nearDuplicate,
                interactionMode: .keepBest
            )
        }
    }

    // MARK: - Signal 2: Screenshot Sub-Clustering

    private func detectScreenshotClusters(assets: [PhotoAsset], excludeIDs: Set<String>) -> [PhotoCategory] {
        let candidates = assets.enumerated().filter { _, asset in
            asset.isScreenshot && asset.embedding != nil && !excludeIDs.contains(asset.id)
        }

        guard candidates.count >= config.screenshotMinPoints else { return [] }

        let indices = candidates.map { $0.offset }
        let vectors = candidates.map { $0.element.embedding! }
        let normalized = normalizeVectors(vectors)

        let clusters = dbscan(
            vectors: normalized,
            epsilon: config.screenshotEpsilon,
            minPoints: config.screenshotMinPoints
        )

        return clusters.compactMap { clusterLocalIndices in
            let assetIndices = clusterLocalIndices.map { indices[$0] }
            let groupAssets = assetIndices.map { assets[$0] }
            guard groupAssets.count >= config.screenshotMinPoints else { return nil }

            let dateRange = computeDateRange(groupAssets)
            let totalSize = groupAssets.reduce(Int64(0)) { $0 + $1.fileSize }

            return PhotoCategory(
                id: UUID(),
                label: "\(groupAssets.count) similar screenshots",
                photoIDs: groupAssets.map { $0.id },
                confidence: .high,
                score: 0.0,
                photoCount: groupAssets.count,
                estimatedSize: totalSize,
                dateRange: dateRange,
                dominantType: .screenshots,
                groupingSignal: .screenshot,
                interactionMode: .deleteAll
            )
        }
    }

    // MARK: - Signal 3: Burst Grouping

    private func detectBursts(assets: [PhotoAsset], excludeIDs: Set<String>) -> [PhotoCategory] {
        var burstGroups: [String: [PhotoAsset]] = [:]

        for asset in assets where asset.isBurst && !excludeIDs.contains(asset.id) {
            if let burstID = asset.burstIdentifier {
                burstGroups[burstID, default: []].append(asset)
            }
        }

        return burstGroups.values.compactMap { groupAssets in
            guard groupAssets.count >= 2 else { return nil }

            let dateRange = computeDateRange(groupAssets)
            let totalSize = groupAssets.reduce(Int64(0)) { $0 + $1.fileSize }

            return PhotoCategory(
                id: UUID(),
                label: "\(groupAssets.count) burst photos",
                photoIDs: groupAssets.map { $0.id },
                confidence: .high,
                score: 0.0,
                photoCount: groupAssets.count,
                estimatedSize: totalSize,
                dateRange: dateRange,
                dominantType: .burstPhotos,
                groupingSignal: .burst,
                interactionMode: .keepBest
            )
        }
    }

    // MARK: - Signal 4: Location-Based Trip Detection
    //
    // Strategy: time-first, then location.
    // 1. Find "home" (most frequent location grid cell)
    // 2. Find "away" photos (far from home)
    // 3. Sort by time → split into time segments (gap > 48 hours = different trip)
    // 4. Within each time segment, merge nearby locations
    // This prevents "Tokyo 2023" and "Tokyo 2025" from merging.

    private func detectTrips(assets: [PhotoAsset], excludeIDs: Set<String>) -> [PhotoCategory] {
        let located = assets.filter {
            $0.location != nil && !$0.isScreenshot && $0.mediaType == .image && !excludeIDs.contains($0.id)
        }
        guard located.count >= config.minPhotosWithLocationForTrips else { return [] }

        // Step 1: Determine "home" using grid-based mode (~1km grid)
        let homeGridRes = 0.01
        var gridCounts: [String: (count: Int, lat: Double, lng: Double)] = [:]

        for asset in located {
            guard let loc = asset.location else { continue }
            let gridLat = (loc.coordinate.latitude / homeGridRes).rounded() * homeGridRes
            let gridLng = (loc.coordinate.longitude / homeGridRes).rounded() * homeGridRes
            let key = "\(gridLat),\(gridLng)"
            if let existing = gridCounts[key] {
                gridCounts[key] = (existing.count + 1, gridLat, gridLng)
            } else {
                gridCounts[key] = (1, gridLat, gridLng)
            }
        }

        guard let homeGrid = gridCounts.values.max(by: { $0.count < $1.count }) else { return [] }
        let homeLocation = CLLocation(latitude: homeGrid.lat, longitude: homeGrid.lng)
        let thresholdMeters = config.tripDistanceThresholdKm * 1000

        // Step 2: Find "away" photos
        let awayPhotos = located.filter { asset in
            guard let loc = asset.location else { return false }
            return loc.distance(from: homeLocation) > thresholdMeters
        }

        guard awayPhotos.count >= config.minPhotosPerTrip else { return [] }

        // Step 3: Sort by time → split into time segments.
        // A gap of >48 hours between consecutive away photos = different trip.
        let sorted = awayPhotos.sorted { ($0.creationDate ?? .distantPast) < ($1.creationDate ?? .distantPast) }
        let tripTimeGapSeconds: Double = 48 * 3600 // 48 hours

        var timeSegments: [[PhotoAsset]] = []
        var currentSegment: [PhotoAsset] = [sorted[0]]

        for i in 1..<sorted.count {
            let prevDate = sorted[i - 1].creationDate ?? .distantPast
            let currDate = sorted[i].creationDate ?? .distantPast
            let gap = currDate.timeIntervalSince(prevDate)

            if gap > tripTimeGapSeconds {
                timeSegments.append(currentSegment)
                currentSegment = [sorted[i]]
            } else {
                currentSegment.append(sorted[i])
            }
        }
        timeSegments.append(currentSegment)

        // Step 4: Within each time segment, merge photos that are geographically close.
        // Photos within tripLocationGridKm of each other in the same time window = same trip.
        var trips: [[PhotoAsset]] = []
        let mergeRadiusMeters = config.tripLocationGridKm * 1000

        for segment in timeSegments {
            // Simple greedy merge: start with first photo, add any photo within radius
            var remaining = segment
            while !remaining.isEmpty {
                var trip = [remaining.removeFirst()]

                // Expand: keep adding photos close to any photo already in the trip
                var changed = true
                while changed {
                    changed = false
                    var nextRemaining: [PhotoAsset] = []
                    for candidate in remaining {
                        let candidateLoc = candidate.location!
                        let isClose = trip.contains { tripAsset in
                            tripAsset.location!.distance(from: candidateLoc) < mergeRadiusMeters
                        }
                        if isClose {
                            trip.append(candidate)
                            changed = true
                        } else {
                            nextRemaining.append(candidate)
                        }
                    }
                    remaining = nextRemaining
                }

                if trip.count >= config.minPhotosPerTrip {
                    trips.append(trip)
                }
            }
        }

        return trips.map { tripAssets in
            let dateRange = computeDateRange(tripAssets)
            let totalSize = tripAssets.reduce(Int64(0)) { $0 + $1.fileSize }

            var label = "\(tripAssets.count) trip photos"
            if let range = dateRange {
                let formatter = DateFormatter()
                formatter.dateFormat = "MMM d"
                let start = formatter.string(from: range.lowerBound)
                let end = formatter.string(from: range.upperBound)
                if start == end {
                    label = "\(tripAssets.count) trip photos — \(start)"
                } else {
                    label = "\(tripAssets.count) trip photos — \(start)–\(end)"
                }
            }

            return PhotoCategory(
                id: UUID(),
                label: label,
                photoIDs: tripAssets.map { $0.id },
                confidence: .low,
                score: 0.0,
                photoCount: tripAssets.count,
                estimatedSize: totalSize,
                dateRange: dateRange,
                dominantType: .tripPhotos,
                groupingSignal: .trip,
                interactionMode: .deleteAll
            )
        }
    }

    // MARK: - Signal 5: Blur Grouping

    private func detectBlurGroups(assets: [PhotoAsset], excludeIDs: Set<String>) -> [PhotoCategory] {
        let withScores = assets.filter { $0.blurScore != nil && !excludeIDs.contains($0.id) }
        guard !withScores.isEmpty else { return [] }

        var groups: [PhotoCategory] = []

        let veryBlurry = withScores.filter { $0.blurScore! < config.veryBlurryThreshold }
        if veryBlurry.count >= 2 {
            let dateRange = computeDateRange(veryBlurry)
            let totalSize = veryBlurry.reduce(Int64(0)) { $0 + $1.fileSize }
            groups.append(PhotoCategory(
                id: UUID(),
                label: "\(veryBlurry.count) blurry photos",
                photoIDs: veryBlurry.map { $0.id },
                confidence: .high,
                score: 0.0,
                photoCount: veryBlurry.count,
                estimatedSize: totalSize,
                dateRange: dateRange,
                dominantType: .blurryPhotos,
                groupingSignal: .blur,
                interactionMode: .deleteAll
            ))
        }

        let slightlyBlurry = withScores.filter {
            $0.blurScore! >= config.veryBlurryThreshold && $0.blurScore! < config.somewhatBlurryThreshold
        }
        if slightlyBlurry.count >= 3 {
            let dateRange = computeDateRange(slightlyBlurry)
            let totalSize = slightlyBlurry.reduce(Int64(0)) { $0 + $1.fileSize }
            groups.append(PhotoCategory(
                id: UUID(),
                label: "\(slightlyBlurry.count) slightly blurry photos",
                photoIDs: slightlyBlurry.map { $0.id },
                confidence: .medium,
                score: 0.0,
                photoCount: slightlyBlurry.count,
                estimatedSize: totalSize,
                dateRange: dateRange,
                dominantType: .blurryPhotos,
                groupingSignal: .blur,
                interactionMode: .deleteAll
            ))
        }

        return groups
    }

    // MARK: - Signal 6: Video Detection

    private func detectVideos(assets: [PhotoAsset], excludeIDs: Set<String>) -> [PhotoCategory] {
        let videos = assets.filter { $0.isVideo && !excludeIDs.contains($0.id) }
        guard !videos.isEmpty else { return [] }

        let thresholdBytes = Int64(config.largeVideoThresholdMB) * 1_000_000
        var groups: [PhotoCategory] = []

        let largeVideos = videos.filter { $0.fileSize > thresholdBytes }
            .sorted { $0.fileSize > $1.fileSize }
        if largeVideos.count >= 1 {
            let dateRange = computeDateRange(largeVideos)
            let totalSize = largeVideos.reduce(Int64(0)) { $0 + $1.fileSize }
            let sizeStr = ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file)
            groups.append(PhotoCategory(
                id: UUID(),
                label: "\(largeVideos.count) large videos (\(sizeStr))",
                photoIDs: largeVideos.map { $0.id },
                confidence: .high,
                score: 0.0,
                photoCount: largeVideos.count,
                estimatedSize: totalSize,
                dateRange: dateRange,
                dominantType: .videos,
                groupingSignal: .video,
                interactionMode: .deleteAll
            ))
        }

        let smallVideos = videos.filter { $0.fileSize <= thresholdBytes }
            .sorted { $0.fileSize > $1.fileSize }
        if smallVideos.count >= 3 {
            let dateRange = computeDateRange(smallVideos)
            let totalSize = smallVideos.reduce(Int64(0)) { $0 + $1.fileSize }
            groups.append(PhotoCategory(
                id: UUID(),
                label: "\(smallVideos.count) other videos",
                photoIDs: smallVideos.map { $0.id },
                confidence: .low,
                score: 0.0,
                photoCount: smallVideos.count,
                estimatedSize: totalSize,
                dateRange: dateRange,
                dominantType: .videos,
                groupingSignal: .video,
                interactionMode: .deleteAll
            ))
        }

        return groups
    }

    // MARK: - Signal 7: Screen Recording Detection

    private func detectScreenRecordings(assets: [PhotoAsset], excludeIDs: Set<String>) -> [PhotoCategory] {
        let recordings = assets.filter { asset in
            !excludeIDs.contains(asset.id) &&
            asset.isVideo &&
            (asset.originalFilename?.hasPrefix("RPReplay_") ?? false)
        }
        guard !recordings.isEmpty else { return [] }

        let sorted = recordings.sorted { $0.fileSize > $1.fileSize }
        let dateRange = computeDateRange(sorted)
        let totalSize = sorted.reduce(Int64(0)) { $0 + $1.fileSize }
        let sizeStr = ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file)

        return [PhotoCategory(
            id: UUID(),
            label: "\(sorted.count) screen recordings (\(sizeStr))",
            photoIDs: sorted.map { $0.id },
            confidence: .high,
            score: 0.0,
            photoCount: sorted.count,
            estimatedSize: totalSize,
            dateRange: dateRange,
            dominantType: .screenRecordings,
            groupingSignal: .screenRecording,
            interactionMode: .deleteAll
        )]
    }

    // MARK: - Signal 8: Live Photo Detection

    private func detectLivePhotos(assets: [PhotoAsset], excludeIDs: Set<String>) -> [PhotoCategory] {
        let livePhotos = assets.filter { $0.isLivePhoto && !excludeIDs.contains($0.id) }
        guard livePhotos.count >= config.livePhotoMinCount else { return [] }

        let dateRange = computeDateRange(livePhotos)
        let totalSize = livePhotos.reduce(Int64(0)) { $0 + $1.fileSize }

        return [PhotoCategory(
            id: UUID(),
            label: "\(livePhotos.count) live photos (convert to still to save space)",
            photoIDs: livePhotos.map { $0.id },
            confidence: .low,
            score: 0.0,
            photoCount: livePhotos.count,
            estimatedSize: totalSize,
            dateRange: dateRange,
            dominantType: .livePhotos,
            groupingSignal: .livePhoto,
            interactionMode: .deleteAll
        )]
    }

    // MARK: - Signal 9: Old Unfavorited Photo Detection

    private func detectOldPhotos(assets: [PhotoAsset], excludeIDs: Set<String>) -> [PhotoCategory] {
        let threshold = config.oldPhotoAgeDays
        let old = assets.filter {
            !excludeIDs.contains($0.id) &&
            $0.ageDays > threshold &&
            !$0.isFavorite &&
            $0.mediaType == .image
        }
        guard !old.isEmpty else { return [] }

        // Group by year
        let calendar = Calendar.current
        var byYear: [Int: [PhotoAsset]] = [:]
        for asset in old {
            guard let date = asset.creationDate else { continue }
            let year = calendar.component(.year, from: date)
            byYear[year, default: []].append(asset)
        }

        return byYear.compactMap { year, yearAssets in
            guard yearAssets.count >= 5 else { return nil }
            let dateRange = computeDateRange(yearAssets)
            let totalSize = yearAssets.reduce(Int64(0)) { $0 + $1.fileSize }

            return PhotoCategory(
                id: UUID(),
                label: "\(yearAssets.count) photos from \(year) (not favorited)",
                photoIDs: yearAssets.map { $0.id },
                confidence: .low,
                score: 0.0,
                photoCount: yearAssets.count,
                estimatedSize: totalSize,
                dateRange: dateRange,
                dominantType: .oldPhotos,
                groupingSignal: .oldPhoto,
                interactionMode: .deleteAll
            )
        }
    }

    // MARK: - Signal 10: Dark/Underexposed Photo Detection

    private func detectDarkPhotos(assets: [PhotoAsset], excludeIDs: Set<String>) -> [PhotoCategory] {
        let withBrightness = assets.filter { $0.brightnessScore != nil && !excludeIDs.contains($0.id) }
        guard !withBrightness.isEmpty else { return [] }

        var groups: [PhotoCategory] = []

        let veryDark = withBrightness.filter { $0.brightnessScore! < config.veryDarkBrightnessThreshold }
        if veryDark.count >= 2 {
            let dateRange = computeDateRange(veryDark)
            let totalSize = veryDark.reduce(Int64(0)) { $0 + $1.fileSize }
            groups.append(PhotoCategory(
                id: UUID(),
                label: "\(veryDark.count) very dark photos",
                photoIDs: veryDark.map { $0.id },
                confidence: .high,
                score: 0.0,
                photoCount: veryDark.count,
                estimatedSize: totalSize,
                dateRange: dateRange,
                dominantType: .darkPhotos,
                groupingSignal: .dark,
                interactionMode: .deleteAll
            ))
        }

        let somewhatDark = withBrightness.filter {
            $0.brightnessScore! >= config.veryDarkBrightnessThreshold &&
            $0.brightnessScore! < config.darkBrightnessThreshold
        }
        if somewhatDark.count >= 3 {
            let dateRange = computeDateRange(somewhatDark)
            let totalSize = somewhatDark.reduce(Int64(0)) { $0 + $1.fileSize }
            groups.append(PhotoCategory(
                id: UUID(),
                label: "\(somewhatDark.count) dark photos",
                photoIDs: somewhatDark.map { $0.id },
                confidence: .medium,
                score: 0.0,
                photoCount: somewhatDark.count,
                estimatedSize: totalSize,
                dateRange: dateRange,
                dominantType: .darkPhotos,
                groupingSignal: .dark,
                interactionMode: .deleteAll
            ))
        }

        return groups
    }

    // MARK: - Signal 11: Document Photo Detection

    private func detectDocuments(assets: [PhotoAsset], excludeIDs: Set<String>) -> [PhotoCategory] {
        let docs = assets.filter {
            ($0.isDocument ?? false) && !excludeIDs.contains($0.id)
        }
        guard docs.count >= 3 else { return [] }

        let dateRange = computeDateRange(docs)
        let totalSize = docs.reduce(Int64(0)) { $0 + $1.fileSize }

        return [PhotoCategory(
            id: UUID(),
            label: "\(docs.count) document photos (receipts, notes, whiteboards)",
            photoIDs: docs.map { $0.id },
            confidence: .medium,
            score: 0.0,
            photoCount: docs.count,
            estimatedSize: totalSize,
            dateRange: dateRange,
            dominantType: .documentPhotos,
            groupingSignal: .document,
            interactionMode: .deleteAll
        )]
    }

    // MARK: - Signal 12: Saved/Received Image Detection

    private func detectSavedImages(assets: [PhotoAsset], excludeIDs: Set<String>) -> [PhotoCategory] {
        // Common camera resolutions to exclude (width × height)
        let cameraResolutions: Set<String> = [
            "4032x3024", "3024x4032", // iPhone 12MP
            "4000x3000", "3000x4000",
            "3264x2448", "2448x3264",
            "4608x3456", "3456x4608",
            "4284x5712", "5712x4284", // iPhone 48MP binned
        ]

        let candidates = assets.filter { asset in
            guard !excludeIDs.contains(asset.id),
                  asset.mediaType == .image,
                  !asset.isScreenshot,
                  asset.burstIdentifier == nil else { return false }

            var signals = 0

            // No location data
            if asset.location == nil { signals += 1 }

            // Small file size
            if asset.fileSize < config.savedImageMaxFileSize { signals += 1 }

            // Non-standard dimensions
            let dimKey = "\(asset.pixelWidth)x\(asset.pixelHeight)"
            if !cameraResolutions.contains(dimKey) { signals += 1 }

            // No EXIF-style creation pattern (very old or no date)
            if asset.creationDate == nil { signals += 1 }

            // Small dimensions (typical for shared/saved images)
            if asset.pixelWidth < 2000 && asset.pixelHeight < 2000 { signals += 1 }

            return signals >= 3
        }

        guard candidates.count >= 5 else { return [] }

        let dateRange = computeDateRange(candidates)
        let totalSize = candidates.reduce(Int64(0)) { $0 + $1.fileSize }

        return [PhotoCategory(
            id: UUID(),
            label: "\(candidates.count) likely saved/received images",
            photoIDs: candidates.map { $0.id },
            confidence: .medium,
            score: 0.0,
            photoCount: candidates.count,
            estimatedSize: totalSize,
            dateRange: dateRange,
            dominantType: .savedImages,
            groupingSignal: .savedImage,
            interactionMode: .deleteAll
        )]
    }

    // MARK: - DBSCAN

    private func dbscan(vectors: [[Float]], epsilon: Float, minPoints: Int) -> [[Int]] {
        let n = vectors.count
        guard n > 0 else { return [] }

        let dim = vectors[0].count
        var flat = [Float](repeating: 0, count: n * dim)
        for i in 0..<n {
            flat.replaceSubrange(i * dim..<(i + 1) * dim, with: vectors[i])
        }

        var labels = Array(repeating: -1, count: n)
        var clusterID = 0

        for i in 0..<n {
            guard labels[i] == -1 else { continue }

            let neighbors = regionQuery(index: i, flat: flat, n: n, dim: dim, epsilon: epsilon)
            if neighbors.count < minPoints {
                labels[i] = -2
                continue
            }

            labels[i] = clusterID
            var seedSet = Set(neighbors)
            seedSet.remove(i)
            var queue = Array(seedSet)
            var queueIndex = 0

            while queueIndex < queue.count {
                let j = queue[queueIndex]
                queueIndex += 1

                if labels[j] == -2 { labels[j] = clusterID }
                guard labels[j] == -1 else { continue }
                labels[j] = clusterID

                let jNeighbors = regionQuery(index: j, flat: flat, n: n, dim: dim, epsilon: epsilon)
                if jNeighbors.count >= minPoints {
                    for neighbor in jNeighbors {
                        if (labels[neighbor] == -1 || labels[neighbor] == -2) && !seedSet.contains(neighbor) {
                            seedSet.insert(neighbor)
                            queue.append(neighbor)
                        }
                    }
                }
            }

            clusterID += 1
        }

        var clusters: [Int: [Int]] = [:]
        for (i, label) in labels.enumerated() {
            guard label >= 0 else { continue }
            clusters[label, default: []].append(i)
        }
        return Array(clusters.values).sorted { $0.count > $1.count }
    }

    private func regionQuery(index: Int, flat: [Float], n: Int, dim: Int, epsilon: Float) -> [Int] {
        let threshold = 1.0 - epsilon
        var neighbors: [Int] = []
        neighbors.reserveCapacity(32)

        let queryStart = index * dim
        let query = Array(flat[queryStart..<queryStart + dim])

        query.withUnsafeBufferPointer { queryPtr in
            for j in 0..<n {
                let jStart = j * dim
                flat.withUnsafeBufferPointer { flatPtr in
                    var result: Float = 0
                    vDSP_dotpr(queryPtr.baseAddress!, 1,
                              flatPtr.baseAddress! + jStart, 1,
                              &result,
                              vDSP_Length(dim))
                    if result >= threshold {
                        neighbors.append(j)
                    }
                }
            }
        }

        return neighbors
    }

    // MARK: - Helpers

    private func normalizeVectors(_ vectors: [[Float]]) -> [[Float]] {
        vectors.map { v in
            var norm: Float = 0
            vDSP_svesq(v, 1, &norm, vDSP_Length(v.count))
            norm = sqrt(norm)
            guard norm > 0 else { return v }
            var result = [Float](repeating: 0, count: v.count)
            var divisor = norm
            vDSP_vsdiv(v, 1, &divisor, &result, 1, vDSP_Length(v.count))
            return result
        }
    }

    private func computeDateRange(_ assets: [PhotoAsset]) -> ClosedRange<Date>? {
        let dates = assets.compactMap { $0.creationDate }.sorted()
        guard let first = dates.first, let last = dates.last else { return nil }
        return first...last
    }
}
