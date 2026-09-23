-- NutriKin: scan history.
-- Run this in Supabase SQL Editor (Project > SQL Editor > New query),
-- after migration_003_sex.sql.
--
-- Each row is a snapshot of one scan: the product plus what every family
-- member's verdict was at that moment, so history stays meaningful even
-- after the family's conditions change. Same "anyone with the household id"
-- access model as the rest of the app (see README: move to real sign-in
-- before wider use).

create table if not exists scans (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references households(id) on delete cascade,
  barcode text not null,
  product_name text not null,
  brand text,
  image_url text,
  results jsonb not null default '[]'::jsonb,   -- [{member_name, score, verdict, blocked_by_allergy}]
  alerts jsonb not null default '[]'::jsonb,    -- ["Nitrite / nitrate preservatives", ...]
  scanned_at timestamptz not null default now()
);

create index if not exists scans_household_scanned_idx
  on scans (household_id, scanned_at desc);

alter table scans enable row level security;

create policy "scans are readable by anyone with the household id"
  on scans for select using (true);
create policy "scans are insertable by anyone with the household id"
  on scans for insert with check (true);
create policy "scans are deletable by anyone with the household id"
  on scans for delete using (true);
