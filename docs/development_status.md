# Photon — Development Status & Session Notes

Last updated: 2026-02-28

---

## Milestone Status

### Milestone 1: On-Device Intelligence — COMPLETE
Scan pipeline fully working on a real iPhone 11 with ~3,600 photos:
- PhotoKit integration (fetch all photos + videos)
- MobileCLIP S2 Core ML embedding generation (progressive, with progress UI)
- Blur detection via Apple Vision Framework (Laplacian variance)
- Brightness scoring and document detection
- Multi-signal grouping pipeline (near-duplicates, blur, temporal bursts, screenshots, large files)
- Confidence scoring (high/medium/low) and category ranking
- Category list with collapse logic per signal type

### Milestone 2: Core Deletion Flow — COMPLETE
Full deletion workflow tested on physical device:
- Category-by-category review with photo grid
- Selection model: all photos start selected for deletion, tap to keep (deselect)
- Green checkmark = selected for deletion, empty circle = kept
- Floating deletion bar with photo count and byte estimate
- Double-confirm deletion: app confirmation dialog + iOS system dialog
- "Delete & Don't Ask Again" option (skips app dialog after first use)
- Session stats tracking: photos deleted, bytes freed, categories cleaned
- Category status badges: "Viewed" (eye icon) and "Cleaned" (green checkmark + strikethrough)
- Long-press photo preview with drag-to-dismiss and in-preview selection toggle
- Auto-pop back to category list when all photos in a category are deleted
- Deleted photos pruned from master asset array and all categories

**Deferred from Milestone 2 (intentionally skipped):**
- Onboarding screens / deletion goal question — deferred until Cloud AI can use it effectively
- Representative sample picks / yes-no voting — current "all-selected grid" flow is efficient enough

### Milestone 3: Cloud AI Integration — NOT STARTED
Proposed approach (discussed, not finalized):
- **Goal:** Improve photo understanding to make deletion decisions easier
- **3a (validate):** Direct GPT-4o API call from app, send 2-3 representative thumbnails per category, get back descriptive labels + deletion rationale + best photo suggestion
- **3b (production):** AWS Lambda proxy, credit system, auth tokens, rate limiting
- **Key improvements:** descriptive category labels ("41 photos of your dog on the couch" vs generic template), deletion rationale, best photo pick for "Keep Best" groups

### Milestones 4-6: NOT STARTED
- Milestone 4: Return user experience (incremental scan, persist decisions, preference model)
- Milestone 5: Polish & QA (performance, edge cases, accessibility)
- Milestone 6: App Store submission

---

## UX Issues Fixed (Milestone 2 Polish)

During on-device testing, 16 issues were identified and resolved:

| # | Issue | Fix |
|---|-------|-----|
| 1 | 5-10s delay after "Start Scanning" | Added `.preparing` state + parallel model loading via `Task.detached` |
| 2 | Photo grid misalignment | Rewrote `PhotoThumbnailView` with `Color.clear.overlay` pattern for uniform square cells |
| 3 | Extra tap needed to start selection | Auto-enter selection mode in `.onAppear` |
| 4.1 | Double confirmation gets tiring | `@AppStorage("skipAppConfirmation")` + "Delete & Don't Ask Again" option |
| 4.2 | Deleted photos still showing in grid | Prune `photoService.allAssets` + use updated category after deletion |
| 5 | Confusing toolbar button | Removed; merged with auto-selection (issue 3) |
| 6 | Selection model backwards | Inverted: `selectedIDs` = photos to DELETE, all start selected |
| 7 | Category badges too small | Larger font, icon added, capsule background, `.fixedSize()` |
| 8 | No visited vs cleaned distinction | "Viewed" badge + "Cleaned" badge with strikethrough and opacity |
| 9 | "Finish" button does nothing | Removed from toolbar |
| 10 | No way to enlarge photos | Long-press preview overlay with drag-to-dismiss |
| 11 | App freeze regression | Fixed `async let` blocking main actor; used `Task.detached` + `Task.yield()` |
| 12 | "Requesting Access" shown when authorized | Check existing permission before prompting |
| 13 | Grid still misaligned (ZStack sizing) | `Color.clear.overlay` pattern instead of `ZStack` with `scaledToFill` |
| 14 | Selection circles cut off | Fixed by `.overlay(alignment: .topTrailing)` on fixed-size cell |
| 15 | Badge text wrapping ("Ke ep B es t") | `.fixedSize()` on badge HStack, `.lineLimit(1)` on stats text |
| 16 | Selection circles not showing "selected" | Flipped visual: green = selected for deletion, empty = kept |

---

## Manual Regression Tests

Perform these on a physical device after any code change:

### Scan Flow
1. **Cold start scan:** Open app → tap "Start Scanning" → should see "Preparing..." instantly (no 5-10s blank delay)
2. **Permission skip:** If already authorized, should NOT show "Requesting Access" screen
3. **Progress updates:** Scan should show "Analyzing photos... X/Y" with progress bar
4. **Scan completion:** Category list appears with summary card (photos scanned, groups found, to review)
5. **Empty library:** If no photos, should show "No photos found" / "Your library looks clean"

### Category List
6. **Confidence sections:** Categories sorted into "Likely to Delete" (green), "Maybe Delete" (orange), "Probably Keep" (blue)
7. **Badge layout:** "Keep Best" and "Delete All" badges should be on one line, not wrapping
8. **Stats text:** "15 photos" and "40.3 MB" should stay on one line, even when "Viewed"/"Cleaned" badge is showing
9. **Collapse logic:** If a signal type has many groups, excess groups collapse into "N more ... groups" row

### Photo Grid (CategoryDetailView)
10. **Uniform grid:** All photo cells are identical squares in a 3-column grid with 2pt spacing
11. **Auto-selection:** All photos start with green checkmarks (selected for deletion)
12. **Tap to keep:** Tap a photo → green checkmark disappears (empty circle = kept), deletion count decreases
13. **Tap to re-select:** Tap a kept photo again → green checkmark returns, deletion count increases
14. **Selection circles visible:** Top-right checkmark circles never cut off or hidden
15. **Deletion count:** Bottom bar shows correct "N photos to delete" and "Frees X MB"

### Long-Press Preview
16. **Trigger speed:** Long-press (0.15s) shows full-screen preview quickly
17. **Nav bar hidden:** No "<" back button or "Cancel" button from the grid view showing through
18. **Close button:** X button (top-left) returns to photo grid, NOT to category list
19. **Selection circle:** Top-right circle in preview matches the photo's selection state in the grid
20. **Toggle in preview:** Tapping the selection circle in preview toggles the photo's state (grid updates on dismiss)
21. **Drag to dismiss:** Swipe down closes the preview

### Deletion Flow
22. **App confirmation:** Tap Delete → app dialog appears with "Delete", "Delete & Don't Ask Again", "Cancel"
23. **Cancel preserves selection:** Cancel the app dialog → selection unchanged
24. **iOS system dialog:** After app confirmation, iOS system "Delete N items?" dialog appears
25. **Deny system dialog:** Tapping "Don't Allow" → no changes, no toast
26. **Successful deletion:** Confirm both dialogs → toast shows "Deleted N photos — X freed"
27. **Grid refresh:** After deletion, grid only shows remaining photos (no stale thumbnails)
28. **Auto-pop:** If all photos deleted, automatically navigate back to category list
29. **Skip app dialog:** After choosing "Don't Ask Again", future deletes skip the app dialog (go straight to iOS dialog)

### Session Tracking
30. **Session banner:** After first deletion, category list shows stats banner (deleted count, bytes freed, categories cleaned)
31. **Viewed badge:** Opening a category marks it "Viewed" (eye icon, 0.85 opacity)
32. **Cleaned badge:** Deleting from a category marks it "Cleaned" (green checkmark, strikethrough, 0.5 opacity)
33. **Category removal:** If all photos in a category are deleted, the category row disappears from the list

---

## Deployment to Physical Device

### Prerequisites
- iPhone connected via USB cable
- iPhone unlocked and trusted ("Trust This Computer" accepted)
- Xcode command-line tools installed
- Developer signing configured in `Photon.xcodeproj`

### Build & Deploy Commands

```bash
# 1. Find your device identifier
xcrun devicectl list devices

# 2. Clean both build caches (important — stale caches cause "changes not showing" issues)
rm -rf /Users/tonyli/Desktop/photon_app/build
rm -rf ~/Library/Developer/Xcode/DerivedData/Photon-*

# 3. Build for iOS device
xcodebuild clean build \
  -scheme Photon \
  -destination 'generic/platform=iOS' \
  -derivedDataPath /Users/tonyli/Desktop/photon_app/build \
  2>&1 | tail -3

# 4. Uninstall old app (prevents stale bundle caching)
xcrun devicectl device uninstall app \
  --device <DEVICE_ID> \
  com.lihuangxiao.photon

# 5. Install fresh build
xcrun devicectl device install app \
  --device <DEVICE_ID> \
  /Users/tonyli/Desktop/photon_app/build/Build/Products/Debug-iphoneos/Photon.app
```

**Current device ID:** `E6406AA7-904F-5CED-B10E-2F70581C0BB0` (iPhone 11)

### Troubleshooting

| Problem | Cause | Fix |
|---------|-------|-----|
| Changes not showing on device | Stale build cache | Delete BOTH `build/` and `~/Library/Developer/Xcode/DerivedData/Photon-*` before building |
| `devicectl` times out | Phone locked or disconnected | Unlock phone, reconnect USB, retry |
| `xcodebuild install` doesn't deploy | Wrong command | Use `xcrun devicectl device install app`, NOT `xcodebuild install` |
| App freezes on scan start | Main actor blocked | Ensure model loading uses `Task.detached`, not `async let` |

---

## E2E UI Tests (Simulator)

Tests are in `PhotonUITests/PhotonE2ETests.swift`. Run on simulator only (requires test photos loaded).

```bash
# Setup: load test photos into simulator
scripts/run_e2e_tests.sh

# Or run tests manually:
xcodebuild test \
  -scheme PhotonUITests \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -derivedDataPath build
```

**7 tests:** scan completion, cancel app dialog, cancel iOS dialog, delete flow, session summary, cleaned badge, delete-all auto-pop.

**Known issue:** iOS 26.2 simulator has TCC permission flakiness. May need to erase simulator (`xcrun simctl erase`) between test runs if permissions fail.

---

## Project Structure

```
photon_app/
├── Photon/
│   ├── App/PhotonApp.swift              # App entry point
│   ├── ML/mobileclip_s2_image.mlpackage # Core ML model (~68MB, Git LFS)
│   ├── Models/                          # PhotoAsset, PhotoCategory, SessionStats
│   ├── Resources/                       # Info.plist, Assets.xcassets
│   ├── Services/                        # EmbeddingService, BlurDetectionService,
│   │                                    # GroupingPipeline, ScoringService,
│   │                                    # PhotoLibraryService, DeletionService
│   ├── ViewModels/ScanViewModel.swift   # Scan pipeline orchestration
│   └── Views/                           # All SwiftUI views
├── PhotonUITests/PhotonE2ETests.swift   # E2E UI tests
├── docs/
│   ├── product_deck.md                  # Full product specification
│   └── development_status.md            # This file
├── scripts/                             # Test photo generator, E2E runner
├── project.yml                          # XcodeGen project definition
└── Photon.xcodeproj/                    # Generated Xcode project
```

## Git Setup

- **Branch:** `main`
- **Git LFS:** Tracks `*.bin` and `*.mlmodel` (MobileCLIP model weights)
- **`.gitignore`:** Excludes `build/`, `DerivedData/`, `xcuserdata/`, `.DS_Store`, `.claude/`
