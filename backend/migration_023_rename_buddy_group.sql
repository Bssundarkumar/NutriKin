-- Run after migration_022. Only the creator, while still a member, may rename a group.
create or replace function public.rename_buddy_group(p_group uuid, p_name text)
returns public.buddy_groups
language plpgsql security definer set search_path = public as $$
declare g public.buddy_groups; cleaned text := btrim(p_name);
begin
  if auth.uid() is null then raise exception 'not signed in'; end if;
  if cleaned is null or char_length(cleaned) not between 1 and 50 then
    raise exception 'group name must be between 1 and 50 characters';
  end if;
  select * into g from public.buddy_groups where id = p_group for update;
  if not found or g.created_by is distinct from auth.uid()
     or not public.is_buddy_group_member(p_group) then
    raise exception 'only the current group creator can rename this group';
  end if;
  update public.buddy_groups set name = cleaned where id = p_group returning * into g;
  return g;
end;
$$;
revoke all on function public.rename_buddy_group(uuid, text) from public, anon;
grant execute on function public.rename_buddy_group(uuid, text) to authenticated;
