-- NutriKin 1.1: fibre and total fat on logged food.
-- Run this in the Supabase SQL Editor after migration_007_tracking_workouts_groceries.sql.
-- Existing rows get 0 (unknown), so nothing already logged changes.

alter table food_log add column if not exists fiber_g double precision not null default 0
  check (fiber_g between 0 and 1000);
alter table food_log add column if not exists fat_g double precision not null default 0
  check (fat_g between 0 and 1000);
