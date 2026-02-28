import Foundation
import Photos
import UIKit

/// Handles all interactions with the iOS Photo Library via PhotoKit
@MainActor
class PhotoLibraryService: ObservableObject {
    @Published var authorizationStatus: PHAuthorizationStatus = .notDetermined
    @Published var allAssets: [PhotoAsset] = []
    @Published var fetchProgress: Double = 0.0 // 0.0 to 1.0
    @Published var isFetching: Bool = false
    @Published var totalPhotoCount: Int = 0

    private let imageManager = PHCachingImageManager()

    /// Request photo library authorization
    func requestAuthorization() async -> PHAuthorizationStatus {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        authorizationStatus = status
        return status
    }

    /// Check current authorization without prompting
    func checkAuthorization() {
        authorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    }

    /// Fetch all photo assets from the library progressively
    func fetchAllAssets() async {
        isFetching = true
        fetchProgress = 0.0
        allAssets = []

        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        // Fetch photos and videos
        fetchOptions.predicate = NSPredicate(
            format: "mediaType == %d OR mediaType == %d",
            PHAssetMediaType.image.rawValue,
            PHAssetMediaType.video.rawValue
        )

        let results = PHAsset.fetchAssets(with: fetchOptions)
        totalPhotoCount = results.count

        guard totalPhotoCount > 0 else {
            isFetching = false
            fetchProgress = 1.0
            return
        }

        // Process in batches for progressive updates
        let batchSize = 100
        var processed = 0
        var assets: [PhotoAsset] = []
        assets.reserveCapacity(totalPhotoCount)

        results.enumerateObjects { phAsset, index, _ in
            let asset = PhotoAsset(phAsset: phAsset)
            assets.append(asset)
            processed += 1

            // Update progress in batches to avoid UI thrashing
            if processed % batchSize == 0 || processed == self.totalPhotoCount {
                let currentAssets = assets
                let progress = Double(processed) / Double(self.totalPhotoCount)
                Task { @MainActor in
                    self.allAssets = currentAssets
                    self.fetchProgress = progress
                }
            }
        }

        allAssets = assets
        fetchProgress = 1.0
        isFetching = false
    }

    /// Request a thumbnail image for a photo asset
    func requestThumbnail(
        for asset: PHAsset,
        targetSize: CGSize = CGSize(width: 390, height: 390),
        completion: @escaping (UIImage?) -> Void
    ) {
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.isNetworkAccessAllowed = true
        options.resizeMode = .fast

        imageManager.requestImage(
            for: asset,
            targetSize: targetSize,
            contentMode: .aspectFill,
            options: options
        ) { image, _ in
            completion(image)
        }
    }

    /// Request a full-size image for ML processing
    func requestImageForML(
        for asset: PHAsset,
        targetSize: CGSize = CGSize(width: 256, height: 256),
        completion: @escaping (UIImage?) -> Void
    ) {
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        options.isSynchronous = false
        options.resizeMode = .exact

        imageManager.requestImage(
            for: asset,
            targetSize: targetSize,
            contentMode: .aspectFill,
            options: options
        ) { image, info in
            // Only use the final result, not the degraded placeholder
            let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
            if !isDegraded {
                completion(image)
            }
        }
    }

    /// Request a display-quality image suitable for full-screen preview
    func requestPreviewImage(
        for asset: PHAsset,
        completion: @escaping (UIImage?) -> Void
    ) {
        let scale = UIScreen.main.scale
        let screenSize = UIScreen.main.bounds.size
        let targetSize = CGSize(width: screenSize.width * scale, height: screenSize.height * scale)

        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        options.resizeMode = .fast

        imageManager.requestImage(
            for: asset,
            targetSize: targetSize,
            contentMode: .aspectFit,
            options: options
        ) { image, info in
            let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
            if !isDegraded {
                completion(image)
            }
        }
    }

    /// Start caching thumbnails for a set of assets
    func startCaching(assets: [PHAsset], targetSize: CGSize = CGSize(width: 390, height: 390)) {
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        imageManager.startCachingImages(for: assets, targetSize: targetSize, contentMode: .aspectFill, options: options)
    }

    /// Stop caching thumbnails
    func stopCaching(assets: [PHAsset], targetSize: CGSize = CGSize(width: 390, height: 390)) {
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        imageManager.stopCachingImages(for: assets, targetSize: targetSize, contentMode: .aspectFill, options: options)
    }
}
