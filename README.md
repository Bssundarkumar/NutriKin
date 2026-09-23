# NutriKin

Scan a grocery barcode, look the product up in Open Food Facts, and see whether
it suits **each person in your family**, based on their conditions, allergies,
goals and vitals. Ingredients worth limiting are flagged with a plain reason.

SwiftUI, iOS 17+, backed by Supabase for shared family data.

## What it does

- **Scan** a barcode with the camera (or type one in the Simulator). QR codes
  work too when they carry a product number (GS1 Digital Link).
- **Score** the product 0-100 for every family member, with a readable reason
  for each deduction. Allergies are a hard block.
- **Ingredient alerts** for things like trans fat, nitrite preservatives and
  children's-hyperactivity colours, plus condition-specific notes (added sugar
  for diabetes, sodium additives for high blood pressure, and so on).
- **Family** shared across phones with an invite code: add members with
  conditions, custom conditions/allergies, age, height, weight, sex and goals.
- **Apple Health** read access for the device owner (weight, glucose, blood
  pressure, calories).

## Layout

| Path | What it holds |
|---|---|
| `FamilyFoodScanner/App` | App entry point |
| `FamilyFoodScanner/Models` | Members, conditions, allergens, products, scores |
| `FamilyFoodScanner/Services` | Scoring, ingredient analysis, Open Food Facts, Supabase, HealthKit |
| `FamilyFoodScanner/Views` | Scan, result, family, onboarding and edit screens |
| `FamilyFoodScanner/Tests` | Unit tests (scoring, ingredient alerts, scanner parsing) |
| `FamilyFoodScanner/Assets.xcassets` | App icon and images |
| `NutriKin/project.yml` | XcodeGen spec that generates the Xcode project |
| `backend/` | Supabase SQL: `schema.sql` then the numbered migrations, in order |
| `branding/` | Logo variants |

(The source folder keeps its original `FamilyFoodScanner` name; the app and
Xcode project are called NutriKin.)

## Setup

1. Install XcodeGen: `brew install xcodegen`
2. Generate the project:
   ```bash
   cd NutriKin && xcodegen generate && open NutriKin.xcodeproj
   ```
   The `.xcodeproj` is generated and git-ignored; `project.yml` is the source
   of truth. Re-run `xcodegen generate` after adding or removing files.
3. **Supabase:** create a project, then run every file in `backend/` in the SQL
   Editor in order (`schema.sql`, then `migration_002...`, `migration_003...`
   and so on). Put your project URL and **anon** key in
   `FamilyFoodScanner/Services/SupabaseConfig.swift`. Never use the
   `service_role` key in the app.
4. **Signing:** in Xcode, Signing & Capabilities, choose your team. A free
   personal team works. The app only requests plain HealthKit, not Clinical
   Health Records (which needs a paid account).
5. **Run on a real iPhone** to use the camera scanner and HealthKit. The
   Simulator can't do either; there, type a barcode instead
   (`3017620422003` is a well-known product).

## Tests

```bash
cd NutriKin && xcodebuild test -project NutriKin.xcodeproj -scheme NutriKin \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -only-testing:NutriKinTests
```

## How scoring works

- Allergies are checked first against the product's allergen tags, falling back
  to ingredient text. A match means **Avoid, score 0**, with no exceptions.
- Otherwise the score starts at 100 and loses points for sugar and carbs
  (diabetes), sodium (high blood pressure), saturated and trans fat (high
  cholesterol), and a large share of the daily calorie goal.
- Where guidelines differ by sex (added-sugar limit, typical calories), the
  member's sex picks the default target when they haven't set their own goal.
- **70+** is Okay, **40-69** Caution, **below 40** Avoid.
- Ingredient alerts are informational and never change a score.

## Known simplifications

- Open Food Facts reports **total** sugar, while sugar goals are usually about
  **added** sugar, so the score is conservative.
- Thresholds, penalty weights and the ingredient watchlist are starting points.
  **Review them with a dietitian before launch.**
- Nutrition data is crowd-sourced and sometimes missing; missing values are
  skipped, not guessed.
- **Family access is by invite code only.** Anyone holding a household's code
  can read and edit its members, health conditions included. Move to real
  sign-in (Supabase Auth with row-level security per user) before wider use.
- Don't store health data in iCloud (App Store guideline 5.1.3).

## Next steps

1. Scan history.
2. Real sign-in and per-user access rules.
3. Use Apple Health readings in scoring.
4. Read the label from a photo when a product isn't in the database.
