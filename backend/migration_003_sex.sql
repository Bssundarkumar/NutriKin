-- NutriKin: add sex to members, used only to pick a more accurate
-- default daily nutrition target (calories, added sugar, etc.) when a
-- member hasn't set their own goal. Optional; NULL means unspecified.
-- Run this in Supabase SQL Editor (Project > SQL Editor > New query),
-- after migration_002_physical_stats.sql.

alter table members add column if not exists sex text
  check (sex is null or sex in ('female', 'male'));
