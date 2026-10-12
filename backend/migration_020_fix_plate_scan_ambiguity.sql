-- NutriKin 1.2: fixes a real bug in try_use_plate_scan (migration 019): its RETURNS TABLE declared a column
-- named "count", which PL/pgSQL also treats as an implicit variable for the whole function body. The line
-- `set count = count + 1` was then ambiguous between that variable and the plate_scan_usage.count column,
-- so the function threw on every call that should have succeeded, and the app misread that failure as
-- "today's free scans are used up" instead of a real error. Renaming the output column removes the clash.
-- Run this after migration_019_shared_plate_scans.sql.

create or replace function try_use_plate_scan(hid uuid, cap integer)
returns table(allowed boolean, scans_used integer)
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
  update plate_scan_usage set count = plate_scan_usage.count + 1 where household_id = hid and day = current_date
    returning plate_scan_usage.count into current_count;
  return query select true, current_count;
end;
$$;
