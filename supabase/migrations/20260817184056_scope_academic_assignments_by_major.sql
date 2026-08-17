create or replace function public.set_student_academic_group(p_student_ids uuid[], p_academic_level text, p_major text)
returns integer language plpgsql security definer set search_path = '' as $$
declare selected_count integer;
begin
  if not public.is_admin() then raise exception 'Administrator access required'; end if;
  if p_academic_level not in ('foundation','semester-1','semester-2','semester-3','semester-4','bachelor') then raise exception 'Invalid academic group'; end if;
  if p_major not in ('CS','NW','ME','EE') then raise exception 'Invalid major'; end if;
  delete from public.academic_assignments a using public.profiles p
  where a.email=lower(p.email) and p.academic_level=p_academic_level and p.major=p_major
    and not (p.id=any(coalesce(p_student_ids,array[]::uuid[])));
  update public.profiles set academic_level=null,major=null,updated_at=now()
  where academic_level=p_academic_level and major=p_major and not (id=any(coalesce(p_student_ids,array[]::uuid[])));
  update public.profiles set academic_level=p_academic_level,major=p_major,updated_at=now()
  where id=any(coalesce(p_student_ids,array[]::uuid[]));
  insert into public.academic_assignments(email,academic_level,major,created_by)
  select lower(email),p_academic_level,p_major,(select auth.uid()) from public.profiles
  where id=any(coalesce(p_student_ids,array[]::uuid[]))
  on conflict (email) do update set academic_level=excluded.academic_level,major=excluded.major,updated_at=now();
  select count(*) into selected_count from public.profiles where academic_level=p_academic_level and major=p_major;
  return selected_count;
end;
$$;
revoke all on function public.set_student_academic_group(uuid[],text,text) from public,anon;
grant execute on function public.set_student_academic_group(uuid[],text,text) to authenticated;
