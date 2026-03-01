import SwiftUI

struct PaywallView: View {
    @EnvironmentObject var storeService: StoreKitService
    @Environment(\.dismiss) private var dismiss
    var onPurchaseComplete: (() -> Void)?

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()

                // Sparkle icon with gradient
                Image(systemName: "sparkles")
                    .font(.system(size: 64))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.purple, .blue],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                Text("Unlock Photon Pro")
                    .font(.title2)
                    .fontWeight(.bold)

                Text("Your first scan was free. Unlock unlimited scans with a one-time purchase.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                // Feature rows
                VStack(alignment: .leading, spacing: 16) {
                    FeatureRow(icon: "infinity", text: "Unlimited photo scans")
                    FeatureRow(icon: "sparkles.rectangle.stack", text: "AI-powered cleanup forever")
                    FeatureRow(icon: "heart.fill", text: "Support an indie developer")
                }
                .padding(.horizontal, 32)

                Spacer()

                // Purchase button
                if let product = storeService.proProduct {
                    Button {
                        Task { await storeService.purchase() }
                    } label: {
                        if storeService.isLoading {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                                .padding()
                        } else {
                            Text("Unlock for \(product.displayPrice)")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(storeService.isLoading)
                    .padding(.horizontal, 24)
                } else if storeService.isLoading {
                    ProgressView()
                        .padding()
                } else {
                    Button {
                        Task { await storeService.loadProducts() }
                    } label: {
                        Text("Retry")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.horizontal, 24)
                }

                // Restore link
                Button("Already purchased on another device?") {
                    Task { await storeService.restore() }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)

                // Error message
                if let error = storeService.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }

                Spacer()
                    .frame(height: 20)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Not Now") { dismiss() }
                }
            }
        }
        .onChange(of: storeService.isPro) { _, purchased in
            if purchased {
                dismiss()
                onPurchaseComplete?()
            }
        }
    }
}

private struct FeatureRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(.purple)
                .frame(width: 24)
            Text(text)
                .font(.body)
        }
    }
}
