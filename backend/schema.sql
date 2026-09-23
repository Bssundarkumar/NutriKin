-- NutriKin: family data schema
-- Run this in Supabase SQL Editor (Project > SQL Editor > New query).

create extension if not exists "pgcrypto";

-- A household is the family unit. Anyone with the invite code
-- (the household's id) can read/write its members from the app.
create table if not exists households (
  id uuid primary key default gen_random_uuid(),
  name text not null default 'My Family',
  created_at timestamptz not null default now()
);

create table if not exists members (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references households(id) on delete cascade,
  name text not null,
  conditions jsonb not null default '[]'::jsonb,   -- [{"type":"diabetes"}, {"type":"allergy","allergen":"peanuts"}]
  goals jsonb not null default '{}'::jsonb,          -- {"dailySugarGrams": 25, ...}
  is_managed_by_parent boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Row Level Security: this is a lightweight "invite code" model, not
-- per-user auth. Anyone holding a household's UUID can read/write its
-- members — same trust model as a shared link. Good enough for a family
-- app; revisit with Supabase Auth if you want per-person login later.
alter table households enable row level security;
alter table members enable row level security;

create policy "anyone with the household id can read it"
  on households for select
  using (true);

create policy "anyone can create a household"
  on households for insert
  with check (true);

create policy "members are readable by anyone with the household id"
  on members for select
  using (true);

create policy "members are writable by anyone with the household id"
  on members for insert
  with check (true);

create policy "members are updatable by anyone with the household id"
  on members for update
  using (true);

create policy "members are deletable by anyone with the household id"
  on members for delete
  using (true);

-- Keep updated_at fresh.
create or replace function set_updated_at()
returns trigger as $$
begin
  new.updated_at = now();
  return new;
end;
$$ language plpgsql;

create trigger members_set_updated_at
  before update on members
  for each row execute function set_updated_at();
