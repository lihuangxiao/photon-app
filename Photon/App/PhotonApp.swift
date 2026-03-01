import SwiftUI
import os

private let logger = Logger(subsystem: "com.photonapp.photon", category: "app")

@main
struct PhotonApp: App {
    @StateObject private var storeService = StoreKitService()

    init() {
        logger.notice("[Photon] App init")

        if ProcessInfo.processInfo.arguments.contains("-resetForTesting") {
            logger.notice("[Photon] Resetting state for testing")
            UserDefaults.standard.removeObject(forKey: "completedScanCount")
            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            try? FileManager.default.removeItem(at: docs.appendingPathComponent("scan_result.json"))
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(storeService)
                .task { await storeService.loadProducts() }
                .onAppear {
                    logger.notice("[Photon] ContentView appeared")
                }
        }
    }
}
