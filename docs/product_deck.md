# Photon App - Product Deck & Plan of Action
### Working Title: Photon | Photo Cleanup App for iOS
### Last Updated: 2026-02-26

---

## 1. Product Vision

**One-liner:** An AI-powered photo cleanup app that helps users delete unwanted photos in the most efficient and user-friendly way possible.

**Core Insight:** Existing apps are either "swipe left/right on every photo" (exhausting) or "here are your duplicates" (limited). No app combines intelligent categorization with a guided, progressive workflow that makes a 10,000+ photo library feel manageable.

**Key Differentiators:**
- Category-by-category guided deletion workflow (not per-photo)
- Multi-signal scoring algorithm (visual similarity + metadata + photo type + temporal patterns)
- Tiered AI: on-device for speed/privacy, cloud AI for deeper intelligence
- Trust-first design: double confirmation, per-session privacy consent, generous free tier
- Progressive results: start showing value within seconds, not minutes

---

## 2. Target Audience

**Primary:** Casual phone users (broad demographic)
- 2,000-10,000 photos
- Phone says "storage full" or feels cluttered
- Non-technical, values simplicity and trust
- Has never used a photo cleanup app before

**Secondary:** Photo hoarders
- 10,000-50,000+ photos
- Knows they have a problem, feels overwhelmed
- Willing to pay for a tool that actually works

**Adaptive approach:** The app detects user type through behavior (library size, response patterns) and adjusts the workflow accordingly -- more aggressive suggestions for willing deleters, gentler for cautious users.

---

## 3. Core Workflow

### Step 1: Onboarding & Goal Setting
- Request photo library access (full access required)
- Soft deletion goal question: **"Do you have a goal for deleting photos?"**
  - A) A majority of them
  - B) A lot, but I don't know how many
  - C) Some, but I don't know how many
  - D) I don't know
- This calibrates the aggressiveness of suggestions throughout the session

### Step 2: Progressive Scan (On-Device)
- Immediately begin scanning with MobileCLIP (Core ML)
- Start with most recent 3 months (results in ~5-10 seconds)
- Show progressive results as scanning continues: "Found 200 screenshots so far..."
- Generate embeddings (~3-7ms/photo), cluster by visual similarity
- Cross-reference with metadata: timestamps, file sizes, photo type (screenshot/burst/Live Photo)
- Apply multi-signal scoring algorithm to assign deletion confidence per cluster
- UI: Animated progress screen showing categories emerging in real-time

### Step 3: Category-by-Category Review

**3.1 High-confidence categories found:**
1. Present category: grid overview of all photos + 3-5 representative highlighted photos
2. Explain the category (template: "We found [N] similar [type] photos from [date range]")
3. User reviews representative samples with yes/no
4. If all yes → ask permission to delete entire category (→ Apple system dialog)
5. If all no → skip category, move to next
6. If mixed → offer to sub-categorize or let user manually select from grid

**3.2 High-confidence categories exhausted:**
1. Move to medium-confidence categories (lower threshold for suggestions)
2. Adaptive sampling: use diverse samples (not just representative) to avoid false positives
3. If no more suggestions: inform user and offer to exit

**3.3 Cloud AI integration (when available):**
- Triggered when on-device analysis isn't confident enough
- Per-session user consent: "For better results, we can analyze these photos with our AI. No photos are stored. Allow?"
- Tiered disclosure: send embeddings + metadata first; request permission for thumbnails only if needed
- Cloud AI provides: better categorization, natural language explanations, behavioral pattern detection

### Step 4: Deletion
- App-level confirmation: summary screen ("Delete 47 photos from this category?")
- iOS system confirmation: mandatory Apple dialog ("Delete 47 photos?")
- Photos move to iOS "Recently Deleted" (recoverable for 30 days)
- Double confirmation positioned as safety feature: "Extra safe - confirmed twice"

### Step 5: Progress & Completion
- Running tally: "You've freed up 2.3 GB so far"
- Session summary when done: total photos reviewed, deleted, storage freed
- Encourage return: "Come back anytime - we'll scan new photos automatically"

---

## 4. Return User Experience

- Remember all previous decisions (categories accepted/rejected)
- Incremental scan: only process new photos since last session
- Dashboard on return: "Last cleanup: 3 days ago. 47 new photos since then."
- Build a preference model: user always deletes screenshots → boost screenshot detection next time
- Don't re-suggest rejected categories unless they've grown significantly

---

## 5. Scoring Algorithm (On-Device)

**Multi-signal weighted scoring for "likely to delete" confidence:**

| Signal | Weight | Rationale |
|--------|--------|-----------|
| Cluster size | High | 200 similar photos = likely junk; 3 unique photos = likely meaningful |
| Photo type | High | Screenshots, burst photos get a base score boost |
| Visual content | Medium | MobileCLIP embedding classification (game UI, receipt, meme, etc.) |
| Age | Medium | Older photos in large clusters more likely deletable |
| Temporal density | Medium | 50 similar photos in 1 day = burst behavior, likely deletable |
| File size | Low | Very large files (videos) get flagged for storage impact |
| Recency | Negative | Very recent photos get score penalty (user might still need them) |

Final score → Categorized as: **High confidence** / **Medium confidence** / **Low confidence** / **Keep**

---

## 6. Technical Architecture

### iOS App (Native Swift)
- **Language:** Swift 5.9+
- **UI Framework:** SwiftUI (primary), UIKit for performance-critical photo grids
- **Photo Access:** PhotoKit (PHAsset, PHFetchResult, PHCachingImageManager)
- **On-Device ML:** Core ML + Apple Vision Framework
- **Embedding Model:** MobileCLIP-S1 (or S0 for broader device support)
- **Local Storage:** Core Data or SQLite for embeddings, user decisions, session history
- **Minimum iOS:** iOS 17+ (for latest SwiftUI features + stable Core ML performance)
- **Target Devices:** iPhone (iPad later)

### Backend (Serverless - Python)
- **Platform:** AWS Lambda + API Gateway
- **Language:** Python 3.12
- **Database:** DynamoDB (user accounts, credit balances, usage logs)
- **AI Proxy:** Lambda function that forwards requests to OpenAI GPT-4o API
- **Auth:** Anonymous device-based tokens (no account required for free tier)
- **Payments:** App Store Server API for receipt validation (StoreKit 2 on client)

### Cloud AI (OpenAI GPT-4o)
- **Provider:** OpenAI GPT-4o (cheapest vision model, ~$0.15/M input tokens)
- **Abstraction:** Provider interface so we can swap to Claude/Gemini later
- **Input Tier 1:** Embedding vectors + metadata (timestamps, cluster info, photo types)
- **Input Tier 2:** Low-res thumbnails (256x256) for specific groups needing deeper analysis
- **Output:** Category labels, confidence scores, natural language explanations
- **Cost estimate:** ~$0.01-0.05 per user session (depending on library size and tier)

### Architecture Diagram
```
┌─────────────────────────────────────────────────────┐
│                    iOS App (Swift)                    │
│                                                       │
│  ┌─────────────┐  ┌──────────────┐  ┌─────────────┐ │
│  │  PhotoKit    │  │  Core ML     │  │  SwiftUI    │ │
│  │  (Photos)    │  │  MobileCLIP  │  │  (UI)       │ │
│  │             │  │  Vision FW   │  │             │ │
│  └──────┬──────┘  └──────┬───────┘  └─────────────┘ │
│         │                │                            │
│  ┌──────┴────────────────┴───────┐                   │
│  │     Local SQLite/CoreData     │                   │
│  │  (embeddings, decisions, etc) │                   │
│  └───────────────────────────────┘                   │
│                    │                                  │
│         (per-session user consent)                    │
└────────────────────┼──────────────────────────────────┘
                     │ HTTPS
          ┌──────────┴──────────┐
          │   API Gateway (AWS)  │
          └──────────┬──────────┘
                     │
          ┌──────────┴──────────┐
          │  Lambda Functions    │
          │  (Python)            │
          │  - AI Proxy          │
          │  - Receipt Validator │
          │  - Credit Manager    │
          └──────────┬──────────┘
                     │
          ┌──────────┴──────────┐
          │   OpenAI GPT-4o API  │
          │   (abstracted)       │
          └─────────────────────┘
```

---

## 7. Business Model

### Free Tier (majority of casual users)
- Unlimited on-device photo analysis
- Visual similarity grouping + scoring
- Template-based category explanations
- Full deletion workflow
- N free cloud AI credits on signup (exact N to be determined based on cost analysis)

### Paid Tier (power users who want more AI)
- **Credit Packs (one-time):**
  - Small: $2.99 for 500 cloud AI analyses
  - Medium: $9.99 for 2,000 cloud AI analyses
  - Large: $19.99 for 5,000 cloud AI analyses
- **Subscription (optional):**
  - $1.99/month or $9.99/year for unlimited cloud AI
- Users choose whichever model suits them

### Pricing Philosophy
- Most casual users should delete tons of easy-to-identify photos without paying anything
- Cloud AI credits prove their value before users need to buy more
- Dramatically cheaper than competitors ($5-10/week subscriptions)
- No ads, ever
- No dark patterns, no trial-to-subscription traps

---

## 8. Privacy Policy

- **Default:** All analysis happens on-device. No data leaves the phone.
- **Cloud AI (opt-in):** Per-session user consent with clear explanation
- **Tiered disclosure:** Embeddings + metadata sent first. Thumbnails only with additional permission for specific photo groups.
- **No storage:** Cloud AI requests are processed and immediately discarded. No photos or embeddings are stored on servers.
- **No tracking:** Minimal analytics (app opens, features used, deletion counts). No ad networks. No selling data.
- **Compliance:** GDPR and CCPA compliant by design (minimal data collection, user consent, right to deletion).

---

## 9. MVP Scope (v1.0)

### Included in MVP
- [x] Photo library access and scanning
- [x] On-device MobileCLIP embedding generation (progressive)
- [x] Multi-signal scoring algorithm (visual + metadata + type + temporal)
- [x] Visual similarity clustering
- [x] Category-by-category review flow
- [x] Grid overview + representative/diverse sample picks (adaptive)
- [x] "Delete goal" soft question (A/B/C/D)
- [x] Template-based category explanations
- [x] Cloud AI integration (GPT-4o) with free credits
- [x] Per-session cloud AI consent flow
- [x] Double-confirm deletion (app + iOS system dialog)
- [x] Progress tracking (storage freed, photos deleted)
- [x] Session summary
- [x] Remember previous decisions (return user awareness)
- [x] Clean, simple SwiftUI interface
- [x] Serverless backend (AWS Lambda, Python)
- [x] Basic credit system (free credits, no payment yet in v1 if needed to ship faster)

### Deferred to v2+
- [ ] In-app purchases / subscriptions (StoreKit 2)
- [ ] Natural language user-directed search ("delete my lecture photos")
- [ ] Behavioral pattern detection (beyond visual + metadata)
- [ ] On-device LLM fallback (Apple Foundation Models)
- [ ] Advanced sub-categorization within categories
- [ ] Android version
- [ ] Photo organization features (albums, favorites)
- [ ] iPad support
- [ ] Widgets / Share extensions
- [ ] Social features / sharing cleanup stats

---

## 10. Development Milestones

### Milestone 1: Thin Vertical Slice — On-Device Intelligence (Validate Core Bet)
The goal is to answer: **does the AI grouping actually work well on real photo libraries?**

**Build:**
- Xcode project setup with SwiftUI
- PhotoKit integration: request permissions, fetch all photos
- Integrate MobileCLIP Core ML model (S0 or S1)
- Generate embeddings for all photos with progressive background processing
- Store embeddings in local SQLite/Core Data database
- Implement clustering algorithm (DBSCAN or k-means on embeddings)
- Multi-signal scoring: visual similarity + photo type (screenshot/burst/Live Photo) + temporal density + recency
- Rank and display categories by confidence score

**See/Use/Test:**
1. Open app → grant photo permission
2. Watch progressive scan ("Scanning... 500/3,000 photos")
3. See categories appear in real-time as scanning progresses:
   - "47 similar screenshots" (High confidence)
   - "23 burst photos from Tuesday" (High confidence)
   - "156 travel photos" (Low confidence)
4. Tap a category → see photo grid of all photos in that group
5. See confidence scores on each group

**Validate:**
- Is MobileCLIP grouping photos sensibly on YOUR real library?
- Are the confidence scores reasonable? (High-confidence groups = actually junk?)
- How fast does scanning feel on a real device?
- Does it handle your full library size without crashing or freezing?
- Are there obvious mis-groupings or categories that make no sense?

**No deletion, no backend, no cloud AI, no onboarding polish.**

### Milestone 2: Core Deletion Flow
- Onboarding screens (permissions, deletion goal A/B/C/D question)
- Category review screen: grid overview + representative/diverse sample picks
- Yes/No voting on sample photos
- Adaptive sampling: representative for high-confidence, diverse for medium
- Bulk deletion confirmation screen → PhotoKit deleteAssets → iOS system dialog
- Progress tracking: running tally of photos deleted and storage freed
- Session summary screen

### Milestone 3: Cloud AI Integration
- AWS Lambda functions (Python): AI proxy, credit manager
- API Gateway setup with device-based auth tokens
- OpenAI GPT-4o integration (embeddings + metadata → enhanced categories + explanations)
- Per-session consent flow in iOS app
- Tiered disclosure: embeddings first, thumbnail upgrade with permission
- Template-based explanations as fallback when no cloud AI
- Free credit allocation and tracking

### Milestone 4: Return User Experience
- Persist user decisions in local database
- Incremental scanning (only new photos since last session)
- Dashboard home screen for return visits
- Preference model: adjust scoring based on past accept/reject decisions
- Don't re-suggest rejected categories unless significantly grown

### Milestone 5: Polish & QA
- Performance optimization for large libraries (10K+ photos)
- Error handling and edge cases (permissions denied, empty library, low storage)
- Memory management for photo processing
- UI polish, animations, transitions
- Progressive scan animation refinement
- Accessibility (VoiceOver, Dynamic Type)
- Battery impact testing

### Milestone 6: App Store Submission
- App Store metadata (screenshots, description, keywords)
- Privacy policy and terms of service
- App Store review notes (explain deletion feature, emphasize safety)
- TestFlight beta testing
- Submit for review

---

## 11. Key Risks & Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| Swift learning curve (Python dev) | Dev speed | Heavy AI-assisted coding (Claude Code). Swift/SwiftUI is readable and well-documented. |
| MobileCLIP accuracy insufficient | Core product value | Test early with real photo libraries. Fall back to Vision framework classification if needed. Supplement with cloud AI. |
| App Store rejection | Launch delay | Follow all guidelines strictly. Prepare detailed review notes. Avoid any claim of "permanent deletion." |
| Cloud AI costs exceed budget | Business model | Generous but bounded free tier. Monitor usage closely. GPT-4o is cheapest option. |
| Users don't trust the app with deletion | Adoption | Double-confirmation, clear explanations, on-device default, transparent privacy policy. |
| Large libraries cause performance issues | UX quality | Progressive scanning, thumbnail-first loading, background processing, pagination. |
| Low differentiation from competitors | Market position | Workflow is genuinely novel. No competitor does category-by-category guided deletion with adaptive AI. |

---

## 12. Competitive Positioning

```
                    Simple UX ──────────────────── Complex UX
                         │                              │
  AI-Powered ─── ┌──────┼──────────────────────────────┤
                  │      │                              │
                  │  Photon (us)          CleanMyPhone  │
                  │      │                              │
                  │  Clever Cleaner       Smart Cleaner │
                  │      │                              │
                  │  SnapSift                           │
  Manual ──────── ├──────┼──────────────────────────────┤
                  │      │                              │
                  │  Flic              Slidebox          │
                  │      │                              │
                  │  Swipe Delete      GetSorted         │
                  │      │                              │
                  └──────┴──────────────────────────────┘
```

**Our position:** AI-powered + Simple UX. The intelligence is in the background; the user experience is effortless.

---

## 13. Market Context

- Global Mobile Cleaner App Market: ~$620M (2025), projected ~$1.56B by 2033
- 60% of people never delete photos (massive addressable market)
- Average user: 2,000-5,000 photos, ~20 new photos/day
- Users spend $260-520/year on predatory subscription apps
- Market is hungry for a trustworthy, fairly-priced alternative
- Apple's built-in duplicate detection (iOS 16+) only catches exact duplicates, leaving significant room for smarter tools

---

*This is a living document. Updated as decisions evolve.*
