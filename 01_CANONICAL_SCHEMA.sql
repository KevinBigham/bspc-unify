-- ============================================================================
-- BSPC UNIFY — 01_CANONICAL_SCHEMA.sql
-- The canonical Postgres schema. THIS FILE IS LAW.
--
-- Strategy: "BSPC's schema, extended." Every BSPC parent-app table is kept
-- (some widened per ratified decisions); the Coach App's Firestore model is
-- folded in as additive tables, gated from parents by strict RLS.
--
-- DESIGN ARTIFACT — not yet applied to any database. Data backfill / migration
-- scripts are a SEPARATE deliverable (this file is structure only).
--
-- Ratified decisions (see UNIFY/00_TERRAIN.md §6):
--   #1  Swim times stored as HUNDREDTHS of a second everywhere (was time_ms).
--   #2  Single 8-value practice_group enum (adds Masters + Swim Lessons).
--   #3  One identity model: profiles (coaches/parents collapsed); coach role
--       map admin->super_admin, coach->coach_admin; coaches.groups[] -> coach_groups.
--   #4  Relational households kept (families); + see D-A.
--   #5  Attendance widened (nullable schedule_event_id + practice_date +
--       check-in/out + status enum); parents read a derived present/absent VIEW.
--   #6  meets is a superset (parent-info + competition columns) + child meet_entries.
--   #7  Push = Expo only (push_tokens); coaches.fcmTokens[] dropped.
--   SCOPE  Coach-only data (notes, goals, media, plans, medical) HOSTED but
--          walled off from parents by strict RLS (COPPA / SafeSport).
--   AR-1  Standards/age-group kept as free text on time_standards.
--   AR-2  BSPC scrape pipeline canonical; coach calendar in a SEPARATE table.
--
-- RATIFIED RED-TEAM DECISIONS (see UNIFY/02_SCHEMA_REDTEAM.md):
--   D-A  GUARDIANSHIPS join table replaces the singular swimmers.family_id access
--        model. A swimmer may have multiple guardians across multiple households
--        (shared custody). swimmers.family_id is REMOVED; access resolves through
--        guardianships(guardian_profile_id <-> swimmer_id). is_my_swimmer() and all
--        family-facing RLS resolve through it. families/profiles.family_id remain
--        only as a guardian "household" grouping. (Resolves P0-9; also moots P1-2.)
--   D-B  Attendance two-a-days use TWO PARTIAL UNIQUE INDEXES + ON DELETE RESTRICT
--        on schedule_event_id. NULLS NOT DISTINCT and its Postgres-15 dependency
--        are REMOVED. (Resolves P0-6, P2-7; Coach App attendance tests verified green.)
--
-- RED-TEAM FIXES APPLIED (severity — see 02_SCHEMA_REDTEAM.md):
--   PRIVACY FIRST: P0-1 profiles privilege-escalation (trigger + WITH CHECK);
--     P0-2 calendar_event_rsvps cross-family minor-PII leak (scoped RLS).
--   P0-3 attendance.status nullable; P0-4 parent-view present/absent mapping;
--   P0-5 swim_results.date nullable; P0-6/D-B attendance keys.
--   P1-1 coach-deletion policy (ON DELETE RESTRICT on coach authorship);
--   P1-3 nullable *_by -> ON DELETE SET NULL; P1-4 media multi-select normalized to
--     junction tables (consent integrity); P1-5 source_ref_id split into typed FKs;
--   P1-6 in_app rule_id FK; P1-7 in_app UPDATE WITH CHECK; P1-8 is_active_account()
--     gate (pending may read team data, deactivated may not — see NOTES);
--   P1-9 schedule_change_log staff-only; P1-10 RLS helper refactor;
--   P1-11 attendance_parent_view ownership contract documented (fails closed);
--   P1-13 personal_bests.course NOT NULL (dedup); P2-3 in_app idempotency partial
--     index; P2-4 personal_bests.meet_name provenance.
--   Actor refs (created_by/marked_by/reviewed_by/coach_id) STANDARDIZED on
--     profiles(id) — removes the dual-remap landmine (P0-8). Per-user own-row tables
--     (push_tokens, notification_preferences, in_app_notifications, feedback) keep
--     user_id -> auth.users(id) since their RLS is user_id = auth.uid().
--
-- DEFERRED P2s (with reason):
--   P2-1/P2-2 (parent sees own-child media_consent / coach_id on meets&calendar):
--     RLS cannot hide columns; resolved by parent-facing VIEWS in the APP migration.
--   P2-5 aggregations recompute, P2-8 enum hygiene, P2-9 recurring expansion,
--     P2-10 ratings JSONB key rewrite, P2-6 name/location relaxation: BACKFILL/APP.
--   P2-11 template_source_id cycle guard: low priority, deferred.
-- Intentionally OMITTED (declared-but-unimplemented in Firestore): messages,
-- coach_chat, workout_library, and meet relays/live_events/splits.
-- ============================================================================

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ============================================================================
-- ENUMS
-- ============================================================================
CREATE TYPE user_role       AS ENUM ('family', 'coach_admin', 'super_admin');
CREATE TYPE account_status  AS ENUM ('pending', 'approved', 'deactivated');
CREATE TYPE urgency_level   AS ENUM ('urgent', 'normal', 'fyi');

-- [#5] attendance_status widened; coach "normal" maps to 'present' at backfill.
CREATE TYPE attendance_status AS ENUM
  ('present', 'absent', 'excused', 'sick', 'injured', 'left_early');

-- [#2] Single 8-value practice-group set.
CREATE TYPE practice_group AS ENUM
  ('Bronze', 'Silver', 'Gold', 'Advanced', 'Platinum', 'Diamond', 'Masters', 'Swim Lessons');

CREATE TYPE course           AS ENUM ('SCY', 'SCM', 'LCM');
CREATE TYPE gender           AS ENUM ('M', 'F');
CREATE TYPE standard_level   AS ENUM ('B', 'BB', 'A', 'AA', 'AAA', 'AAAA');
CREATE TYPE meet_status      AS ENUM ('upcoming', 'in_progress', 'completed', 'cancelled');
CREATE TYPE calendar_event_type AS ENUM ('practice', 'meet', 'team_event', 'fundraiser', 'social');
CREATE TYPE rsvp_status      AS ENUM ('going', 'maybe', 'not_going');
CREATE TYPE swim_time_source AS ENUM ('manual', 'sdif_import', 'hy3_import');
CREATE TYPE note_source      AS ENUM ('manual', 'audio_ai', 'video_ai', 'voice_inline');
CREATE TYPE note_tag AS ENUM (
  'technique','freestyle','backstroke','breaststroke','butterfly','IM','starts',
  'turns','underwaters','breakouts','kick','pull','drill','endurance','speed',
  'race strategy','mental','attendance','general');
CREATE TYPE audio_session_status AS ENUM
  ('queued','uploading','uploaded','transcribing','extracting','review','posted','failed');
CREATE TYPE video_session_status AS ENUM
  ('queued','uploading','uploaded','extracting_frames','analyzing','review','posted','failed');
CREATE TYPE video_analysis_phase AS ENUM
  ('stroke','turn','start','underwater','breakout','finish','general');
CREATE TYPE season_phase_type AS ENUM
  ('base','build1','build2','peak','taper','race','recovery');
CREATE TYPE notification_rule_trigger AS ENUM
  ('attendance_streak','missed_practice','pr_achieved','time_standard_met','birthday','custom');
CREATE TYPE notification_category AS ENUM
  ('schedule_change','announcement','daily_digest','ai_drafts_ready','standard_achieved','general');
CREATE TYPE import_job_type   AS ENUM ('csv_roster','sdif','hy3','cl2');
CREATE TYPE import_job_status AS ENUM ('processing','complete','failed');
CREATE TYPE media_select_kind AS ENUM ('tagged','selected');  -- [P1-4] media junction role

-- (RLS helper functions + attendance_parent_view are defined AFTER the tables
-- they read — see the "RLS HELPER FUNCTIONS + PARENT VIEW" section below the table
-- definitions — so their SQL bodies validate against existing tables under
-- Postgres's default check_function_bodies.)

-- ============================================================================
-- IDENTITY, HOUSEHOLDS & GUARDIANSHIPS
-- ============================================================================

-- families — household grouping of guardians (a guardian's profiles.family_id).
-- [D-A] swimmers are NO LONGER tied to a family; access is via guardianships.
CREATE TABLE families (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- profiles — [#3] the single identity table (coaches + parents folded in).
-- [P0-1] role/account_status/family_id are protected by a BEFORE UPDATE trigger
-- (enforce_profile_self_update) so a user cannot self-escalate or self-link.
CREATE TABLE profiles (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL UNIQUE REFERENCES auth.users(id) ON DELETE CASCADE,
  email TEXT NOT NULL,
  full_name TEXT NOT NULL,
  role user_role NOT NULL DEFAULT 'family',
  account_status account_status NOT NULL DEFAULT 'pending',
  family_id UUID REFERENCES families(id) ON DELETE SET NULL,   -- household (guardians)
  push_enabled BOOLEAN NOT NULL DEFAULT TRUE,
  deck_mode BOOLEAN NOT NULL DEFAULT FALSE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- coach_groups — [#3] replaces coaches.groups[].
CREATE TABLE coach_groups (
  profile_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  practice_group practice_group NOT NULL,
  PRIMARY KEY (profile_id, practice_group)
);

-- swimmers — [D-A] family_id REMOVED. A swimmer stands alone on the roster and is
-- linked to guardians via guardianships. created_by / consent-granter -> SET NULL.
CREATE TABLE swimmers (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  first_name TEXT NOT NULL,
  last_name TEXT,                                                -- [P2-6] nullable (mononym/incomplete roster)
  display_name TEXT,
  practice_group practice_group NOT NULL,
  date_of_birth DATE,
  gender gender,
  usa_swimming_id TEXT,
  profile_photo_url TEXT,
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  do_not_photograph BOOLEAN NOT NULL DEFAULT FALSE,
  media_consent_granted BOOLEAN NOT NULL DEFAULT FALSE,
  media_consent_at TIMESTAMPTZ,
  media_consent_expires_at TIMESTAMPTZ,
  media_consent_granted_by UUID REFERENCES profiles(id) ON DELETE SET NULL,  -- [P1-3]
  media_consent_notes TEXT,
  created_by UUID REFERENCES profiles(id) ON DELETE SET NULL,                -- [P1-3]
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- guardianships — [D-A] THE access primitive. guardian profile <-> swimmer, N:M,
-- across households (shared custody). Writes are STAFF-ONLY / via SECURITY DEFINER
-- invite redemption — a family user must NEVER self-insert a link (that would be a
-- P0-1-class access grant). is_primary marks the lead household for display.
CREATE TABLE guardianships (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  guardian_profile_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  swimmer_id UUID NOT NULL REFERENCES swimmers(id) ON DELETE CASCADE,
  relationship TEXT,                              -- 'mother','father','guardian',...
  is_primary BOOLEAN NOT NULL DEFAULT FALSE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (guardian_profile_id, swimmer_id)
);

-- swimmer_coach_profile — [SCOPE] coach assessments. Strict staff-only.
CREATE TABLE swimmer_coach_profile (
  swimmer_id UUID PRIMARY KEY REFERENCES swimmers(id) ON DELETE CASCADE,
  strengths TEXT[] NOT NULL DEFAULT '{}',
  weaknesses TEXT[] NOT NULL DEFAULT '{}',
  technique_focus_areas TEXT[] NOT NULL DEFAULT '{}',
  meet_schedule TEXT[] NOT NULL DEFAULT '{}',
  parent_contacts JSONB NOT NULL DEFAULT '[]',
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- swimmer_medical — [SCOPE] strictest wall: staff read, super_admin write.
CREATE TABLE swimmer_medical (
  swimmer_id UUID PRIMARY KEY REFERENCES swimmers(id) ON DELETE CASCADE,
  allergies TEXT,
  conditions TEXT,
  medications TEXT,
  emergency_contact JSONB,
  info JSONB,
  updated_by UUID REFERENCES profiles(id) ON DELETE SET NULL,  -- [P1-3]
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- parent_invites — [D-A] redemption creates a guardianship (link redeemer<->swimmer)
-- via a SECURITY DEFINER RPC. coach_id authorship -> RESTRICT [P1-1]; redeemer -> SET NULL.
CREATE TABLE parent_invites (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  code TEXT NOT NULL UNIQUE,
  swimmer_id UUID NOT NULL REFERENCES swimmers(id) ON DELETE CASCADE,
  coach_id UUID NOT NULL REFERENCES profiles(id) ON DELETE RESTRICT,  -- [P1-1]
  redeemed BOOLEAN NOT NULL DEFAULT FALSE,
  redeemed_by UUID REFERENCES profiles(id) ON DELETE SET NULL,        -- [P1-3]
  redeemed_at TIMESTAMPTZ,
  expires_at TIMESTAMPTZ NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================================================
-- SCHEDULE — BSPC scrape pipeline + [AR-2] coach calendar
-- ============================================================================
CREATE TABLE schedule_events (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  practice_group practice_group NOT NULL,
  title TEXT NOT NULL,
  start_time TIMESTAMPTZ NOT NULL,
  end_time TIMESTAMPTZ NOT NULL,
  location TEXT NOT NULL DEFAULT 'Blue Springs Aquatic Center',
  is_cancelled BOOLEAN NOT NULL DEFAULT FALSE,
  cancellation_reason TEXT,
  notes TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE raw_schedule_snapshots (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  raw_html TEXT NOT NULL,
  source_url TEXT NOT NULL,
  scraped_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  is_valid BOOLEAN NOT NULL DEFAULT TRUE
);

CREATE TABLE imported_schedule_events (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  snapshot_id UUID NOT NULL REFERENCES raw_schedule_snapshots(id) ON DELETE CASCADE,
  practice_group practice_group NOT NULL,
  title TEXT NOT NULL,
  start_time TIMESTAMPTZ NOT NULL,
  end_time TIMESTAMPTZ NOT NULL,
  location TEXT,
  imported_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- created_by standardized on profiles(id) + SET NULL [P1-3, actor-ref standardization].
CREATE TABLE schedule_overrides (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  schedule_event_id UUID REFERENCES schedule_events(id) ON DELETE CASCADE,
  practice_group practice_group NOT NULL,
  title TEXT,
  start_time TIMESTAMPTZ,
  end_time TIMESTAMPTZ,
  location TEXT,
  is_cancelled BOOLEAN,
  cancellation_reason TEXT,
  notes TEXT,
  created_by UUID REFERENCES profiles(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE schedule_change_log (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  schedule_event_id UUID REFERENCES schedule_events(id) ON DELETE SET NULL,
  change_type TEXT NOT NULL CHECK (change_type IN ('created','updated','cancelled','restored')),
  change_summary TEXT NOT NULL,
  previous_data JSONB,
  new_data JSONB,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- [AR-2] coach-authored calendar (kept separate from the scrape pipeline).
-- [D-H3, ratified 2026-06-10] hosts the iCal sync: + source/ical_uid/raw_rrule/
-- synced_at; coach_id relaxed to NULLABLE + SET NULL (synced rows carry
-- coach_id NULL + source='ical_sync'; the FK keeps fake owners unrepresentable
-- — a string sentinel can never exist). Upsert key = the plain ical_uid UNIQUE.
CREATE TABLE calendar_events (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  title TEXT NOT NULL,
  description TEXT,
  type calendar_event_type NOT NULL,
  start_date DATE NOT NULL,
  start_time TEXT,
  end_date DATE,
  end_time TEXT,
  location TEXT,
  groups practice_group[] NOT NULL DEFAULT '{}',
  recurring JSONB,
  coach_id UUID REFERENCES profiles(id) ON DELETE SET NULL,  -- [P1-1 spirit; D-H3 nullable]
  source TEXT,                                     -- [D-H3] provenance ('ical_sync')
  ical_uid TEXT UNIQUE,                            -- [D-H3] the sync upsert key
  raw_rrule TEXT,                                  -- [D-H3]
  synced_at TIMESTAMPTZ,                           -- [D-H3]
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE calendar_event_rsvps (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  event_id UUID NOT NULL REFERENCES calendar_events(id) ON DELETE CASCADE,
  swimmer_id UUID NOT NULL REFERENCES swimmers(id) ON DELETE CASCADE,
  status rsvp_status NOT NULL,
  parent_name TEXT,
  note TEXT,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (event_id, swimmer_id)
);

-- ============================================================================
-- ANNOUNCEMENTS — created_by standardized on profiles(id) + SET NULL.
-- ============================================================================
CREATE TABLE announcements (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  title TEXT NOT NULL,
  body TEXT NOT NULL,
  urgency urgency_level NOT NULL DEFAULT 'normal',
  target_group practice_group,
  is_pinned BOOLEAN NOT NULL DEFAULT FALSE,
  expires_at TIMESTAMPTZ,
  created_by UUID REFERENCES profiles(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================================================
-- MEETS — [#6] superset + child meet_entries.
-- ============================================================================
CREATE TABLE meets (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  location TEXT NOT NULL,
  address TEXT,
  start_date DATE NOT NULL,
  end_date DATE,
  warmup_time TIME,
  event_start_time TIME,
  what_to_bring TEXT,
  notes TEXT,
  commit_url TEXT,
  course course,
  status meet_status,
  events JSONB,
  groups practice_group[] NOT NULL DEFAULT '{}',
  sanction_number TEXT,
  host_team TEXT,
  coach_id UUID REFERENCES profiles(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE meet_entries (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  meet_id UUID NOT NULL REFERENCES meets(id) ON DELETE CASCADE,
  swimmer_id UUID NOT NULL REFERENCES swimmers(id) ON DELETE CASCADE,
  practice_group practice_group,
  gender gender,
  age INTEGER,
  event_name TEXT NOT NULL,
  event_number INTEGER,
  seed_time_hundredths INTEGER,                    -- [#1]
  final_time_hundredths INTEGER,                   -- [#1]
  place INTEGER,
  heat INTEGER,
  lane INTEGER,
  is_personal_best BOOLEAN NOT NULL DEFAULT FALSE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================================================
-- TIMES, PERSONAL BESTS, GOALS
-- ============================================================================

-- swim_results — [#1] time_hundredths. [P0-5] date NULLABLE (Coach App manual
-- times carry no date; backfill date := COALESCE(meet_date, created_at::date)).
CREATE TABLE swim_results (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  swimmer_id UUID NOT NULL REFERENCES swimmers(id) ON DELETE CASCADE,
  event_name TEXT NOT NULL,
  course course,
  time_hundredths INTEGER NOT NULL,                -- [#1]
  splits INTEGER[],                                -- [#1] hundredths per 50
  meet_id UUID REFERENCES meets(id) ON DELETE SET NULL,
  meet_name TEXT,
  date DATE,                                       -- [P0-5] nullable
  is_personal_best BOOLEAN NOT NULL DEFAULT FALSE,
  source swim_time_source NOT NULL DEFAULT 'manual',
  created_by UUID REFERENCES profiles(id) ON DELETE SET NULL,  -- [P1-3]
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- personal_bests — [#1] hundredths. [P1-13] course NOT NULL (a PB is course-
-- specific) so (swimmer, event, course) dedups cleanly (backfill assigns course to
-- legacy BSPC rows). [P2-4] meet_name provenance fallback added.
CREATE TABLE personal_bests (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  swimmer_id UUID NOT NULL REFERENCES swimmers(id) ON DELETE CASCADE,
  event_name TEXT NOT NULL,
  course course NOT NULL,                          -- [P1-13]
  time_hundredths INTEGER NOT NULL,                -- [#1]
  achieved_at DATE NOT NULL,
  meet_id UUID REFERENCES meets(id) ON DELETE SET NULL,
  meet_name TEXT,                                  -- [P2-4]
  UNIQUE (swimmer_id, event_name, course)
);

-- goals — [SCOPE] family-readable for own swimmer; staff write.
CREATE TABLE goals (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  swimmer_id UUID NOT NULL REFERENCES swimmers(id) ON DELETE CASCADE,
  event_name TEXT NOT NULL,
  course course,
  target_standard standard_level,
  target_time_hundredths INTEGER,                  -- [#1]
  current_time_hundredths INTEGER,                 -- [#1]
  notes TEXT,
  achieved BOOLEAN NOT NULL DEFAULT FALSE,
  achieved_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================================================
-- COACHING NOTES — [SCOPE] strict staff-only. coach_id -> RESTRICT [P1-1].
-- [P1-5] source_ref_id split into two typed nullable FKs (added at end to avoid a
-- create-order cycle) + a CHECK that at most one is set.
-- ============================================================================
CREATE TABLE swimmer_notes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  swimmer_id UUID NOT NULL REFERENCES swimmers(id) ON DELETE CASCADE,
  content TEXT NOT NULL,
  tags note_tag[] NOT NULL DEFAULT '{}',
  source note_source NOT NULL DEFAULT 'manual',
  source_audio_draft_id UUID,                      -- [P1-5] FK added below
  source_voice_note_id UUID,                       -- [P1-5] FK added below
  coach_id UUID NOT NULL REFERENCES profiles(id) ON DELETE RESTRICT,  -- [P1-1]
  practice_date DATE NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CHECK (num_nonnulls(source_audio_draft_id, source_voice_note_id) <= 1)  -- [P1-5]
);

CREATE TABLE group_notes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  content TEXT NOT NULL,
  tags note_tag[] NOT NULL DEFAULT '{}',
  practice_group practice_group NOT NULL,
  practice_date DATE NOT NULL,
  coach_id UUID NOT NULL REFERENCES profiles(id) ON DELETE RESTRICT,  -- [P1-1]
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE swimmer_voice_notes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  swimmer_id UUID NOT NULL REFERENCES swimmers(id) ON DELETE CASCADE,
  coach_id UUID NOT NULL REFERENCES profiles(id) ON DELETE RESTRICT,  -- [P1-1]
  storage_path TEXT,
  duration_sec INTEGER,
  practice_date DATE,
  transcription TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================================================
-- MEDIA + AI DRAFTS — [SCOPE] strict staff-only. [P1-4] multi-selects normalized
-- into junction tables so consent/roster integrity is enforced by FK (no orphan
-- swimmer ids in arrays); posted_note_id FKs added at end (cycle with swimmer_notes).
-- ============================================================================
CREATE TABLE audio_sessions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  coach_id UUID NOT NULL REFERENCES profiles(id) ON DELETE RESTRICT,  -- [P1-1]
  storage_path TEXT,
  duration_sec INTEGER,
  practice_date DATE NOT NULL,
  practice_group practice_group,
  status audio_session_status NOT NULL DEFAULT 'queued',
  transcription TEXT,
  error_message TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- [P1-4] replaces audio_sessions.selected_swimmer_ids UUID[].
CREATE TABLE audio_session_swimmers (
  session_id UUID NOT NULL REFERENCES audio_sessions(id) ON DELETE CASCADE,
  swimmer_id UUID NOT NULL REFERENCES swimmers(id) ON DELETE CASCADE,
  PRIMARY KEY (session_id, swimmer_id)
);

CREATE TABLE audio_session_drafts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  session_id UUID NOT NULL REFERENCES audio_sessions(id) ON DELETE CASCADE,
  swimmer_id UUID NOT NULL REFERENCES swimmers(id) ON DELETE CASCADE,
  observation TEXT NOT NULL,
  tags note_tag[] NOT NULL DEFAULT '{}',
  confidence REAL,
  approved BOOLEAN,
  reviewed_by UUID REFERENCES profiles(id) ON DELETE SET NULL,  -- [P1-3]
  posted_note_id UUID,                             -- [P1-5] FK added below
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE video_sessions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  coach_id UUID NOT NULL REFERENCES profiles(id) ON DELETE RESTRICT,  -- [P1-1]
  storage_path TEXT,
  thumbnail_path TEXT,
  duration_sec INTEGER,
  practice_date DATE NOT NULL,
  practice_group practice_group,
  status video_session_status NOT NULL DEFAULT 'queued',
  frame_count INTEGER,
  error_message TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- [P1-4] replaces video_sessions.tagged_swimmer_ids / selected_swimmer_ids UUID[].
-- kind='tagged' is the media-consent-gated set; FK guarantees no stale swimmer id.
CREATE TABLE video_session_swimmers (
  session_id UUID NOT NULL REFERENCES video_sessions(id) ON DELETE CASCADE,
  swimmer_id UUID NOT NULL REFERENCES swimmers(id) ON DELETE CASCADE,
  kind media_select_kind NOT NULL,
  PRIMARY KEY (session_id, swimmer_id, kind)
);

CREATE TABLE video_session_drafts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  session_id UUID NOT NULL REFERENCES video_sessions(id) ON DELETE CASCADE,
  swimmer_id UUID NOT NULL REFERENCES swimmers(id) ON DELETE CASCADE,
  observation TEXT NOT NULL,
  diagnosis TEXT,
  drill_recommendation TEXT,
  phase video_analysis_phase NOT NULL DEFAULT 'general',
  tags note_tag[] NOT NULL DEFAULT '{}',
  confidence REAL,
  approved BOOLEAN,
  reviewed_by UUID REFERENCES profiles(id) ON DELETE SET NULL,  -- [P1-3]
  posted_note_id UUID,                             -- [P1-5] FK added below
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================================================
-- PRACTICE & SEASON PLANNING — [SCOPE] staff-only. coach_id -> RESTRICT [P1-1].
-- ============================================================================
CREATE TABLE practice_plans (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  title TEXT NOT NULL,
  description TEXT,
  practice_group practice_group,
  is_template BOOLEAN NOT NULL DEFAULT FALSE,
  is_public BOOLEAN NOT NULL DEFAULT FALSE,
  template_source_id UUID REFERENCES practice_plans(id) ON DELETE SET NULL,
  plan_date DATE,
  total_duration_min INTEGER,
  tags TEXT[] NOT NULL DEFAULT '{}',
  ratings JSONB NOT NULL DEFAULT '{}',
  sets JSONB NOT NULL DEFAULT '[]',
  document_type TEXT,
  storage_path TEXT,
  filename TEXT,
  uploaded_at TIMESTAMPTZ,
  size_bytes INTEGER,
  page_count INTEGER,
  coach_id UUID NOT NULL REFERENCES profiles(id) ON DELETE RESTRICT,  -- [P1-1]
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE season_plans (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  practice_group practice_group NOT NULL,
  start_date DATE NOT NULL,
  end_date DATE NOT NULL,
  phases JSONB NOT NULL DEFAULT '[]',
  total_weeks INTEGER,
  coach_id UUID NOT NULL REFERENCES profiles(id) ON DELETE RESTRICT,  -- [P1-1]
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE season_plan_weeks (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  season_plan_id UUID NOT NULL REFERENCES season_plans(id) ON DELETE CASCADE,
  week_number INTEGER NOT NULL,
  start_date DATE NOT NULL,
  end_date DATE NOT NULL,
  phase season_phase_type NOT NULL,
  target_yardage INTEGER,
  actual_yardage INTEGER,
  practice_count INTEGER NOT NULL DEFAULT 0,
  notes TEXT,
  practice_plan_ids UUID[] NOT NULL DEFAULT '{}',  -- best-effort refs (not FK-enforced)
  UNIQUE (season_plan_id, week_number)
);

-- ============================================================================
-- ATTENDANCE — [#5] widened. [D-B] two-a-days via PARTIAL UNIQUE INDEXES (below)
-- + schedule_event_id ON DELETE RESTRICT (no SET-NULL convergence collision).
-- [P0-3] status NULLABLE (check-in writes null; "row exists" => present).
-- marked_by standardized on profiles(id) + SET NULL.
-- ============================================================================
CREATE TABLE attendance (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  swimmer_id UUID NOT NULL REFERENCES swimmers(id) ON DELETE CASCADE,
  schedule_event_id UUID REFERENCES schedule_events(id) ON DELETE RESTRICT,  -- [D-B/P0-6]
  practice_date DATE NOT NULL,
  practice_group practice_group,
  status attendance_status,                        -- [P0-3] nullable; NULL = checked-in/present
  arrived_at TIMESTAMPTZ,
  departed_at TIMESTAMPTZ,
  note TEXT,
  marked_by UUID REFERENCES profiles(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
  -- uniqueness enforced by partial indexes below ([D-B]).
);

-- (attendance_parent_view is defined in the "RLS HELPER FUNCTIONS + PARENT VIEW"
-- section below, after is_my_swimmer() exists.)

-- ============================================================================
-- NOTIFICATIONS & PUSH — own-row tables keep user_id -> auth.users(id).
-- ============================================================================
CREATE TABLE push_tokens (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  expo_push_token TEXT NOT NULL,
  platform TEXT NOT NULL CHECK (platform IN ('ios','android')),
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (user_id, expo_push_token)
);

CREATE TABLE notification_preferences (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL UNIQUE REFERENCES auth.users(id) ON DELETE CASCADE,
  push_enabled BOOLEAN NOT NULL DEFAULT TRUE,
  daily_digest BOOLEAN,
  new_notes BOOLEAN,
  attendance_alerts BOOLEAN,
  ai_drafts_ready BOOLEAN,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE notification_jobs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  title TEXT NOT NULL,
  body TEXT NOT NULL,
  deep_link TEXT,
  target_group practice_group,
  target_user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  is_urgent BOOLEAN NOT NULL DEFAULT FALSE,
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','sent','failed')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  sent_at TIMESTAMPTZ
);

-- [P1-6] rule_id FK added; [P2-3] idempotency via partial unique index (below);
-- [P1-7] UPDATE WITH CHECK enforced in RLS.
CREATE TABLE in_app_notifications (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  title TEXT NOT NULL,
  body TEXT NOT NULL,
  deep_link TEXT,
  category notification_category,
  data JSONB,
  rule_id UUID,                                    -- [P1-6] FK added in the deferred-FK section (notification_rules is created later)
  swimmer_id UUID REFERENCES swimmers(id) ON DELETE SET NULL,
  source_eval_date DATE,
  is_read BOOLEAN NOT NULL DEFAULT FALSE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE notification_rules (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  trigger notification_rule_trigger NOT NULL,
  enabled BOOLEAN NOT NULL DEFAULT TRUE,
  config JSONB NOT NULL DEFAULT '{}',
  coach_id UUID NOT NULL REFERENCES profiles(id) ON DELETE RESTRICT,  -- [P1-1]
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================================================
-- IMPORTS — [SCOPE] staff-only. coach_id -> RESTRICT [P1-1].
-- ============================================================================
CREATE TABLE import_jobs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  type import_job_type NOT NULL,
  file_name TEXT NOT NULL,
  storage_path TEXT,
  status import_job_status NOT NULL DEFAULT 'processing',
  error_message TEXT,
  summary JSONB,
  coach_id UUID NOT NULL REFERENCES profiles(id) ON DELETE RESTRICT,  -- [P1-1]
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ
);

-- ============================================================================
-- AGGREGATIONS — [SCOPE] read-model store; staff read; writes by service role/
-- triggers only. [P2-5] DO NOT migrate rows; recompute post-migration.
-- [D-J2, ratified 2026-06-10] the JSONB doc-store table drafted here is
-- RETIRED from canonical (a narrowing — no migration ever created it; the
-- 04 §156 "PG-computed views" wording prevails). Phase J recomputes via
-- STAFF-GATED, COMPUTE-ON-READ VIEWS, each carrying an explicit is_staff()
-- arm (the no-widening wall; family/pending/anon prove to zero rows). The
-- [P2-5] law above survives verbatim — it is the law the views implement;
-- "writes by service role/triggers" is moot (a view is not written). The
-- RLS-enable + select policy retired below under the same decision.
-- ============================================================================

-- ============================================================================
-- REFERENCE & MISC — [#1] time_hundredths; [AR-1] standards free text.
-- ============================================================================
CREATE TABLE team_records (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  event_name TEXT NOT NULL,
  time_hundredths INTEGER NOT NULL,                -- [#1]
  holder_name TEXT NOT NULL,
  year_set INTEGER NOT NULL,
  age_group TEXT,
  notes TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE hall_of_fame (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  swimmer_name TEXT NOT NULL,
  college TEXT NOT NULL,
  graduation_year INTEGER NOT NULL,
  notes TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE glossary_terms (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  term TEXT NOT NULL UNIQUE,
  definition TEXT NOT NULL,
  category TEXT
);

CREATE TABLE time_standards (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  standard_name TEXT NOT NULL,
  event_name TEXT NOT NULL,
  age_group TEXT NOT NULL,
  gender gender NOT NULL,
  time_hundredths INTEGER NOT NULL,                -- [#1]
  course course NOT NULL,
  season_year INTEGER NOT NULL
);

CREATE TABLE feedback (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  subject TEXT NOT NULL,
  body TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================================================
-- DEFERRED CROSS-TABLE FKs — [P1-5] note <-> draft cycle resolved here so neither
-- table needs the other to exist first.
-- ============================================================================
ALTER TABLE swimmer_notes
  ADD CONSTRAINT fk_notes_source_audio_draft
    FOREIGN KEY (source_audio_draft_id) REFERENCES audio_session_drafts(id) ON DELETE SET NULL,
  ADD CONSTRAINT fk_notes_source_voice_note
    FOREIGN KEY (source_voice_note_id) REFERENCES swimmer_voice_notes(id) ON DELETE SET NULL;
ALTER TABLE audio_session_drafts
  ADD CONSTRAINT fk_audio_draft_posted_note
    FOREIGN KEY (posted_note_id) REFERENCES swimmer_notes(id) ON DELETE SET NULL;
ALTER TABLE video_session_drafts
  ADD CONSTRAINT fk_video_draft_posted_note
    FOREIGN KEY (posted_note_id) REFERENCES swimmer_notes(id) ON DELETE SET NULL;
-- [P1-6] forward reference (notification_rules created after in_app_notifications).
ALTER TABLE in_app_notifications
  ADD CONSTRAINT fk_in_app_rule
    FOREIGN KEY (rule_id) REFERENCES notification_rules(id) ON DELETE SET NULL;

-- ============================================================================
-- RLS HELPER FUNCTIONS + PARENT VIEW
-- Defined here, AFTER their tables exist, so SQL bodies validate under Postgres's
-- default check_function_bodies. SECURITY DEFINER + STABLE: they read profiles/
-- guardianships WITHOUT the caller's RLS -> avoids the self-referential recursion
-- footgun and keeps every policy one line. [P1-10]
-- ============================================================================

CREATE OR REPLACE FUNCTION auth_profile_id()
RETURNS uuid LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT id FROM profiles WHERE user_id = auth.uid();
$$;

CREATE OR REPLACE FUNCTION is_staff()
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (SELECT 1 FROM profiles
                 WHERE user_id = auth.uid() AND role IN ('coach_admin','super_admin'));
$$;

CREATE OR REPLACE FUNCTION is_super_admin()
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (SELECT 1 FROM profiles WHERE user_id = auth.uid() AND role = 'super_admin');
$$;

-- [P1-8] team-wide reads: pending OR approved may read; deactivated may NOT.
CREATE OR REPLACE FUNCTION is_active_account()
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (SELECT 1 FROM profiles
                 WHERE user_id = auth.uid() AND account_status <> 'deactivated');
$$;

-- [D-A] swimmer access resolves through guardianships, and ONLY for an APPROVED
-- guardian (pending guardians get team data but no swimmer-specific data — the
-- BSPC "limited access while pending" rule, now enforced centrally).
CREATE OR REPLACE FUNCTION is_my_swimmer(target uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (
    SELECT 1 FROM guardianships g
    JOIN profiles p ON p.id = g.guardian_profile_id
    WHERE g.swimmer_id = target
      AND p.user_id = auth.uid()
      AND p.account_status = 'approved'
  );
$$;

-- [D-H1, ratified 2026-06-10] within-staff ownership: does this coach_id
-- reference the CALLER's profile row? Powers the per-coach walls on
-- practice_plans + import_jobs (the D-F4 within-staff no-widening doctrine).
CREATE OR REPLACE FUNCTION is_my_profile(p uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (SELECT 1 FROM profiles WHERE id = p AND user_id = auth.uid());
$$;

-- [P1-10] the caller's household ids (for families_select_own).
CREATE OR REPLACE FUNCTION my_family_ids()
RETURNS SETOF uuid LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT family_id FROM profiles WHERE user_id = auth.uid() AND family_id IS NOT NULL;
$$;

-- [P1-10] practice groups of the caller's (approved) guardianship swimmers.
CREATE OR REPLACE FUNCTION my_swimmer_groups()
RETURNS SETOF practice_group LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT DISTINCT s.practice_group
  FROM swimmers s
  JOIN guardianships g ON g.swimmer_id = s.id
  JOIN profiles p ON p.id = g.guardian_profile_id
  WHERE p.user_id = auth.uid() AND p.account_status = 'approved';
$$;

-- attendance_parent_view — [#5/P0-4] derived present/absent for the parent app.
-- Mapping: present/left_early/NULL(checked-in) => 'present'; absent/excused/sick/
-- injured => 'absent'. SECURITY-DEFINER-BY-OWNERSHIP [P1-11]: created by the
-- migration role (Supabase 'postgres', which bypasses RLS) so it reads the
-- staff-only base table; its WHERE is_my_swimmer() is the security boundary and the
-- wall FAILS CLOSED (zero rows) if ever owned by a non-privileged role. Parents are
-- GRANTed this view, never the base table.
CREATE VIEW attendance_parent_view AS
SELECT
  a.id, a.swimmer_id, a.practice_date, a.schedule_event_id,
  CASE WHEN a.status IN ('absent','excused','sick','injured') THEN 'absent' ELSE 'present' END AS status,
  a.created_at
FROM attendance a
WHERE is_my_swimmer(a.swimmer_id);

-- ============================================================================
-- TRIGGERS
-- ============================================================================
CREATE OR REPLACE FUNCTION update_updated_at()
RETURNS TRIGGER AS $$
BEGIN NEW.updated_at = NOW(); RETURN NEW; END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_families_updated_at              BEFORE UPDATE ON families              FOR EACH ROW EXECUTE FUNCTION update_updated_at();
CREATE TRIGGER trg_profiles_updated_at              BEFORE UPDATE ON profiles              FOR EACH ROW EXECUTE FUNCTION update_updated_at();
CREATE TRIGGER trg_swimmers_updated_at              BEFORE UPDATE ON swimmers              FOR EACH ROW EXECUTE FUNCTION update_updated_at();
CREATE TRIGGER trg_swimmer_coach_profile_updated_at BEFORE UPDATE ON swimmer_coach_profile FOR EACH ROW EXECUTE FUNCTION update_updated_at();
CREATE TRIGGER trg_swimmer_medical_updated_at       BEFORE UPDATE ON swimmer_medical       FOR EACH ROW EXECUTE FUNCTION update_updated_at();
CREATE TRIGGER trg_schedule_events_updated_at       BEFORE UPDATE ON schedule_events       FOR EACH ROW EXECUTE FUNCTION update_updated_at();
CREATE TRIGGER trg_calendar_events_updated_at       BEFORE UPDATE ON calendar_events       FOR EACH ROW EXECUTE FUNCTION update_updated_at();
CREATE TRIGGER trg_announcements_updated_at         BEFORE UPDATE ON announcements         FOR EACH ROW EXECUTE FUNCTION update_updated_at();
CREATE TRIGGER trg_meets_updated_at                 BEFORE UPDATE ON meets                 FOR EACH ROW EXECUTE FUNCTION update_updated_at();
CREATE TRIGGER trg_goals_updated_at                 BEFORE UPDATE ON goals                 FOR EACH ROW EXECUTE FUNCTION update_updated_at();
CREATE TRIGGER trg_audio_sessions_updated_at        BEFORE UPDATE ON audio_sessions        FOR EACH ROW EXECUTE FUNCTION update_updated_at();
CREATE TRIGGER trg_video_sessions_updated_at        BEFORE UPDATE ON video_sessions        FOR EACH ROW EXECUTE FUNCTION update_updated_at();
CREATE TRIGGER trg_practice_plans_updated_at        BEFORE UPDATE ON practice_plans        FOR EACH ROW EXECUTE FUNCTION update_updated_at();
CREATE TRIGGER trg_season_plans_updated_at          BEFORE UPDATE ON season_plans          FOR EACH ROW EXECUTE FUNCTION update_updated_at();
CREATE TRIGGER trg_notification_preferences_updated_at BEFORE UPDATE ON notification_preferences FOR EACH ROW EXECUTE FUNCTION update_updated_at();
CREATE TRIGGER trg_notification_rules_updated_at    BEFORE UPDATE ON notification_rules    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- [P0-1] Privilege-escalation guard: a normal user cannot change their own role,
-- account_status, or family_id. Only a super_admin may change role; only staff may
-- change account_status/family_id (the approve/link flow). Service-role/backend
-- writes (auth.uid() IS NULL) are exempt so the backfill can set roles.
CREATE OR REPLACE FUNCTION enforce_profile_self_update()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF auth.uid() IS NOT NULL THEN
    IF NEW.role IS DISTINCT FROM OLD.role AND NOT is_super_admin() THEN
      RAISE EXCEPTION 'profiles.role may be changed only by a super_admin';
    END IF;
    IF (NEW.account_status IS DISTINCT FROM OLD.account_status
        OR NEW.family_id IS DISTINCT FROM OLD.family_id)
       AND NOT is_staff() THEN
      RAISE EXCEPTION 'profiles.account_status/family_id may be changed only by staff';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;
CREATE TRIGGER trg_profiles_guard_privileged BEFORE UPDATE ON profiles
  FOR EACH ROW EXECUTE FUNCTION enforce_profile_self_update();

-- Auto-create a profile on signup (family/pending). [P0-8] DISABLE during backfill.
CREATE OR REPLACE FUNCTION handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO profiles (user_id, email, full_name, role, account_status)
  VALUES (NEW.id, NEW.email,
          COALESCE(NEW.raw_user_meta_data->>'full_name', 'New User'),
          'family', 'pending');
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users FOR EACH ROW EXECUTE FUNCTION handle_new_user();

-- ============================================================================
-- INDEXES
-- ============================================================================
CREATE INDEX idx_profiles_user_id          ON profiles(user_id);
CREATE INDEX idx_profiles_family_id        ON profiles(family_id);
CREATE INDEX idx_profiles_role             ON profiles(role);
CREATE INDEX idx_coach_groups_profile      ON coach_groups(profile_id);
CREATE INDEX idx_swimmers_practice_group   ON swimmers(practice_group);
CREATE INDEX idx_swimmers_active           ON swimmers(is_active, last_name);
CREATE INDEX idx_swimmers_usa_id           ON swimmers(usa_swimming_id);
CREATE INDEX idx_guardianships_swimmer     ON guardianships(swimmer_id);       -- [D-A]
CREATE INDEX idx_guardianships_guardian    ON guardianships(guardian_profile_id);
CREATE INDEX idx_parent_invites_code       ON parent_invites(code);
CREATE INDEX idx_parent_invites_swimmer    ON parent_invites(swimmer_id);
CREATE INDEX idx_schedule_events_group     ON schedule_events(practice_group);
CREATE INDEX idx_schedule_events_start     ON schedule_events(start_time);
CREATE INDEX idx_calendar_events_type_date ON calendar_events(type, start_date);
CREATE INDEX idx_calendar_events_coach     ON calendar_events(coach_id);
CREATE INDEX idx_calendar_rsvps_event      ON calendar_event_rsvps(event_id);
CREATE INDEX idx_calendar_rsvps_swimmer    ON calendar_event_rsvps(swimmer_id);  -- [P0-2] RLS path
CREATE INDEX idx_announcements_target      ON announcements(target_group);
CREATE INDEX idx_meets_start_date          ON meets(start_date);
CREATE INDEX idx_meets_status              ON meets(status, start_date);
CREATE INDEX idx_meet_entries_meet         ON meet_entries(meet_id);
CREATE INDEX idx_meet_entries_swimmer      ON meet_entries(swimmer_id);
CREATE INDEX idx_swim_results_swimmer      ON swim_results(swimmer_id);
CREATE INDEX idx_swim_results_meet         ON swim_results(meet_id);
CREATE INDEX idx_personal_bests_swimmer    ON personal_bests(swimmer_id);
CREATE INDEX idx_goals_swimmer             ON goals(swimmer_id);
CREATE INDEX idx_swimmer_notes_swimmer     ON swimmer_notes(swimmer_id, practice_date DESC);
CREATE INDEX idx_group_notes_group         ON group_notes(practice_group, practice_date DESC);
CREATE INDEX idx_voice_notes_swimmer       ON swimmer_voice_notes(swimmer_id);
CREATE INDEX idx_audio_sessions_coach      ON audio_sessions(coach_id, created_at DESC);
CREATE INDEX idx_audio_sessions_status     ON audio_sessions(status, created_at DESC);
CREATE INDEX idx_audio_session_swimmers_sw ON audio_session_swimmers(swimmer_id);
CREATE INDEX idx_audio_drafts_session      ON audio_session_drafts(session_id);
CREATE INDEX idx_video_sessions_coach      ON video_sessions(coach_id, created_at DESC);
CREATE INDEX idx_video_sessions_status     ON video_sessions(status, created_at DESC);
CREATE INDEX idx_video_session_swimmers_sw ON video_session_swimmers(swimmer_id);
CREATE INDEX idx_video_drafts_session      ON video_session_drafts(session_id);
CREATE INDEX idx_practice_plans_template   ON practice_plans(is_template, created_at DESC);
CREATE INDEX idx_practice_plans_public     ON practice_plans(is_template, is_public, updated_at DESC);
CREATE INDEX idx_practice_plans_coach      ON practice_plans(coach_id);
CREATE INDEX idx_season_plans_coach        ON season_plans(coach_id, start_date DESC);
CREATE INDEX idx_season_plan_weeks_plan    ON season_plan_weeks(season_plan_id, week_number);
CREATE INDEX idx_attendance_swimmer        ON attendance(swimmer_id, practice_date DESC);
CREATE INDEX idx_attendance_date           ON attendance(practice_date);
CREATE INDEX idx_attendance_schedule_event ON attendance(schedule_event_id);
CREATE INDEX idx_push_tokens_user          ON push_tokens(user_id);
CREATE INDEX idx_in_app_user               ON in_app_notifications(user_id, is_read);
CREATE INDEX idx_notification_rules_coach  ON notification_rules(coach_id);
CREATE INDEX idx_import_jobs_coach         ON import_jobs(coach_id, created_at DESC);
CREATE INDEX idx_feedback_user             ON feedback(user_id);
CREATE INDEX idx_glossary_term             ON glossary_terms(term);
CREATE INDEX idx_time_standards_event      ON time_standards(event_name, age_group, gender, course);

-- [D-B] Attendance two-a-day uniqueness via PARTIAL indexes (PG-version agnostic):
--   one NULL-event ("day-keyed", Coach App) row per swimmer/day;
--   plus distinct event-linked rows for AM/PM two-a-days.
CREATE UNIQUE INDEX attendance_day_key   ON attendance (swimmer_id, practice_date)
  WHERE schedule_event_id IS NULL;
CREATE UNIQUE INDEX attendance_event_key ON attendance (swimmer_id, practice_date, schedule_event_id)
  WHERE schedule_event_id IS NOT NULL;

-- [P2-3] in_app idempotency: dedup rule-driven rows (even with NULL swimmer/eval)
-- while leaving non-rule rows (digests/announcements, rule_id NULL) unconstrained.
CREATE UNIQUE INDEX in_app_rule_idem ON in_app_notifications
  (rule_id,
   COALESCE(swimmer_id, '00000000-0000-0000-0000-000000000000'::uuid),
   COALESCE(source_eval_date, '0001-01-01'::date))
  WHERE rule_id IS NOT NULL;

-- ============================================================================
-- ROW LEVEL SECURITY
-- Parent-facing tables keep BSPC semantics via helper fns; coach-side tables are
-- staff-only. Family read is granted ONLY where the parent app legitimately needs
-- it (own swimmer's results/PBs/goals, the attendance VIEW). [SCOPE] COPPA wall.
-- ============================================================================
ALTER TABLE families                ENABLE ROW LEVEL SECURITY;
ALTER TABLE profiles                ENABLE ROW LEVEL SECURITY;
ALTER TABLE coach_groups            ENABLE ROW LEVEL SECURITY;
ALTER TABLE swimmers                ENABLE ROW LEVEL SECURITY;
ALTER TABLE guardianships           ENABLE ROW LEVEL SECURITY;
ALTER TABLE swimmer_coach_profile   ENABLE ROW LEVEL SECURITY;
ALTER TABLE swimmer_medical         ENABLE ROW LEVEL SECURITY;
ALTER TABLE parent_invites          ENABLE ROW LEVEL SECURITY;
ALTER TABLE schedule_events         ENABLE ROW LEVEL SECURITY;
ALTER TABLE raw_schedule_snapshots  ENABLE ROW LEVEL SECURITY;
ALTER TABLE imported_schedule_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE schedule_overrides      ENABLE ROW LEVEL SECURITY;
ALTER TABLE schedule_change_log     ENABLE ROW LEVEL SECURITY;
ALTER TABLE calendar_events         ENABLE ROW LEVEL SECURITY;
ALTER TABLE calendar_event_rsvps    ENABLE ROW LEVEL SECURITY;
ALTER TABLE announcements           ENABLE ROW LEVEL SECURITY;
ALTER TABLE meets                   ENABLE ROW LEVEL SECURITY;
ALTER TABLE meet_entries            ENABLE ROW LEVEL SECURITY;
ALTER TABLE swim_results            ENABLE ROW LEVEL SECURITY;
ALTER TABLE personal_bests          ENABLE ROW LEVEL SECURITY;
ALTER TABLE goals                   ENABLE ROW LEVEL SECURITY;
ALTER TABLE swimmer_notes           ENABLE ROW LEVEL SECURITY;
ALTER TABLE group_notes             ENABLE ROW LEVEL SECURITY;
ALTER TABLE swimmer_voice_notes     ENABLE ROW LEVEL SECURITY;
ALTER TABLE audio_sessions          ENABLE ROW LEVEL SECURITY;
ALTER TABLE audio_session_swimmers  ENABLE ROW LEVEL SECURITY;
ALTER TABLE audio_session_drafts    ENABLE ROW LEVEL SECURITY;
ALTER TABLE video_sessions          ENABLE ROW LEVEL SECURITY;
ALTER TABLE video_session_swimmers  ENABLE ROW LEVEL SECURITY;
ALTER TABLE video_session_drafts    ENABLE ROW LEVEL SECURITY;
ALTER TABLE practice_plans          ENABLE ROW LEVEL SECURITY;
ALTER TABLE season_plans            ENABLE ROW LEVEL SECURITY;
ALTER TABLE season_plan_weeks       ENABLE ROW LEVEL SECURITY;
ALTER TABLE attendance              ENABLE ROW LEVEL SECURITY;
ALTER TABLE push_tokens             ENABLE ROW LEVEL SECURITY;
ALTER TABLE notification_preferences ENABLE ROW LEVEL SECURITY;
ALTER TABLE notification_jobs       ENABLE ROW LEVEL SECURITY;
ALTER TABLE in_app_notifications    ENABLE ROW LEVEL SECURITY;
ALTER TABLE notification_rules      ENABLE ROW LEVEL SECURITY;
ALTER TABLE import_jobs             ENABLE ROW LEVEL SECURITY;
-- [D-J2, ratified 2026-06-10] aggregations RLS-enable retired with the table.
ALTER TABLE team_records            ENABLE ROW LEVEL SECURITY;
ALTER TABLE hall_of_fame            ENABLE ROW LEVEL SECURITY;
ALTER TABLE glossary_terms          ENABLE ROW LEVEL SECURITY;
ALTER TABLE time_standards          ENABLE ROW LEVEL SECURITY;
ALTER TABLE feedback                ENABLE ROW LEVEL SECURITY;

-- ---- Identity & people ----
-- [P0-1] note: the privileged-column guard is enforced by trigger, not WITH CHECK
-- (RLS WITH CHECK can't see OLD); the policy still scopes the row to the caller.
CREATE POLICY profiles_select_own   ON profiles FOR SELECT TO authenticated USING (user_id = auth.uid());
CREATE POLICY profiles_select_staff ON profiles FOR SELECT TO authenticated USING (is_staff());
CREATE POLICY profiles_update_own   ON profiles FOR UPDATE TO authenticated USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());
CREATE POLICY profiles_update_staff ON profiles FOR UPDATE TO authenticated USING (is_staff())          WITH CHECK (is_staff());

CREATE POLICY families_select_own   ON families FOR SELECT TO authenticated USING (id IN (SELECT my_family_ids()));
CREATE POLICY families_staff_all    ON families FOR ALL    TO authenticated USING (is_staff()) WITH CHECK (is_staff());

CREATE POLICY coach_groups_staff    ON coach_groups FOR ALL TO authenticated USING (is_staff()) WITH CHECK (is_staff());

-- [D-A] swimmer rows visible to an approved guardian (own swimmer) or staff.
CREATE POLICY swimmers_select_own   ON swimmers FOR SELECT TO authenticated USING (is_my_swimmer(id));
CREATE POLICY swimmers_staff_all    ON swimmers FOR ALL    TO authenticated USING (is_staff()) WITH CHECK (is_staff());

-- [D-A] guardianships: a guardian sees ONLY their own links; writes are staff-only
-- (or via the SECURITY DEFINER invite-redemption RPC). No family self-insert.
CREATE POLICY guardianships_select_own ON guardianships FOR SELECT TO authenticated
  USING (guardian_profile_id = auth_profile_id() OR is_staff());
CREATE POLICY guardianships_staff_write ON guardianships FOR ALL TO authenticated
  USING (is_staff()) WITH CHECK (is_staff());

CREATE POLICY scp_staff_all          ON swimmer_coach_profile FOR ALL TO authenticated USING (is_staff()) WITH CHECK (is_staff());

CREATE POLICY medical_select_staff   ON swimmer_medical FOR SELECT TO authenticated USING (is_staff());
CREATE POLICY medical_write_admin    ON swimmer_medical FOR ALL    TO authenticated USING (is_super_admin()) WITH CHECK (is_super_admin());

CREATE POLICY parent_invites_staff   ON parent_invites FOR ALL TO authenticated USING (is_staff()) WITH CHECK (is_staff());

-- ---- Schedule ([P1-8] is_active_account: pending may read, deactivated may not) ----
CREATE POLICY schedule_select_active ON schedule_events FOR SELECT TO authenticated USING (is_active_account());
CREATE POLICY schedule_staff_all     ON schedule_events FOR ALL    TO authenticated USING (is_staff()) WITH CHECK (is_staff());
CREATE POLICY raw_snapshots_staff    ON raw_schedule_snapshots   FOR ALL TO authenticated USING (is_staff()) WITH CHECK (is_staff());
CREATE POLICY imported_events_staff  ON imported_schedule_events FOR ALL TO authenticated USING (is_staff()) WITH CHECK (is_staff());
CREATE POLICY overrides_staff        ON schedule_overrides       FOR ALL TO authenticated USING (is_staff()) WITH CHECK (is_staff());
CREATE POLICY change_log_staff       ON schedule_change_log      FOR SELECT TO authenticated USING (is_staff());  -- [P1-9]

-- [SCOPE-DEFERRED / D-H5(b), ratified 2026-06-10] The active-read + family-RSVP
-- arms below remain ratified canonical law but are DEFERRED: no parent calendar
-- UI exists in either app, so live migrations land BOTH tables STAFF-ONLY until
-- a parent calendar feature ships (the arms then land as a one-line policy swap
-- + proofs — a named post-cutover product line item, never drift).
CREATE POLICY calendar_select_active ON calendar_events FOR SELECT TO authenticated USING (is_active_account());
CREATE POLICY calendar_staff_all     ON calendar_events FOR ALL    TO authenticated USING (is_staff()) WITH CHECK (is_staff());

-- [P0-2] RSVPs scoped to own swimmer or staff; families may write their own RSVP.
-- ([SCOPE-DEFERRED / D-H5(b)] — see the calendar annotation above.)
CREATE POLICY rsvps_select_own       ON calendar_event_rsvps FOR SELECT TO authenticated USING (is_my_swimmer(swimmer_id) OR is_staff());
CREATE POLICY rsvps_family_write     ON calendar_event_rsvps FOR ALL    TO authenticated USING (is_my_swimmer(swimmer_id)) WITH CHECK (is_my_swimmer(swimmer_id));
CREATE POLICY rsvps_staff_all        ON calendar_event_rsvps FOR ALL    TO authenticated USING (is_staff()) WITH CHECK (is_staff());

-- ---- Announcements ([P1-8] gated to active accounts; group via helper [P1-10]) ----
CREATE POLICY announcements_select   ON announcements FOR SELECT TO authenticated
  USING (is_active_account() AND (target_group IS NULL OR target_group IN (SELECT my_swimmer_groups())));
CREATE POLICY announcements_staff_all ON announcements FOR ALL TO authenticated USING (is_staff()) WITH CHECK (is_staff());

-- ---- Meets ([D-H9, ratified 2026-06-10] NAMED WIDENING — the first on the
-- books: coach-app meets were staff-only in Firestore; the merged table is
-- parent-readable because the parent-facing meets feature exists and ships in
-- BSPC (capability follows product). meet_entries — children's race data —
-- stays strictly staff-only and does not widen one bit.) ----
CREATE POLICY meets_select_active    ON meets        FOR SELECT TO authenticated USING (is_active_account());
CREATE POLICY meets_staff_all        ON meets        FOR ALL    TO authenticated USING (is_staff()) WITH CHECK (is_staff());
CREATE POLICY meet_entries_staff     ON meet_entries FOR ALL    TO authenticated USING (is_staff()) WITH CHECK (is_staff());

-- ---- Results / PBs / Goals (family-readable for own swimmer) ----
CREATE POLICY swim_results_select_own  ON swim_results  FOR SELECT TO authenticated USING (is_my_swimmer(swimmer_id));
CREATE POLICY swim_results_staff_all   ON swim_results  FOR ALL    TO authenticated USING (is_staff()) WITH CHECK (is_staff());
CREATE POLICY personal_bests_select_own ON personal_bests FOR SELECT TO authenticated USING (is_my_swimmer(swimmer_id));
CREATE POLICY personal_bests_staff_all  ON personal_bests FOR ALL  TO authenticated USING (is_staff()) WITH CHECK (is_staff());
CREATE POLICY goals_select_own       ON goals FOR SELECT TO authenticated USING (is_my_swimmer(swimmer_id));
CREATE POLICY goals_staff_all        ON goals FOR ALL    TO authenticated USING (is_staff()) WITH CHECK (is_staff());

-- ---- Coaching notes / media / planning [SCOPE]: STRICT staff-only ----
CREATE POLICY swimmer_notes_staff    ON swimmer_notes        FOR ALL TO authenticated USING (is_staff()) WITH CHECK (is_staff());
CREATE POLICY group_notes_staff      ON group_notes          FOR ALL TO authenticated USING (is_staff()) WITH CHECK (is_staff());
CREATE POLICY voice_notes_staff      ON swimmer_voice_notes  FOR ALL TO authenticated USING (is_staff()) WITH CHECK (is_staff());
CREATE POLICY audio_sessions_staff   ON audio_sessions       FOR ALL TO authenticated USING (is_staff()) WITH CHECK (is_staff());
CREATE POLICY audio_sess_sw_staff    ON audio_session_swimmers FOR ALL TO authenticated USING (is_staff()) WITH CHECK (is_staff());
CREATE POLICY audio_drafts_staff     ON audio_session_drafts FOR ALL TO authenticated USING (is_staff()) WITH CHECK (is_staff());
CREATE POLICY video_sessions_staff   ON video_sessions       FOR ALL TO authenticated USING (is_staff()) WITH CHECK (is_staff());
CREATE POLICY video_sess_sw_staff    ON video_session_swimmers FOR ALL TO authenticated USING (is_staff()) WITH CHECK (is_staff());
CREATE POLICY video_drafts_staff     ON video_session_drafts FOR ALL TO authenticated USING (is_staff()) WITH CHECK (is_staff());
-- [D-H1, ratified 2026-06-10] WITHIN-STAFF walls (the D-F4 doctrine): practice
-- plans are owner-private with the deliberate public-share arm; import jobs are
-- owner + super_admin. Verbatim mirror of today's Firestore rules — the drafted
-- staff-wide policies were a drafting error against standing law. season_plans
-- stays staff-shared: that IS today's wall; the asymmetry is real and preserved.
CREATE POLICY plans_select_own_or_public ON practice_plans FOR SELECT TO authenticated
  USING (is_staff() AND (is_my_profile(coach_id) OR is_public));
CREATE POLICY plans_insert_own       ON practice_plans FOR INSERT TO authenticated
  WITH CHECK (is_staff() AND is_my_profile(coach_id));
CREATE POLICY plans_update_own       ON practice_plans FOR UPDATE TO authenticated
  USING (is_staff() AND is_my_profile(coach_id)) WITH CHECK (is_staff() AND is_my_profile(coach_id));
CREATE POLICY plans_delete_own       ON practice_plans FOR DELETE TO authenticated
  USING (is_staff() AND is_my_profile(coach_id));
CREATE POLICY season_plans_staff     ON season_plans         FOR ALL TO authenticated USING (is_staff()) WITH CHECK (is_staff());
CREATE POLICY season_weeks_staff     ON season_plan_weeks    FOR ALL TO authenticated USING (is_staff()) WITH CHECK (is_staff());
CREATE POLICY import_jobs_select_own_or_admin ON import_jobs FOR SELECT TO authenticated
  USING (is_super_admin() OR (is_staff() AND is_my_profile(coach_id)));
CREATE POLICY import_jobs_insert_own ON import_jobs FOR INSERT TO authenticated
  WITH CHECK (is_staff() AND is_my_profile(coach_id));
CREATE POLICY import_jobs_update_own ON import_jobs FOR UPDATE TO authenticated
  USING (is_staff() AND is_my_profile(coach_id)) WITH CHECK (is_staff() AND is_my_profile(coach_id));
CREATE POLICY import_jobs_delete_admin ON import_jobs FOR DELETE TO authenticated
  USING (is_super_admin());
CREATE POLICY notification_rules_staff ON notification_rules FOR ALL TO authenticated USING (is_staff()) WITH CHECK (is_staff());
-- [D-J2, ratified 2026-06-10] aggregations_select_staff retired with the
-- table; the Phase J views carry the is_staff() arm directly (no-widening
-- preserved; family/pending/anon prove to zero rows in pgTAP 014).

-- ---- Attendance [#5]: base table STAFF-ONLY; parents use attendance_parent_view ----
CREATE POLICY attendance_staff_all   ON attendance FOR ALL TO authenticated USING (is_staff()) WITH CHECK (is_staff());
GRANT SELECT ON attendance_parent_view TO authenticated;

-- ---- Notifications / prefs / push (own-row) ----
CREATE POLICY push_tokens_own        ON push_tokens            FOR ALL    TO authenticated USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());
CREATE POLICY notif_prefs_own        ON notification_preferences FOR ALL  TO authenticated USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());
CREATE POLICY notif_jobs_staff       ON notification_jobs      FOR ALL    TO authenticated USING (is_staff()) WITH CHECK (is_staff());
CREATE POLICY in_app_select_own      ON in_app_notifications   FOR SELECT TO authenticated USING (user_id = auth.uid());
CREATE POLICY in_app_update_own      ON in_app_notifications   FOR UPDATE TO authenticated USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());  -- [P1-7]

-- ---- Reference (active accounts read, staff write) ----
CREATE POLICY team_records_select    ON team_records  FOR SELECT TO authenticated USING (is_active_account());
CREATE POLICY team_records_staff     ON team_records  FOR ALL    TO authenticated USING (is_staff()) WITH CHECK (is_staff());
CREATE POLICY hall_of_fame_select    ON hall_of_fame  FOR SELECT TO authenticated USING (is_active_account());
CREATE POLICY hall_of_fame_staff     ON hall_of_fame  FOR ALL    TO authenticated USING (is_staff()) WITH CHECK (is_staff());
CREATE POLICY glossary_select        ON glossary_terms FOR SELECT TO authenticated USING (is_active_account());
CREATE POLICY glossary_staff         ON glossary_terms FOR ALL    TO authenticated USING (is_staff()) WITH CHECK (is_staff());
CREATE POLICY standards_select       ON time_standards FOR SELECT TO authenticated USING (is_active_account());
CREATE POLICY standards_staff        ON time_standards FOR ALL    TO authenticated USING (is_staff()) WITH CHECK (is_staff());

-- ---- Feedback ----
CREATE POLICY feedback_insert_own    ON feedback FOR INSERT TO authenticated WITH CHECK (user_id = auth.uid());
CREATE POLICY feedback_select_staff  ON feedback FOR SELECT TO authenticated USING (is_staff());

-- ============================================================================
-- END — review against UNIFY/02_SCHEMA_REDTEAM.md + UNIFY/NOTES.md.
-- ============================================================================

-- ============================================================================
-- APPENDIX A — STORAGE: every bucket, its limits, and its walls, in words.
-- [APPENDED IN PLACE 2026-06-11 per D-CUT9 (CUT-3 rider commit, e71050a
-- annotation precedent). This closes the Phase-H bank: "UNIFY/01 gains a
-- storage appendix cataloging every bucket, its limits, and its walls in
-- words — due no later than the convergence sweep." Source of truth for the
-- DDL: BSPC migrations 00007 (Phase F) and 00009 (Phase H §9).]
-- ============================================================================
--
-- FOUR canonical buckets exist. All four are PRIVATE (public = false);
-- nothing is ever served unauthenticated. There is NO imports bucket and
-- never will be (D-H2b: no import file was ever uploaded; absence is
-- parity).
--
--   1. media-audio    — 100MB cap (104857600), MIME audio/*.
--      Wall: STAFF-ONLY, all operations (media_audio_staff: is_staff() on
--      USING and WITH CHECK). Holds practice/voice audio, including the
--      legacy audio/swimmers/... voice-note keys (copied 1:1 at the 06 §B1
--      file-copy step).
--   2. media-video    — 500MB cap (524288000), MIME video/*.
--      Wall: STAFF-ONLY, all operations (media_video_staff). The 500MB cap
--      is the F-bank pre-check at the file-copy step: confirm the hosted
--      storage tier covers it BEFORE copying.
--   3. profile-photos — 5MB cap (5242880), MIME image/*.
--      Wall: STAFF-ONLY, all operations (profile_photos_staff). Parents'
--      ONE affordance is the signed capability URL stored in
--      swimmers.profile_photo_url, issued staff-side at upload — parents
--      never touch the bucket itself.
--   4. practice-plans — 25MB cap (26214400), MIME application/pdf.
--      Wall: is_staff() AND owner path segment
--      ((storage.foldername(name))[1] = auth.uid()) on USING and WITH
--      CHECK (practice_plans_files_owner) — a coach reads/writes only
--      their own folder. The is_staff() arm is the ONE named divergence
--      from the legacy Firebase rule (RH-14 hole-closing, ratified at H);
--      any second behavioral divergence is a tripwire. At the 06 §B1 copy,
--      legacy /practice_plans/{firebaseUid}/** keys remap to
--      practice-plans/{auth.users.id}/... via migration_identity_map AND
--      the practice_plans rows' storage-path values are rewritten — both
--      halves together close the D-K2 pre-H 404 caveat.
--
-- Legacy Firebase path map (the 06 PART B §B1 copy table, restated):
--   /audio/**           -> media-audio     (keys 1:1, no row rewrites)
--   /video/**           -> media-video     (keys 1:1, no row rewrites)
--   /profiles/**        -> profile-photos  (keys 1:1, no row rewrites)
--   /practice_plans/**  -> practice-plans  (owner-folder remap + row
--                                           rewrite, above)
--   /imports/**         -> NO DESTINATION  (D-H2b; verify-EMPTY named
--                                           no-op)
-- The legacy storage.rules retire WITH the copy (RF-4 under D-F1(a)).
-- ============================================================================
