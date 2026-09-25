# NutriKin

Scan a grocery barcode, look the product up in Open Food Facts, and see whether
it suits **each person in your family**, based on their conditions, allergies,
goals and vitals. Ingredients worth limiting are flagged with a plain reason.

SwiftUI, iOS 17+, backed by Supabase for shared family data.

## What it does

- **Scan** a barcode with the camera (or type one in the Simulator). Barcodes are
  read at any angle. Tap the barcode to focus on that spot, pinch or use the
  1x/2x/3x buttons to zoom, or leave **Auto** on to let it step the zoom when it
  can't find a code. QR codes work too when they carry a product number (GS1
  Digital Link).
- **No barcode?** Show the app the product instead. Photograph the **front of
  the pack** (Apple's document camera, or pictures from your library): the phone
  reads the product name on-device (nothing is uploaded), searches Open Food
  Facts, and you **confirm the match**, then the real ingredients and nutrition
  load. Or type the name yourself. Photograph the **ingredients list** and it's
  read directly, then you check and correct it before it's scored. A barcode in
  the picture is used as-is. Photo-read products can't be reopened from History.
- **Score** the product 0-100 for every family member, with a readable reason
  for each deduction. Allergies are a hard block.
- **Ingredient amounts:** each ingredient shows how much of the product it makes
  up, from Open Food Facts (printed percentages exact, the rest marked `~` as
  estimates), with a summary bar of how much is worth limiting. Tap a flagged
  ingredient for why.
- **Ingredient alerts** for things like trans fat, nitrite preservatives and
  children's-hyperactivity colours, plus condition-specific notes (added sugar
  for diabetes, sodium additives for high blood pressure, and so on).
- **Sign in** with Apple, Google, or an email and a 6-digit code (a password option exists for the App Review demo account). Each person has
  their own account; access is enforced in the database.
- **Family** shared across phones with a short invite code: add members with
  conditions, custom conditions/allergies, age, height, weight, sex and goals.
- **Invite** relatives from the Family tab: a share button sends the code (and a
  `nutrikin://join?code=...` link that opens the app) by Messages, Mail or any
  share target.
- **Missing data is never "safe":** no ingredient list, "may contain" traces or a
  missing key figure (sugar for diabetes, and so on) caps an affected member at
  "caution" instead of "okay".
- **Quality grades:** Nutri-Score and NOVA from Open Food Facts (with an in-app
  explainer; hidden for dietary supplements), and "Try this instead" alternatives
  ranked per 100 g and safe for everyone.
- **Weight and intake plan** per adult from BMI: target weight, a paced calorie
  target (Mifflin-St Jeor, with a safe floor; no plans for children) and a
  shortcut that saves it as the calorie goal.
- **Optional AI features.** Chat about a scanned product and a day of meal ideas per
  member run on Apple's on-device model where available (iOS 26, Apple Intelligence;
  free, nothing leaves the phone), or on the person's own key for Claude, OpenAI, Grok or Gemini (stored only
  in the iPhone Keychain, sent only to that provider; OpenAI, Grok and Gemini use
  their OpenAI-compatible endpoints and the app picks the newest suitable model). Plate-photo calorie estimates and
  reading a product label from photos need the key, because the on-device model reads
  text, not images. The app re-checks every AI meal against the person's allergies, and
  the person confirms every AI-read label before it's scored.
- **AI guardrails** (`Services/AIGuardrails.swift`) apply to every AI feature: prompts confine the AI to food and
  nutrition for the family; emergencies, crisis language, medication or dose questions and jailbreak attempts get a
  fixed, human-written reply and never reach the AI; product, label and family text is passed as data, not
  instructions; replies have links and dosing advice removed, allergen mentions flagged and length capped; AI meal
  plans are re-checked against allergies; and model-written fields are sanitised. All of it is unit tested.
- **Today** dashboard: log food (from a scan, a plate photo, a typed or AI-estimated description) and workouts per
  person, with calories left (half of exercise calories is added back) and daily sugar, sodium and saturated-fat limits.
- **Groceries**: one shared list for the family; buying an item removes it for everyone, with undo. Items can be added
  from a scan result or a meal plan.
- **History** of past scans, one entry per product, with each member's verdict at the time.
- **Apple Health** read access for the device owner (weight, glucose, blood
  pressure, calories).

## Layout

| Path | What it holds |
|---|---|
| `FamilyFoodScanner/App` | App entry point |
| `FamilyFoodScanner/Models` | Members, conditions, allergens, products, scores |
| `FamilyFoodScanner/Services` | Scoring, ingredient analysis, Open Food Facts, Supabase, HealthKit, nutrition planner, AI client |
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
3. **Supabase:**
   1. Create a project and put its URL and **anon** key in
      `FamilyFoodScanner/Services/SupabaseConfig.swift` (never the
      `service_role` key).
   2. In the SQL Editor run the files in `backend/` in order: `schema.sql`,
      `migration_002...` through `migration_004...`.
   3. **Email sign-in:** Authentication, Emails, open the **Magic Link**
      template and make sure the body contains `{{ .Token }}` (the 6-digit
      code), for example `<p>Your NutriKin code: <b>{{ .Token }}</b></p>`.
      Supabase's built-in email sender allows only a few emails per hour, so
      set up custom SMTP (Authentication, Emails, SMTP) before real use.
   4. Run `migration_006_delete_account.sql` (powers in-app Delete account).
      **Sign in with Apple:** Authentication, Sign In / Providers, Apple: enable it and
      put the bundle ID `com.sundarBandiguptapu.NutriKin` in *Client IDs* (no secret is
      needed for the native flow). **Google:** create a Google Cloud OAuth client of type
      *Web application* with Supabase's callback URL
      (`https://<project>.supabase.co/auth/v1/callback`) as the authorized redirect, enable
      Google in Supabase with that client ID and secret, and add `nutrikin://login-callback`
      under URL Configuration, Redirect URLs. Keep the client secret out of the repo.
   4b. Run `migration_007_tracking_workouts_groceries.sql` then `migration_008_fiber_and_fat.sql` (Today, Workouts and Groceries in 1.1), then `migration_009_medications.sql` and `migration_010_health_workouts.sql` (1.2), then `migration_011_strength_exercises.sql` and `migration_012_member_ownership.sql` and `migration_013_edit_workouts.sql` and `migration_014_workout_templates.sql` and `migration_015_body_measurements.sql` (1.2).
   5. Install a build that has sign-in, **then** run `migration_005_auth.sql`.
      It locks the data down, so an older build stops working once it runs.
   6. Optional: `claim_existing_household.sql` re-attaches a family created
      before sign-in existed to your account.
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
- Any signed-in member of a family can edit its members and delete scans;
  there are no separate parent and child permissions yet.
- The invite link is a custom-scheme link, so it only opens the app on phones
  that already have NutriKin; a web link that also works for people without the
  app needs a paid Apple developer account. The message always includes the plain
  code too.
- An invite code never expires. Anyone who has it and an account can join, so
  share it only with family. There's no code rotation or removing another
  member yet.
- Don't store health data in iCloud (App Store guideline 5.1.3).

## Next steps

1. Use Apple Health readings in scoring.
2. Read the label from a photo when a product isn't in the database.
3. Invite-code rotation and removing members.

## Data sources and licences

Product data comes from [Open Food Facts](https://world.openfoodfacts.org): the
database is under the Open Database License (ODbL), individual contents under the
Database Contents License, and product photos under CC BY-SA. Commercial use is
allowed with attribution, which the app shows on the result screen and in
Family, Credits. Keep that credit in place. If you ever publish a database built
from Open Food Facts data (rather than showing it in the app), the ODbL's
share-alike terms apply, so read them first.
