-- Apply after migration_021. Allows a current adult buddy to log a shared session
-- for selected adult participants in the same group, without granting general edit access.
begin;
create table if not exists buddy_workout_batches (
  id uuid primary key,
  group_id uuid references buddy_groups(id) on delete set null,
  created_by uuid not null references auth.users(id) on delete cascade,
  request jsonb not null,
  created_at timestamptz not null default now()
);
alter table buddy_workout_batches enable row level security;
alter table workouts add column if not exists buddy_batch_id uuid references buddy_workout_batches(id) on delete set null;
create unique index if not exists workouts_buddy_batch_member_idx on workouts(buddy_batch_id, member_id) where buddy_batch_id is not null;

create or replace function log_buddy_group_workout(
  p_batch uuid, p_group uuid, p_members uuid[], p_done_at timestamptz,
  p_kind text, p_minutes integer, p_intensity text, p_note text, p_exercises jsonb
) returns setof workouts language plpgsql security definer set search_path = public as $$
declare
  actor uuid := auth.uid(); ids uuid[]; request_body jsonb; prior buddy_workout_batches;
  participant members; ex jsonb; item jsonb; met double precision; kcal integer;
begin
  if actor is null then raise exception 'not signed in'; end if;
  if p_batch is null or p_group is null then raise exception 'missing group or request'; end if;
  -- Keep group membership stable for this transaction (a concurrent leave waits).
  perform 1 from buddy_members where group_id = p_group for share;
  perform m.id from members m join buddy_members b on b.member_id = m.id where b.group_id = p_group for share of m;
  -- All saves, including retries, require current membership and an adult linked actor.
  perform 1 from buddy_members b join members m on m.id = b.member_id
    where b.group_id = p_group and b.user_id = actor and m.user_id = actor and coalesce(m.age,0) >= 18;
  if not found then raise exception 'join this group with your adult profile first'; end if;
  select array_agg(distinct mid order by mid) into ids from unnest(p_members) mid;
  if ids is null or cardinality(ids) < 1 or cardinality(ids) > 20 or array_position(ids, null) is not null then
    raise exception 'select between 1 and 20 participants';
  end if;
  if (select count(*) from buddy_members b join members m on m.id = b.member_id
      where b.group_id = p_group and b.member_id = any(ids) and m.user_id = b.user_id and coalesce(m.age,0) >= 18) <> cardinality(ids) then
    raise exception 'selected participants must still be adult members of this group';
  end if;
  if p_done_at is null or p_done_at > now() + interval '5 minutes' or p_minutes is null or p_minutes not between 1 and 600 then
    raise exception 'invalid workout date or duration';
  end if;
  if p_kind is null or p_kind not in ('walking','running','cycling','swimming','yoga','strength','hiit','dance','sports','housework','other')
    or p_intensity is null or p_intensity not in ('light','moderate','vigorous') then raise exception 'invalid workout type or effort'; end if;
  if coalesce(char_length(p_note),0) > 200 then raise exception 'note is too long'; end if;
  if p_kind = 'strength' then
    if p_exercises is null or jsonb_typeof(p_exercises) <> 'array' then raise exception 'add strength exercises'; end if;
    if jsonb_array_length(p_exercises) not between 1 and 30 then raise exception 'invalid exercise count'; end if;
    for ex in select value from jsonb_array_elements(p_exercises) loop
      if jsonb_typeof(ex) <> 'object' or coalesce(char_length(trim(ex->>'name')),0) not between 1 and 60
        or jsonb_typeof(ex->'sets') is distinct from 'array' then raise exception 'invalid exercise'; end if;
      if jsonb_array_length(ex->'sets') not between 1 and 30 then raise exception 'invalid set count'; end if;
      for item in select value from jsonb_array_elements(ex->'sets') loop
        if jsonb_typeof(item->'reps') is distinct from 'number' or jsonb_typeof(item->'weight_kg') is distinct from 'number' then raise exception 'invalid set'; end if;
        if (item->>'reps')::numeric not between 1 and 999 or (item->>'reps')::numeric <> trunc((item->>'reps')::numeric)
          or (item->>'weight_kg')::numeric not between 0 and 1000 then raise exception 'invalid reps or weight'; end if;
      end loop;
    end loop;
  elsif p_exercises is not null then raise exception 'sets require strength'; end if;
  request_body := jsonb_build_object('group',p_group,'members',ids,'date',p_done_at,'kind',p_kind,'minutes',p_minutes,'intensity',p_intensity,'note',p_note,'exercises',p_exercises);
  perform pg_advisory_xact_lock(hashtextextended(p_batch::text,0));
  select * into prior from buddy_workout_batches where id = p_batch;
  if found then
    if prior.created_by <> actor or prior.request <> request_body then raise exception 'save request already used'; end if;
    return query select * from workouts where buddy_batch_id = p_batch;
    return;
  end if;
  insert into buddy_workout_batches(id,group_id,created_by,request) values(p_batch,p_group,actor,request_body);
  -- Same estimator as the app, using each participant's stored weight privately.
  met := case p_kind
    when 'walking' then case p_intensity when 'light' then 2.8 when 'moderate' then 3.5 else 5.0 end
    when 'running' then case p_intensity when 'light' then 7.0 when 'moderate' then 9.8 else 11.5 end
    when 'cycling' then case p_intensity when 'light' then 4.0 when 'moderate' then 6.8 else 10.0 end
    when 'swimming' then case p_intensity when 'light' then 5.0 when 'moderate' then 6.0 else 9.8 end
    when 'yoga' then case p_intensity when 'light' then 2.5 when 'moderate' then 3.0 else 4.0 end
    when 'strength' then case p_intensity when 'light' then 3.5 when 'moderate' then 5.0 else 6.0 end
    when 'hiit' then case p_intensity when 'light' then 6.0 when 'moderate' then 8.0 else 10.0 end
    when 'dance' then case p_intensity when 'light' then 4.5 when 'moderate' then 5.5 else 7.0 end
    when 'sports' then case p_intensity when 'light' then 5.0 when 'moderate' then 7.0 else 9.0 end
    when 'housework' then case p_intensity when 'light' then 2.5 when 'moderate' then 3.5 else 5.0 end
    else case p_intensity when 'light' then 3.0 when 'moderate' then 5.0 else 7.0 end end;
  for participant in select m.* from members m where m.id = any(ids) loop
    kcal := least(5000, round(met * least(250,greatest(30,coalesce(participant.weight_kg,70))) * p_minutes / 60)::integer);
    insert into workouts(household_id,member_id,done_at,kind,minutes,intensity,calories_burned,note,exercises,created_by,buddy_batch_id)
      values(participant.household_id,participant.id,p_done_at,p_kind,p_minutes,p_intensity,kcal,nullif(trim(p_note),''),p_exercises,actor,p_batch);
  end loop;
  return query select * from workouts where buddy_batch_id = p_batch;
end;
$$;
revoke all on function log_buddy_group_workout(uuid,uuid,uuid[],timestamptz,text,integer,text,text,jsonb) from public,anon;
grant execute on function log_buddy_group_workout(uuid,uuid,uuid[],timestamptz,text,integer,text,text,jsonb) to authenticated;
commit;
