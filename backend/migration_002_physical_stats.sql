-- NutriKin: add age/height/weight to members.
-- Run this in Supabase SQL Editor (Project > SQL Editor > New query),
-- after schema.sql. Custom conditions/allergies don't need new columns —
-- they're stored as extra entries in the existing `conditions` jsonb column.

alter table members add column if not exists age integer;
alter table members add column if not exists height_cm numeric;
alter table members add column if not exists weight_kg numeric;
