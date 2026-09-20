-- 003_frontend_contract_operations.sql
--
-- The read and write operations behind `/api/v1/*`. Business rules here mirror
-- the ones the frontend already enforces in `lib/services/*` and
-- `lib/store/grogu-store.ts` (ownership, status transitions, duplicate
-- applications, the notifications each event raises), so the server is
-- authoritative instead of trusting the client.
--
-- Requires 002_frontend_contract_functions.sql.

BEGIN;

/* -------------------------------------------------------------------------- */
/*  Auth                                                                       */
/* -------------------------------------------------------------------------- */

CREATE OR REPLACE FUNCTION grogu_login(p_email text, p_password text) RETURNS jsonb
  LANGUAGE plpgsql AS $$
DECLARE u users;
BEGIN
  SELECT * INTO u FROM users WHERE lower(email) = lower(trim(p_email));

  -- One message for "no such account" and "wrong password" so the endpoint
  -- can't be used to enumerate registered emails.
  IF u.id IS NULL OR u.password IS NULL OR u.password <> crypt(p_password, u.password) THEN
    RAISE EXCEPTION 'Incorrect email or password.' USING ERRCODE = 'GR002';
  END IF;

  RETURN grogu_user_json(u, u.id);
END;
$$;

CREATE OR REPLACE FUNCTION grogu_signup(p_input jsonb) RETURNS jsonb
  LANGUAGE plpgsql AS $$
DECLARE
  v_role_db  text;
  v_email    text := trim(p_input ->> 'email');
  v_name     text := trim(coalesce(p_input ->> 'name', ''));
  v_handle   text;
  v_suffix   integer := 0;
  u          users;
BEGIN
  v_role_db := grogu_role_to_db(p_input ->> 'role');
  IF v_role_db IS NULL THEN
    RAISE EXCEPTION 'Pick whether you are a tester or a developer.' USING ERRCODE = 'GR005';
  END IF;
  IF v_email IS NULL OR v_email = '' THEN
    RAISE EXCEPTION 'Enter an email address.' USING ERRCODE = 'GR005';
  END IF;
  IF length(coalesce(p_input ->> 'password', '')) < 6 THEN
    RAISE EXCEPTION 'Password must be at least 6 characters.' USING ERRCODE = 'GR005';
  END IF;
  IF v_name = '' THEN
    RAISE EXCEPTION 'Enter your name.' USING ERRCODE = 'GR005';
  END IF;

  IF EXISTS (SELECT 1 FROM users WHERE lower(email) = lower(v_email)) THEN
    RAISE EXCEPTION 'An account with that email already exists.' USING ERRCODE = 'GR003';
  END IF;

  -- Mirrors the frontend's handle derivation, then de-duplicates.
  -- `|| NULL` yields NULL in SQL, so the suffix is coalesced to '' rather than
  -- being appended via nullif directly.
  v_handle := left(regexp_replace(lower(v_name), '[^a-z0-9]', '', 'g'), 16);
  IF v_handle = '' THEN v_handle := 'grogu'; END IF;
  WHILE EXISTS (
    SELECT 1 FROM users WHERE handle = v_handle || coalesce(nullif(v_suffix, 0)::text, '')
  ) LOOP
    v_suffix := v_suffix + 1;
  END LOOP;
  v_handle := v_handle || coalesce(nullif(v_suffix, 0)::text, '');

  INSERT INTO users (email, role, password, name, handle, location, bio)
  VALUES (
    v_email,
    v_role_db,
    crypt(p_input ->> 'password', gen_salt('bf', 10)),
    v_name,
    v_handle,
    coalesce(p_input ->> 'location', ''),
    CASE WHEN v_role_db = 'Player'
         THEN 'New Grogu playtester.'
         ELSE coalesce(p_input ->> 'studioName', v_name) || ' on Grogu.' END
  )
  RETURNING * INTO u;

  IF v_role_db = 'Player' THEN
    INSERT INTO players (user_id, experience, platforms, genres, weekly_availability_hours)
    VALUES (
      u.id,
      coalesce(p_input ->> 'experienceLevel', 'casual'),
      array_to_string(grogu_jsonb_text_array(p_input -> 'platforms'), ','),
      array_to_string(grogu_jsonb_text_array(p_input -> 'preferredGenres'), ','),
      coalesce((p_input ->> 'weeklyAvailabilityHours')::int, 5)
    );
  ELSE
    INSERT INTO studios (user_id, name, website, studio_size)
    VALUES (
      u.id,
      coalesce(nullif(trim(coalesce(p_input ->> 'studioName', '')), ''), v_name),
      nullif(trim(coalesce(p_input ->> 'website', '')), ''),
      coalesce(p_input ->> 'studioSize', 'solo')
    );
  END IF;

  RETURN grogu_user_json(u, u.id);
END;
$$;

/* -------------------------------------------------------------------------- */
/*  Bootstrap                                                                  */
/* -------------------------------------------------------------------------- */
-- One document holding every collection the frontend store keeps. The client
-- does all its joins and aggregations locally over these arrays (30-odd
-- selector hooks in `lib/hooks/use-grogu.ts`), so serving them together keeps
-- that code working unchanged while the data becomes real.
--
-- Scoped to the viewer: a tester never receives another tester's applications,
-- feedback, progress or notifications, and a developer only sees those
-- belonging to their own playtests. Passing NULL yields the anonymous view used
-- by the marketing and discover pages.

CREATE OR REPLACE FUNCTION grogu_bootstrap(p_viewer_id integer) RETURNS jsonb
  LANGUAGE plpgsql STABLE AS $$
DECLARE
  v_role       text;
  v_player_id  integer;
  v_studio_id  integer;
  v_result     jsonb;
BEGIN
  SELECT grogu_role_to_api(role) INTO v_role FROM users WHERE id = p_viewer_id;
  SELECT id INTO v_player_id FROM players WHERE user_id = p_viewer_id;
  SELECT id INTO v_studio_id FROM studios WHERE user_id = p_viewer_id;

  SELECT jsonb_build_object(

    'session', CASE WHEN v_role IS NULL THEN NULL ELSE
      (SELECT jsonb_build_object('user', grogu_user_json(u, p_viewer_id), 'role', v_role)
         FROM users u WHERE u.id = p_viewer_id) END,

    -- Public directory: every user, with emails masked to all but the viewer.
    'users', coalesce((SELECT jsonb_agg(grogu_user_json(u, p_viewer_id) ORDER BY u.id)
                         FROM users u WHERE u.role <> 'Admin'), '[]'::jsonb),

    'testerProfiles', coalesce((SELECT jsonb_agg(grogu_tester_profile_json(pl) ORDER BY pl.id)
                                  FROM players pl), '[]'::jsonb),

    'developerProfiles', coalesce((SELECT jsonb_agg(grogu_developer_profile_json(s) ORDER BY s.id)
                                     FROM studios s), '[]'::jsonb),

    'games', coalesce((SELECT jsonb_agg(grogu_game_json(g) ORDER BY g.updated_at DESC, g.id)
                         FROM games g), '[]'::jsonb),

    -- Drafts are visible only to the developer who owns them.
    'playtests', coalesce((SELECT jsonb_agg(grogu_playtest_json(p) ORDER BY p.created_at DESC, p.id)
                             FROM playtests p
                            WHERE p.game_id IS NOT NULL
                              AND (p.status <> 'draft' OR p.studio_id = v_studio_id)), '[]'::jsonb),

    'applications', coalesce((SELECT jsonb_agg(grogu_application_json(a) ORDER BY a.created_at DESC, a.id)
                                FROM applications a
                                JOIN playtests p ON p.id = a.playtest_id
                               WHERE a.player_id = v_player_id
                                  OR p.studio_id = v_studio_id), '[]'::jsonb),

    'feedback', coalesce((SELECT jsonb_agg(grogu_feedback_json(f) ORDER BY f.created_at DESC, f.id)
                            FROM feedback f
                            JOIN playtests p ON p.id = f.playtest_id
                           WHERE f.player_id = v_player_id
                              OR p.studio_id = v_studio_id), '[]'::jsonb),

    'testProgress', coalesce((SELECT jsonb_agg(grogu_progress_json(tp) ORDER BY tp.id)
                                FROM test_progress tp
                                JOIN playtests p ON p.id = tp.playtest_id
                               WHERE tp.tester_user_id = p_viewer_id
                                  OR p.studio_id = v_studio_id), '[]'::jsonb),

    'notifications', coalesce((SELECT jsonb_agg(grogu_notification_json(n) ORDER BY n.created_at DESC, n.id)
                                 FROM notifications n
                                WHERE n.user_id = p_viewer_id), '[]'::jsonb),

    -- Public totals for the marketing pages. These are counts over the whole
    -- platform, not over the caller's scoped collections, so an anonymous
    -- visitor still sees real numbers instead of zeroes.
    'stats', jsonb_build_object(
      'games',             (SELECT count(*) FROM games),
      'activePlaytests',   (SELECT count(*) FROM playtests
                             WHERE status IN ('recruiting', 'in-progress')),
      'testers',           (SELECT count(*) FROM users WHERE role = 'Player'),
      'feedbackSubmitted', (SELECT count(*) FROM feedback)
    )
  ) INTO v_result;

  RETURN v_result;
END;
$$;

/* -------------------------------------------------------------------------- */
/*  Games                                                                      */
/* -------------------------------------------------------------------------- */

CREATE OR REPLACE FUNCTION grogu_game_save(
  p_user_id integer, p_game_id integer, p_input jsonb
) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE g games;
BEGIN
  PERFORM grogu_require_role(p_user_id, 'developer');

  IF coalesce(trim(p_input ->> 'title'), '') = '' THEN
    RAISE EXCEPTION 'Give the game a title.' USING ERRCODE = 'GR005';
  END IF;

  IF p_game_id IS NULL THEN
    INSERT INTO games (developer_user_id, title, tagline, description, genres, platforms,
                       status, accent_hue, build_version)
    VALUES (
      p_user_id,
      trim(p_input ->> 'title'),
      coalesce(p_input ->> 'tagline', ''),
      coalesce(p_input ->> 'description', ''),
      grogu_jsonb_text_array(p_input -> 'genres'),
      grogu_jsonb_text_array(p_input -> 'platforms'),
      coalesce(p_input ->> 'status', 'in-development'),
      coalesce((p_input ->> 'accentHue')::int, 210),
      coalesce(p_input ->> 'buildVersion', '0.1.0')
    )
    RETURNING * INTO g;
  ELSE
    UPDATE games SET
      title         = trim(p_input ->> 'title'),
      tagline       = coalesce(p_input ->> 'tagline', ''),
      description   = coalesce(p_input ->> 'description', ''),
      genres        = grogu_jsonb_text_array(p_input -> 'genres'),
      platforms     = grogu_jsonb_text_array(p_input -> 'platforms'),
      status        = coalesce(p_input ->> 'status', 'in-development'),
      accent_hue    = coalesce((p_input ->> 'accentHue')::int, 210),
      build_version = coalesce(p_input ->> 'buildVersion', '0.1.0'),
      updated_at    = now()
     WHERE id = p_game_id AND developer_user_id = p_user_id
    RETURNING * INTO g;

    IF g.id IS NULL THEN
      RAISE EXCEPTION 'Game not found.' USING ERRCODE = 'GR001';
    END IF;
  END IF;

  RETURN grogu_game_json(g);
END;
$$;

/* -------------------------------------------------------------------------- */
/*  Playtests                                                                  */
/* -------------------------------------------------------------------------- */

-- Replaces the playtest's task list with the one supplied, preserving the ids
-- of tasks the client sent back so a tester's recorded progress still points at
-- the right row.
CREATE OR REPLACE FUNCTION grogu_sync_tasks(p_playtest_id integer, p_tasks jsonb) RETURNS void
  LANGUAGE plpgsql AS $$
DECLARE
  t        jsonb;
  v_keep   integer[] := '{}';
  v_pos    integer := 0;
  v_id     integer;
BEGIN
  FOR t IN SELECT * FROM jsonb_array_elements(coalesce(p_tasks, '[]'::jsonb)) LOOP
    v_id := nullif(t ->> 'id', '')::int;

    IF v_id IS NOT NULL AND EXISTS (
      SELECT 1 FROM playtest_tasks WHERE id = v_id AND playtest_id = p_playtest_id
    ) THEN
      UPDATE playtest_tasks SET
        title             = coalesce(t ->> 'title', ''),
        description       = coalesce(t ->> 'description', ''),
        type              = coalesce(t ->> 'type', 'objective'),
        required          = coalesce((t ->> 'required')::boolean, true),
        estimated_minutes = coalesce((t ->> 'estimatedMinutes')::int, 15),
        position          = v_pos
       WHERE id = v_id;
    ELSE
      INSERT INTO playtest_tasks (playtest_id, title, description, type, required, estimated_minutes, position)
      VALUES (
        p_playtest_id,
        coalesce(t ->> 'title', ''),
        coalesce(t ->> 'description', ''),
        coalesce(t ->> 'type', 'objective'),
        coalesce((t ->> 'required')::boolean, true),
        coalesce((t ->> 'estimatedMinutes')::int, 15),
        v_pos
      )
      RETURNING id INTO v_id;
    END IF;

    v_keep := v_keep || v_id;
    v_pos  := v_pos + 1;
  END LOOP;

  DELETE FROM playtest_tasks WHERE playtest_id = p_playtest_id AND NOT (id = ANY (v_keep));
END;
$$;

CREATE OR REPLACE FUNCTION grogu_playtest_save(
  p_user_id integer, p_playtest_id integer, p_input jsonb
) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE
  p          playtests;
  g          games;
  v_studio   integer;
  v_status   text;
BEGIN
  PERFORM grogu_require_role(p_user_id, 'developer');
  v_studio := grogu_studio_id(p_user_id);

  SELECT * INTO g FROM games
   WHERE id = nullif(p_input ->> 'gameId', '')::int AND developer_user_id = p_user_id;
  IF g.id IS NULL THEN
    RAISE EXCEPTION 'Pick one of your games.' USING ERRCODE = 'GR005';
  END IF;

  IF coalesce(trim(p_input ->> 'title'), '') = '' THEN
    RAISE EXCEPTION 'Give the playtest a title.' USING ERRCODE = 'GR005';
  END IF;
  IF coalesce((p_input ->> 'maxTesters')::int, 0) < 1 THEN
    RAISE EXCEPTION 'A playtest needs at least one tester.' USING ERRCODE = 'GR005';
  END IF;

  IF p_playtest_id IS NULL THEN
    v_status := CASE WHEN coalesce((p_input ->> 'publish')::boolean, false)
                     THEN 'recruiting' ELSE 'draft' END;

    INSERT INTO playtests (
      studio_id, game_id, title, summary, goals, focus_areas, status, requirements_json,
      reward, cash_reward, max_testers, build_url, opens_at, closes_at,
      -- legacy columns, kept populated so `/api/playtests/*` still works
      game_name, genre, platform, requirements, target_players
    ) VALUES (
      v_studio, g.id,
      trim(p_input ->> 'title'),
      coalesce(p_input ->> 'summary', ''),
      grogu_jsonb_text_array(p_input -> 'goals'),
      grogu_jsonb_text_array(p_input -> 'focusAreas'),
      v_status,
      coalesce(p_input -> 'requirements', '{}'::jsonb),
      coalesce(p_input ->> 'reward', ''),
      nullif(p_input ->> 'cashReward', '')::int,
      (p_input ->> 'maxTesters')::int,
      coalesce(p_input ->> 'buildUrl', ''),
      now(),
      nullif(p_input ->> 'closesAt', '')::timestamptz,
      g.title,
      coalesce(array_to_string(g.genres, ', '), ''),
      coalesce(array_to_string(g.platforms, ', '), ''),
      coalesce(p_input ->> 'summary', ''),
      (p_input ->> 'maxTesters')::int
    )
    RETURNING * INTO p;

    IF v_status = 'recruiting' THEN
      PERFORM grogu_notify(
        p_user_id, 'playtest-published', p.title || ' is live',
        'Your playtest is now visible on Discover and open for applications.',
        '/developer/playtests/' || p.id);
    END IF;
  ELSE
    SELECT * INTO p FROM playtests WHERE id = p_playtest_id AND studio_id = v_studio;
    IF p.id IS NULL THEN
      RAISE EXCEPTION 'Playtest not found.' USING ERRCODE = 'GR001';
    END IF;
    IF p.status <> 'draft' THEN
      RAISE EXCEPTION 'Only draft playtests can be edited.' USING ERRCODE = 'GR003';
    END IF;

    UPDATE playtests SET
      game_id           = g.id,
      title             = trim(p_input ->> 'title'),
      summary           = coalesce(p_input ->> 'summary', ''),
      goals             = grogu_jsonb_text_array(p_input -> 'goals'),
      focus_areas       = grogu_jsonb_text_array(p_input -> 'focusAreas'),
      requirements_json = coalesce(p_input -> 'requirements', '{}'::jsonb),
      reward            = coalesce(p_input ->> 'reward', ''),
      cash_reward       = nullif(p_input ->> 'cashReward', '')::int,
      max_testers       = (p_input ->> 'maxTesters')::int,
      closes_at         = nullif(p_input ->> 'closesAt', '')::timestamptz,
      game_name         = g.title,
      genre             = coalesce(array_to_string(g.genres, ', '), ''),
      platform          = coalesce(array_to_string(g.platforms, ', '), ''),
      target_players    = (p_input ->> 'maxTesters')::int
     WHERE id = p_playtest_id
    RETURNING * INTO p;
  END IF;

  PERFORM grogu_sync_tasks(p.id, p_input -> 'tasks');

  SELECT * INTO p FROM playtests WHERE id = p.id;
  RETURN grogu_playtest_json(p);
END;
$$;

CREATE OR REPLACE FUNCTION grogu_playtest_set_status(
  p_user_id integer, p_playtest_id integer, p_status text
) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE
  p        playtests;
  v_studio integer;
  v_ok     boolean;
BEGIN
  PERFORM grogu_require_role(p_user_id, 'developer');
  v_studio := grogu_studio_id(p_user_id);

  SELECT * INTO p FROM playtests WHERE id = p_playtest_id AND studio_id = v_studio;
  IF p.id IS NULL THEN
    RAISE EXCEPTION 'Playtest not found.' USING ERRCODE = 'GR001';
  END IF;

  -- Same transition table as PLAYTEST_STATUS_TRANSITIONS in `lib/domain.ts`.
  v_ok := CASE p.status
            WHEN 'draft'       THEN p_status = 'recruiting'
            WHEN 'recruiting'  THEN p_status IN ('in-progress', 'closed')
            WHEN 'in-progress' THEN p_status IN ('review', 'closed')
            WHEN 'review'      THEN p_status IN ('completed', 'closed')
            WHEN 'completed'   THEN p_status = 'archived'
            WHEN 'closed'      THEN p_status = 'archived'
            ELSE false
          END;

  IF NOT v_ok THEN
    RAISE EXCEPTION 'A % playtest cannot move to %.', p.status, p_status USING ERRCODE = 'GR003';
  END IF;

  UPDATE playtests SET status = p_status WHERE id = p.id RETURNING * INTO p;

  IF p_status = 'recruiting' THEN
    PERFORM grogu_notify(
      p_user_id, 'playtest-published', p.title || ' is live',
      'Your playtest is now visible on Discover and open for applications.',
      '/developer/playtests/' || p.id);
  END IF;

  RETURN grogu_playtest_json(p);
END;
$$;

/* -------------------------------------------------------------------------- */
/*  Applications                                                               */
/* -------------------------------------------------------------------------- */

CREATE OR REPLACE FUNCTION grogu_application_create(
  p_user_id integer, p_playtest_id integer, p_input jsonb
) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE
  a          applications;
  p          playtests;
  v_player   integer;
  v_dev      integer;
BEGIN
  PERFORM grogu_require_role(p_user_id, 'tester');
  v_player := grogu_player_id(p_user_id);

  SELECT * INTO p FROM playtests WHERE id = p_playtest_id;
  IF p.id IS NULL THEN
    RAISE EXCEPTION 'Playtest not found.' USING ERRCODE = 'GR001';
  END IF;
  IF p.status <> 'recruiting' THEN
    RAISE EXCEPTION 'This playtest is not accepting applications.' USING ERRCODE = 'GR003';
  END IF;
  IF NOT coalesce((p_input ->> 'agreedToTerms')::boolean, false) THEN
    RAISE EXCEPTION 'You must accept the playtest terms.' USING ERRCODE = 'GR005';
  END IF;

  IF EXISTS (
    SELECT 1 FROM applications
     WHERE playtest_id = p_playtest_id AND player_id = v_player AND status <> 'Withdrawn'
  ) THEN
    RAISE EXCEPTION 'You''ve already applied to this playtest.' USING ERRCODE = 'GR003';
  END IF;

  -- A withdrawn application is reused, because (player_id, playtest_id) is unique.
  INSERT INTO applications (player_id, playtest_id, status, message, device, experience_note)
  VALUES (v_player, p_playtest_id, 'Pending',
          coalesce(p_input ->> 'message', ''),
          coalesce(p_input ->> 'device', ''),
          coalesce(p_input ->> 'experienceNote', ''))
  ON CONFLICT (player_id, playtest_id) DO UPDATE SET
    status          = 'Pending',
    message         = excluded.message,
    device          = excluded.device,
    experience_note = excluded.experience_note,
    decided_at      = NULL,
    decision_note   = NULL,
    created_at      = now()
  RETURNING * INTO a;

  SELECT s.user_id INTO v_dev FROM studios s WHERE s.id = p.studio_id;
  PERFORM grogu_notify(
    v_dev, 'application-received',
    'New applicant for ' || coalesce(p.title, p.game_name),
    coalesce((SELECT name FROM users WHERE id = p_user_id), 'A tester') || ' applied to your playtest.',
    '/developer/playtests/' || p.id);

  RETURN grogu_application_json(a);
END;
$$;

CREATE OR REPLACE FUNCTION grogu_application_withdraw(
  p_user_id integer, p_application_id integer
) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE
  a        applications;
  v_player integer;
BEGIN
  PERFORM grogu_require_role(p_user_id, 'tester');
  v_player := grogu_player_id(p_user_id);

  UPDATE applications SET status = 'Withdrawn', decided_at = now()
   WHERE id = p_application_id AND player_id = v_player
  RETURNING * INTO a;

  IF a.id IS NULL THEN
    RAISE EXCEPTION 'Application not found.' USING ERRCODE = 'GR001';
  END IF;

  RETURN grogu_application_json(a);
END;
$$;

CREATE OR REPLACE FUNCTION grogu_application_decide(
  p_user_id integer, p_application_id integer, p_decision text, p_note text
) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE
  a          applications;
  p          playtests;
  v_studio   integer;
  v_tester   integer;
  v_accepted integer;
BEGIN
  PERFORM grogu_require_role(p_user_id, 'developer');
  v_studio := grogu_studio_id(p_user_id);

  IF p_decision NOT IN ('accepted', 'rejected') THEN
    RAISE EXCEPTION 'Decision must be accepted or rejected.' USING ERRCODE = 'GR005';
  END IF;

  SELECT a2.* INTO a
    FROM applications a2
    JOIN playtests p2 ON p2.id = a2.playtest_id
   WHERE a2.id = p_application_id AND p2.studio_id = v_studio;
  IF a.id IS NULL THEN
    RAISE EXCEPTION 'Application not found.' USING ERRCODE = 'GR001';
  END IF;
  IF a.status = 'Withdrawn' THEN
    RAISE EXCEPTION 'That application was withdrawn.' USING ERRCODE = 'GR003';
  END IF;

  SELECT * INTO p FROM playtests WHERE id = a.playtest_id;
  SELECT pl.user_id INTO v_tester FROM players pl WHERE pl.id = a.player_id;

  -- The roster cap is the developer's own `maxTesters`; the mock never enforced
  -- it because nothing could oversubscribe a local store.
  IF p_decision = 'accepted' AND a.status <> 'Selected' THEN
    SELECT count(*) INTO v_accepted FROM applications
     WHERE playtest_id = p.id AND status IN ('Selected', 'Completed');
    IF v_accepted >= p.max_testers THEN
      RAISE EXCEPTION 'This playtest is already full (% of % testers).', v_accepted, p.max_testers
        USING ERRCODE = 'GR003';
    END IF;
  END IF;

  UPDATE applications SET
    status        = grogu_appstatus_to_db(p_decision),
    decided_at    = now(),
    decision_note = coalesce(nullif(trim(coalesce(p_note, '')), ''), decision_note)
   WHERE id = a.id
  RETURNING * INTO a;

  IF p_decision = 'accepted' THEN
    INSERT INTO test_progress (playtest_id, tester_user_id)
    VALUES (p.id, v_tester)
    ON CONFLICT (playtest_id, tester_user_id) DO NOTHING;

    PERFORM grogu_notify(
      v_tester, 'application-accepted',
      'You''re in: ' || coalesce(p.title, p.game_name),
      'Your application was accepted. Open the test workspace to get started.',
      '/tests/' || p.id);
  ELSE
    PERFORM grogu_notify(
      v_tester, 'application-rejected',
      'Update on ' || coalesce(p.title, p.game_name),
      coalesce(nullif(trim(coalesce(p_note, '')), ''),
               'Your application wasn''t selected this time. Keep an eye on Discover for more playtests.'),
      '/discover');
  END IF;

  RETURN grogu_application_json(a);
END;
$$;

/* -------------------------------------------------------------------------- */
/*  Tester workspace                                                           */
/* -------------------------------------------------------------------------- */

-- A tester may only touch a playtest they were accepted to.
CREATE OR REPLACE FUNCTION grogu_require_accepted(p_user_id integer, p_playtest_id integer)
  RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  PERFORM grogu_require_role(p_user_id, 'tester');
  IF NOT EXISTS (
    SELECT 1 FROM applications a
      JOIN players pl ON pl.id = a.player_id
     WHERE a.playtest_id = p_playtest_id
       AND pl.user_id = p_user_id
       AND a.status IN ('Selected', 'Completed')
  ) THEN
    RAISE EXCEPTION 'You are not on the roster for this playtest.' USING ERRCODE = 'GR004';
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION grogu_progress_row(p_playtest_id integer, p_user_id integer)
  RETURNS test_progress LANGUAGE plpgsql AS $$
DECLARE tp test_progress;
BEGIN
  SELECT * INTO tp FROM test_progress
   WHERE playtest_id = p_playtest_id AND tester_user_id = p_user_id;
  IF tp.id IS NULL THEN
    INSERT INTO test_progress (playtest_id, tester_user_id)
    VALUES (p_playtest_id, p_user_id)
    RETURNING * INTO tp;
  END IF;
  RETURN tp;
END;
$$;

CREATE OR REPLACE FUNCTION grogu_test_download(p_user_id integer, p_playtest_id integer)
  RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE tp test_progress;
BEGIN
  PERFORM grogu_require_accepted(p_user_id, p_playtest_id);
  tp := grogu_progress_row(p_playtest_id, p_user_id);

  UPDATE test_progress SET
    build_downloaded = true,
    stage            = CASE WHEN stage = 'not-started' THEN 'in-progress' ELSE stage END,
    started_at       = coalesce(started_at, now())
   WHERE id = tp.id
  RETURNING * INTO tp;

  RETURN grogu_progress_json(tp);
END;
$$;

CREATE OR REPLACE FUNCTION grogu_test_toggle_task(
  p_user_id integer, p_playtest_id integer, p_task_id integer
) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE
  tp            test_progress;
  v_completed   integer[];
  v_all_required boolean;
  v_stage       text;
BEGIN
  PERFORM grogu_require_accepted(p_user_id, p_playtest_id);

  IF NOT EXISTS (SELECT 1 FROM playtest_tasks WHERE id = p_task_id AND playtest_id = p_playtest_id) THEN
    RAISE EXCEPTION 'Task not found.' USING ERRCODE = 'GR001';
  END IF;

  tp := grogu_progress_row(p_playtest_id, p_user_id);

  v_completed := CASE
    WHEN p_task_id = ANY (tp.completed_task_ids)
      THEN array_remove(tp.completed_task_ids, p_task_id)
    ELSE tp.completed_task_ids || p_task_id
  END;

  SELECT NOT EXISTS (
    SELECT 1 FROM playtest_tasks t
     WHERE t.playtest_id = p_playtest_id AND t.required AND NOT (t.id = ANY (v_completed))
  ) INTO v_all_required;

  -- Mirrors the stage machine in `grogu-store.ts#toggleTask`: only the
  -- pre-feedback stages move, so a completed test never regresses.
  v_stage := CASE
    WHEN tp.stage IN ('not-started', 'in-progress')
      THEN CASE WHEN v_all_required THEN 'tasks-complete' ELSE 'in-progress' END
    WHEN tp.stage = 'tasks-complete' AND NOT v_all_required
      THEN 'in-progress'
    ELSE tp.stage
  END;

  UPDATE test_progress SET
    completed_task_ids = v_completed,
    stage              = v_stage,
    started_at         = coalesce(started_at, now())
   WHERE id = tp.id
  RETURNING * INTO tp;

  RETURN grogu_progress_json(tp);
END;
$$;

CREATE OR REPLACE FUNCTION grogu_feedback_submit(
  p_user_id integer, p_playtest_id integer, p_input jsonb
) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE
  f          feedback;
  tp         test_progress;
  p          playtests;
  v_player   integer;
  v_dev      integer;
  v_ratings  jsonb := coalesce(p_input -> 'ratings', '{}'::jsonb);
  v_avg      integer;
BEGIN
  PERFORM grogu_require_accepted(p_user_id, p_playtest_id);
  v_player := grogu_player_id(p_user_id);

  IF EXISTS (SELECT 1 FROM feedback WHERE playtest_id = p_playtest_id AND player_id = v_player) THEN
    RAISE EXCEPTION 'You have already submitted feedback for this playtest.' USING ERRCODE = 'GR003';
  END IF;

  FOREACH v_avg IN ARRAY ARRAY[
    coalesce((v_ratings ->> 'fun')::int, 0),
    coalesce((v_ratings ->> 'difficulty')::int, 0),
    coalesce((v_ratings ->> 'clarity')::int, 0),
    coalesce((v_ratings ->> 'performance')::int, 0),
    coalesce((v_ratings ->> 'polish')::int, 0)
  ] LOOP
    IF v_avg < 1 OR v_avg > 5 THEN
      RAISE EXCEPTION 'Every rating must be between 1 and 5.' USING ERRCODE = 'GR005';
    END IF;
  END LOOP;

  SELECT * INTO p FROM playtests WHERE id = p_playtest_id;

  INSERT INTO feedback (
    playtest_id, player_id,
    rating_fun, rating_difficulty, rating_clarity, rating_performance, rating_polish,
    sentiment, summary, highlights, pain_points, bugs, answers, would_recommend, hours_played,
    -- legacy columns, kept populated so `/api/feedback/*` still works
    rating, comment
  ) VALUES (
    p_playtest_id, v_player,
    (v_ratings ->> 'fun')::int,
    (v_ratings ->> 'difficulty')::int,
    (v_ratings ->> 'clarity')::int,
    (v_ratings ->> 'performance')::int,
    (v_ratings ->> 'polish')::int,
    coalesce(p_input ->> 'sentiment', 'neutral'),
    coalesce(p_input ->> 'summary', ''),
    grogu_jsonb_text_array(p_input -> 'highlights'),
    grogu_jsonb_text_array(p_input -> 'painPoints'),
    grogu_jsonb_text_array(p_input -> 'bugs'),
    coalesce(p_input -> 'answers', '[]'::jsonb),
    coalesce((p_input ->> 'wouldRecommend')::boolean, true),
    coalesce((p_input ->> 'hoursPlayed')::numeric, 0),
    greatest(1, least(5, round((
      coalesce((v_ratings ->> 'fun')::int, 3) +
      coalesce((v_ratings ->> 'difficulty')::int, 3) +
      coalesce((v_ratings ->> 'clarity')::int, 3) +
      coalesce((v_ratings ->> 'performance')::int, 3) +
      coalesce((v_ratings ->> 'polish')::int, 3)
    ) / 5.0)::int)),
    coalesce(p_input ->> 'summary', '')
  )
  RETURNING * INTO f;

  tp := grogu_progress_row(p_playtest_id, p_user_id);
  UPDATE test_progress SET
    stage        = 'completed',
    feedback_id  = f.id,
    completed_at = now(),
    started_at   = coalesce(started_at, now())
   WHERE id = tp.id
  RETURNING * INTO tp;

  -- An accepted tester who has finished is marked Completed, which is what the
  -- legacy application status vocabulary already meant by it.
  UPDATE applications SET status = 'Completed'
   WHERE playtest_id = p_playtest_id AND player_id = v_player AND status = 'Selected';

  SELECT s.user_id INTO v_dev FROM studios s WHERE s.id = p.studio_id;
  PERFORM grogu_notify(
    v_dev, 'feedback-received',
    'New feedback for ' || coalesce(p.title, p.game_name),
    'A tester submitted feedback (' || coalesce(p_input ->> 'hoursPlayed', '0') || 'h played).',
    '/developer/playtests/' || p.id);

  RETURN jsonb_build_object(
    'feedback', grogu_feedback_json(f),
    'progress', grogu_progress_json(tp)
  );
END;
$$;

/* -------------------------------------------------------------------------- */
/*  Notifications                                                              */
/* -------------------------------------------------------------------------- */

CREATE OR REPLACE FUNCTION grogu_notification_read(
  p_user_id integer, p_notification_id integer
) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE n notifications;
BEGIN
  UPDATE notifications SET read = true
   WHERE id = p_notification_id AND user_id = p_user_id
  RETURNING * INTO n;

  IF n.id IS NULL THEN
    RAISE EXCEPTION 'Notification not found.' USING ERRCODE = 'GR001';
  END IF;

  RETURN grogu_notification_json(n);
END;
$$;

CREATE OR REPLACE FUNCTION grogu_notification_read_all(p_user_id integer) RETURNS jsonb
  LANGUAGE plpgsql AS $$
DECLARE v_count integer;
BEGIN
  UPDATE notifications SET read = true WHERE user_id = p_user_id AND NOT read;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN jsonb_build_object('updated', v_count);
END;
$$;

/* -------------------------------------------------------------------------- */
/*  Profiles                                                                   */
/* -------------------------------------------------------------------------- */

CREATE OR REPLACE FUNCTION grogu_profile_save(p_user_id integer, p_input jsonb) RETURNS jsonb
  LANGUAGE plpgsql AS $$
DECLARE
  u      users;
  v_role text;
BEGIN
  SELECT grogu_role_to_api(role) INTO v_role FROM users WHERE id = p_user_id;
  IF v_role IS NULL THEN
    RAISE EXCEPTION 'Not signed in.' USING ERRCODE = 'GR004';
  END IF;

  UPDATE users SET
    name       = coalesce(nullif(trim(coalesce(p_input ->> 'name', '')), ''), name),
    location   = coalesce(p_input ->> 'location', location),
    bio        = coalesce(p_input ->> 'bio', bio),
    avatar_url = coalesce(p_input ->> 'avatarUrl', avatar_url)
   WHERE id = p_user_id
  RETURNING * INTO u;

  IF v_role = 'tester' THEN
    PERFORM grogu_player_id(p_user_id);
    UPDATE players SET
      experience                = coalesce(p_input ->> 'experienceLevel', experience),
      platforms                 = coalesce(array_to_string(grogu_jsonb_text_array(p_input -> 'platforms'), ','), platforms),
      genres                    = coalesce(array_to_string(grogu_jsonb_text_array(p_input -> 'preferredGenres'), ','), genres),
      languages                 = coalesce(nullif(grogu_jsonb_text_array(p_input -> 'languages'), '{}'), languages),
      weekly_availability_hours = coalesce((p_input ->> 'weeklyAvailabilityHours')::int, weekly_availability_hours)
     WHERE user_id = p_user_id;
  ELSIF v_role = 'developer' THEN
    PERFORM grogu_studio_id(p_user_id);
    UPDATE studios SET
      name         = coalesce(nullif(trim(coalesce(p_input ->> 'studioName', '')), ''), name),
      website      = coalesce(p_input ->> 'website', website),
      studio_size  = coalesce(p_input ->> 'studioSize', studio_size),
      founded_year = coalesce((p_input ->> 'foundedYear')::int, founded_year)
     WHERE user_id = p_user_id;
  END IF;

  RETURN grogu_user_json(u, p_user_id);
END;
$$;

COMMIT;
