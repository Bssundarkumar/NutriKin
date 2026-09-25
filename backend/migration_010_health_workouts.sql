-- NutriKin 1.2: workouts imported from Apple Health.
-- Run this in the Supabase SQL Editor after migration_009_medications.sql.
--
-- `source` says where a workout came from ('manual' or 'health') and `external_id` is the Health app's id
-- for it, so the same workout is never added twice. Typing a workout in never uses these columns.

alter table workouts add column if not exists source text check (source is null or source in ('manual', 'health'));
alter table workouts add column if not exists external_id text check (external_id is null or char_length(external_id) <= 80);

create unique index if not exists workouts_external_id_key
  on workouts (household_id, member_id, external_id) where external_id is not null;
