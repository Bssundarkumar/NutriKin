-- NutriKin: real sign-in and per-family access control.
-- Run this in Supabase SQL Editor AFTER installing the app build that has
-- sign-in (an older build will be locked out the moment this runs).
--
-- Before: anyone holding a household's id could read and edit its members.
-- After:  only signed-in users who belong to a household can touch its data.
-- People join with a short invite code through join_household(), which is the
-- only way to gain membership.

-- 1. Who belongs to which household ---------------------------------------
create table if not exists household_users (
  household_id uuid not null references households(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null default 'member' check (role in ('owner', 'member')),
  joined_at timestamptz not null default now(),
  primary key (household_id, user_id)
);
alter table household_users enable row level security;

-- 2. Short, shareable invite codes (replaces sharing the raw UUID) ---------
alter table households add column if not exists invite_code text;
update households
   set invite_code = upper(substr(md5(random()::text || clock_timestamp()::text || id::text), 1, 8))
 where invite_code is null;
alter table households alter column invite_code set not null;
alter table households alter column invite_code
  set default upper(substr(md5(random()::text || clock_timestamp()::text), 1, 8));
create unique index if not exists households_invite_code_key on households (invite_code);

-- 3. Membership check used by every policy ---------------------------------
-- SECURITY DEFINER so the policy can read household_users without recursing
-- into that table's own policies.
create or replace function is_household_member(hid uuid)
returns boolean
language sql security definer stable
set search_path = public
as $$
  select exists (
    select 1 from household_users
    where household_id = hid and user_id = auth.uid()
  );
$$;

-- 4. Replace the old "anyone can" policies ---------------------------------
drop policy if exists "anyone with the household id can read it" on households;
drop policy if exists "anyone can create a household" on households;
drop policy if exists "members are readable by anyone with the household id" on members;
drop policy if exists "members are writable by anyone with the household id" on members;
drop policy if exists "members are updatable by anyone with the household id" on members;
drop policy if exists "members are deletable by anyone with the household id" on members;
drop policy if exists "scans are readable by anyone with the household id" on scans;
drop policy if exists "scans are insertable by anyone with the household id" on scans;
drop policy if exists "scans are deletable by anyone with the household id" on scans;

-- households: read/rename if you belong; created only via create_household()
create policy "households: members read" on households
  for select to authenticated using (is_household_member(id));
create policy "households: members rename" on households
  for update to authenticated
  using (is_household_member(id)) with check (is_household_member(id));

-- household_users: see your own family's roster; leave a family yourself
create policy "household_users: see your family" on household_users
  for select to authenticated
  using (user_id = auth.uid() or is_household_member(household_id));
create policy "household_users: leave" on household_users
  for delete to authenticated using (user_id = auth.uid());

-- members
create policy "members: read" on members
  for select to authenticated using (is_household_member(household_id));
create policy "members: add" on members
  for insert to authenticated with check (is_household_member(household_id));
create policy "members: edit" on members
  for update to authenticated
  using (is_household_member(household_id)) with check (is_household_member(household_id));
create policy "members: remove" on members
  for delete to authenticated using (is_household_member(household_id));

-- scans
create policy "scans: read" on scans
  for select to authenticated using (is_household_member(household_id));
create policy "scans: add" on scans
  for insert to authenticated with check (is_household_member(household_id));
create policy "scans: remove" on scans
  for delete to authenticated using (is_household_member(household_id));

-- 5. The only ways in: create a family, or join with its code -------------
create or replace function create_household(p_name text)
returns households
language plpgsql security definer
set search_path = public
as $$
declare h households;
begin
  if auth.uid() is null then raise exception 'not signed in'; end if;
  insert into households (name)
    values (coalesce(nullif(trim(p_name), ''), 'My Family'))
    returning * into h;
  insert into household_users (household_id, user_id, role)
    values (h.id, auth.uid(), 'owner');
  return h;
end;
$$;

create or replace function join_household(p_code text)
returns households
language plpgsql security definer
set search_path = public
as $$
declare h households;
begin
  if auth.uid() is null then raise exception 'not signed in'; end if;
  select * into h from households where invite_code = upper(trim(p_code));
  if not found then raise exception 'no family with that code'; end if;
  insert into household_users (household_id, user_id, role)
    values (h.id, auth.uid(), 'member')
    on conflict do nothing;
  return h;
end;
$$;

-- Only signed-in users may call these (not the anonymous role).
revoke all on function is_household_member(uuid) from public, anon;
revoke all on function create_household(text) from public, anon;
revoke all on function join_household(text) from public, anon;
grant execute on function is_household_member(uuid) to authenticated;
grant execute on function create_household(text) to authenticated;
grant execute on function join_household(text) to authenticated;
