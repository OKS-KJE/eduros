-- =====================================================================
--  JAN-9301 Project Room — Supabase setup (v2: dates, phases, documents)
--  Run once in Supabase Dashboard → SQL Editor → New query → Run.
--  Safe to re-run: tables use IF NOT EXISTS, policies are recreated,
--  seed rows use ON CONFLICT DO NOTHING.
-- =====================================================================

create extension if not exists pgcrypto;

-- ---------------------------------------------------------------------
-- 1. Tables
-- ---------------------------------------------------------------------

-- Who may use the project room, and which side they sign off for.
create table if not exists public.members (
  email      text primary key,
  name       text not null default '',
  org        text not null check (org in ('jrc','kj')),   -- 'jrc' = JRC, 'kj' = KJ Engineering / EDUROS
  created_at timestamptz not null default now()
);

-- Proposal sections and the sign-off of each side.
create table if not exists public.sections (
  id         text primary key,
  no         int  not null,
  title      text not null,
  anchor     text,                -- section id inside the proposal page
  summary    text,
  jrc_status text not null default 'pending' check (jrc_status in ('pending','approved','changes')),
  jrc_by     uuid,
  jrc_at     timestamptz,
  kj_status  text not null default 'pending' check (kj_status in ('pending','approved','changes')),
  kj_by      uuid,
  kj_at      timestamptz
);

create table if not exists public.tasks (
  id         uuid primary key default gen_random_uuid(),
  title      text not null check (char_length(title) between 1 and 300),
  owner      text not null check (owner in ('jrc','kj','joint')),
  phase      text not null check (phase in ('poc','dev','launch','release')),
  status     text not null default 'todo' check (status in ('todo','doing','review','done')),
  start_date date,                 -- start
  due        date,                 -- planned completion
  done_date  date,                 -- completed
  sort       int  not null default 99,
  created_by uuid default auth.uid(),
  created_at timestamptz not null default now(),
  updated_by uuid,
  updated_at timestamptz not null default now()
);

create table if not exists public.decisions (
  id         text primary key,
  no         int  not null,
  title      text not null,
  context    text not null default '',
  options    jsonb not null default '[]'::jsonb,
  status     text not null default 'open' check (status in ('open','agreed','deferred')),
  outcome    text not null default '',
  start_date date,                 -- start
  due_date   date,                 -- planned completion
  done_date  date,                 -- completed
  updated_by uuid,
  updated_at timestamptz not null default now()
);

create table if not exists public.comments (
  id           uuid primary key default gen_random_uuid(),
  ref          text not null,       -- 'sections/<id>' or 'decisions/<id>'
  body         text not null check (char_length(body) between 1 and 5000),
  org          text not null check (org in ('jrc','kj')),
  author       uuid not null default auth.uid(),
  author_email text not null default lower(coalesce(auth.jwt() ->> 'email','')),
  created_at   timestamptz not null default now()
);
create index if not exists comments_ref_idx on public.comments (ref);

-- Columns added in this version (for databases created with the earlier script)
alter table public.tasks     add column if not exists start_date date;
alter table public.tasks     add column if not exists done_date  date;
alter table public.decisions add column if not exists start_date date;
alter table public.decisions add column if not exists due_date   date;
alter table public.decisions add column if not exists done_date  date;

-- Roadmap phases with start, planned completion and completed dates.
create table if not exists public.phases (
  id         text primary key,
  name       text not null,
  sort       int  not null,
  start_date date,                 -- start
  due_date   date,                 -- planned completion
  done_date  date,                 -- completed
  updated_by uuid,
  updated_at timestamptz not null default now()
);

-- Shared documents (files live in the private Storage bucket "documents").
create table if not exists public.documents (
  id           uuid primary key default gen_random_uuid(),
  cat          text not null check (cat in ('proposal','nda','contract')),
  name         text not null check (char_length(name) between 1 and 255),
  size         bigint not null default 0,
  mime         text not null default 'application/octet-stream',
  path         text not null unique,
  org          text not null check (org in ('jrc','kj')),
  author       uuid not null default auth.uid(),
  author_email text not null default lower(coalesce(auth.jwt() ->> 'email','')),
  created_at   timestamptz not null default now()
);

create table if not exists public.doc_status (
  cat        text primary key check (cat in ('proposal','nda','contract')),
  status     text not null default 'none' check (status in ('none','draft','review','signed')),
  updated_by uuid,
  updated_at timestamptz not null default now()
);

-- ---------------------------------------------------------------------
-- 2. Helper functions
-- ---------------------------------------------------------------------

-- The signed-in user's side ('jrc' or 'kj'), or null if not a member.
create or replace function public.my_org()
returns text language sql stable security definer set search_path = public as $$
  select org from public.members
  where lower(email) = lower(coalesce(auth.jwt() ->> 'email',''))
  limit 1
$$;

create or replace function public.is_member()
returns boolean language sql stable security definer set search_path = public as $$
  select public.my_org() is not null
$$;

-- ---------------------------------------------------------------------
-- 3. Triggers (server-side rules the page cannot bypass)
-- ---------------------------------------------------------------------

-- Each side can change only its own sign-off; who/when is stamped by the server.
-- Section text can only be changed from the SQL Editor (not from the page).
create or replace function public.guard_section_update()
returns trigger language plpgsql security definer set search_path = public as $$
declare o text := public.my_org();
begin
  if auth.uid() is not null then
    if (new.no, new.title, new.anchor, new.summary) is distinct from (old.no, old.title, old.anchor, old.summary) then
      raise exception 'Section text can only be changed by the administrator' using errcode = '42501';
    end if;
    if new.jrc_status is distinct from old.jrc_status and o is distinct from 'jrc' then
      raise exception 'Only JRC members can change the JRC sign-off' using errcode = '42501';
    end if;
    if new.kj_status is distinct from old.kj_status and o is distinct from 'kj' then
      raise exception 'Only KJ Engineering / EDUROS members can change their sign-off' using errcode = '42501';
    end if;
  end if;
  if new.jrc_status is distinct from old.jrc_status then new.jrc_by := auth.uid(); new.jrc_at := now();
  else new.jrc_by := old.jrc_by; new.jrc_at := old.jrc_at; end if;
  if new.kj_status is distinct from old.kj_status then new.kj_by := auth.uid(); new.kj_at := now();
  else new.kj_by := old.kj_by; new.kj_at := old.kj_at; end if;
  return new;
end $$;
drop trigger if exists sections_guard on public.sections;
create trigger sections_guard before update on public.sections
  for each row execute function public.guard_section_update();

-- Comments always carry the real author and side.
create or replace function public.stamp_comment()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is not null then
    new.author := auth.uid();
    new.author_email := lower(auth.jwt() ->> 'email');
    new.org := public.my_org();
  end if;
  new.created_at := now();
  return new;
end $$;
drop trigger if exists comments_stamp on public.comments;
create trigger comments_stamp before insert on public.comments
  for each row execute function public.stamp_comment();

-- Tasks and decisions: stamp who changed them last.
create or replace function public.stamp_update()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  new.updated_by := auth.uid();
  new.updated_at := now();
  return new;
end $$;
drop trigger if exists tasks_stamp on public.tasks;
create trigger tasks_stamp before insert or update on public.tasks
  for each row execute function public.stamp_update();
drop trigger if exists decisions_stamp on public.decisions;
create trigger decisions_stamp before update on public.decisions
  for each row execute function public.stamp_update();
drop trigger if exists phases_stamp on public.phases;
create trigger phases_stamp before update on public.phases
  for each row execute function public.stamp_update();
drop trigger if exists doc_status_stamp on public.doc_status;
create trigger doc_status_stamp before insert or update on public.doc_status
  for each row execute function public.stamp_update();

-- Phase names and order can only be changed from the SQL Editor; members change the dates.
create or replace function public.guard_phase_update()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is not null and (new.id, new.name, new.sort) is distinct from (old.id, old.name, old.sort) then
    raise exception 'Phase names are managed by the administrator' using errcode = '42501';
  end if;
  return new;
end $$;
drop trigger if exists phases_guard on public.phases;
create trigger phases_guard before update on public.phases
  for each row execute function public.guard_phase_update();

-- Documents always carry the real uploader and side.
create or replace function public.stamp_document()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is not null then
    new.author := auth.uid();
    new.author_email := lower(auth.jwt() ->> 'email');
    new.org := public.my_org();
  end if;
  new.created_at := now();
  return new;
end $$;
drop trigger if exists documents_stamp on public.documents;
create trigger documents_stamp before insert on public.documents
  for each row execute function public.stamp_document();

-- ---------------------------------------------------------------------
-- 4. Row Level Security: only listed members can read or write
-- ---------------------------------------------------------------------
alter table public.members   enable row level security;
alter table public.sections  enable row level security;
alter table public.tasks     enable row level security;
alter table public.decisions enable row level security;
alter table public.comments  enable row level security;

drop policy if exists members_read on public.members;
create policy members_read on public.members for select to authenticated using (public.is_member());

drop policy if exists sections_read on public.sections;
create policy sections_read on public.sections for select to authenticated using (public.is_member());
drop policy if exists sections_signoff on public.sections;
create policy sections_signoff on public.sections for update to authenticated
  using (public.is_member()) with check (public.is_member());

drop policy if exists tasks_read on public.tasks;
create policy tasks_read on public.tasks for select to authenticated using (public.is_member());
drop policy if exists tasks_insert on public.tasks;
create policy tasks_insert on public.tasks for insert to authenticated with check (public.is_member());
drop policy if exists tasks_update on public.tasks;
create policy tasks_update on public.tasks for update to authenticated using (public.is_member()) with check (public.is_member());
drop policy if exists tasks_delete on public.tasks;
create policy tasks_delete on public.tasks for delete to authenticated using (public.is_member());

drop policy if exists decisions_read on public.decisions;
create policy decisions_read on public.decisions for select to authenticated using (public.is_member());
drop policy if exists decisions_update on public.decisions;
create policy decisions_update on public.decisions for update to authenticated using (public.is_member()) with check (public.is_member());

alter table public.phases     enable row level security;
alter table public.documents  enable row level security;
alter table public.doc_status enable row level security;

drop policy if exists phases_read on public.phases;
create policy phases_read on public.phases for select to authenticated using (public.is_member());
drop policy if exists phases_update on public.phases;
create policy phases_update on public.phases for update to authenticated using (public.is_member()) with check (public.is_member());

drop policy if exists documents_read on public.documents;
create policy documents_read on public.documents for select to authenticated using (public.is_member());
drop policy if exists documents_insert on public.documents;
create policy documents_insert on public.documents for insert to authenticated with check (public.is_member());
drop policy if exists documents_delete on public.documents;
create policy documents_delete on public.documents for delete to authenticated using (public.is_member());

drop policy if exists doc_status_read on public.doc_status;
create policy doc_status_read on public.doc_status for select to authenticated using (public.is_member());
drop policy if exists doc_status_insert on public.doc_status;
create policy doc_status_insert on public.doc_status for insert to authenticated with check (public.is_member());
drop policy if exists doc_status_update on public.doc_status;
create policy doc_status_update on public.doc_status for update to authenticated using (public.is_member()) with check (public.is_member());

drop policy if exists comments_read on public.comments;
create policy comments_read on public.comments for select to authenticated using (public.is_member());
drop policy if exists comments_insert on public.comments;
create policy comments_insert on public.comments for insert to authenticated with check (public.is_member());
drop policy if exists comments_update_own on public.comments;
create policy comments_update_own on public.comments for update to authenticated using (author = auth.uid()) with check (author = auth.uid());
drop policy if exists comments_delete_own on public.comments;
create policy comments_delete_own on public.comments for delete to authenticated using (author = auth.uid());

-- ---------------------------------------------------------------------
-- 4b. File storage: private bucket "documents", members only (20 MB per file)
-- ---------------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit)
values ('documents', 'documents', false, 20971520)
on conflict (id) do update set public = false, file_size_limit = 20971520;

drop policy if exists "documents members read" on storage.objects;
create policy "documents members read" on storage.objects for select to authenticated
  using (bucket_id = 'documents' and public.is_member());
drop policy if exists "documents members upload" on storage.objects;
create policy "documents members upload" on storage.objects for insert to authenticated
  with check (bucket_id = 'documents' and public.is_member());
drop policy if exists "documents members delete" on storage.objects;
create policy "documents members delete" on storage.objects for delete to authenticated
  using (bucket_id = 'documents' and public.is_member());

-- ---------------------------------------------------------------------
-- 5. Realtime (live updates between JRC and EDUROS)
-- ---------------------------------------------------------------------
do $$
declare t text;
begin
  foreach t in array array['sections','tasks','decisions','comments','phases','documents','doc_status'] loop
    begin
      execute format('alter publication supabase_realtime add table public.%I', t);
    exception when duplicate_object then null;
    end;
  end loop;
end $$;

-- ---------------------------------------------------------------------
-- 6. Members — EDIT THESE before running (one row per person)
--    org: 'jrc' for JRC staff, 'kj' for KJ Engineering / EDUROS staff
-- ---------------------------------------------------------------------
-- insert into public.members (email, name, org) values
--   ('your.name@your-company.com', 'Your Name', 'kj'),
--   ('jrc.contact@jrc-domain.com', 'JRC Contact Name', 'jrc')
-- on conflict (email) do update set name = excluded.name, org = excluded.org;

-- ---------------------------------------------------------------------
-- 7. Seed data from the proposal
-- ---------------------------------------------------------------------
insert into public.sections (id, no, title, anchor, summary) values
 ('s02', 2,  'Executive Summary', 's2', 'Godot 4 simulation core with no licence fees; JAN-9301 added to the existing EDUROS platform; the proven 13-stage, 840-min course carried over; ready before the 2028 product release.'),
 ('s03', 3,  'Our Partnership Track Record', 's3', '20+ years as JRC''s official agent in Korea, ECDIS curriculum co-developed with JRC HQ in 2013, JAN-901B and JAN-9201 courses on EDUROS today.'),
 ('s04', 4,  'References: Training Delivered to Date', 'sref', 'Course Types A–E: 14,034 training records in total (JAN-901B series 3,645, JAN-9201 series 10,389).'),
 ('s05', 5,  'Why a New Training Format for JAN-9301', 's4', 'From Windows-only apps with large installers and e-mailed accounts to web, PC and tablet access with a one-time install on first web access, self-service accounts, natural voice narration and skill-level records.'),
 ('s06', 6,  'From the Course Outline to the Platform', 's5', 'Lecture 320, demonstration 210, exercise 220 and MCQ 90 minutes mapped to online lessons, guided demonstrations, scored CBT exercises and an online MCQ test.'),
 ('s07', 7,  'Course Outline & Timetable: 840 Minutes', 's6', 'Current JRC ECDIS course outline (Rev. 0.0) with 13 learning stages, carried over to JAN-9301 with stage content updated to JAN-9301 functions. See the ClassNK guide for how the stages cover the 10 NK learning areas.'),
 ('s08', 8,  'Technology: Godot 4', 's7', 'Open-source engine (MIT licence) for a 2D CBT JAN-9301 screen replica; delivered by web access with one-time install, Windows PC and tablet; records kept in the existing EDUROS LMS.'),
 ('s09', 9,  'One Platform for All JRC ECDIS Series', 's8', 'JAN-901B, JAN-9201 and JAN-9301 on eduros.com with one pattern: one account and training history, the same course and certificate steps, one place to manage records and certificates, and a new model added as a series rather than a new system.'),
 ('s10', 10, 'Learning Records & Certification', 's9', 'Trainee results flow to the EDUROS LMS and certificate; example assessed actions for stages 5, 6, 7 and 11; results kept offline and synced when connected.'),
 ('s11', 11, 'Certificate Issuance Procedure', 'scert', 'Log in, contents learning, complete, test, pass, user verification (interview, guarantee letter), pass, JRC TST certificate issue.'),
 ('s12', 12, 'Roadmap 2026 – 2028', 's10', 'PoC Q4 2026 – Q1 2027 (Stage 5 Route planning), full development H1 2027, launch H2 2027, JAN-9301 release 2028.'),
 ('s13', 13, 'Under Review: Cyber Security (IACS UR E26/E27)', 'sreview', 'Not part of the type-specific syllabus. Options: A not included, B separate optional module on EDUROS, C add later if JRC confirms operator-level procedures.'),
 ('s14', 14, 'Roles & Points to Agree', 's11', 'What JRC provides (software, emulator, UI specifications and assets, technical review, co-branding) and what EDUROS / KJ Engineering provides (development, platform, instructors, updates).')
on conflict (id) do nothing;

insert into public.tasks (id, title, owner, phase, status, start_date, due, done_date, sort) values
 ('00000000-0000-4000-8000-000000000001', 'Kick-off meeting with the JRC training team', 'joint', 'poc', 'todo', null, null, null, 1),
 ('00000000-0000-4000-8000-000000000002', 'Agree PoC scope (Stage 5 Route planning) and review schedule', 'joint', 'poc', 'todo', null, null, null, 2),
 ('00000000-0000-4000-8000-000000000003', 'Share JAN-9301 software, emulator and UI specifications', 'jrc', 'poc', 'todo', null, null, null, 3),
 ('00000000-0000-4000-8000-000000000004', 'Provide JAN-9301 screen designs, icons and UI assets', 'jrc', 'poc', 'todo', null, null, null, 4),
 ('00000000-0000-4000-8000-000000000005', 'Build Stage 5 Route planning PoC (2D CBT, Godot 4) on web and PC', 'kj', 'poc', 'todo', null, null, null, 5),
 ('00000000-0000-4000-8000-000000000006', 'Joint PoC review before end of Q1 2027', 'joint', 'poc', 'todo', null, '2027-03-31', null, 6),
 ('00000000-0000-4000-8000-000000000007', 'Develop all 13 stages as 2D CBT', 'kj', 'dev', 'todo', null, null, null, 1),
 ('00000000-0000-4000-8000-000000000008', 'Build the JAN-9301 MCQ question bank', 'kj', 'dev', 'todo', null, null, null, 2),
 ('00000000-0000-4000-8000-000000000009', 'Natural multilingual voice narration', 'kj', 'dev', 'todo', null, null, null, 3),
 ('00000000-0000-4000-8000-000000000010', 'Add JAN-9301 series to the EDUROS LMS (self-service account and install, certificate type)', 'kj', 'dev', 'todo', null, null, null, 4),
 ('00000000-0000-4000-8000-000000000011', 'Technical review of content and scenarios', 'jrc', 'dev', 'todo', null, null, null, 5),
 ('00000000-0000-4000-8000-000000000012', 'Confirm ClassNK learning-area coverage for JAN-9301 (areas a–j)', 'joint', 'dev', 'todo', null, null, null, 6),
 ('00000000-0000-4000-8000-000000000013', 'Launch the online service on EDUROS', 'kj', 'launch', 'todo', null, null, null, 1),
 ('00000000-0000-4000-8000-000000000014', 'Pilot with training centres and fleets', 'joint', 'launch', 'todo', null, null, null, 2),
 ('00000000-0000-4000-8000-000000000015', 'Co-branding and promotion to JRC customers', 'jrc', 'launch', 'todo', null, null, null, 3),
 ('00000000-0000-4000-8000-000000000016', 'Align content with the final JAN-9301 software', 'joint', 'release', 'todo', null, null, null, 1),
 ('00000000-0000-4000-8000-000000000017', 'Global roll-out and updates aligned with JRC software releases', 'joint', 'release', 'todo', null, null, null, 2)
on conflict (id) do nothing;

insert into public.decisions (id, no, title, context, options) values
 ('d1', 1, 'PoC scope and review schedule', 'Proposed PoC: Stage 5 Route planning (120 min), built on web and PC, reviewed jointly with the JRC training team.', '[]'),
 ('d2', 2, 'Timing and terms for sharing JAN-9301 data', 'JAN-9301 software, emulator, UI specifications and screen assets needed before the PoC can start.', '[]'),
 ('d3', 3, 'Cyber security (IACS UR E26/E27)', 'Not part of the JRC ECDIS type-specific syllabus. Whether and how to cover it is under review.',
   '["A: Not included", "B: Separate optional module on EDUROS, outside the 840-min syllabus and the TST certificate", "C: Add later if JRC confirms operator-level security procedures in the JAN-9301 manual"]'),
 ('d4', 4, 'Kick-off meeting and PoC review timing', 'Kick-off with the JRC training team, and PoC review before the end of Q1 2027.', '[]'),
 ('d5', 5, 'Use of Stage 12 (Operation of the former ECDIS)', 'Proposed use for JAN-9301: a migration course for trainees moving from JAN-9201.', '[]')
on conflict (id) do nothing;

insert into public.phases (id, name, sort, start_date, due_date) values
 ('poc',     'Proof of concept', 1, '2026-10-01', '2027-03-31'),
 ('dev',     'Full development', 2, '2027-04-01', '2027-06-30'),
 ('launch',  'Launch',           3, '2027-07-01', '2027-12-31'),
 ('release', 'JAN-9301 release', 4, '2028-01-01', '2028-12-31')
on conflict (id) do nothing;

insert into public.doc_status (cat, status) values
 ('proposal', 'review'), ('nda', 'none'), ('contract', 'none')
on conflict (cat) do nothing;
