#!/bin/bash
set -euo pipefail

# E2E test runner for Photon — generates test photos, loads them into
# the simulator, and runs XCUITests.
#
# Uses build-for-testing + grant + test-without-building to ensure
# photo library permission is granted after the app is installed.
#
# Destructive tests (04-07) each delete photos, so we reload test photos
# into the simulator before each one.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
SIM_UDID="A8DF1AFA-6BB2-4CA0-A8F8-4EA9D0989DC6"  # iPhone 17 Pro
BUNDLE_ID="com.photonapp.photon"
TEST_CLASS="PhotonUITests/PhotonE2ETests"
PERSISTENCE_CLASS="PhotonUITests/PhotonPersistenceTests"

echo "=== Photon E2E Test Runner ==="
echo ""

# Step 1: Generate test photos
echo "[1/7] Generating test photos..."
python3 "$SCRIPT_DIR/generate_test_photos.py"
echo ""

# Step 2: Regenerate Xcode project
echo "[2/7] Regenerating Xcode project..."
cd "$PROJECT_DIR"
xcodegen generate
echo ""

# Step 3: Boot simulator
echo "[3/7] Booting simulator..."
xcrun simctl boot "$SIM_UDID" 2>/dev/null || echo "  (Simulator already booted)"
sleep 5

# Step 4: Add test photos to simulator
echo "[4/7] Adding test photos to simulator..."
xcrun simctl addmedia "$SIM_UDID" "$SCRIPT_DIR/test_photos/"*.jpg
echo "  Added $(ls "$SCRIPT_DIR/test_photos/"*.jpg | wc -l | tr -d ' ') photos"
echo ""

# Step 5: Build and install (this clears TCC entries)
echo "[5/7] Building and installing..."
xcodebuild build-for-testing \
  -project "$PROJECT_DIR/Photon.xcodeproj" \
  -scheme PhotonUITests \
  -destination "platform=iOS Simulator,id=$SIM_UDID" \
  -quiet
echo "  Build complete"
echo ""

# Step 6: Grant photo library permission AFTER install
echo "[6/7] Granting photo library permission..."
xcrun simctl privacy "$SIM_UDID" grant photos "$BUNDLE_ID"
xcrun simctl privacy "$SIM_UDID" grant photos-add "$BUNDLE_ID"
echo "  Permission granted"
echo ""

# Helper: run a single test (or group) without rebuilding
run_test() {
  local test_name="$1"
  xcodebuild test-without-building \
    -project "$PROJECT_DIR/Photon.xcodeproj" \
    -scheme PhotonUITests \
    -destination "platform=iOS Simulator,id=$SIM_UDID" \
    -test-timeouts-enabled YES \
    -maximum-test-execution-time-allowance 600 \
    -only-testing:"$test_name" \
    2>&1 | grep -E '(Test Case|passed|failed|error:|Executed)' || true
}

# Helper: reload test photos into the simulator
reload_photos() {
  echo "  Reloading test photos..."
  xcrun simctl addmedia "$SIM_UDID" "$SCRIPT_DIR/test_photos/"*.jpg 2>/dev/null
}

echo "[7/7] Running XCUITests..."
echo "  (Each test rescans photos; expect ~30s per test)"
echo ""

FAILED=0

# --- Non-destructive tests (01-03): run together, photos stay intact ---
echo "--- Running non-destructive tests (01-03) ---"
run_test "$TEST_CLASS/test01_ScanCompletesAndShowsCategories" || FAILED=1
run_test "$TEST_CLASS/test02_CancelAppConfirmation" || FAILED=1
run_test "$TEST_CLASS/test03_CancelIOSSystemDialog" || FAILED=1
echo ""

# --- Destructive tests (04-07): reload photos before each ---
for test in test04_DeleteAllFlow test05_SessionSummary test06_CleanedCategoryBadge test07_DeleteAllPhotosAutoPopBack; do
  echo "--- Running $test ---"
  reload_photos
  run_test "$TEST_CLASS/$test" || FAILED=1
  echo ""
done

# --- Persistence + paywall tests (08-13): each resets its own state ---
# These use -resetForTesting launch arg, so no photo reload needed between tests.
# Exception: test11 deletes photos, so reload before it.
echo "--- Running persistence + paywall tests (08-13) ---"
reload_photos
run_test "$PERSISTENCE_CLASS/test08_PersistenceRestoresAfterRelaunch" || FAILED=1
run_test "$PERSISTENCE_CLASS/test09_RescanShowsPaywall" || FAILED=1
run_test "$PERSISTENCE_CLASS/test10_KillDuringScanShowsWelcomeOnRelaunch" || FAILED=1
echo ""

echo "--- Running test11 (deletion persistence, needs fresh photos) ---"
reload_photos
run_test "$PERSISTENCE_CLASS/test11_DeletionPersistsAcrossRelaunch" || FAILED=1
echo ""

echo "--- Running test12 (purchase flow) ---"
reload_photos
run_test "$PERSISTENCE_CLASS/test12_PurchaseUnlocksRescan" || FAILED=1
echo ""

echo "--- Running test13 (first scan free) ---"
run_test "$PERSISTENCE_CLASS/test13_FirstScanIsFree" || FAILED=1
echo ""

if [ "$FAILED" -ne 0 ]; then
  echo "=== Some tests failed. Check output above for details. ==="
  exit 1
fi

echo "=== All E2E tests passed! ==="
