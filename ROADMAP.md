# NutriKin roadmap

The 1.0 build (13) is tagged `v1.0.0-build13`. Work for the next release happens on the `release-1.1` branch so `main`
always matches what Apple reviewed.

## Release 1.1: "trust it more, use it every day"

Target: 2 to 3 weeks after 1.0 is approved. Version 1.1.0, first build 14.

### Must have (P0)
| # | Item | Why | Status |
|---|---|---|---|
| 1 | Fixes from TestFlight and App Review feedback | Real-phone bugs matter more than new features | open |
| 2 | **History: delete and keep it local** (select several, delete for everyone, "this phone only", clear all, saved offline copy) | Asked for by users; privacy control | **done on `release-1.1`, needs a phone test** |
| 3 | Sign in with Apple token revocation when an account is deleted (small Supabase Edge Function) | Apple expects it for Sign in with Apple accounts | open |
| 4 | Dietitian review of scoring thresholds and the ingredient watchlist | Health guidance needs expert sign-off before promotion | open |

### Should have (P1)
| # | Item | Notes |
|---|---|---|
| 5 | **Daily tracking**: "I ate this" on a scan or plate, and "today so far" per person against their limits | **Built on `release-1.1`** (Today tab), needs migration 007 and a phone test |
| 6 | **Apple Health burned calories** feed the day's allowance; activity level detected from 2 weeks of data | Needs read access for active energy and a one-time "This is me" link |
| 7 | **Real nutrition data for plates** (USDA FoodData Central or Open Food Facts lookup) instead of AI-guessed per-100 g values | Biggest accuracy win; a light form of RAG |
| 8 | **Curated guideline snippets** (WHO, AHA, ADA limits and allergen facts) matched to each person's conditions and given to the chat, with citations | Keeps chat grounded; stored in the app, no server |
| 9 | Move AI key setup under an "Advanced" section; Apple Intelligence stays the default | Four key providers confuse most people |

### Nice to have (P2)
| # | Item |
|---|---|
| 10 | Invite codes that expire and can be revoked, with rate limiting |
| 11 | Offline product cache for recent scans |
| 12 | Accessibility pass (Dynamic Type, VoiceOver labels) and localisation prep (Hindi, Telugu?) |
| 13 | Crash and performance reporting (MetricKit); GitHub Actions running the tests on every push |
| 14 | Home Screen widget and Shortcuts action to open the scanner |
| 18 | **Better plate estimates**: a dietitian-style prompt (portion anchors, hidden oil and salt, per-100 g values as served), fibre and total fat added, and a check that calories match the reported macros | **Built on `release-1.1`**, needs migration 008 and a real-photo test |
| 19 | **Medications, step 1**: per-person medicine list, reminders on this iPhone (with Taken and Skip buttons), a dose log shared with the family, and a Medications card on Today | **Built on `release-1.2`**, needs migration 009 and a real-phone test of notifications |
| 20 | **Medications, step 2**: alert a chosen family member when a dose isn't marked in time (server job plus push notifications) | open; needs an Apple push key and a scheduled Supabase function |
| 21 | **Apple Health activity**: steps, active calories and workouts read (never written) for the phone's owner, one-tap workout import without duplicates, and the calorie allowance uses the larger of Health's active calories and logged workouts | **Built on `release-1.2`**, needs migration 010 and a real-phone test with an Apple Watch |
| 22 | **Pregnancy** as a tracked condition (stored so older versions still read it): alcohol, raw or undercooked foods, unpasteurised dairy, liver and high-mercury fish flagged and capped in scores, caffeine noted; no weight plan; risky meal ideas removed | **Built on `release-1.2`** |
| 23 | **Today adapts to age**: children get no calorie ring or adult limits, older adults see medications first, and a due or unmarked dose moves medications to the top for anyone | **Built on `release-1.2`** |
| 24 | **Walk-it-off** idea on plate results (steps, walking and dance equivalents in a light tone; adults only, off for pregnancy and underweight) | **Built on `release-1.2`** |
| 15 | **Workouts** (log activity, MET-based calorie estimate, half added back to the day's allowance) | **Built on `release-1.1`** |
| 16 | **Shared grocery list** with buy-to-remove and undo, plus add-from-scan and add-from-meal-plan | **Built on `release-1.1`** |
| 17 | App **redesign**: Today as the home screen, five tabs, shared design components, dark mode checked | **Built on `release-1.1`** |

## Release process (repeat every release)
1. Branch from `main` (`release-x.y`); bump `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in `NutriKin/project.yml`.
2. Run all tests; archive; upload; TestFlight with two phones (one with Apple Intelligence).
3. Run the test list: sign-in (three ways), family and invite, scan, label and plate photos, chat and meals, history
   deletion, Delete Account, every Close button.
4. Update `docs/privacy.html`, `docs/app-store-listing.md` and the App Privacy answers if data use changed.
5. Submit with manual release; tag the reviewed commit; merge the branch into `main` once approved.

## Risks to watch
- Features tested only in the Simulator (camera, AR measure, Apple Intelligence, AI keys): keep them behind real-phone tests.
- Scope creep: 1.1 ships P0 and the P1 items that are ready; the rest move to 1.2.
- App Review: any new data collected needs a privacy policy and App Privacy update before submission.
