-- Apply after migration_020. Tokens are private to their signed-in owner.
create table public.push_devices (
  token text primary key check (token ~ '^[a-f0-9]{64,200}$'),
  user_id uuid not null references auth.users(id) on delete cascade,
  environment text not null check (environment in ('sandbox','production')),
  enabled boolean not null default false,
  updated_at timestamptz not null default now()
);
alter table public.push_devices enable row level security;
create policy "devices: own" on public.push_devices for all to authenticated
using (user_id = auth.uid()) with check (user_id = auth.uid());
-- Reassign a physical token safely after account switching, without exposing its previous owner.
create function public.register_push_device(p_token text, p_environment text, p_enabled boolean)
returns void language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'Sign in first'; end if;
  insert into push_devices(token,user_id,environment,enabled) values(p_token,auth.uid(),p_environment,p_enabled)
  on conflict(token) do update set user_id=auth.uid(),environment=excluded.environment,enabled=excluded.enabled,updated_at=now();
end $$;
revoke all on function public.register_push_device(text,text,boolean) from public;
grant execute on function public.register_push_device(text,text,boolean) to authenticated;

create table public.medication_pokes (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households(id) on delete cascade,
  medication_id uuid not null references public.medications(id) on delete cascade,
  member_id uuid not null references public.members(id) on delete cascade,
  sender_id uuid not null references auth.users(id) on delete cascade,
  recipient_id uuid not null references auth.users(id) on delete cascade,
  due_at timestamptz not null,
  state text not null default 'queued' check(state in ('queued','accepted','failed')),
  created_at timestamptz not null default now()
);
alter table public.medication_pokes enable row level security;
create policy "pokes: participants read" on public.medication_pokes for select to authenticated
using (is_household_member(household_id) and (sender_id=auth.uid() or recipient_id=auth.uid()));
-- Only this verified function can create a poke. No direct client inserts/updates.
create function public.request_medication_poke(p_medication uuid,p_due timestamptz,p_timezone text)
returns public.medication_pokes language plpgsql security definer set search_path = public as $$
declare med medications; target members; result medication_pokes; local_due timestamp;
begin
  select * into med from medications where id=p_medication and active;
  if med.id is null or not is_household_member(med.household_id) then raise exception 'Medication not found'; end if;
  -- Serializes concurrent reminders to this person, including different medications.
  select * into target from members where id=med.member_id for update;
  if target.user_id is null or target.user_id=auth.uid() then raise exception 'This member needs their own linked phone'; end if;
  if not exists(select 1 from household_users where household_id=med.household_id and user_id=target.user_id) then
    raise exception 'This person is no longer in your family';
  end if;
  if p_due > now() or p_due < now()-interval '24 hours' then raise exception 'Only outstanding doses from the last 24 hours can be reminded'; end if;
  local_due := p_due at time zone p_timezone;
  if not (to_char(local_due,'HH24:MI')=any(med.times)) or not (extract(isodow from local_due)::int=any(med.days_of_week))
     or extract(second from p_due) <> 0 then raise exception 'This dose is not scheduled'; end if;
  if exists(select 1 from medication_doses where medication_id=med.id and abs(extract(epoch from due_at-p_due))<60) then
    raise exception 'This dose has already been marked taken or skipped';
  end if;
  if exists(select 1 from medication_pokes where recipient_id=target.user_id and created_at>now()-interval '15 minutes' and state<>'failed') then
    raise exception 'A reminder was sent recently. Please wait 15 minutes';
  end if;
  if not exists(select 1 from push_devices where user_id=target.user_id and enabled) then
    raise exception 'Ask them to enable Family reminders on their phone';
  end if;
  insert into medication_pokes(household_id,medication_id,member_id,sender_id,recipient_id,due_at)
  values(med.household_id,med.id,target.id,auth.uid(),target.user_id,p_due) returning * into result;
  return result;
end $$;
revoke all on function public.request_medication_poke(uuid,timestamptz,text) from public;
grant execute on function public.request_medication_poke(uuid,timestamptz,text) to authenticated;
