import Foundation
import Accelerate
import UIKit
import Photos
import Vision

/// Detects blurry photos, dark photos, and document photos using image analysis.
/// Blur: Laplacian variance — higher = sharper, lower = blurrier.
/// Brightness: mean grayscale value — lower = darker.
/// Document: Vision framework document segmentation.
class BlurDetectionService {

    struct Config {
        /// Photos below this threshold are "definitely blurry"
        var veryBlurryThreshold: Float = 50
        /// Photos below this threshold are "somewhat blurry"
        var somewhatBlurryThreshold: Float = 150
        /// Document detection confidence threshold
        var documentConfidenceThreshold: Float = 0.8
    }

    /// Results from image analysis pipeline
    struct ImageAnalysisResult {
        let blurScore: Float
        let brightnessScore: Float
        let isDocument: Bool
    }

    var config: Config

    init(config: Config = Config()) {
        self.config = config
    }

    /// Compute blur, brightness, and document scores for all image assets.
    /// Returns a map of asset ID → ImageAnalysisResult.
    @MainActor
    func detectBlur(
        for assets: [PhotoAsset],
        onProgress: @escaping (Int, Int) -> Void
    ) async -> [String: ImageAnalysisResult] {
        let total = assets.count
        let docConfidence = config.documentConfidenceThreshold

        let results: [String: ImageAnalysisResult] = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                var results: [String: ImageAnalysisResult] = [:]
                results.reserveCapacity(total)
                let reportInterval = max(total / 100, 1)

                for (index, asset) in assets.enumerated() {
                    guard asset.phAsset.mediaType == .image else { continue }

                    if let image = self.fetchImageSync(for: asset.phAsset),
                       let cgImage = image.cgImage {
                        let blurScore = self.computeLaplacianVariance(from: cgImage)
                        let brightness = self.computeMeanBrightness(from: cgImage)
                        let isDoc = self.detectDocument(cgImage: cgImage, confidenceThreshold: docConfidence)

                        results[asset.id] = ImageAnalysisResult(
                            blurScore: blurScore,
                            brightnessScore: brightness,
                            isDocument: isDoc
                        )
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

        print("[Photon] Image analysis done: \(results.count)/\(total) scores computed")
        return results
    }

    /// Compute the Laplacian variance of a grayscale image.
    /// Uses Accelerate for the convolution. Higher variance = sharper.
    func computeLaplacianVariance(from cgImage: CGImage) -> Float {
        let width = cgImage.width
        let height = cgImage.height
        guard width > 3 && height > 3 else { return 0 }

        // Convert to grayscale float buffer
        guard let grayscale = toGrayscaleFloats(cgImage: cgImage, width: width, height: height) else {
            return 0
        }

        // 3x3 Laplacian kernel: [0, 1, 0, 1, -4, 1, 0, 1, 0]
        let kernel: [Float] = [
            0,  1, 0,
            1, -4, 1,
            0,  1, 0
        ]

        // Output buffer — vDSP_imgfir output is same size as input
        var output = [Float](repeating: 0, count: width * height)

        // Apply 2D convolution using vDSP
        grayscale.withUnsafeBufferPointer { srcPtr in
            output.withUnsafeMutableBufferPointer { dstPtr in
                kernel.withUnsafeBufferPointer { kernelPtr in
                    vDSP_imgfir(
                        srcPtr.baseAddress!, vDSP_Length(height), vDSP_Length(width),
                        kernelPtr.baseAddress!,
                        dstPtr.baseAddress!,
                        3, 3
                    )
                }
            }
        }

        // Compute variance of the Laplacian response
        let count = vDSP_Length(output.count)
        var mean: Float = 0
        vDSP_meanv(output, 1, &mean, count)

        var meanSq: Float = 0
        vDSP_measqv(output, 1, &meanSq, count)

        let variance = meanSq - mean * mean
        return max(variance, 0)
    }

    /// Compute mean brightness from a CGImage (0-255 scale, lower = darker).
    func computeMeanBrightness(from cgImage: CGImage) -> Float {
        let width = cgImage.width
        let height = cgImage.height
        guard width > 0 && height > 0 else { return 128 }

        guard let grayscale = toGrayscaleFloats(cgImage: cgImage, width: width, height: height) else {
            return 128
        }

        var mean: Float = 0
        vDSP_meanv(grayscale, 1, &mean, vDSP_Length(grayscale.count))
        return mean
    }

    /// Detect if image contains a document using Vision framework.
    func detectDocument(cgImage: CGImage, confidenceThreshold: Float) -> Bool {
        let request = VNDetectDocumentSegmentationRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

        do {
            try handler.perform([request])
            guard let result = request.results?.first else { return false }
            return result.confidence >= confidenceThreshold
        } catch {
            return false
        }
    }

    // MARK: - Private

    private func toGrayscaleFloats(cgImage: CGImage, width: Int, height: Int) -> [Float]? {
        let colorSpace = CGColorSpaceCreateDeviceGray()
        let bytesPerRow = width
        var pixels = [UInt8](repeating: 0, count: width * height)

        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return nil }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        // Convert UInt8 to Float (0-255 range)
        var floats = [Float](repeating: 0, count: width * height)
        vDSP_vfltu8(pixels, 1, &floats, 1, vDSP_Length(width * height))

        return floats
    }

    /// Synchronous image fetch for blur detection. Uses small thumbnails for speed.
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
}
