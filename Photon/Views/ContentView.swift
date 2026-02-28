import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = ScanViewModel()

    var body: some View {
        NavigationStack {
            Group {
                switch viewModel.state {
                case .idle:
                    WelcomeView(onStart: {
                        Task { await viewModel.startScan() }
                    })

                case .requestingPermission:
                    ProgressMessageView(
                        title: "Requesting Access",
                        message: "Please allow access to your photo library"
                    )

                case .permissionDenied:
                    PermissionDeniedView()

                case .preparing:
                    ScanProgressView(
                        phase: "Preparing",
                        message: viewModel.statusMessage,
                        progress: nil,
                        photosProcessed: 0,
                        totalPhotos: 0
                    )

                case .fetchingPhotos:
                    ScanProgressView(
                        phase: "Loading Photos",
                        message: viewModel.statusMessage,
                        progress: viewModel.fetchProgress,
                        photosProcessed: viewModel.totalPhotos,
                        totalPhotos: viewModel.totalPhotos
                    )

                case .generatingEmbeddings:
                    ScanProgressView(
                        phase: "Analyzing",
                        message: viewModel.statusMessage,
                        progress: viewModel.embeddingProgress,
                        photosProcessed: viewModel.photosProcessed,
                        totalPhotos: viewModel.totalPhotos
                    )

                case .detectingBlur:
                    ScanProgressView(
                        phase: "Detecting Blur",
                        message: viewModel.statusMessage,
                        progress: viewModel.blurProgress,
                        photosProcessed: viewModel.blurPhotosProcessed,
                        totalPhotos: viewModel.totalPhotos
                    )

                case .grouping:
                    ScanProgressView(
                        phase: "Finding Patterns",
                        message: viewModel.statusMessage,
                        progress: nil,
                        photosProcessed: viewModel.totalPhotos,
                        totalPhotos: viewModel.totalPhotos
                    )

                case .complete:
                    CategoryListView(viewModel: viewModel)

                case .error(let message):
                    ErrorView(message: message, onRetry: {
                        Task { await viewModel.startScan() }
                    })
                }
            }
            .navigationTitle("Photon")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                if viewModel.state == .complete && !viewModel.categories.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            viewModel.showDebug = true
                        } label: {
                            Image(systemName: "slider.horizontal.3")
                        }
                    }
                }
            }
            .sheet(isPresented: $viewModel.showDebug) {
                DebugView(viewModel: viewModel)
            }
        }
        // Toast overlay
        .overlay(alignment: .top) {
            if let message = viewModel.toastMessage {
                ToastView(message: message)
                    .accessibilityIdentifier("toast_view")
                    .padding(.top, 60)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .animation(.spring(duration: 0.4), value: viewModel.toastMessage)
                    .zIndex(100)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: viewModel.toastMessage)
        // Session summary
        .fullScreenCover(isPresented: $viewModel.showSessionSummary) {
            SessionSummaryView(
                stats: viewModel.sessionStats,
                totalPhotos: viewModel.totalPhotos,
                onDismiss: { viewModel.showSessionSummary = false }
            )
        }
    }
}

// MARK: - Welcome View

struct WelcomeView: View {
    let onStart: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "sparkles.rectangle.stack")
                .font(.system(size: 80))
                .foregroundStyle(Color.accentColor)

            Text("Smart Photo Cleanup")
                .font(.title)
                .fontWeight(.bold)

            Text("We'll analyze your photo library and find groups of photos you might want to delete.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Spacer()

            Button(action: onStart) {
                Text("Start Scanning")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
            }
            .accessibilityIdentifier("start_scanning")
            .buttonStyle(.borderedProminent)
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
    }
}

// MARK: - Permission Denied View

struct PermissionDeniedView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "photo.badge.exclamationmark")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)

            Text("Photo Access Required")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Photon needs full access to your photo library to analyze and help clean up your photos. Please grant access in Settings.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 8)
        }
    }
}

// MARK: - Progress Message View

struct ProgressMessageView: View {
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)
            Text(title)
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Error View

struct ErrorView: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 50))
                .foregroundStyle(.orange)

            Text("Something Went Wrong")
                .font(.title2)
                .fontWeight(.semibold)

            Text(message)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Button("Try Again", action: onRetry)
                .buttonStyle(.borderedProminent)
        }
    }
}

#Preview {
    ContentView()
}
