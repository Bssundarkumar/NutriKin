-- NutriKin 1.2: medication list and dose log (reminders and tracking).
-- Run this in the Supabase SQL Editor after migration_008_fiber_and_fat.sql.
--
-- NutriKin records what the family types in. It does not check doses, interactions or
-- give medical advice. Rows are scoped to a household and visible only to its members.
-- Deleting a member or household deletes their medication rows, so account deletion
-- keeps working without changes.

create table if not exists medications (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references households(id) on delete cascade,
  member_id uuid not null references members(id) on delete cascade,
  name text not null check (char_length(name) between 1 and 80),
  dose text check (dose is null or char_length(dose) <= 60),
  notes text check (notes is null or char_length(notes) <= 200),
  -- Local times of day as 'HH:MM' (24 hour), e.g. {08:00,20:00}
  times text[] not null default '{}' check (cardinality(times) <= 8),
  -- ISO weekdays: 1 = Monday ... 7 = Sunday
  days_of_week integer[] not null default '{1,2,3,4,5,6,7}',
  active boolean not null default true,
  created_by uuid default auth.uid(),
  created_at timestamptz not null default now()
);
create index if not exists medications_household_idx on medications (household_id, member_id);

-- One row per dose the family has marked as taken or skipped.
create table if not exists medication_doses (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references households(id) on delete cascade,
  medication_id uuid not null references medications(id) on delete cascade,
  member_id uuid not null references members(id) on delete cascade,
  due_at timestamptz not null,
  status text not null check (status in ('taken', 'skipped')),
  taken_at timestamptz not null default now(),
  recorded_by uuid default auth.uid(),
  unique (medication_id, due_at)
);
create index if not exists medication_doses_day_idx on medication_doses (household_id, due_at desc);

alter table medications enable row level security;
alter table medication_doses enable row level security;

create policy "medications: read" on medications
  for select to authenticated using (is_household_member(household_id));
create policy "medications: add" on medications
  for insert to authenticated with check (is_household_member(household_id));
create policy "medications: edit" on medications
  for update to authenticated
  using (is_household_member(household_id)) with check (is_household_member(household_id));
create policy "medications: remove" on medications
  for delete to authenticated using (is_household_member(household_id));

create policy "doses: read" on medication_doses
  for select to authenticated using (is_household_member(household_id));
create policy "doses: add" on medication_doses
  for insert to authenticated with check (is_household_member(household_id));
create policy "doses: remove" on medication_doses
  for delete to authenticated using (is_household_member(household_id));
