import Foundation

/// Which detection signal produced this group
enum GroupingSignal: String, CaseIterable {
    case nearDuplicate = "Near-Duplicates"
    case screenshot = "Screenshots"
    case burst = "Burst Photos"
    case trip = "Trip Photos"
    case blur = "Blurry Photos"
    case video = "Videos"
    case screenRecording = "Screen Recordings"
    case livePhoto = "Live Photos"
    case oldPhoto = "Old Photos"
    case dark = "Dark Photos"
    case document = "Document Photos"
    case savedImage = "Saved Images"
    case ai = "AI Detected"

    var systemImage: String {
        switch self {
        case .nearDuplicate: return "square.on.square"
        case .screenshot: return "rectangle.portrait.on.rectangle.portrait"
        case .burst: return "bolt.circle"
        case .trip: return "map"
        case .blur: return "aqi.medium"
        case .video: return "video"
        case .screenRecording: return "record.circle"
        case .livePhoto: return "livephoto"
        case .oldPhoto: return "clock.arrow.circlepath"
        case .dark: return "moon.fill"
        case .document: return "doc.text.viewfinder"
        case .savedImage: return "square.and.arrow.down"
        case .ai: return "brain"
        }
    }
}

/// How the user interacts with this group
enum InteractionMode: String {
    /// User reviews the group and deletes the entire group (screenshots, blur, trips)
    case deleteAll = "Delete All"
    /// User picks which to keep, rest get deleted (bursts, near-duplicates)
    case keepBest = "Keep Best"
}

/// A group of similar photos identified by the grouping pipeline
struct PhotoCategory: Identifiable {
    let id: UUID
    let label: String
    let photoIDs: [String] // PHAsset localIdentifiers
    let confidence: ConfidenceLevel
    let score: Double // 0.0 to 1.0, higher = more likely deletable
    let photoCount: Int
    let estimatedSize: Int64 // bytes
    let dateRange: ClosedRange<Date>?
    let dominantType: DominantType
    let groupingSignal: GroupingSignal
    let interactionMode: InteractionMode
    var cloudReason: String? // For future AI labeling

    enum ConfidenceLevel: String, CaseIterable, Comparable {
        case high = "High"
        case medium = "Medium"
        case low = "Low"

        static func < (lhs: ConfidenceLevel, rhs: ConfidenceLevel) -> Bool {
            let order: [ConfidenceLevel] = [.low, .medium, .high]
            return order.firstIndex(of: lhs)! < order.firstIndex(of: rhs)!
        }
    }

    enum DominantType: String {
        case screenshots = "Screenshots"
        case burstPhotos = "Burst Photos"
        case livePhotos = "Live Photos"
        case similarPhotos = "Similar Photos"
        case videos = "Videos"
        case screenRecordings = "Screen Recordings"
        case blurryPhotos = "Blurry Photos"
        case tripPhotos = "Trip Photos"
        case oldPhotos = "Old Photos"
        case darkPhotos = "Dark Photos"
        case documentPhotos = "Document Photos"
        case savedImages = "Saved Images"
        case mixed = "Mixed"
    }

    /// Human-readable description of the category
    var description: String {
        var parts: [String] = []
        parts.append("\(photoCount) \(dominantType.rawValue.lowercased())")
        if let range = dateRange {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .none
            let start = formatter.string(from: range.lowerBound)
            let end = formatter.string(from: range.upperBound)
            if start == end {
                parts.append("from \(start)")
            } else {
                parts.append("from \(start) to \(end)")
            }
        }
        return parts.joined(separator: " ")
    }

    /// Human-readable file size
    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: estimatedSize, countStyle: .file)
    }
}
