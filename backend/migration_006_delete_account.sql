-- NutriKin: in-app account deletion (App Store guideline 5.1.1(v)).
-- Run this in Supabase SQL Editor after migration_005_auth.sql.
--
-- delete_my_account() removes the signed-in user's login. Any family where
-- they were the only member is deleted too (its members and scan history go
-- with it). A family that still has other people is left untouched.

create or replace function delete_my_account()
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  uid uuid := auth.uid();
begin
  if uid is null then raise exception 'not signed in'; end if;

  delete from households h
  where exists (select 1 from household_users u where u.household_id = h.id and u.user_id = uid)
    and not exists (select 1 from household_users u where u.household_id = h.id and u.user_id <> uid);

  delete from auth.users where id = uid;   -- cascades household_users
end;
$$;

revoke all on function delete_my_account() from public, anon;
grant execute on function delete_my_account() to authenticated;
