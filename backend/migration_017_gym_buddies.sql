-- NutriKin 1.2: gym buddies. Adults share their workouts with friends in a buddy group, across families.
-- Run this in the Supabase SQL Editor after migration_016_activity_schedules.sql.
--
-- What a buddy can see: ONLY the workouts of the one person who joined the group (type, time, effort, note,
-- and strength exercises). Never that person's food, medicines, weight, health data, or anyone else in their family.
-- Only adults (18+) who have linked themselves ("This is me") can join. Up to 20 people per group. Either
-- person can leave at any time, which removes access immediately. Deleting an account removes it too.

create table if not exists buddy_groups (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(name) between 1 and 50),
  invite_code text not null unique default upper(substr(md5(random()::text || clock_timestamp()::text), 1, 8)),
  created_by uuid default auth.uid(),
  created_at timestamptz not null default now()
);

create table if not exists buddy_members (
  group_id uuid not null references buddy_groups(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  member_id uuid not null references members(id) on delete cascade,
  display_name text not null check (char_length(display_name) between 1 and 40),
  joined_at timestamptz not null default now(),
  primary key (group_id, user_id),
  unique (group_id, member_id)
);
create index if not exists buddy_members_user_idx on buddy_members (user_id);
create index if not exists buddy_members_member_idx on buddy_members (member_id);

alter table buddy_groups enable row level security;
alter table buddy_members enable row level security;

create or replace function is_buddy_group_member(gid uuid)
returns boolean language sql security definer stable set search_path = public as $$
  select exists (select 1 from buddy_members where group_id = gid and user_id = auth.uid());
$$;

-- True when the workouts belong to someone who shares a buddy group with the signed-in user.
create or replace function is_buddy_of_member(mid uuid)
returns boolean language sql security definer stable set search_path = public as $$
  select exists (
    select 1 from buddy_members me
    join buddy_members them on them.group_id = me.group_id
    where me.user_id = auth.uid() and them.member_id = mid and them.user_id <> auth.uid()
  );
$$;

drop policy if exists "buddy groups: read" on buddy_groups;
create policy "buddy groups: read" on buddy_groups for select to authenticated using (is_buddy_group_member(id));

drop policy if exists "buddy members: read" on buddy_members;
drop policy if exists "buddy members: leave" on buddy_members;
create policy "buddy members: read" on buddy_members for select to authenticated using (is_buddy_group_member(group_id));
create policy "buddy members: leave" on buddy_members for delete to authenticated using (user_id = auth.uid());

-- Buddies may read the workouts of the person who joined (and nothing else of theirs).
drop policy if exists "workouts: buddies read" on workouts;
create policy "workouts: buddies read" on workouts for select to authenticated using (is_buddy_of_member(member_id));

-- Groups can only be made or joined through these functions, which check the person is an adult and linked.
create or replace function buddy_check_person(p_member uuid)
returns members language plpgsql security definer set search_path = public as $$
declare m members;
begin
  if auth.uid() is null then raise exception 'not signed in'; end if;
  select * into m from members where id = p_member and user_id = auth.uid();
  if not found then raise exception 'link yourself first: open your profile and turn on "This is me"'; end if;
  if coalesce(m.age, 0) < 18 then raise exception 'gym buddies are for adults (18 or over): add your age to your profile'; end if;
  if (select count(*) from buddy_members where user_id = auth.uid()) >= 5 then raise exception 'you are already in 5 buddy groups'; end if;
  return m;
end;
$$;

create or replace function create_buddy_group(p_name text, p_member uuid)
returns buddy_groups language plpgsql security definer set search_path = public as $$
declare m members; g buddy_groups;
begin
  m := buddy_check_person(p_member);
  insert into buddy_groups (name) values (left(coalesce(nullif(trim(p_name), ''), 'Gym buddies'), 50)) returning * into g;
  insert into buddy_members (group_id, user_id, member_id, display_name)
    values (g.id, auth.uid(), m.id, left(m.name, 40));
  return g;
end;
$$;

create or replace function join_buddy_group(p_code text, p_member uuid)
returns buddy_groups language plpgsql security definer set search_path = public as $$
declare m members; g buddy_groups;
begin
  m := buddy_check_person(p_member);
  select * into g from buddy_groups where invite_code = upper(trim(p_code));
  if not found then raise exception 'no group with that code'; end if;
  if (select count(*) from buddy_members where group_id = g.id) >= 20 then raise exception 'this group is full (20 people)'; end if;
  insert into buddy_members (group_id, user_id, member_id, display_name)
    values (g.id, auth.uid(), m.id, left(m.name, 40))
    on conflict do nothing;
  return g;
end;
$$;

revoke all on function is_buddy_group_member(uuid), is_buddy_of_member(uuid), buddy_check_person(uuid),
  create_buddy_group(text, uuid), join_buddy_group(text, uuid) from public, anon;
grant execute on function is_buddy_group_member(uuid), is_buddy_of_member(uuid),
  create_buddy_group(text, uuid), join_buddy_group(text, uuid) to authenticated;
