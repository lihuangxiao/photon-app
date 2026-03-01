# Photon — App Store Metadata

## App Name
Photon

## Subtitle (30 chars max)
AI Photo Cleanup

## Description

Photon uses on-device AI to find groups of similar, blurry, and unnecessary photos cluttering your library — so you can free up storage in minutes.

**How it works:**
1. Tap "Start Scanning" — Photon analyzes your entire photo library on-device
2. Review organized groups: near-duplicates, blurry shots, old screenshots, dark photos, and more
3. Delete what you don't need with a single tap — photos go to Recently Deleted so you can recover them for 30 days

**What Photon finds:**
- Near-duplicate photos (similar shots from the same moment)
- Blurry and out-of-focus photos
- Screenshots and screen recordings
- Dark and underexposed photos
- Old unfavorited photos
- Documents, receipts, and whiteboard photos
- Saved/received images from messaging apps
- Large videos taking up storage
- Burst photos and Live Photos
- Trip photo collections

**Privacy first:**
- All analysis happens on your device — no photos leave your phone
- No accounts, no tracking, no ads
- Deletion is always double-confirmed for safety

**Free to try:**
- Your first scan is completely free
- Unlock unlimited scans with a one-time $1.99 purchase

Clean up your photo library the smart way.

## Keywords (100 chars max)
photo cleanup,delete photos,storage,duplicates,similar photos,photo organizer,free up space,AI

## What's New (v1.0.0)
Initial release — AI-powered photo cleanup that finds groups of similar, blurry, and screenshot photos to help you free up storage.

## Category
- **Primary:** Utilities
- **Secondary:** Photo & Video

## Age Rating
4+ (no objectionable content)

## Price
Free (with In-App Purchase)

---

## App Review Notes

Photon analyzes the user's photo library entirely on-device using Apple's Core ML and Vision frameworks. No server calls are made for photo analysis.

Key points for review:

1. **Photo library access:** Required for core functionality. The app analyzes photos to find groups of similar, blurry, and unnecessary images.

2. **Deletion behavior:** Photos are moved to the iOS "Recently Deleted" album (recoverable for 30 days). Deletion requires double confirmation — first an in-app confirmation dialog, then the iOS system deletion dialog. This is an intentional safety feature.

3. **In-App Purchase:** One non-consumable IAP ("Photon Pro", $1.99) unlocks unlimited scans. The first scan is free. Restore Purchases is available on the Paywall screen and in the Settings screen.

4. **No account required:** The app works without any sign-in or account creation.

5. **No data collection:** No analytics, no tracking, no ad networks. All data stays on device.

6. **Demo account:** N/A — no accounts exist. To test, simply allow photo library access and tap "Start Scanning."

---

## Screenshot Checklist (iPhone 6.7" — required)

Capture from iPhone 15 Pro Max simulator (or 6.7" device):

1. **Welcome screen** — Shows "Smart Photo Cleanup" with "Start Scanning" button and "First scan is free"
2. **Scan in progress** — "Analyzing" phase with progress bar
3. **Category list** — Main results screen showing groups sorted by confidence (Likely to Delete / Maybe Delete / Probably Keep)
4. **Photo grid with selection** — Inside a category, showing photo thumbnails with green checkmarks for selection
5. **Deletion confirmation** — The confirmation dialog or session stats banner showing deleted count and space freed
6. **Paywall** (optional) — "Unlock Photon Pro" screen showing features and price

### How to capture simulator screenshots:
```bash
# Boot the simulator
xcrun simctl boot "iPhone 15 Pro Max"

# Take a screenshot
xcrun simctl io booted screenshot screenshot_1_welcome.png
```

Or use Cmd+S in the Simulator app.
