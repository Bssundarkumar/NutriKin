-- NutriKin 1.2: edit a logged workout (for example add another set to a strength session).
-- Run this in the Supabase SQL Editor after migration_012_member_ownership.sql.

drop policy if exists "workouts: edit" on workouts;
create policy "workouts: edit" on workouts
  for update to authenticated
  using (is_household_member(household_id)) with check (is_household_member(household_id));
