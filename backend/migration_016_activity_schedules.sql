-- NutriKin 1.2: weekly activity schedule ("Swimming Tue and Thu at 5pm") with optional reminders.
-- Run this in the Supabase SQL Editor after migration_015_body_measurements.sql.
--
-- Everyone in the family can see a person's schedule; only that person, or a parent for someone managed
-- by a parent (see migration_012_member_ownership.sql), can change it. Reminders are notifications made
-- on the phones of the people who can change the schedule.

create table if not exists activity_schedules (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references households(id) on delete cascade,
  member_id uuid not null references members(id) on delete cascade,
  kind text not null check (char_length(kind) between 1 and 30),
  label text check (label is null or char_length(label) <= 60),
  minutes integer not null default 60 check (minutes between 5 and 600),
  -- Local time of day as 'HH:MM' (24 hour)
  time text not null default '17:00' check (time ~ '^[0-2][0-9]:[0-5][0-9]$'),
  -- ISO weekdays: 1 = Monday ... 7 = Sunday
  days_of_week integer[] not null default '{}' check (cardinality(days_of_week) <= 7),
  remind boolean not null default true,
  active boolean not null default true,
  created_by uuid default auth.uid(),
  created_at timestamptz not null default now()
);
create index if not exists activity_schedules_member_idx on activity_schedules (household_id, member_id);

alter table activity_schedules enable row level security;
drop policy if exists "schedules: read" on activity_schedules;
drop policy if exists "schedules: add" on activity_schedules;
drop policy if exists "schedules: edit" on activity_schedules;
drop policy if exists "schedules: remove" on activity_schedules;
create policy "schedules: read" on activity_schedules
  for select to authenticated using (is_household_member(household_id));
create policy "schedules: add" on activity_schedules
  for insert to authenticated with check (is_household_member(household_id) and can_manage_member(member_id));
create policy "schedules: edit" on activity_schedules
  for update to authenticated
  using (can_manage_member(member_id)) with check (is_household_member(household_id) and can_manage_member(member_id));
create policy "schedules: remove" on activity_schedules
  for delete to authenticated using (can_manage_member(member_id));
