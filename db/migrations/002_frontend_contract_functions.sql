-- 002_frontend_contract_functions.sql
--
-- The `/api/v1/*` surface, expressed the way this backend already expresses
-- business logic: PostgreSQL stored functions. Each one returns a jsonb
-- document shaped exactly like the corresponding type in the frontend's
-- `lib/types.ts`, so the C# controllers stay thin pass-throughs.
--
-- Errors are raised with custom SQLSTATEs that the API layer maps onto HTTP
-- status codes and onto the frontend's `ServiceError` codes:
--
--   GR001  not-found             -> 404
--   GR002  invalid-credentials   -> 401
--   GR003  conflict              -> 409
--   GR004  forbidden             -> 403
--   GR005  validation            -> 400
--
-- Requires 001_frontend_contract_schema.sql.

BEGIN;

/* -------------------------------------------------------------------------- */
/*  Vocabulary mapping                                                         */
/* -------------------------------------------------------------------------- */
-- The database speaks Player/Studio and Pending/Selected; the frontend speaks
-- tester/developer and pending/accepted. Existing rows and the legacy `/api/*`
-- endpoints depend on the database spelling, so the two are mapped here rather
-- than migrated.

CREATE OR REPLACE FUNCTION grogu_role_to_api(p_role text) RETURNS text
  LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE p_role WHEN 'Player' THEN 'tester'
                     WHEN 'Studio' THEN 'developer'
                     ELSE lower(p_role) END;
$$;

CREATE OR REPLACE FUNCTION grogu_role_to_db(p_role text) RETURNS text
  LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE lower(p_role) WHEN 'tester'    THEN 'Player'
                            WHEN 'developer' THEN 'Studio'
                            WHEN 'admin'     THEN 'Admin'
                            ELSE NULL END;
$$;

CREATE OR REPLACE FUNCTION grogu_appstatus_to_api(p_status text) RETURNS text
  LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE p_status WHEN 'Pending'   THEN 'pending'
                       WHEN 'Selected'  THEN 'accepted'
                       WHEN 'Completed' THEN 'accepted'
                       WHEN 'Rejected'  THEN 'rejected'
                       WHEN 'Withdrawn' THEN 'withdrawn'
                       ELSE 'pending' END;
$$;

CREATE OR REPLACE FUNCTION grogu_appstatus_to_db(p_status text) RETURNS text
  LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE lower(p_status) WHEN 'pending'   THEN 'Pending'
                              WHEN 'accepted'  THEN 'Selected'
                              WHEN 'rejected'  THEN 'Rejected'
                              WHEN 'withdrawn' THEN 'Withdrawn'
                              ELSE NULL END;
$$;

-- The frontend parses every timestamp with `new Date(...)` and sorts them as
-- strings, so they must be fixed-width UTC ISO-8601.
CREATE OR REPLACE FUNCTION grogu_iso(p_ts timestamptz) RETURNS text
  LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE WHEN p_ts IS NULL THEN NULL
              ELSE to_char(p_ts AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"') END;
$$;

/* -------------------------------------------------------------------------- */
/*  Row provisioning                                                           */
/* -------------------------------------------------------------------------- */
-- `applications.player_id` points at players.id and `playtests.studio_id` at
-- studios.id, but the frontend only ever knows a single user id. These resolve
-- one to the other, creating the side table row on first use so a user who
-- signed up before this migration can still act.

CREATE OR REPLACE FUNCTION grogu_player_id(p_user_id integer) RETURNS integer
  LANGUAGE plpgsql AS $$
DECLARE v_id integer;
BEGIN
  SELECT id INTO v_id FROM players WHERE user_id = p_user_id;
  IF v_id IS NULL THEN
    INSERT INTO players (user_id) VALUES (p_user_id) RETURNING id INTO v_id;
  END IF;
  RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION grogu_studio_id(p_user_id integer) RETURNS integer
  LANGUAGE plpgsql AS $$
DECLARE v_id integer;
BEGIN
  SELECT id INTO v_id FROM studios WHERE user_id = p_user_id;
  IF v_id IS NULL THEN
    INSERT INTO studios (user_id, name)
    VALUES (p_user_id, coalesce((SELECT name FROM users WHERE id = p_user_id), 'Studio'))
    RETURNING id INTO v_id;
  END IF;
  RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION grogu_require_role(p_user_id integer, p_role text) RETURNS void
  LANGUAGE plpgsql AS $$
DECLARE v_role text;
BEGIN
  SELECT grogu_role_to_api(role) INTO v_role FROM users WHERE id = p_user_id;
  IF v_role IS NULL THEN
    RAISE EXCEPTION 'Not signed in.' USING ERRCODE = 'GR004';
  END IF;
  IF v_role <> p_role THEN
    RAISE EXCEPTION 'Sign in as a % to do that.', p_role USING ERRCODE = 'GR004';
  END IF;
END;
$$;

/* -------------------------------------------------------------------------- */
/*  Helpers                                                                    */
/* -------------------------------------------------------------------------- */

-- `players.platforms` / `.genres` are legacy comma-separated text. The frontend
-- needs arrays drawn from its own unions, so unknown entries are dropped rather
-- than passed through and failing a type check downstream.
CREATE OR REPLACE FUNCTION grogu_split_csv(p_value text) RETURNS text[]
  LANGUAGE sql IMMUTABLE AS $$
  SELECT coalesce(array_agg(t ORDER BY t), '{}')
    FROM (
      SELECT DISTINCT trim(lower(unnest(string_to_array(coalesce(p_value, ''), ',')))) AS t
    ) s
   WHERE t <> '';
$$;

CREATE OR REPLACE FUNCTION grogu_notify(
  p_user_id integer, p_type text, p_title text, p_body text, p_href text
) RETURNS void LANGUAGE sql AS $$
  INSERT INTO notifications (user_id, type, title, body, href)
  VALUES (p_user_id, p_type, p_title, coalesce(p_body, ''), p_href);
$$;

-- jsonb array -> text[], tolerating null/missing.
CREATE OR REPLACE FUNCTION grogu_jsonb_text_array(p jsonb) RETURNS text[]
  LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE
    WHEN p IS NULL OR jsonb_typeof(p) <> 'array' THEN '{}'::text[]
    ELSE ARRAY(SELECT jsonb_array_elements_text(p))
  END;
$$;

/* -------------------------------------------------------------------------- */
/*  Entity -> JSON                                                             */
/* -------------------------------------------------------------------------- */

-- Another user's email is never exposed: the UI only ever renders
-- `session.user.email`, so everyone else's is blanked.
CREATE OR REPLACE FUNCTION grogu_user_json(u users, p_viewer_id integer) RETURNS jsonb
  LANGUAGE sql STABLE AS $$
  SELECT jsonb_build_object(
    'id',        u.id::text,
    'role',      grogu_role_to_api(u.role),
    'name',      coalesce(u.name, ''),
    'handle',    coalesce(u.handle, ''),
    'email',     CASE WHEN p_viewer_id IS NOT NULL AND u.id = p_viewer_id THEN u.email ELSE '' END,
    'avatarUrl', u.avatar_url,
    'location',  coalesce(u.location, ''),
    'bio',       coalesce(u.bio, ''),
    'joinedAt',  grogu_iso(u.created_at)
  );
$$;

CREATE OR REPLACE FUNCTION grogu_tester_profile_json(pl players) RETURNS jsonb
  LANGUAGE sql STABLE AS $$
  SELECT jsonb_build_object(
    'userId',                  pl.user_id::text,
    'experienceLevel',         coalesce(pl.experience, 'casual'),
    'preferredGenres',         to_jsonb(grogu_split_csv(pl.genres)),
    'platforms',               to_jsonb(grogu_split_csv(pl.platforms)),
    'languages',               to_jsonb(pl.languages),
    'weeklyAvailabilityHours', pl.weekly_availability_hours,
    'reputation',              pl.reputation,
    'completedPlaytests',      (SELECT count(*) FROM test_progress tp
                                 WHERE tp.tester_user_id = pl.user_id AND tp.stage = 'completed'),
    'averageFeedbackRating',   coalesce((
                                 SELECT round(avg((f.rating_fun + f.rating_difficulty + f.rating_clarity
                                                 + f.rating_performance + f.rating_polish) / 5.0), 2)
                                   FROM feedback f WHERE f.player_id = pl.id), 0),
    'badges',                  to_jsonb(pl.badges)
  );
$$;

CREATE OR REPLACE FUNCTION grogu_developer_profile_json(s studios) RETURNS jsonb
  LANGUAGE sql STABLE AS $$
  SELECT jsonb_build_object(
    'userId',         s.user_id::text,
    'studioName',     s.name,
    'studioSize',     s.studio_size,
    'website',        coalesce(s.website, ''),
    'foundedYear',    s.founded_year,
    'gamesPublished', (SELECT count(*) FROM games g WHERE g.developer_user_id = s.user_id),
    'activePlaytests',(SELECT count(*) FROM playtests p
                        WHERE p.studio_id = s.id AND p.status IN ('recruiting', 'in-progress'))
  );
$$;

CREATE OR REPLACE FUNCTION grogu_game_json(g games) RETURNS jsonb
  LANGUAGE sql STABLE AS $$
  SELECT jsonb_build_object(
    'id',            g.id::text,
    'developerId',   g.developer_user_id::text,
    'title',         g.title,
    'tagline',       g.tagline,
    'description',   g.description,
    'genres',        to_jsonb(g.genres),
    'platforms',     to_jsonb(g.platforms),
    'status',        g.status,
    'coverImageUrl', g.cover_image_url,
    'accentHue',     g.accent_hue,
    'buildVersion',  g.build_version,
    'updatedAt',     grogu_iso(g.updated_at)
  );
$$;

CREATE OR REPLACE FUNCTION grogu_playtest_json(p playtests) RETURNS jsonb
  LANGUAGE sql STABLE AS $$
  SELECT jsonb_build_object(
    'id',          p.id::text,
    'gameId',      p.game_id::text,
    'developerId', (SELECT s.user_id::text FROM studios s WHERE s.id = p.studio_id),
    'title',       coalesce(p.title, p.game_name),
    'summary',     p.summary,
    'goals',       to_jsonb(p.goals),
    'focusAreas',  to_jsonb(p.focus_areas),
    'status',      p.status,
    'requirements',p.requirements_json,
    'tasks',       coalesce((
                     SELECT jsonb_agg(jsonb_build_object(
                              'id',               t.id::text,
                              'title',            t.title,
                              'description',      t.description,
                              'type',             t.type,
                              'required',         t.required,
                              'estimatedMinutes', t.estimated_minutes
                            ) ORDER BY t.position, t.id)
                       FROM playtest_tasks t WHERE t.playtest_id = p.id), '[]'::jsonb),
    'reward',      p.reward,
    'cashReward',  p.cash_reward,
    'maxTesters',  p.max_testers,
    -- Denormalised counters the frontend reads straight off the playtest.
    'acceptedTesters', (SELECT count(*) FROM applications a
                         WHERE a.playtest_id = p.id AND a.status IN ('Selected', 'Completed')),
    'applicantCount',  (SELECT count(*) FROM applications a
                         WHERE a.playtest_id = p.id AND a.status <> 'Withdrawn'),
    'buildUrl',    p.build_url,
    'opensAt',     grogu_iso(p.opens_at),
    'closesAt',    grogu_iso(p.closes_at),
    'createdAt',   grogu_iso(p.created_at)
  );
$$;

CREATE OR REPLACE FUNCTION grogu_application_json(a applications) RETURNS jsonb
  LANGUAGE sql STABLE AS $$
  SELECT jsonb_build_object(
    'id',           a.id::text,
    'playtestId',   a.playtest_id::text,
    'testerId',     (SELECT pl.user_id::text FROM players pl WHERE pl.id = a.player_id),
    'status',       grogu_appstatus_to_api(a.status),
    'message',      a.message,
    'submittedAt',  grogu_iso(a.created_at),
    'decidedAt',    grogu_iso(a.decided_at),
    'decisionNote', a.decision_note
  );
$$;

CREATE OR REPLACE FUNCTION grogu_feedback_json(f feedback) RETURNS jsonb
  LANGUAGE sql STABLE AS $$
  SELECT jsonb_build_object(
    'id',         f.id::text,
    'playtestId', f.playtest_id::text,
    'testerId',   (SELECT pl.user_id::text FROM players pl WHERE pl.id = f.player_id),
    'ratings',    jsonb_build_object(
                    'fun',         f.rating_fun,
                    'difficulty',  f.rating_difficulty,
                    'clarity',     f.rating_clarity,
                    'performance', f.rating_performance,
                    'polish',      f.rating_polish),
    'sentiment',       f.sentiment,
    'summary',         f.summary,
    'highlights',      to_jsonb(f.highlights),
    'painPoints',      to_jsonb(f.pain_points),
    'bugs',            to_jsonb(f.bugs),
    'answers',         f.answers,
    'wouldRecommend',  f.would_recommend,
    'hoursPlayed',     f.hours_played::float8,
    'submittedAt',     grogu_iso(f.created_at)
  );
$$;

CREATE OR REPLACE FUNCTION grogu_progress_json(tp test_progress) RETURNS jsonb
  LANGUAGE sql STABLE AS $$
  SELECT jsonb_build_object(
    'id',               tp.id::text,
    'playtestId',       tp.playtest_id::text,
    'testerId',         tp.tester_user_id::text,
    'stage',            tp.stage,
    'completedTaskIds', to_jsonb(ARRAY(SELECT x::text FROM unnest(tp.completed_task_ids) AS x)),
    'buildDownloaded',  tp.build_downloaded,
    'startedAt',        grogu_iso(tp.started_at),
    'completedAt',      grogu_iso(tp.completed_at),
    'feedbackId',       tp.feedback_id::text
  );
$$;

CREATE OR REPLACE FUNCTION grogu_notification_json(n notifications) RETURNS jsonb
  LANGUAGE sql STABLE AS $$
  SELECT jsonb_build_object(
    'id',        n.id::text,
    'userId',    n.user_id::text,
    'type',      n.type,
    'title',     n.title,
    'body',      n.body,
    'href',      n.href,
    'read',      n.read,
    'createdAt', grogu_iso(n.created_at)
  );
$$;

/* -------------------------------------------------------------------------- */
/*  Legacy function compatibility                                              */
/* -------------------------------------------------------------------------- */
-- Migration 001 replaced every stored password with a bcrypt digest. The two
-- legacy auth functions compared and stored them verbatim, so they are updated
-- here in step; without this, `POST /api/auth/login` would reject every
-- existing account the moment 001 runs.
--
-- Their signatures and result shapes are unchanged, so the legacy controllers
-- keep working untouched.

CREATE OR REPLACE FUNCTION public.verify_user_login(
  p_email character varying, p_password character varying
) RETURNS TABLE(id integer, email character varying, role character varying)
 LANGUAGE plpgsql
AS $function$
BEGIN
  RETURN QUERY
  SELECT u.id, u.email, u.role
    FROM users u
   WHERE lower(u.email) = lower(p_email)
     AND u.password IS NOT NULL
     AND u.password = crypt(p_password, u.password);
END;
$function$;

CREATE OR REPLACE FUNCTION public.register_user(
  p_email character varying, p_role character varying, p_password character varying
) RETURNS integer
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_new_id INTEGER;
BEGIN
    INSERT INTO users (email, role, password, name, handle)
    VALUES (
      p_email,
      p_role,
      crypt(p_password, gen_salt('bf', 10)),
      initcap(replace(split_part(p_email, '@', 1), '.', ' ')),
      -- Handle has a unique index; fall back to the row id when the derived
      -- one is taken.
      NULL
    )
    RETURNING id INTO v_new_id;

    UPDATE users
       SET handle = coalesce(
             (SELECT h FROM (
                SELECT left(regexp_replace(lower(split_part(p_email, '@', 1)), '[^a-z0-9]', '', 'g'), 16) AS h
              ) c WHERE NOT EXISTS (SELECT 1 FROM users u2 WHERE u2.handle = c.h)),
             'user' || v_new_id::text)
     WHERE id = v_new_id;

    RETURN v_new_id;
END;
$function$;

COMMIT;
