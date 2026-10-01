# Readability and visual consistency review

October 1, 2026

## Changes

- Shared text styles use larger defaults: body 18 pt, secondary text 17 pt, supporting labels at least 15 pt. They scale with iOS Dynamic Type.
- Shared cards, lists, and forms use the Today background, rounded surfaces, subtle shadows, and green brand color.
- Crowded rows stack at larger text sizes. Badges wrap, nutrition and check-in grids adapt, and common icon actions have 44 pt targets.
- Sign-in, household setup, goal onboarding, the welcome carousel, and scan choices can scroll so text and controls remain reachable.
- Workout shortcuts use full-width cards; exercise metadata wraps without dropping tags.

## Source review

Reviewed the view files for Today and check-ins, activity and strength, exercise selection, meals and food editing, medications, schedules, growth, nutrition plans, barcode/photo/plate scanning and results, ingredient lists and scan history, groceries, family/member setup, onboarding/sign-in, buddies, and AI connection/chat/meal ideas. Changes are presentation-only; existing bindings, validation, actions, permissions, saving, scoring, and service logic are retained.

## Validation

- Final Debug simulator build succeeds; whitespace checks pass.
- Full initial unit run: 367 tests, one skipped. The Keychain round-trip test had four assertions fail with code signing disabled; no other test failed.
- Regression rerun excluding that Keychain test: 366 tests executed, one skipped, zero failures.
- Visual review on iPhone 17 Pro includes Today, family, groceries, scan result, food choices, medications, activity, strength, and exercise selection.
- Today and exercise selection checked at the accessibility-medium text size; simulator text size restored to large afterward.
- Exercise Add action verified: the button changes to its added state. Existing sets, units, template controls, and Save remain available in the workout editor.

Live authentication, AI services, Apple Health authorization, notifications, and camera capture were not exercised against real accounts or hardware. Those require a signed build and/or a physical iPhone; simulator review uses offline demo data.

## Follow-up refinements

- Today check-ins stay in one row; at accessibility text sizes the row scrolls horizontally.
- Family selection uses name tabs with a green underline; Food quality explicitly shows a score out of 100 and its grade.
- Meals Add opens food logging directly; Activity shows equal-sized icon-and-number tiles for Steps and Workouts. The Activity page’s three Health metrics also share equal widths, heights and value baselines.
- Buddy Create/Join remain available after joining a group; the existing five-group server limit is respected.
- Strength sets have Save/Edit/Delete, direct input and plus/minus controls, adjustable weight steps, and protected local drafts scoped to account, member and workout. Past sessions/templates reuse values with unlocked sets.
- Five new regression tests cover older set decoding, saved-state round trips, draft restore/edit/delete/account isolation, template reuse, bounds and weight increments.
- Latest regression run: 378 tests executed, one skipped, zero failures, excluding the same unsigned-simulator Keychain test.
- Offline UI checks verified food-only Add, plus/minus values, Save set, Edit set, Save edited values, and Delete set. Live buddy membership RPCs were not exercised against a real account.

- Reduced Today check-in, calorie and Activity card heights by tightening padding and arranging Activity's icon statistics beside its ring. Normal text preserves the requested one-row layouts; accessibility text can scroll or stack as needed.
- Family management has a summary card, prominent Add action, member profile cards and a matching profile editor header. Existing invite, edit, delete, goals, AI, Health and account actions remain available.
- Automatic Health reads/writes and opt-in remote family medicine reminders are implemented; real-device Health verification and APNs backend deployment remain required (see `health-sync.md` and `family-reminders.md`).
