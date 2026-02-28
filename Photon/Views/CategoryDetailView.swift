import SwiftUI
import Photos

/// Shows a grid of photos in a category for review, with selection and deletion
struct CategoryDetailView: View {
    let category: PhotoCategory
    @ObservedObject var viewModel: ScanViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var assets: [PhotoAsset] = []
    @State private var isSelecting = false
    @State private var selectedIDs: Set<String> = []  // IDs of photos to DELETE
    @State private var showDeleteConfirmation = false
    @AppStorage("skipAppConfirmation") private var skipAppConfirmation = false

    // Photo preview
    @State private var previewAsset: PhotoAsset?
    @State private var previewImage: UIImage?

    // Fixed 3-column grid, 2pt spacing
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 3)

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    CategoryInfoHeader(category: category)
                        .padding(.horizontal)

                    LazyVGrid(columns: columns, spacing: 2) {
                        ForEach(assets) { asset in
                            PhotoThumbnailView(
                                phAsset: asset.phAsset,
                                photoService: viewModel.photoService,
                                blurScore: asset.blurScore,
                                showBlurBadge: category.groupingSignal == .blur,
                                isVideo: asset.isVideo,
                                videoDuration: asset.duration,
                                fileSize: asset.fileSize,
                                isSelecting: isSelecting,
                                isKept: !selectedIDs.contains(asset.id)
                            )
                            .accessibilityIdentifier("photo_\(asset.id)")
                            .aspectRatio(1, contentMode: .fit)
                            .clipped()
                            .contentShape(Rectangle())
                            .onTapGesture {
                                guard isSelecting else { return }
                                toggleSelection(asset.id)
                            }
                            .onLongPressGesture(minimumDuration: 0.15) {
                                showPreview(for: asset)
                            }
                        }
                    }
                    .background(Color(.systemGray5))

                    // Bottom padding so floating bar doesn't cover content
                    if isSelecting {
                        Spacer().frame(height: 100)
                    }
                }
            }

            // Floating deletion bar
            if isSelecting {
                DeletionBar(
                    photosToDelete: photosToDeleteCount,
                    bytesToFree: bytesToFree,
                    onDelete: {
                        if skipAppConfirmation {
                            Task { await performDeletion() }
                        } else {
                            showDeleteConfirmation = true
                        }
                    },
                    onCancel: { exitSelectionMode() }
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: isSelecting)
        .navigationTitle(category.groupingSignal.rawValue)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !assets.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") {
                        exitSelectionMode()
                        dismiss()
                    }
                }
            }
        }
        .confirmationDialog(
            "Delete \(photosToDeleteCount) photo\(photosToDeleteCount == 1 ? "" : "s")?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                Task { await performDeletion() }
            }
            Button("Delete & Don't Ask Again", role: .destructive) {
                skipAppConfirmation = true
                Task { await performDeletion() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("They'll move to Recently Deleted where you can recover them for 30 days.")
        }
        .onAppear {
            assets = viewModel.assets(for: category)
            viewModel.markReviewed(category)
            let phAssets = assets.map(\.phAsset)
            viewModel.photoService.startCaching(assets: phAssets)

            if !assets.isEmpty {
                enterSelectionMode()
            }
        }
        .onDisappear {
            let phAssets = assets.map(\.phAsset)
            viewModel.photoService.stopCaching(assets: phAssets)
        }
        .toolbar(previewAsset != nil ? .hidden : .visible, for: .navigationBar)
        .overlay {
            if let asset = previewAsset {
                PhotoPreviewOverlay(
                    image: previewImage,
                    isSelected: selectedIDs.contains(asset.id),
                    onToggleSelection: { toggleSelection(asset.id) },
                    onDismiss: { dismissPreview() }
                )
            }
        }
    }

    // MARK: - Preview

    private func showPreview(for asset: PhotoAsset) {
        previewAsset = asset
        previewImage = nil
        viewModel.photoService.requestPreviewImage(for: asset.phAsset) { img in
            Task { @MainActor in
                if previewAsset?.id == asset.id {
                    previewImage = img
                }
            }
        }
    }

    private func dismissPreview() {
        previewAsset = nil
        previewImage = nil
    }

    // MARK: - Selection Logic

    private func enterSelectionMode() {
        isSelecting = true
        // All photos start selected for deletion
        selectedIDs = Set(assets.map(\.id))
    }

    private func exitSelectionMode() {
        isSelecting = false
        selectedIDs = []
    }

    private func toggleSelection(_ id: String) {
        if selectedIDs.contains(id) {
            selectedIDs.remove(id)
        } else {
            selectedIDs.insert(id)
        }
    }

    /// IDs that will be deleted
    private var idsToDelete: [String] {
        Array(selectedIDs)
    }

    private var photosToDeleteCount: Int {
        idsToDelete.count
    }

    private var bytesToFree: Int64 {
        let deleteSet = Set(idsToDelete)
        return assets.filter { deleteSet.contains($0.id) }.reduce(Int64(0)) { $0 + $1.fileSize }
    }

    // MARK: - Deletion

    private func performDeletion() async {
        let toDelete = idsToDelete
        guard !toDelete.isEmpty else { return }

        let success = await viewModel.deletePhotos(identifiers: toDelete, from: category)
        if success {
            // Refresh assets using the UPDATED category (original has stale photoIDs)
            if let updatedCategory = viewModel.categories.first(where: { $0.id == category.id }) {
                assets = viewModel.assets(for: updatedCategory)
            } else {
                assets = []  // Category fully deleted
            }
            exitSelectionMode()

            // If category is now empty, pop back
            if assets.isEmpty {
                dismiss()
            }
        }
    }
}

// MARK: - Category Info Header

struct CategoryInfoHeader: View {
    let category: PhotoCategory

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: category.groupingSignal.systemImage)
                    .foregroundStyle(confidenceColor)
                Text(category.confidence.rawValue + " Confidence")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(confidenceColor)

                Spacer()

                Text("Score: \(Int(category.score * 100))%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 6) {
                Image(systemName: category.interactionMode == .keepBest ? "hand.tap" : "trash")
                    .font(.caption)
                Text(category.interactionMode == .keepBest
                     ? "Pick your favorites — the rest can be deleted"
                     : "Review and delete the entire group")
                    .font(.caption)
            }
            .foregroundStyle(category.interactionMode == .keepBest ? .blue : .red)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                (category.interactionMode == .keepBest ? Color.blue : Color.red)
                    .opacity(0.08)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8))

            Text(category.description)
                .font(.body)
                .foregroundStyle(.secondary)

            HStack(spacing: 16) {
                Label("\(category.photoCount) photos", systemImage: "photo")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if category.estimatedSize > 0 {
                    Label(category.formattedSize, systemImage: "externaldrive")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Label(category.groupingSignal.rawValue, systemImage: category.groupingSignal.systemImage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()
        }
    }

    private var confidenceColor: Color {
        switch category.confidence {
        case .high: return .green
        case .medium: return .orange
        case .low: return .blue
        }
    }
}

// MARK: - Photo Thumbnail View

struct PhotoThumbnailView: View {
    let phAsset: PHAsset
    let photoService: PhotoLibraryService
    var blurScore: Float? = nil
    var showBlurBadge: Bool = false
    var isVideo: Bool = false
    var videoDuration: TimeInterval = 0
    var fileSize: Int64 = 0
    var isSelecting: Bool = false
    var isKept: Bool = false

    @State private var image: UIImage?

    var body: some View {
        // Color.clear fills the exact proposed size (square from .aspectRatio(1, .fit))
        // Using .overlay ensures the image is sized relative to this fixed frame
        Color.clear
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                        .overlay {
                            ProgressView()
                                .scaleEffect(0.6)
                        }
                }
            }
            .clipped()
            .overlay(alignment: .topLeading) {
                // Large file badge (top-left, >50MB)
                if fileSize > 50_000_000 {
                    Text(ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file))
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(.orange)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .padding(4)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                // Video duration badge (bottom-right)
                if isVideo && videoDuration > 0 {
                    HStack(spacing: 2) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 7))
                        Text(formatDuration(videoDuration))
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(.black.opacity(0.6))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .padding(4)
                }
                // Blur score badge (bottom-right, only if not video)
                else if showBlurBadge, let score = blurScore {
                    Text("\(Int(score))")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(blurBadgeColor(score: score))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .padding(4)
                }
            }
            .overlay(alignment: .topTrailing) {
                // Selection checkmark (top-right)
                // Green filled = selected for deletion, empty = kept
                if isSelecting {
                    ZStack {
                        Circle()
                            .fill(isKept ? .clear : .green)
                            .frame(width: 24, height: 24)
                        Circle()
                            .strokeBorder(.white, lineWidth: 2)
                            .frame(width: 24, height: 24)
                        if !isKept {
                            Image(systemName: "checkmark")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(.white)
                        }
                    }
                    .shadow(color: .black.opacity(0.3), radius: 2)
                    .padding(6)
                }
            }
            .onAppear {
                loadThumbnail()
            }
            .onDisappear {
                image = nil
            }
    }

    private func loadThumbnail() {
        photoService.requestThumbnail(for: phAsset, targetSize: CGSize(width: 390, height: 390)) { img in
            Task { @MainActor in
                self.image = img
            }
        }
    }

    private func blurBadgeColor(score: Float) -> Color {
        if score < 50 { return .red }
        if score < 150 { return .orange }
        return .green
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Floating Deletion Bar

struct DeletionBar: View {
    let photosToDelete: Int
    let bytesToFree: Int64
    let onDelete: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(photosToDelete) photo\(photosToDelete == 1 ? "" : "s") to delete")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .accessibilityIdentifier("deletion_count")
                    if bytesToFree > 0 {
                        Text("Frees \(ByteCountFormatter.string(fromByteCount: bytesToFree, countStyle: .file))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Button(role: .destructive, action: onDelete) {
                    Text("Delete")
                        .fontWeight(.semibold)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                }
                .accessibilityIdentifier("delete_button")
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(photosToDelete == 0)
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
        }
        .background(.ultraThinMaterial)
    }
}

// MARK: - Photo Preview Overlay

struct PhotoPreviewOverlay: View {
    let image: UIImage?
    let isSelected: Bool  // true = selected for deletion
    let onToggleSelection: () -> Void
    let onDismiss: () -> Void

    @State private var dragOffset: CGSize = .zero
    @State private var appeared = false

    var body: some View {
        ZStack {
            // Dark background
            Color.black.opacity(appeared ? 0.95 : 0)
                .ignoresSafeArea()

            // Photo
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 60)
                    .offset(y: dragOffset.height)
                    .scaleEffect(max(0.8, 1 - abs(dragOffset.height) / 600))
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                dragOffset = value.translation
                            }
                            .onEnded { value in
                                if abs(value.translation.height) > 100 {
                                    onDismiss()
                                } else {
                                    withAnimation(.spring(duration: 0.25)) {
                                        dragOffset = .zero
                                    }
                                }
                            }
                    )
            } else {
                ProgressView()
                    .tint(.white)
                    .scaleEffect(1.5)
            }

            // Top controls
            VStack {
                HStack {
                    // Close button (top-left) — goes back to photo grid
                    Button { onDismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 32, height: 32)
                            .background(.white.opacity(0.2))
                            .clipShape(Circle())
                    }

                    Spacer()

                    // Selection circle (top-right) — toggle select/deselect
                    Button { onToggleSelection() } label: {
                        ZStack {
                            Circle()
                                .fill(isSelected ? .green : .clear)
                                .frame(width: 30, height: 30)
                            Circle()
                                .strokeBorder(.white, lineWidth: 2)
                                .frame(width: 30, height: 30)
                            if isSelected {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)

                Spacer()

                Text("Swipe down to close")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.4))
                    .padding(.bottom, 40)
            }
        }
        .transition(.opacity)
        .animation(.easeInOut(duration: 0.2), value: appeared)
        .onAppear { appeared = true }
    }
}
