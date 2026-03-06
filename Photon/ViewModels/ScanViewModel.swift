import Foundation
import Photos
import Combine
import SwiftUI
import StoreKit
import os

private let scanLog = Logger(subsystem: "com.lihuangxiao.photon", category: "scan")

/// Manages the entire scan pipeline: fetch → embed → blur detect → group → score
@MainActor
class ScanViewModel: ObservableObject {

    enum ScanState: Equatable {
        case idle
        case requestingPermission
        case permissionDenied
        case preparing
        case fetchingPhotos
        case generatingEmbeddings
        case detectingBlur
        case grouping
        case complete
        case error(String)

        static func == (lhs: ScanState, rhs: ScanState) -> Bool {
            switch (lhs, rhs) {
            case (.idle, .idle), (.requestingPermission, .requestingPermission),
                 (.permissionDenied, .permissionDenied), (.preparing, .preparing),
                 (.fetchingPhotos, .fetchingPhotos),
                 (.generatingEmbeddings, .generatingEmbeddings), (.detectingBlur, .detectingBlur),
                 (.grouping, .grouping), (.complete, .complete):
                return true
            case (.error(let a), .error(let b)):
                return a == b
            default:
                return false
            }
        }
    }

    @Published var state: ScanState = .idle
    @Published var categories: [PhotoCategory] = []

    // Progress tracking
    @Published var fetchProgress: Double = 0.0
    @Published var embeddingProgress: Double = 0.0
    @Published var blurProgress: Double = 0.0
    @Published var totalPhotos: Int = 0
    @Published var photosProcessed: Int = 0
    @Published var blurPhotosProcessed: Int = 0
    @Published var categoriesFound: Int = 0

    // Status message for UI
    @Published var statusMessage: String = "Ready to scan"

    // Debug mode
    #if DEBUG
    @Published var showDebug: Bool = false
    #endif
    var groupingConfig = GroupingConfig()

    // Session tracking
    @Published var sessionStats = SessionStats()
    @Published var categoryStatuses: [UUID: CategoryStatus] = [:]
    @Published var showSessionSummary = false
    @Published var toastMessage: String?

    // Rating prompt — only once per app version
    @AppStorage("lastRatingPromptVersion") private var lastRatingPromptVersion: String = ""

    // Persistence
    private let scanResultStore = ScanResultStore()

    let photoService = PhotoLibraryService()
    let embeddingService = EmbeddingService()
    private let blurService = BlurDetectionService()
    private let groupingPipeline = GroupingPipeline()
    private let scoringService = ScoringService()
    private let deletionService = DeletionService()

    // MARK: - Persistence

    /// Load persisted scan results on launch. Only restores if state is still idle.
    func loadPersistedResults() async {
        guard state == .idle else { return }
        if let saved = await scanResultStore.load() {
            categories = saved.categories
            totalPhotos = saved.totalPhotos
            categoriesFound = categories.count

            let totalDeletable = categories
                .filter { $0.confidence >= .medium }
                .reduce(0) { $0 + $1.photoCount }

            if categories.isEmpty {
                statusMessage = "Your library looks clean!"
            } else {
                statusMessage = "Found \(categories.count) groups (\(totalDeletable) photos to review)"
            }

            state = .complete
        }
    }

    // MARK: - Rescan

    /// Clear persisted data and re-run the full scan pipeline.
    func rescan() {
        Task {
            await scanResultStore.clear()
            resetForScan()
            await startScan()
        }
    }

    private func resetForScan() {
        state = .idle
        categories = []
        fetchProgress = 0
        embeddingProgress = 0
        blurProgress = 0
        totalPhotos = 0
        photosProcessed = 0
        blurPhotosProcessed = 0
        categoriesFound = 0
        statusMessage = "Ready to scan"
        sessionStats = SessionStats()
        categoryStatuses = [:]
    }

    /// Start the full scan pipeline
    func startScan() async {
        scanLog.notice("startScan() called, current state: \(String(describing: self.state))")
        // Step 1: Check existing permission, only prompt if needed
        let currentStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        scanLog.notice("Photo auth status: \(String(describing: currentStatus.rawValue))")
        let status: PHAuthorizationStatus
        if currentStatus == .authorized || currentStatus == .limited {
            status = currentStatus
        } else {
            state = .requestingPermission
            statusMessage = "Requesting photo access..."
            status = await photoService.requestAuthorization()
        }

        guard status == .authorized || status == .limited else {
            scanLog.notice("Permission denied: \(String(describing: status.rawValue))")
            state = .permissionDenied
            statusMessage = "Photo access is required to scan your library"
            return
        }

        scanLog.notice("Permission granted, starting fetch")
        // Step 2: Show immediate feedback, then fetch photos
        state = .preparing
        statusMessage = "Preparing..."
        await Task.yield()  // Let UI render before heavy work

        // Start model loading in the background while we fetch photos
        let embeddingSvc = embeddingService
        let modelLoadTask = Task.detached {
            try await embeddingSvc.loadModel()
        }

        await photoService.fetchAllAssets()
        totalPhotos = photoService.totalPhotoCount
        fetchProgress = 1.0
        scanLog.notice("Fetched \(self.totalPhotos) photos")

        guard totalPhotos > 0 else {
            modelLoadTask.cancel()
            state = .complete
            statusMessage = "No photos found in your library"
            return
        }

        // Step 3: Generate embeddings — wait for model if still loading
        state = .generatingEmbeddings
        statusMessage = "Analyzing photos..."

        do {
            try await modelLoadTask.value
        } catch {
            state = .error("Failed to load AI model: \(error.localizedDescription)")
            return
        }

        let embeddings = await embeddingService.generateEmbeddings(
            for: photoService.allAssets
        ) { [weak self] processed, total in
            Task { @MainActor in
                self?.photosProcessed = processed
                self?.embeddingProgress = Double(processed) / Double(total)
                self?.statusMessage = "Analyzing photos... \(processed)/\(total)"
            }
        }

        // Apply embeddings back to assets
        for i in 0..<photoService.allAssets.count {
            let id = photoService.allAssets[i].id
            if let embedding = embeddings[id] {
                photoService.allAssets[i].embedding = embedding
            }
        }

        let embeddedCount = embeddings.count
        statusMessage = "Analyzed \(embeddedCount)/\(totalPhotos) photos"

        // Step 4: Detect blur scores
        state = .detectingBlur
        statusMessage = "Checking for blurry photos..."

        let analysisResults = await blurService.detectBlur(
            for: photoService.allAssets
        ) { [weak self] processed, total in
            Task { @MainActor in
                self?.blurPhotosProcessed = processed
                self?.blurProgress = Double(processed) / Double(total)
                self?.statusMessage = "Analyzing images... \(processed)/\(total)"
            }
        }

        // Apply blur, brightness, and document scores back to assets
        for i in 0..<photoService.allAssets.count {
            let id = photoService.allAssets[i].id
            if let result = analysisResults[id] {
                photoService.allAssets[i].blurScore = result.blurScore
                photoService.allAssets[i].brightnessScore = result.brightnessScore
                photoService.allAssets[i].isDocument = result.isDocument
            }
        }

        statusMessage = "Image analysis complete"
        scanLog.notice("Blur detection complete, running grouping")

        // Step 5: Run grouping pipeline + scoring
        await runGroupingAndScoring()
    }

    /// Re-run only the grouping + scoring phase with new parameters (no re-embedding needed).
    /// Called from DebugView.
    func rerunGrouping(with config: GroupingConfig) async {
        groupingConfig = config
        await runGroupingAndScoring()
    }

    /// Shared grouping + scoring logic
    private func runGroupingAndScoring() async {
        state = .grouping
        statusMessage = "Finding patterns..."

        let assetsSnapshot = photoService.allAssets
        let currentConfig = groupingConfig

        let scoredCategories = await Task.detached(priority: .userInitiated) {
            let pipeline = GroupingPipeline(config: currentConfig)
            let groups = pipeline.runAllSignals(assets: assetsSnapshot)
            let scorer = ScoringService()
            return scorer.scoreCategories(categories: groups, allAssets: assetsSnapshot)
        }.value

        categories = scoredCategories
        categoriesFound = categories.count
        state = .complete

        let totalDeletable = categories
            .filter { $0.confidence >= .medium }
            .reduce(0) { $0 + $1.photoCount }

        if categories.isEmpty {
            statusMessage = "Your library looks clean!"
        } else {
            statusMessage = "Found \(categories.count) groups (\(totalDeletable) photos to review)"
        }

        scanLog.notice("Grouping complete: \(self.categories.count) categories, saving")
        // Persist results
        try? await scanResultStore.save(totalPhotos: totalPhotos, categories: categories)
    }

    /// Get PhotoAsset objects for a category
    func assets(for category: PhotoCategory) -> [PhotoAsset] {
        let idSet = Set(category.photoIDs)
        return photoService.allAssets.filter { idSet.contains($0.id) }
    }

    // MARK: - Deletion

    /// Delete photos and update session stats. Returns true on success.
    func deletePhotos(identifiers: [String], from category: PhotoCategory) async -> Bool {
        let result = await deletionService.deletePhotos(localIdentifiers: identifiers)

        switch result {
        case .success(let count, let bytes):
            sessionStats.photosDeleted += count
            sessionStats.bytesFreed += bytes
            categoryStatuses[category.id] = .cleaned

            // Remove deleted IDs from all categories
            removeDeletedPhotos(identifiers: identifiers)

            // Count cleaned categories
            sessionStats.categoriesCleaned = categoryStatuses.values.filter { $0 == .cleaned }.count

            // Show toast
            showToast("Deleted \(count) photo\(count == 1 ? "" : "s") — \(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)) freed")

            // Request app rating after first successful deletion (once per version)
            requestRatingIfNeeded()

            return true

        case .cancelled:
            // User denied the iOS dialog — do nothing, selection preserved
            return false

        case .error(let message):
            showToast("Error: \(message)")
            return false
        }
    }

    /// Mark a category as reviewed when the user opens it
    func markReviewed(_ category: PhotoCategory) {
        if categoryStatuses[category.id] == nil {
            categoryStatuses[category.id] = .reviewed
        }
    }

    /// Remove deleted photo IDs from all categories, drop empty ones, recalculate sizes
    private func removeDeletedPhotos(identifiers: [String]) {
        let deletedSet = Set(identifiers)

        // Prune deleted assets from the master array
        photoService.allAssets.removeAll { deletedSet.contains($0.id) }

        categories = categories.compactMap { category in
            let remaining = category.photoIDs.filter { !deletedSet.contains($0) }
            guard !remaining.isEmpty else { return nil }

            // Recalculate size from remaining assets
            let remainingSet = Set(remaining)
            let newSize = photoService.allAssets
                .filter { remainingSet.contains($0.id) }
                .reduce(Int64(0)) { $0 + $1.fileSize }

            return PhotoCategory(
                id: category.id,
                label: category.label,
                photoIDs: remaining,
                confidence: category.confidence,
                score: category.score,
                photoCount: remaining.count,
                estimatedSize: newSize,
                dateRange: category.dateRange,
                dominantType: category.dominantType,
                groupingSignal: category.groupingSignal,
                interactionMode: category.interactionMode,
                cloudReason: category.cloudReason
            )
        }

        categoriesFound = categories.count

        // Keep persisted data in sync
        Task {
            try? await scanResultStore.save(totalPhotos: totalPhotos, categories: categories)
        }
    }

    // MARK: - Toast

    private func showToast(_ message: String) {
        toastMessage = message
        Task {
            try? await Task.sleep(for: .seconds(3))
            if toastMessage == message {
                toastMessage = nil
            }
        }
    }

    // MARK: - Rating Prompt

    private func requestRatingIfNeeded() {
        let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        guard lastRatingPromptVersion != currentVersion else { return }
        lastRatingPromptVersion = currentVersion

        // Small delay so the toast shows first
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            if let scene = UIApplication.shared.connectedScenes
                .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene {
                SKStoreReviewController.requestReview(in: scene)
            }
        }
    }
}
