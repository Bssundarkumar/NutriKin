-- NutriKin 1.2: saved strength workout templates ("Push day", "Legs") to reuse on any day.
-- Run this in the Supabase SQL Editor after migration_013_edit_workouts.sql.
--
-- Everyone in the family can see a person's templates; only that person (or a parent, see
-- migration_012_member_ownership.sql) can add, change or delete them.

create table if not exists workout_templates (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references households(id) on delete cascade,
  member_id uuid not null references members(id) on delete cascade,
  name text not null check (char_length(name) between 1 and 60),
  exercises jsonb not null default '[]'
    check (jsonb_typeof(exercises) = 'array' and jsonb_array_length(exercises) <= 30),
  created_by uuid default auth.uid(),
  created_at timestamptz not null default now()
);
create index if not exists workout_templates_member_idx on workout_templates (household_id, member_id);

alter table workout_templates enable row level security;
create policy "templates: read" on workout_templates
  for select to authenticated using (is_household_member(household_id));
create policy "templates: add" on workout_templates
  for insert to authenticated with check (is_household_member(household_id) and can_manage_member(member_id));
create policy "templates: edit" on workout_templates
  for update to authenticated
  using (can_manage_member(member_id)) with check (is_household_member(household_id) and can_manage_member(member_id));
create policy "templates: remove" on workout_templates
  for delete to authenticated using (can_manage_member(member_id));
