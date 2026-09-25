-- NutriKin 1.3: strength workouts with exercises, sets, reps and weight.
-- Run this in the Supabase SQL Editor after migration_010_health_workouts.sql.
--
-- `exercises` holds a small JSON list: [{"name":"Bench press","sets":[{"reps":10,"weight_kg":40}]}].
-- Weights are always stored in kilograms. Workouts without exercises leave it null.

alter table workouts add column if not exists exercises jsonb
  check (exercises is null or (jsonb_typeof(exercises) = 'array' and jsonb_array_length(exercises) <= 30));
