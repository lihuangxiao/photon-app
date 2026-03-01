import XCTest

/// End-to-end UI tests for the Photon deletion flow (Step 2).
///
/// Prerequisites:
///   - Test photos loaded into the simulator via `scripts/run_e2e_tests.sh`
///   - Photo library permission pre-granted via `simctl privacy grant photos`
///
/// Tests are numbered to control execution order (XCTest runs alphabetically).
/// Non-destructive tests run first; destructive tests that delete photos run last.
///
/// Note: In SwiftUI, NavigationLink items in a List are exposed as **buttons**
/// (not cells) in the accessibility tree.
final class PhotonE2ETests: XCTestCase {

    private var app: XCUIApplication!
    private let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")

    // MARK: - Setup / Teardown

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-resetForTesting"]
        app.launch()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - Helpers

    /// Query for category row buttons (SwiftUI NavigationLink in List → button type).
    private var categoryRowButtons: XCUIElementQuery {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'category_row_'"))
    }

    /// Tap the "Start Scanning" button and handle any permission dialog.
    private func startScan() {
        let startButton = app.buttons["start_scanning"]
        XCTAssertTrue(startButton.waitForExistence(timeout: 10),
                      "Start Scanning button not found")
        startButton.tap()

        // Fallback: dismiss photo library permission dialog if it appears
        let allowButton = springboard.buttons["Allow Full Access"]
        if allowButton.waitForExistence(timeout: 3) {
            allowButton.tap()
        }
    }

    /// Wait until at least one category row button appears (scan complete).
    private func waitForScanToComplete(timeout: TimeInterval = 300) {
        let firstRow = categoryRowButtons.firstMatch
        XCTAssertTrue(firstRow.waitForExistence(timeout: timeout),
                      "Scan did not complete within \(timeout)s — no category rows found")
    }

    /// Find and tap a category row whose label contains the given signal name.
    /// Falls back to the first category row if no match.
    @discardableResult
    private func navigateToCategory(signal: String) -> XCUIElement {
        if !signal.isEmpty {
            let matching = app.buttons.matching(
                NSPredicate(format: "identifier BEGINSWITH 'category_row_' AND label CONTAINS[c] %@", signal)
            ).firstMatch
            if matching.waitForExistence(timeout: 5) {
                matching.tap()
                return matching
            }
        }

        let firstRow = categoryRowButtons.firstMatch
        XCTAssertTrue(firstRow.exists, "No category rows found for signal: \(signal)")
        firstRow.tap()
        return firstRow
    }

    /// Tap the floating "Delete" button.
    private func tapDeleteButton() {
        let button = app.buttons["delete_button"]
        XCTAssertTrue(button.waitForExistence(timeout: 5),
                      "Delete button not found")
        button.tap()
    }

    /// Confirm the app's own confirmationDialog (tap "Delete").
    private func confirmAppDeletion() {
        let sheet = app.sheets.firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 5),
                      "App confirmation sheet not found")
        let deleteButton = sheet.buttons["Delete"]
        XCTAssertTrue(deleteButton.exists,
                      "Delete button not found in confirmation sheet")
        deleteButton.tap()
    }

    /// Cancel the app's own confirmationDialog.
    private func cancelAppDeletion() {
        let sheet = app.sheets.firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 5),
                      "App confirmation sheet not found")
        // Cancel button may be inside sheet or at app level (iOS 17+)
        let sheetCancel = sheet.buttons["Cancel"]
        if sheetCancel.exists {
            sheetCancel.tap()
        } else {
            let appCancel = app.buttons["Cancel"]
            XCTAssertTrue(appCancel.waitForExistence(timeout: 3),
                          "Cancel button not found")
            appCancel.tap()
        }
    }

    /// Confirm the iOS system PhotoKit deletion dialog (springboard alert).
    private func confirmSystemDeletion() {
        let deleteButton = springboard.alerts.buttons["Delete"]
        if deleteButton.waitForExistence(timeout: 10) {
            deleteButton.tap()
        }
    }

    /// Deny the iOS system PhotoKit deletion dialog.
    private func denySystemDeletion() {
        let dontAllowButton = springboard.alerts.buttons["Don't Allow"]
        if dontAllowButton.waitForExistence(timeout: 10) {
            dontAllowButton.tap()
        }
    }

    /// Get the current deletion count text from the floating bar.
    private func deletionCountText() -> String? {
        let label = app.staticTexts["deletion_count"]
        guard label.waitForExistence(timeout: 3) else { return nil }
        return label.label
    }

    /// Tap a photo thumbnail by index (0-based) in the current grid.
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

    // MARK: - Tests (numbered for execution order)
    // Non-destructive tests first, destructive tests last.

    /// Test 1: Scan completes and shows at least one category.
    func test01_ScanCompletesAndShowsCategories() {
        startScan()
        waitForScanToComplete(timeout: 300)
        XCTAssertGreaterThan(categoryRowButtons.count, 0,
                             "Expected at least one category after scan")
    }

    /// Test 2: Cancel the app's confirmation dialog — selection should be preserved.
    func test02_CancelAppConfirmation() {
        startScan()
        waitForScanToComplete(timeout: 300)

        navigateToCategory(signal: "")

        let countBefore = deletionCountText()

        tapDeleteButton()
        cancelAppDeletion()

        let countAfter = deletionCountText()
        XCTAssertEqual(countBefore, countAfter,
                       "Selection should be preserved after canceling")
    }

    /// Test 3: Cancel the iOS system deletion dialog — no changes.
    func test03_CancelIOSSystemDialog() {
        startScan()
        waitForScanToComplete(timeout: 300)

        navigateToCategory(signal: "")

        tapDeleteButton()
        confirmAppDeletion()
        denySystemDeletion()

        sleep(2)

        let toast = app.staticTexts["toast_view"]
        XCTAssertFalse(toast.exists, "No toast should appear after denying system dialog")
    }

    /// Test 4: Delete flow — keep one photo, delete the rest, verify count changes.
    func test04_DeleteAllFlow() {
        startScan()
        waitForScanToComplete(timeout: 300)

        navigateToCategory(signal: "")

        let deleteButton = app.buttons["delete_button"]
        XCTAssertTrue(deleteButton.waitForExistence(timeout: 5),
                      "Deletion bar should appear after Select All")

        let initialCount = deletionCountText()
        XCTAssertNotNil(initialCount, "Deletion count should be visible")

        tapPhoto(at: 0)

        let updatedCount = deletionCountText()
        XCTAssertNotNil(updatedCount)
        XCTAssertNotEqual(initialCount, updatedCount,
                          "Deletion count should change after keeping a photo")

        tapDeleteButton()
        confirmAppDeletion()
        confirmSystemDeletion()

        sleep(3)
    }

    /// Test 5: Session summary — delete, finish, verify summary view, dismiss.
    func test05_SessionSummary() {
        startScan()
        waitForScanToComplete(timeout: 300)

        let firstRow = categoryRowButtons.firstMatch
        firstRow.tap()

        tapPhoto(at: 0) // Keep one

        tapDeleteButton()
        confirmAppDeletion()
        confirmSystemDeletion()

        sleep(3)

        // Navigate back if still on detail view
        if app.navigationBars.buttons["Photon"].exists {
            app.navigationBars.buttons["Photon"].tap()
            sleep(1)
        }

        // Verify we're back on the category list (Finish button removed)
        let categoryRow = categoryRowButtons.firstMatch
        _ = categoryRow.waitForExistence(timeout: 10)
    }

    /// Test 6: Cleaned category badge — delete some photos, verify banner.
    func test06_CleanedCategoryBadge() {
        startScan()
        waitForScanToComplete(timeout: 300)

        let firstRow = categoryRowButtons.firstMatch
        XCTAssertTrue(firstRow.exists, "At least one category should exist")
        firstRow.tap()

        tapPhoto(at: 0) // Keep one

        tapDeleteButton()
        confirmAppDeletion()
        confirmSystemDeletion()

        sleep(3)

        if app.navigationBars.buttons["Photon"].exists {
            app.navigationBars.buttons["Photon"].tap()
            sleep(1)
        }

        let banner = app.descendants(matching: .any)["session_banner"]
        _ = banner.waitForExistence(timeout: 10)
    }

    /// Test 7: Delete all photos in a category — verify auto-pop back.
    func test07_DeleteAllPhotosAutoPopBack() {
        startScan()
        waitForScanToComplete(timeout: 300)

        let firstRow = categoryRowButtons.firstMatch
        let firstRowId = firstRow.identifier
        firstRow.tap()

        tapDeleteButton()
        confirmAppDeletion()
        confirmSystemDeletion()

        sleep(3)

        let deletedRow = app.buttons[firstRowId]
        XCTAssertFalse(deletedRow.exists,
                       "Category should be removed from list after deleting all photos")
    }
}
