import SwiftUI
import os

private let logger = Logger(subsystem: "com.photonapp.photon", category: "app")

@main
struct PhotonApp: App {
    init() {
        logger.notice("[Photon] App init")
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onAppear {
                    logger.notice("[Photon] ContentView appeared")
                }
        }
    }
}
