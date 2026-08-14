# Austonian Hub

A responsive student experience platform for Auston students. The project combines a mobile-first progressive web app with a dedicated desktop workspace, verified student access, real-time academic information, and an administrator publishing dashboard.

**Live showcase:** [austonianhub.kaungkhantko.studio](https://austonianhub.kaungkhantko.studio)

![Austonian Hub](frontend/assets/auston-logo.png)

## Highlights

- Official-email authentication with six-digit OTP verification and password recovery
- Responsive mobile PWA and purpose-built laptop interface
- Installable experience for iOS and Android
- Digital student card with user-managed profile portrait
- Real-time class timetable, notices, deadlines, jobs, news, and events
- Personal timetable entries and horizontally scrollable class calendar
- Academic groups for Foundation, Semester 1–4, and Bachelor students
- Administrator bulk assignment using `student@st.auston.edu.mm | 2nd Sem`
- Database-backed pending assignments that activate when a student registers
- Multi-select assignment removal and real-time admin updates
- Supabase row-level security and role-restricted publishing

## Architecture

```text
Browser / Installed PWA
        │
        ├── Responsive HTML, CSS and JavaScript
        ├── Supabase Auth (OTP and password sessions)
        ├── Supabase Postgres (profiles, timetable and content)
        ├── Supabase Realtime (live student updates)
        └── Supabase Storage (student portraits)
```

The frontend is deployed as a static application on Vercel. Authentication, database access, realtime subscriptions, and file storage are handled by Supabase.

## Local setup

1. Create a Supabase project.
2. Copy the public configuration template:

   ```bash
   cp frontend/config.example.js frontend/config.js
   ```

3. Add your Supabase project URL and publishable key to `frontend/config.js`.
4. Run `supabase/schema.sql` in the Supabase SQL editor.
5. Promote the intended administrator from the protected Supabase SQL editor after their profile exists:

   ```sql
   update public.profiles
   set is_admin = true, updated_at = now()
   where lower(email) = lower('YOUR_ADMIN_EMAIL');
   ```

6. Serve the frontend locally:

   ```bash
   cd frontend
   python3 -m http.server 8080
   ```

Then open `http://localhost:8080`.

## Deployment

The `frontend` directory can be deployed directly to Vercel. Supply `frontend/config.js` securely during your deployment process; it is intentionally ignored by Git and is not included in this showcase repository.

Before production use, configure Supabase Auth URLs, an SMTP provider, email templates, and the allowed redirect URLs for your domain.

## Security and privacy

- No production passwords, SMTP credentials, service-role keys, personal student records, or administrator identity are committed.
- Only authenticated users can read application data according to the included row-level security policies.
- Administrative database changes are exposed through security-definer functions that verify the caller’s admin profile.
- Production migrations and VPS retirement scripts are intentionally excluded from the public showcase.

See [SECURITY.md](SECURITY.md) for responsible disclosure guidance.

## Project structure

```text
frontend/
  app.js                 Application and Supabase integration
  styles.css             Mobile interface and shared components
  desktop.css            Laptop and wide-screen experience
  manifest.webmanifest   PWA metadata
  sw.js                  Offline asset cache
  config.example.js      Safe configuration template
supabase/
  schema.sql             Tables, policies, functions and storage rules
```

## Status

This repository is a portfolio showcase of an actively developed student platform. Institution-specific production data and operational configuration are maintained privately.
