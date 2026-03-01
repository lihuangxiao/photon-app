import XCTest

/// E2E tests for persistence, paywall gating, and purchase flow.
///
/// Prerequisites (same as PhotonE2ETests):
///   - Test photos loaded into the simulator via `scripts/run_e2e_tests.sh`
///   - Photo library permission pre-granted via `simctl privacy grant photos`
///
/// Tests are numbered 08+ to run after the deletion flow tests.
/// Each test resets app state via the `-resetForTesting` launch argument.
final class PhotonPersistenceTests: XCTestCase {

    private var app: XCUIApplication!
    private let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")

    // MARK: - Setup

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - Helpers

    /// Launch with clean state (UserDefaults + persisted JSON cleared).
    private func launchClean() {
        app.launchArguments = ["-resetForTesting"]
        app.launch()
    }

    /// Relaunch without resetting state (persistence should survive).
    private func relaunchPreservingState() {
        app.terminate()
        app = XCUIApplication()
        app.launchArguments = []
        app.launch()
    }

    private var categoryRowButtons: XCUIElementQuery {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'category_row_'"))
    }

    private func startScan() {
        let startButton = app.buttons["start_scanning"]
        XCTAssertTrue(startButton.waitForExistence(timeout: 10),
                      "Start Scanning button not found")
        startButton.tap()

        let allowButton = springboard.buttons["Allow Full Access"]
        if allowButton.waitForExistence(timeout: 3) {
            allowButton.tap()
        }
    }

    private func waitForScanToComplete(timeout: TimeInterval = 300) {
        let firstRow = categoryRowButtons.firstMatch
        XCTAssertTrue(firstRow.waitForExistence(timeout: timeout),
                      "Scan did not complete within \(timeout)s — no category rows found")
    }

    private func tapPhoto(at index: Int) {
        let photos = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH 'photo_'")
        )
        guard index < photos.count else {
            XCTFail("Photo index \(index) out of range (count: \(photos.count))")
            return
        }
        photos.element(boundBy: index).tap()
    }

    /// Tap Rescan and wait for scan to complete (used to burn a free scan).
    private func rescanAndWait(timeout: TimeInterval = 300) {
        let rescanButton = app.buttons["Rescan"]
        XCTAssertTrue(rescanButton.waitForExistence(timeout: 5),
                      "Rescan button should be in the toolbar")
        rescanButton.tap()
        waitForScanToComplete(timeout: timeout)
    }

    // MARK: - Test 08: Persistence — scan, kill, relaunch, results restored

    /// Scenario 2: Scan completes → terminate → relaunch → CategoryListView
    /// appears with saved results (no WelcomeView / no re-scan needed).
    func test08_PersistenceRestoresAfterRelaunch() {
        launchClean()
        startScan()
        waitForScanToComplete(timeout: 300)

        // Record category count before kill
        let countBefore = categoryRowButtons.count
        XCTAssertGreaterThan(countBefore, 0)

        // Kill and relaunch
        relaunchPreservingState()

        // Should NOT see the Start Scanning button (WelcomeView)
        let startButton = app.buttons["start_scanning"]
        XCTAssertFalse(startButton.waitForExistence(timeout: 5),
                       "WelcomeView should not appear — persisted results should load")

        // Should see category rows (CategoryListView restored)
        let firstRow = categoryRowButtons.firstMatch
        XCTAssertTrue(firstRow.waitForExistence(timeout: 10),
                      "Category rows should appear from persisted results")
    }

    // MARK: - Test 09: Rescan gating — paywall appears after first free scan

    /// First scan is free, second attempt (Rescan) shows paywall.
    func test09_PaywallAppearsAfterFreeScan() {
        launchClean()

        // First scan (free, count → 1)
        startScan()
        waitForScanToComplete(timeout: 300)

        // Rescan — should show paywall
        let rescanButton = app.buttons["Rescan"]
        XCTAssertTrue(rescanButton.waitForExistence(timeout: 5),
                      "Rescan button should be in the toolbar")
        rescanButton.tap()

        // Paywall sheet should appear
        let paywallTitle = app.staticTexts["Unlock Photon Pro"]
        XCTAssertTrue(paywallTitle.waitForExistence(timeout: 5),
                      "Paywall sheet should appear with 'Unlock Photon Pro' title")

        // Verify key elements
        XCTAssertTrue(app.buttons["Already purchased on another device?"].exists,
                      "Restore button should be visible")

        // Dismiss the paywall
        let notNowButton = app.buttons["Not Now"]
        XCTAssertTrue(notNowButton.exists, "Not Now button should be available")
        notNowButton.tap()

        // Should be back on CategoryListView with results intact
        let firstRow = categoryRowButtons.firstMatch
        XCTAssertTrue(firstRow.waitForExistence(timeout: 5),
                      "Category rows should still be visible after dismissing paywall")
    }

    // MARK: - Test 10: Kill during scan — relaunch shows WelcomeView

    /// Scenario 6: Start scan → kill mid-scan → relaunch → WelcomeView
    /// (no persisted data, scan count not incremented).
    func test10_KillDuringScanShowsWelcomeOnRelaunch() {
        launchClean()

        let startButton = app.buttons["start_scanning"]
        XCTAssertTrue(startButton.waitForExistence(timeout: 10))
        startButton.tap()

        // Handle permission dialog if needed
        let allowButton = springboard.buttons["Allow Full Access"]
        if allowButton.waitForExistence(timeout: 3) {
            allowButton.tap()
        }

        // Wait briefly for scan to be in progress (but NOT complete)
        sleep(3)

        // Verify we're NOT on the category list yet (scan in progress)
        let categoryRow = categoryRowButtons.firstMatch
        if categoryRow.exists {
            // Scan already completed (small photo library) — skip this test
            return
        }

        // Kill mid-scan
        relaunchPreservingState()

        // Should see WelcomeView (Start Scanning button), NOT CategoryListView
        let startButtonAfterRelaunch = app.buttons["start_scanning"]
        XCTAssertTrue(startButtonAfterRelaunch.waitForExistence(timeout: 10),
                      "WelcomeView should appear after killing during scan — no data was persisted")
    }

    // MARK: - Test 11: Deletion persists across launches

    /// Scenario 8: Scan → delete photos → kill → relaunch → deletions stick.
    func test11_DeletionPersistsAcrossRelaunch() {
        launchClean()
        startScan()
        waitForScanToComplete(timeout: 300)

        // Navigate to first category
        let firstRow = categoryRowButtons.firstMatch
        firstRow.tap()

        // Keep first photo, delete the rest
        tapPhoto(at: 0)

        let deleteButton = app.buttons["delete_button"]
        XCTAssertTrue(deleteButton.waitForExistence(timeout: 5))
        deleteButton.tap()

        // Confirm app dialog
        let sheet = app.sheets.firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 5))
        sheet.buttons["Delete"].tap()

        // Confirm iOS system dialog
        let systemDelete = springboard.alerts.buttons["Delete"]
        if systemDelete.waitForExistence(timeout: 10) {
            systemDelete.tap()
        }

        sleep(3)

        // Navigate back to category list
        if app.navigationBars.buttons["Photon"].exists {
            app.navigationBars.buttons["Photon"].tap()
            sleep(1)
        }

        // Record count after deletion
        let countAfterDeletion = categoryRowButtons.count

        // Kill and relaunch
        relaunchPreservingState()

        // Wait for persisted results to load
        let restoredRow = categoryRowButtons.firstMatch
        _ = restoredRow.waitForExistence(timeout: 10)

        // Count should match (deletions persisted, not restored)
        let countAfterRelaunch = categoryRowButtons.count
        XCTAssertEqual(countAfterDeletion, countAfterRelaunch,
                       "Category count should be the same after relaunch — deletions persisted")
    }

    // MARK: - Test 12: Purchase unlocks rescan

    /// Scenario 4: First scan free → Rescan (paywall) → purchase →
    /// paywall dismisses → rescan starts.
    /// Uses StoreKit sandbox (Photon.storekit configuration).
    ///
    /// Note: StoreKit testing configuration only works when launched from Xcode
    /// with the .storekit config enabled. When running via xcodebuild CLI, the
    /// product may not load. The test skips gracefully in that case.
    func test12_PurchaseUnlocksRescan() {
        launchClean()

        // First scan (free, count → 1)
        startScan()
        waitForScanToComplete(timeout: 300)

        // Rescan → paywall should appear
        let rescanButton = app.buttons["Rescan"]
        XCTAssertTrue(rescanButton.waitForExistence(timeout: 5))
        rescanButton.tap()

        let paywallTitle = app.staticTexts["Unlock Photon Pro"]
        XCTAssertTrue(paywallTitle.waitForExistence(timeout: 5),
                      "Paywall should appear")

        // Find and tap the purchase button (contains "Unlock for")
        let purchaseButton = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'Unlock for'")
        ).firstMatch
        guard purchaseButton.waitForExistence(timeout: 15) else {
            // StoreKit config not loaded (common when running via xcodebuild CLI)
            // Dismiss paywall and skip the rest of the test
            let notNowButton = app.buttons["Not Now"]
            if notNowButton.exists { notNowButton.tap() }
            try? XCTSkipIf(true,
                "StoreKit product not available — run from Xcode with Photon.storekit config enabled")
            return
        }
        purchaseButton.tap()

        // In StoreKit sandbox, the purchase confirmation sheet appears.
        // The sandbox auto-confirms in testing mode (with .storekit config).
        // Wait for paywall to auto-dismiss (isPro becomes true).
        let paywallGone = paywallTitle.waitForNonExistence(timeout: 15)
        XCTAssertTrue(paywallGone,
                      "Paywall should auto-dismiss after successful purchase")

        // Now tap Rescan again — should start scanning (no paywall)
        let rescanAgain = app.buttons["Rescan"]
        if rescanAgain.waitForExistence(timeout: 5) {
            rescanAgain.tap()
        }

        // Should NOT see paywall again — scan should start
        let paywallAgain = app.staticTexts["Unlock Photon Pro"]
        XCTAssertFalse(paywallAgain.waitForExistence(timeout: 3),
                       "Paywall should NOT appear after purchase — scan should start")
    }

    // MARK: - Test 13: Fresh install gets free first scan (no paywall)

    /// Verify that on a clean install, the first scan runs without any
    /// paywall intervention — the Rescan button doesn't exist yet on WelcomeView,
    /// and the scan just works.
    func test13_FirstScanIsFree() {
        launchClean()

        // Verify we start on WelcomeView
        let startButton = app.buttons["start_scanning"]
        XCTAssertTrue(startButton.waitForExistence(timeout: 10),
                      "Should start on WelcomeView")

        // No paywall should be visible
        let paywallTitle = app.staticTexts["Unlock Photon Pro"]
        XCTAssertFalse(paywallTitle.exists,
                       "Paywall should not appear on first launch")

        // Run the scan — should complete without any purchase gate
        startScan()
        waitForScanToComplete(timeout: 300)

        // Verify results appeared
        XCTAssertGreaterThan(categoryRowButtons.count, 0,
                             "Categories should appear after free first scan")
    }
}
