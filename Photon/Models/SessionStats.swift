import Foundation

/// Tracks deletion progress within a single cleanup session
struct SessionStats {
    var photosDeleted: Int = 0
    var bytesFreed: Int64 = 0
    var categoriesCleaned: Int = 0

    var formattedBytesFreed: String {
        ByteCountFormatter.string(fromByteCount: bytesFreed, countStyle: .file)
    }
}

/// Tracks whether a category has been acted on
enum CategoryStatus {
    case pending
    case reviewed   // User opened but didn't delete everything
    case cleaned    // User deleted photos from this category
}
