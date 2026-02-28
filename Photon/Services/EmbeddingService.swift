import Foundation
import CoreML
import CoreImage
import Vision
import UIKit
import Photos

/// Generates image embeddings for photo similarity analysis.
///
/// Primary backend: MobileCLIP S2 (Core ML) — 512-dim embeddings, ~3.6ms/image on Neural Engine
/// Fallback: Apple Vision FeaturePrint — built-in feature extraction, works on all devices
class EmbeddingService: ObservableObject {

    enum Backend: String {
        case mobileCLIP = "MobileCLIP S2"
        case visionFeaturePrint = "Vision FeaturePrint"
    }

    @MainActor @Published var isProcessing: Bool = false
    @MainActor @Published var progress: Double = 0.0
    @MainActor @Published var processedCount: Int = 0
    @MainActor @Published var totalCount: Int = 0

    private var imageEncoder: mobileclip_s2_image?
    private var backend: Backend = .visionFeaturePrint

    /// Load the embedding model. Tries MobileCLIP first, falls back to Vision FeaturePrint.
    func loadModel() async throws {
        do {
            let config = MLModelConfiguration()
            config.computeUnits = .all
            imageEncoder = try await mobileclip_s2_image.load(configuration: config)
            backend = .mobileCLIP
            print("[Photon] Loaded MobileCLIP S2")
        } catch {
            print("[Photon] MobileCLIP failed: \(error.localizedDescription). Using Vision FeaturePrint.")
            backend = .visionFeaturePrint
        }
    }

    /// Generate embeddings for all photos, returning a map of asset ID -> embedding.
    /// Work is dispatched to GCD to avoid cooperative thread pool issues.
    @MainActor
    func generateEmbeddings(
        for assets: [PhotoAsset],
        onProgress: @escaping (Int, Int) -> Void
    ) async -> [String: [Float]] {
        let total = assets.count
        isProcessing = true
        totalCount = total
        processedCount = 0
        progress = 0.0

        // Offload all heavy work to a GCD background queue, reporting progress back
        let results: [String: [Float]] = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async { [self] in
                var results: [String: [Float]] = [:]
                results.reserveCapacity(total)
                let reportInterval = max(total / 100, 1)

                for (index, asset) in assets.enumerated() {
                    // Skip videos — only process images
                    guard asset.phAsset.mediaType == .image else { continue }

                    if let embedding = self.processOnePhoto(asset.phAsset) {
                        results[asset.id] = embedding
                    }

                    if (index + 1) % reportInterval == 0 || index == total - 1 {
                        let idx = index + 1
                        DispatchQueue.main.async {
                            onProgress(idx, total)
                        }
                    }
                }

                continuation.resume(returning: results)
            }
        }

        processedCount = total
        progress = 1.0
        isProcessing = false
        print("[Photon] Done: \(results.count)/\(total) embeddings via \(backend.rawValue)")
        return results
    }

    // MARK: - Synchronous per-photo processing (runs on GCD thread)

    /// Process one photo entirely on the current (GCD) thread with a hard timeout.
    /// Returns nil if the photo can't be processed or times out.
    private func processOnePhoto(_ phAsset: PHAsset) -> [Float]? {
        let semaphore = DispatchSemaphore(value: 0)
        var result: [Float]? = nil

        DispatchQueue.global(qos: .userInitiated).async { [self] in
            if let image = self.fetchImageSync(for: phAsset),
               let cgImage = image.cgImage {
                result = self.computeEmbeddingSync(from: cgImage)
            }
            semaphore.signal()
        }

        // Wait up to 3 seconds, then give up
        let timeout = semaphore.wait(timeout: .now() + 3)
        if timeout == .timedOut {
            return nil
        }
        return result
    }

    /// Synchronous image fetch. Blocks the calling thread until done.
    private func fetchImageSync(for phAsset: PHAsset) -> UIImage? {
        var fetchedImage: UIImage? = nil

        let options = PHImageRequestOptions()
        options.deliveryMode = .fastFormat
        options.isNetworkAccessAllowed = false
        options.isSynchronous = true
        options.resizeMode = .fast

        PHCachingImageManager.default().requestImage(
            for: phAsset,
            targetSize: CGSize(width: 256, height: 256),
            contentMode: .aspectFill,
            options: options
        ) { image, _ in
            fetchedImage = image
        }

        return fetchedImage
    }

    /// Synchronous embedding computation.
    private func computeEmbeddingSync(from cgImage: CGImage) -> [Float]? {
        switch backend {
        case .mobileCLIP:
            return computeMobileCLIPEmbedding(from: cgImage)
        case .visionFeaturePrint:
            return computeVisionFeaturePrint(from: cgImage)
        }
    }

    // MARK: - MobileCLIP Backend

    private func computeMobileCLIPEmbedding(from cgImage: CGImage) -> [Float]? {
        guard let encoder = imageEncoder else { return nil }

        do {
            let input = try mobileclip_s2_imageInput(imageWith: cgImage)
            let output = try encoder.prediction(input: input)
            return mlMultiArrayToFloats(output.final_emb_1)
        } catch {
            return nil
        }
    }

    // MARK: - Vision FeaturePrint Backend (Fallback)

    private func computeVisionFeaturePrint(from cgImage: CGImage) -> [Float]? {
        let request = VNGenerateImageFeaturePrintRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

        do {
            try handler.perform([request])
        } catch {
            return nil
        }

        guard let result = request.results?.first as? VNFeaturePrintObservation else {
            return nil
        }

        let data = result.data
        let floatCount = data.count / MemoryLayout<Float>.size
        var floats = [Float](repeating: 0, count: floatCount)
        _ = floats.withUnsafeMutableBytes { buffer in
            data.copyBytes(to: buffer)
        }
        return floats
    }

    // MARK: - Helpers

    private func mlMultiArrayToFloats(_ array: MLMultiArray) -> [Float] {
        let count = array.count
        var floats = [Float](repeating: 0, count: count)
        let ptr = array.dataPointer.bindMemory(to: Float.self, capacity: count)
        for i in 0..<count {
            floats[i] = ptr[i]
        }
        return floats
    }
}
