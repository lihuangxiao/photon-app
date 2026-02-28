import Foundation
import Photos

enum DeletionResult {
    case success(count: Int, bytes: Int64)
    case cancelled
    case error(String)
}

/// Handles PhotoKit deletion with fresh asset fetching and size calculation
struct DeletionService {

    /// Delete photos by their local identifiers.
    /// Fetches fresh PHAssets to avoid stale references.
    func deletePhotos(localIdentifiers: [String]) async -> DeletionResult {
        // Fetch fresh assets — stored references may be stale
        let fetchResult = PHAsset.fetchAssets(
            withLocalIdentifiers: localIdentifiers,
            options: nil
        )

        guard fetchResult.count > 0 else {
            return .error("No matching photos found")
        }

        // Calculate total size before deletion
        var totalBytes: Int64 = 0
        fetchResult.enumerateObjects { asset, _, _ in
            let resources = PHAssetResource.assetResources(for: asset)
            if let size = resources.first?.value(forKey: "fileSize") as? Int64 {
                totalBytes += size
            }
        }

        let count = fetchResult.count

        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.deleteAssets(fetchResult)
            }
            return .success(count: count, bytes: totalBytes)
        } catch let error as NSError {
            // User tapped "Don't Allow" on the iOS system dialog
            if error.domain == "PHPhotosErrorDomain" && error.code == 3072 {
                return .cancelled
            }
            return .error(error.localizedDescription)
        }
    }
}
