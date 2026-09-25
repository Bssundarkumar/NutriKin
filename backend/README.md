# Database

Run in the Supabase SQL Editor, in this order. Each file is safe to run again.

| # | File | Adds |
|---|---|---|
| 0 | `schema.sql` | families, members |
| 2-4 | `migration_002` to `004` | physical stats, sex, scans |
| 5 | `migration_005_auth.sql` | sign-in and row-level security (run after installing a build with sign-in) |
| 6 | `migration_006_delete_account.sql` | delete my account |
| 7-8 | `migration_007`, `008` | food log, workouts, groceries, fibre and fat |
| 9 | `migration_009_medications.sql` | medicines and dose log |
| 10 | `migration_010_health_workouts.sql` | Apple Health workouts |
| 11 | `migration_011_strength_exercises.sql` | strength exercises, sets, weights |
| 12 | `migration_012_member_ownership.sql` | "This is me", who may change medicines |
| 13 | `migration_013_edit_workouts.sql` | edit logged workouts |
| 14 | `migration_014_workout_templates.sql` | strength templates |
| 15 | `migration_015_body_measurements.sql` | height and weight history |
| 16 | `migration_016_activity_schedules.sql` | weekly activity schedule |
| 17 | `migration_017_gym_buddies.sql` | gym buddy groups across families |

`claim_existing_household.sql` is a one-off helper for families created before sign-in existed.
