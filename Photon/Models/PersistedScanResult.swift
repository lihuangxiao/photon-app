import Foundation

struct PersistedScanResult: Codable {
    let scanDate: Date
    let totalPhotosScanned: Int
    let categories: [PersistedCategory]
}

struct PersistedCategory: Codable, Identifiable {
    let id: UUID
    let label: String
    let photoIDs: [String]
    let confidence: String
    let score: Double
    let photoCount: Int
    let estimatedSize: Int64
    let dateRangeStart: Date?
    let dateRangeEnd: Date?
    let dominantType: String
    let groupingSignal: String
    let interactionMode: String
    let cloudReason: String?
}
