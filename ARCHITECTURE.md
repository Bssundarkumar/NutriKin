# NutriKin architecture

A SwiftUI app (iOS 17+) with Supabase for shared family data. This is the map of how it fits together.

## Layers

| Layer | Folder | Rule |
|---|---|---|
| Models | `FamilyFoodScanner/Models` | Plain `Codable` values and pure maths. No UI, no network. |
| Services | `FamilyFoodScanner/Services/<feature>` | `@Observable` stores, network, AI, notifications. No SwiftUI views. |
| Views | `FamilyFoodScanner/Views/<feature>` | SwiftUI only. Read from stores through `@Environment`; hold only view state. |
| App | `FamilyFoodScanner/App` | Entry point, demo mode (DEBUG only, compiled out of release). |

Pure logic (scoring, schedules, goals, permissions, strength maths) lives in Models or in enums inside Services so it can be unit tested without the UI or a network.

## Features

- **Core**: `Backend` (one shared Supabase client, retry, coding), `AuthStore`, `FamilyStore` (family, members, "This is me", roles), `KeychainStore`.
- **Products / Scoring**: barcode and photo lookup (Open Food Facts), the scoring engine, ingredient analysis, alternatives. Allergy checks are code, never AI.
- **Activity**: `TrackingStore` (food, workouts, templates, schedules; split into `+Workouts` and `+Schedules`), `GrowthStore`, Health import, day maths, reminders for scheduled activities.
- **Medications**: list, schedule maths, reminders, dose log.
- **AI**: providers (Apple on-device, or the person's own key for Claude, OpenAI, Grok, Gemini), `AIGuardrails`, `AIQuick` (one place for short AI text), prompts for chat, plates, meal ideas, coaching.

## Rules that hold everywhere

1. **AI is optional and on request.** Every AI feature has a non-AI path or hides itself. All AI text goes through `AIGuardrails.review` and is marked "Written by AI". Prompts pass user data inside `<..._data>` tags as data, never instructions. No medication or dosing advice, no weight-loss talk, no shaming.
2. **Access is enforced in the database (row-level security), not in the app.** The app's `MemberAccess` only decides which buttons to show. Anyone in a family can read; writes to a person's medicines, templates, schedules and measurements need `can_manage_member`: the person themselves, or a parent/carer for someone managed by one.
3. **Backward compatible.** New fields are optional; new enum cases decode as `other` in older apps; new tables are loaded in their own `try` so an old database doesn't break the rest.
4. **Local-first reminders.** Medicine and activity reminders are local notifications on this phone. They are a nudge, never a safety system.
5. **Sign-out wipes local data** (history, tracking, reminders, AI key).

## Data (Supabase)

Run `backend/schema.sql`, then the numbered migrations in order (see `backend/README.md`). Every migration is written to be safe to run more than once.

## Testing

`xcodebuild test` runs the unit tests (`FamilyFoodScanner/Tests`). Demo mode (`-demoMode` and friends, DEBUG only) renders screens with sample data for screenshots.

## Known gaps

Sign in with Apple token revocation on account deletion; server-side alerts for missed medicines; dietitian review of scoring and pregnancy rules; growth percentile curves; offline product cache; invite-code expiry.

## Product structure (what lives where)

The core job is **track food and check whether it is safe**. Everything else is secondary and reached from one place.

| Tier | Features | Where |
|---|---|---|
| Core | Scan and safety score, allergy block, Log food, calories and limits | Scan tab; top of Today |
| Secondary | Medicines, Activity (workouts, steps, strength, schedule, goals), kids' play and stars | Cards on Today; Activity opens its own screen |
| Supporting | Groceries, History, AI chat, meal ideas, tips | Tabs and on-request buttons |
| Admin | Family, members, "This is me", conditions, goals, height and weight chart, plans, AI keys, privacy | Family tab; less-used items in menus |

Patterns used: progressive disclosure (Today shows a summary, Activity opens the detail), bottom sheets for logging, contextual menus (Family "Growth and plan"), AI only on request, and a person-aware Today (children: play first, no calories; older adults: medicines first; pregnancy: rules shown).
