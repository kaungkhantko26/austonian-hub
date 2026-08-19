-- The self-update column grant on profiles never included admit_term when
-- that column was added, so students got a permission-denied error trying
-- to save it from Edit profile.
grant update (full_name, program, admit_term, avatar_url, updated_at) on table public.profiles to authenticated;
