-- NutriKin 1.2: height and weight history, for growth and weight charts.
-- Run this in the Supabase SQL Editor after migration_014_workout_templates.sql.
--
-- One row per person per day. Everyone in the family can see them; only that person, or a parent
-- for someone managed by a parent (see migration_012_member_ownership.sql), can add or remove them.

create table if not exists body_measurements (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references households(id) on delete cascade,
  member_id uuid not null references members(id) on delete cascade,
  measured_on date not null,
  height_cm numeric check (height_cm is null or height_cm between 20 and 260),
  weight_kg numeric check (weight_kg is null or weight_kg between 1 and 500),
  created_by uuid default auth.uid(),
  created_at timestamptz not null default now(),
  check (height_cm is not null or weight_kg is not null),
  unique (member_id, measured_on)
);
create index if not exists body_measurements_member_idx on body_measurements (member_id, measured_on desc);

alter table body_measurements enable row level security;
drop policy if exists "measurements: read" on body_measurements;
drop policy if exists "measurements: add" on body_measurements;
drop policy if exists "measurements: edit" on body_measurements;
drop policy if exists "measurements: remove" on body_measurements;
create policy "measurements: read" on body_measurements
  for select to authenticated using (is_household_member(household_id));
create policy "measurements: add" on body_measurements
  for insert to authenticated with check (is_household_member(household_id) and can_manage_member(member_id));
create policy "measurements: edit" on body_measurements
  for update to authenticated
  using (can_manage_member(member_id)) with check (is_household_member(household_id) and can_manage_member(member_id));
create policy "measurements: remove" on body_measurements
  for delete to authenticated using (can_manage_member(member_id));
