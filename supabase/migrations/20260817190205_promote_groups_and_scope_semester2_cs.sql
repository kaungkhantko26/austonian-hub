create or replace function public.promote_academic_group(
  p_from_level text,
  p_from_major text,
  p_to_level text,
  p_to_major text
)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare saved_count integer:=0; added_count integer:=0; registered_count integer:=0;
begin
  if not public.is_admin() then raise exception 'Administrator access required'; end if;
  if p_from_level not in ('foundation','semester-1','semester-2','semester-3','semester-4','bachelor')
    or p_to_level not in ('foundation','semester-1','semester-2','semester-3','semester-4','bachelor') then
    raise exception 'Invalid academic level';
  end if;
  if p_from_major not in ('CS','NW','ME','EE') or p_to_major not in ('CS','NW','ME','EE') then
    raise exception 'Invalid major';
  end if;
  if p_from_level=p_to_level and p_from_major=p_to_major then raise exception 'Choose a different destination group'; end if;

  update public.academic_assignments
  set academic_level=p_to_level,major=p_to_major,updated_at=now()
  where academic_level=p_from_level and major=p_from_major;
  get diagnostics saved_count=row_count;

  insert into public.academic_assignments(email,academic_level,major,created_by)
  select lower(p.email),p_to_level,p_to_major,(select auth.uid())
  from public.profiles p
  where p.academic_level=p_from_level and p.major=p_from_major
    and not exists (select 1 from public.academic_assignments a where a.email=lower(p.email));
  get diagnostics added_count=row_count;

  update public.profiles
  set academic_level=p_to_level,major=p_to_major,updated_at=now()
  where academic_level=p_from_level and major=p_from_major;
  get diagnostics registered_count=row_count;

  return jsonb_build_object('saved',saved_count+added_count,'registered',registered_count);
end;
$$;

revoke all on function public.promote_academic_group(text,text,text,text) from public, anon;
grant execute on function public.promote_academic_group(text,text,text,text) to authenticated;

create index if not exists profiles_academic_group_idx on public.profiles(academic_level,major);
create index if not exists academic_assignments_group_idx on public.academic_assignments(academic_level,major);
create index if not exists timetable_academic_group_idx on public.timetable(cohort,target_major)
where published and target_user_id is null;

update public.timetable set target_major='CS'
where source='official' and published and target_user_id is null
  and cohort='semester-2' and target_major is null;
