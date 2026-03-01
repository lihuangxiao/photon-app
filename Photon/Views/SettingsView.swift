import SwiftUI
import StoreKit

struct SettingsView: View {
    @EnvironmentObject var storeService: StoreKitService
    @Environment(\.dismiss) private var dismiss
    @State private var showPaywall = false

    // TODO: Replace with your real URLs before submission
    private let privacyPolicyURL = URL(string: "https://example.com/privacy")!
    private let supportEmail = "support@photonapp.com"

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "Photon v\(version) (\(build))"
    }

    var body: some View {
        NavigationStack {
            List {
                // Pro Status
                Section {
                    if storeService.isPro {
                        HStack {
                            Label("Photon Pro", systemImage: "checkmark.seal.fill")
                                .foregroundStyle(.purple)
                                .fontWeight(.semibold)
                            Spacer()
                            Text("Active")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        HStack {
                            Label("Free", systemImage: "sparkles")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("Upgrade") {
                                showPaywall = true
                            }
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        }
                    }
                } header: {
                    Text("Account")
                }

                // Purchases
                Section {
                    Button {
                        Task { await storeService.restore() }
                    } label: {
                        HStack {
                            Label("Restore Purchases", systemImage: "arrow.clockwise")
                            Spacer()
                            if storeService.isLoading {
                                ProgressView()
                            }
                        }
                    }
                    .disabled(storeService.isLoading)
                } header: {
                    Text("Purchases")
                }

                // Support
                Section {
                    Link(destination: URL(string: "mailto:\(supportEmail)")!) {
                        Label("Contact Support", systemImage: "envelope")
                    }

                    Link(destination: privacyPolicyURL) {
                        Label("Privacy Policy", systemImage: "hand.raised")
                    }
                } header: {
                    Text("Support")
                }

                // About
                Section {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text(appVersion)
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Text("Made with")
                        Spacer()
                        Text("love, by an indie dev")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("About")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showPaywall) {
                PaywallView()
            }
        }
    }
}
