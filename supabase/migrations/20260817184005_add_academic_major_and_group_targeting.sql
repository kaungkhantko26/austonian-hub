alter table public.profiles add column if not exists major text;
do $$ begin
  alter table public.profiles add constraint profiles_major_check check (major in ('CS','NW','ME','EE'));
exception when duplicate_object then null; end $$;

alter table public.academic_assignments add column if not exists major text;
do $$ begin
  alter table public.academic_assignments add constraint academic_assignments_major_check check (major in ('CS','NW','ME','EE'));
exception when duplicate_object then null; end $$;

alter table public.timetable add column if not exists target_major text;
do $$ begin
  alter table public.timetable add constraint timetable_target_major_check check (target_major in ('CS','NW','ME','EE'));
exception when duplicate_object then null; end $$;

update public.academic_assignments a set major=p.major
from public.profiles p where lower(p.email)=a.email and a.major is null and p.major is not null;

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

create or replace function public.bulk_assign_academic_groups(p_entries jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare item jsonb; normalized_email text; selected_level text; selected_major text; saved_count integer:=0; registered_count integer:=0; affected integer;
begin
  if not public.is_admin() then raise exception 'Administrator access required'; end if;
  if jsonb_typeof(p_entries)<>'array' then raise exception 'Email assignments must be an array'; end if;
  for item in select value from jsonb_array_elements(p_entries) loop
    normalized_email:=lower(trim(item->>'email')); selected_level:=trim(item->>'academic_level'); selected_major:=upper(trim(item->>'major'));
    if normalized_email !~ '^[^@\s]+@(st\.auston\.edu\.mm|auston\.edu\.mm)$' then raise exception 'Invalid official Auston email: %',normalized_email; end if;
    if selected_level not in ('foundation','semester-1','semester-2','semester-3','semester-4','bachelor') then raise exception 'Invalid academic group for %',normalized_email; end if;
    if selected_major not in ('CS','NW','ME','EE') then raise exception 'Invalid major for %',normalized_email; end if;
    insert into public.academic_assignments(email,academic_level,major,created_by)
    values(normalized_email,selected_level,selected_major,(select auth.uid()))
    on conflict (email) do update set academic_level=excluded.academic_level,major=excluded.major,updated_at=now();
    saved_count:=saved_count+1;
    update public.profiles set academic_level=selected_level,major=selected_major,updated_at=now()
    where lower(email)=normalized_email and (academic_level is distinct from selected_level or major is distinct from selected_major);
    get diagnostics affected=row_count; registered_count:=registered_count+affected;
  end loop;
  return jsonb_build_object('saved',saved_count,'registered',registered_count);
end;
$$;
revoke all on function public.bulk_assign_academic_groups(jsonb) from public,anon;
grant execute on function public.bulk_assign_academic_groups(jsonb) to authenticated;

create or replace function public.remove_academic_assignments(p_emails text[])
returns integer language plpgsql security definer set search_path = '' as $$
declare normalized_emails text[]; removed_count integer;
begin
  if not public.is_admin() then raise exception 'Administrator access required'; end if;
  select coalesce(array_agg(lower(trim(value))),array[]::text[]) into normalized_emails
  from unnest(coalesce(p_emails,array[]::text[])) as value;
  update public.profiles set academic_level=null,major=null,updated_at=now() where lower(email)=any(normalized_emails);
  delete from public.academic_assignments where email=any(normalized_emails);
  get diagnostics removed_count=row_count; return removed_count;
end;
$$;
revoke all on function public.remove_academic_assignments(text[]) from public,anon;
grant execute on function public.remove_academic_assignments(text[]) to authenticated;

create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = '' as $$
declare sid text:=upper(trim(new.raw_user_meta_data->>'student_id')); student_name text:=trim(new.raw_user_meta_data->>'full_name'); assigned_level text; assigned_major text;
begin
  if new.email !~* '^[^@\s]+@(st\.auston\.edu\.mm|auston\.edu\.mm)$' then raise exception 'Only Auston email addresses are allowed'; end if;
  if sid !~ '^AU[0-9]{7}$' then raise exception 'Student ID must match AU followed by seven digits'; end if;
  if char_length(student_name)<2 then raise exception 'Full name is required'; end if;
  select academic_level,major into assigned_level,assigned_major from public.academic_assignments where email=lower(new.email);
  insert into public.profiles(id,email,student_id,full_name,is_admin,academic_level,major)
  values(new.id,lower(new.email),sid,student_name,lower(new.email) ~ '^[^@]+@auston\.edu\.mm$',assigned_level,assigned_major);
  return new;
end;
$$;
revoke execute on function public.handle_new_user() from public,anon,authenticated;

drop policy if exists "Students read published timetable" on public.timetable;
create policy "Students read published timetable" on public.timetable for select to authenticated using (
  ((select public.is_admin()) and source='official')
  or (published and target_user_id=(select auth.uid()))
  or (published and target_user_id is null and cohort='all' and target_major is null)
  or (published and target_user_id is null
      and cohort in ('all',coalesce((select academic_level from public.profiles where id=(select auth.uid())),'none'))
      and target_major=(select major from public.profiles where id=(select auth.uid())))
  or (source='personal' and created_by=(select auth.uid()))
);

drop function if exists public.set_student_academic_level(uuid[],text);
drop function if exists public.bulk_assign_academic_levels(jsonb);

create index if not exists timetable_target_user_id_idx on public.timetable(target_user_id) where target_user_id is not null;
create index if not exists timetable_created_by_idx on public.timetable(created_by) where created_by is not null;
create index if not exists content_items_target_user_id_idx on public.content_items(target_user_id) where target_user_id is not null;
create index if not exists content_items_created_by_idx on public.content_items(created_by) where created_by is not null;
create index if not exists academic_assignments_created_by_idx on public.academic_assignments(created_by) where created_by is not null;
