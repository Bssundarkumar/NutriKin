-- NutriKin 1.2: edit a logged food entry (fix an estimate that missed an ingredient, correct a typo).
-- Run this in the Supabase SQL Editor after migration_017_gym_buddies.sql.

drop policy if exists "food_log: edit" on food_log;
create policy "food_log: edit" on food_log
  for update to authenticated
  using (is_household_member(household_id)) with check (is_household_member(household_id));
