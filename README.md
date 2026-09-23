# Family Food Scanner (SwiftUI starter)

Scan a grocery barcode, look it up in Open Food Facts, and score it for every
family member based on their conditions, allergies and goals.

## What's included

| Folder | What it does |
|---|---|
| `App/` | App entry point, injects the family store and HealthKit manager |
| `Models/` | Members, conditions, allergens, goals, products, scores |
| `Services/ScoringEngine.swift` | Rule-based scoring with a readable reason for every deduction |
| `Services/ProductService.swift` | Open Food Facts barcode lookup |
| `Services/HealthKitManager.swift` | Requests read access and loads the device owner's latest health values |
| `Services/FamilyStore.swift` | Sample family data (replace with backend sync later) |
| `Views/` | Scan, result and family screens, plus the VisionKit scanner wrapper |
| `Tests/` | Unit tests for the scoring engine |

## Setup in Xcode

1. **New project:** File → New → Project → iOS App. Name it `FamilyFoodScanner`, interface SwiftUI, and include tests. Set the deployment target to **iOS 17**.
2. **Add the files:** delete the generated `ContentView.swift` and `FamilyFoodScannerApp.swift`, then drag in `App/`, `Models/`, `Services/` and `Views/`. Add `Tests/ScoringEngineTests.swift` to the test target.
3. **Add HealthKit:** target → Signing & Capabilities → **+ Capability** → HealthKit.
4. **Add Info.plist keys:**
   - `NSCameraUsageDescription`: "Scan product barcodes to check them for your family."
   - `NSHealthShareUsageDescription`: "Read your health data to personalise food recommendations."
5. **Set the User-Agent:** in `ProductService.swift`, replace `you@example.com` with your contact email. Open Food Facts asks every app to identify itself.
6. **Run on a real iPhone.** The live scanner doesn't work in the Simulator. There, type a barcode instead; `3017620422003` is a well-known product in Open Food Facts.

## How scoring works

- Allergies are checked first against the product's allergen tags, falling back to keywords in the ingredient text. A match means **Avoid, score 0**, with no exceptions.
- Otherwise the score starts at 100 and loses points for sugar and carbs (diabetes), sodium (high blood pressure), saturated and trans fat (high cholesterol), and a big share of the daily calorie goal.
- **70 or more** is Okay, **40–69** is Caution, and **below 40** is Avoid.
- Every deduction adds a plain-language reason, shown when you expand a member.

## Known simplifications to revisit

- Open Food Facts reports **total** sugar, while sugar goals are usually about **added** sugar, so the score is conservative.
- Thresholds and penalty weights are starting points. Review them with a dietitian before launch.
- Nutrition data is crowd-sourced and sometimes missing; missing values are skipped, not guessed.
- The family list is local sample data.

## Next steps

1. Add a backend (Supabase, Firebase, or your own API) for family groups, invites and per-metric sharing consent. Don't store health data in iCloud (App Store guideline 5.1.3).
2. Build add/edit screens for members, conditions and goals.
3. Add label photo + OCR as a fallback for products that aren't in the database.
4. Keep a scan history.
