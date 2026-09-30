-- NutriKin 1.2: a shared, free plate-scan allowance. Everyone gets a few AI photo estimates a day, on
-- NutriKin's own Gemini key, with no setup — past that daily cap, it falls back to the on-device guesser
-- (or the person's own key, if they've linked one). Run this after migration_018_edit_food_log.sql.
--
-- One row per household per day. Only the server function (using the service role, which bypasses RLS)
-- writes to this; the app can read its own household's row to show "N scans left today".

create table if not exists plate_scan_usage (
  household_id uuid not null references households(id) on delete cascade,
  day date not null default current_date,
  count integer not null default 0,
  primary key (household_id, day)
);

alter table plate_scan_usage enable row level security;
drop policy if exists "plate_scan_usage: read" on plate_scan_usage;
create policy "plate_scan_usage: read" on plate_scan_usage
  for select to authenticated using (is_household_member(household_id));

-- Atomically checks the household's usage for today against `cap` and, if there's room, increments it in
-- the same statement. Returns the count AFTER this attempt, and whether it was allowed — using one round
-- trip and one row lock, so two scans started at the same moment can't both slip in under the cap.
create or replace function try_use_plate_scan(hid uuid, cap integer)
returns table(allowed boolean, count integer)
language plpgsql security definer set search_path = public as $$
declare current_count integer;
begin
  insert into plate_scan_usage (household_id, day, count) values (hid, current_date, 0)
    on conflict (household_id, day) do nothing;
  select psu.count into current_count from plate_scan_usage psu
    where household_id = hid and day = current_date for update;
  if current_count >= cap then
    return query select false, current_count;
  end if;
  update plate_scan_usage set count = count + 1 where household_id = hid and day = current_date
    returning plate_scan_usage.count into current_count;
  return query select true, current_count;
end;
$$;

revoke all on function try_use_plate_scan(uuid, integer) from public, anon;
grant execute on function try_use_plate_scan(uuid, integer) to service_role;
