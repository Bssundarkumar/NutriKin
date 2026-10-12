-- NutriKin 1.1: daily food tracking, workouts and the shared grocery list.
-- Run this in the Supabase SQL Editor (Project > SQL Editor > New query),
-- after migration_006_delete_account.sql.
--
-- Every table is scoped to a household, and row-level security lets only
-- that household's members read or change rows (same rule as scans and members).
-- Deleting a household or a member deletes their rows too, so account deletion
-- keeps working without changes.

-- Food eaten ---------------------------------------------------------------
create table if not exists food_log (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references households(id) on delete cascade,
  member_id uuid not null references members(id) on delete cascade,
  eaten_at timestamptz not null default now(),
  label text not null check (char_length(label) between 1 and 120),
  barcode text,
  source text not null default 'manual' check (source in ('scan', 'plate', 'manual', 'ai')),
  calories double precision not null default 0 check (calories between 0 and 5000),
  sugar_g double precision not null default 0 check (sugar_g between 0 and 1000),
  carbs_g double precision not null default 0 check (carbs_g between 0 and 1000),
  sodium_mg double precision not null default 0 check (sodium_mg between 0 and 50000),
  sat_fat_g double precision not null default 0 check (sat_fat_g between 0 and 1000),
  protein_g double precision not null default 0 check (protein_g between 0 and 1000),
  created_by uuid default auth.uid()
);
create index if not exists food_log_household_day_idx on food_log (household_id, eaten_at desc);
create index if not exists food_log_member_idx on food_log (member_id, eaten_at desc);

-- Workouts -----------------------------------------------------------------
create table if not exists workouts (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references households(id) on delete cascade,
  member_id uuid not null references members(id) on delete cascade,
  done_at timestamptz not null default now(),
  kind text not null check (char_length(kind) between 1 and 40),
  minutes integer not null check (minutes between 1 and 600),
  intensity text not null default 'moderate' check (intensity in ('light', 'moderate', 'vigorous')),
  calories_burned integer not null default 0 check (calories_burned between 0 and 5000),
  note text check (note is null or char_length(note) <= 200),
  created_by uuid default auth.uid()
);
create index if not exists workouts_household_day_idx on workouts (household_id, done_at desc);
create index if not exists workouts_member_idx on workouts (member_id, done_at desc);

-- Shared grocery list -----------------------------------------------------
-- Anyone in the family adds items; buying one removes it (the app deletes the row).
create table if not exists grocery_items (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references households(id) on delete cascade,
  name text not null check (char_length(name) between 1 and 120),
  quantity text check (quantity is null or char_length(quantity) <= 40),
  note text check (note is null or char_length(note) <= 200),
  barcode text,
  added_by uuid default auth.uid(),
  added_at timestamptz not null default now()
);
create index if not exists grocery_items_household_idx on grocery_items (household_id, added_at);

-- Row-level security -------------------------------------------------------
alter table food_log enable row level security;
alter table workouts enable row level security;
alter table grocery_items enable row level security;

create policy "food_log: read" on food_log
  for select to authenticated using (is_household_member(household_id));
create policy "food_log: add" on food_log
  for insert to authenticated with check (is_household_member(household_id));
create policy "food_log: remove" on food_log
  for delete to authenticated using (is_household_member(household_id));

create policy "workouts: read" on workouts
  for select to authenticated using (is_household_member(household_id));
create policy "workouts: add" on workouts
  for insert to authenticated with check (is_household_member(household_id));
create policy "workouts: remove" on workouts
  for delete to authenticated using (is_household_member(household_id));

create policy "grocery: read" on grocery_items
  for select to authenticated using (is_household_member(household_id));
create policy "grocery: add" on grocery_items
  for insert to authenticated with check (is_household_member(household_id));
create policy "grocery: edit" on grocery_items
  for update to authenticated
  using (is_household_member(household_id)) with check (is_household_member(household_id));
create policy "grocery: remove" on grocery_items
  for delete to authenticated using (is_household_member(household_id));
