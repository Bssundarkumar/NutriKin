-- NutriKin 1.3: who may change whose medicines.
-- Run this in the Supabase SQL Editor after migration_011_strength_exercises.sql.
--
-- Everyone in a family can still SEE each person's medicines and whether a dose was taken.
-- Changing them (adding, editing, deleting, marking taken or skipped) is limited to:
--   1. the person themselves (their account is linked to them, see below), or
--   2. a parent, for anyone marked "Managed by a parent": the family's creator, or a linked adult (18+), or
--   3. the family's creator, for a person no account has been linked to yet.
-- The database enforces this, so an old or modified app cannot get around it.

-- 1. Link a person to the account that owns them ----------------------------
alter table members add column if not exists user_id uuid references auth.users(id) on delete set null;
create unique index if not exists members_one_per_account on members (household_id, user_id) where user_id is not null;

-- The link can only be set through claim_member() / release_member() below. Any other write
-- (an old app, a copied request) keeps whatever the link was, so nobody can take over a person.
create or replace function members_guard_owner() returns trigger
language plpgsql as $$
begin
  if coalesce(current_setting('nutrikin.claiming', true), '') = 'on' then return new; end if;
  if tg_op = 'INSERT' then
    new.user_id := null;
  elsif new.user_id is distinct from old.user_id then
    new.user_id := old.user_id;
  end if;
  return new;
end;
$$;
drop trigger if exists members_guard_owner on members;
create trigger members_guard_owner before insert or update on members
  for each row execute function members_guard_owner();

-- 2. Who may change a person's medicines ------------------------------------
create or replace function is_household_owner(hid uuid)
returns boolean language sql security definer stable set search_path = public as $$
  select exists (select 1 from household_users where household_id = hid and user_id = auth.uid() and role = 'owner');
$$;

create or replace function can_manage_member(mid uuid)
returns boolean language sql security definer stable set search_path = public as $$
  select exists (
    select 1 from members m
    where m.id = mid
      and is_household_member(m.household_id)
      and (
        m.user_id = auth.uid()
        or (m.user_id is null and is_household_owner(m.household_id))
        or (m.is_managed_by_parent and (
              is_household_owner(m.household_id)
              or exists (select 1 from members me
                         where me.household_id = m.household_id and me.user_id = auth.uid() and coalesce(me.age, 0) >= 18)))
      )
  );
$$;

-- 3. "This is me" -----------------------------------------------------------
create or replace function claim_member(p_member uuid)
returns members language plpgsql security definer set search_path = public as $$
declare m members;
begin
  if auth.uid() is null then raise exception 'not signed in'; end if;
  select * into m from members where id = p_member;
  if not found or not is_household_member(m.household_id) then raise exception 'no such person'; end if;
  if m.user_id is not null and m.user_id <> auth.uid()
     and exists (select 1 from household_users where household_id = m.household_id and user_id = m.user_id) then
    raise exception 'someone else is already linked to this person';
  end if;
  if exists (select 1 from members where household_id = m.household_id and user_id = auth.uid() and id <> m.id) then
    raise exception 'you are already linked to someone in this family';
  end if;
  perform set_config('nutrikin.claiming', 'on', true);
  update members set user_id = auth.uid() where id = p_member returning * into m;
  perform set_config('nutrikin.claiming', 'off', true);
  return m;
end;
$$;

create or replace function release_member(p_member uuid)
returns members language plpgsql security definer set search_path = public as $$
declare m members;
begin
  if auth.uid() is null then raise exception 'not signed in'; end if;
  select * into m from members where id = p_member;
  if not found or not is_household_member(m.household_id) then raise exception 'no such person'; end if;
  if m.user_id is distinct from auth.uid() and not is_household_owner(m.household_id) then
    raise exception 'only that person or the family creator can unlink them';
  end if;
  perform set_config('nutrikin.claiming', 'on', true);
  update members set user_id = null where id = p_member returning * into m;
  perform set_config('nutrikin.claiming', 'off', true);
  return m;
end;
$$;

revoke all on function is_household_owner(uuid), can_manage_member(uuid), claim_member(uuid), release_member(uuid) from public, anon;
grant execute on function is_household_owner(uuid), can_manage_member(uuid), claim_member(uuid), release_member(uuid) to authenticated;

-- 4. Medicines and doses: everyone reads, only the right people write ------
drop policy if exists "medications: add" on medications;
drop policy if exists "medications: edit" on medications;
drop policy if exists "medications: remove" on medications;
create policy "medications: add" on medications
  for insert to authenticated with check (is_household_member(household_id) and can_manage_member(member_id));
create policy "medications: edit" on medications
  for update to authenticated
  using (can_manage_member(member_id)) with check (is_household_member(household_id) and can_manage_member(member_id));
create policy "medications: remove" on medications
  for delete to authenticated using (can_manage_member(member_id));

drop policy if exists "doses: add" on medication_doses;
drop policy if exists "doses: remove" on medication_doses;
create policy "doses: add" on medication_doses
  for insert to authenticated with check (is_household_member(household_id) and can_manage_member(member_id));
create policy "doses: remove" on medication_doses
  for delete to authenticated using (can_manage_member(member_id));
