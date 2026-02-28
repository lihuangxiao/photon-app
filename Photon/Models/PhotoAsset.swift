import Foundation
import Photos
import CoreLocation

/// Represents a photo with its metadata and computed embedding
struct PhotoAsset: Identifiable {
    let id: String // PHAsset localIdentifier
    let phAsset: PHAsset
    let creationDate: Date?
    let fileSize: Int64
    let mediaType: PHAssetMediaType
    let mediaSubtypes: PHAssetMediaSubtype
    let location: CLLocation?
    let isFavorite: Bool
    let duration: TimeInterval // 0 for images
    let pixelWidth: Int
    let pixelHeight: Int
    let originalFilename: String?
    var embedding: [Float]?
    var blurScore: Float? // Laplacian variance — lower = blurrier
    var brightnessScore: Float? // Mean brightness 0-255, lower = darker
    var isDocument: Bool? // Detected by Vision document segmentation

    var isScreenshot: Bool {
        mediaSubtypes.contains(.photoScreenshot)
    }

    var isBurst: Bool {
        phAsset.representsBurst
    }

    var burstIdentifier: String? {
        phAsset.burstIdentifier
    }

    var isLivePhoto: Bool {
        mediaSubtypes.contains(.photoLive)
    }

    var isVideo: Bool {
        mediaType == .video
    }

    /// Age in days since creation
    var ageDays: Int {
        guard let date = creationDate else { return 0 }
        return Calendar.current.dateComponents([.day], from: date, to: Date()).day ?? 0
    }

    init(phAsset: PHAsset) {
        self.id = phAsset.localIdentifier
        self.phAsset = phAsset
        self.creationDate = phAsset.creationDate
        self.mediaType = phAsset.mediaType
        self.mediaSubtypes = phAsset.mediaSubtypes
        self.location = phAsset.location
        self.isFavorite = phAsset.isFavorite
        self.duration = phAsset.duration
        self.pixelWidth = phAsset.pixelWidth
        self.pixelHeight = phAsset.pixelHeight

        // File size + original filename from PHAssetResource
        let resources = PHAssetResource.assetResources(for: phAsset)
        self.fileSize = resources.first.flatMap {
            ($0.value(forKey: "fileSize") as? Int64)
        } ?? 0
        self.originalFilename = resources.first?.originalFilename
    }
}
