-- 006_playtest_requirements_defaults.sql
--
-- Guarantees that a playtest's `requirements` always carries all seven fields
-- of the frontend's `TesterRequirements`.
--
-- `grogu_playtest_save` stored whatever jsonb it was handed, defaulting only to
-- `{}`. A request that omitted `requirements`, or sent a partial one, produced a
-- playtest whose `requirements` was missing keys — and the frontend's type says
-- they are always present, so components read `requirements.platforms` and
-- `requirements.estimatedHours` directly. A single such row crashed the whole
-- Discover page with "Cannot read properties of undefined".
--
-- The supplied object is now merged over a complete default derived from the
-- game, and existing incomplete rows are backfilled the same way.

BEGIN;

/* -------------------------------------------------------------------------- */
/*  Complete requirements from a partial one                                   */
/* -------------------------------------------------------------------------- */
-- `||` on jsonb is a shallow merge with the right-hand side winning, so the
-- caller's values override the defaults and any key they omitted survives.

CREATE OR REPLACE FUNCTION grogu_requirements_json(p_input jsonb, p_game_id integer)
  RETURNS jsonb LANGUAGE sql STABLE AS $$
  SELECT jsonb_build_object(
           'minExperienceLevel', 'casual',
           'platforms',          coalesce((SELECT to_jsonb(g.platforms) FROM games g WHERE g.id = p_game_id), '[]'::jsonb),
           'preferredGenres',    coalesce((SELECT to_jsonb(g.genres)    FROM games g WHERE g.id = p_game_id), '[]'::jsonb),
           'languages',          to_jsonb(ARRAY['English']),
           'minReputation',      0,
           'estimatedHours',     4,
           'ndaRequired',        false
         )
         || CASE
              WHEN p_input IS NULL OR jsonb_typeof(p_input) <> 'object'
              THEN '{}'::jsonb
              -- Drop explicit nulls too: a null would pass the key-exists test
              -- but still break the consumer.
              ELSE (SELECT coalesce(jsonb_object_agg(key, value), '{}'::jsonb)
                      FROM jsonb_each(p_input)
                     WHERE jsonb_typeof(value) <> 'null')
            END;
$$;

/* -------------------------------------------------------------------------- */
/*  Use it on write                                                            */
/* -------------------------------------------------------------------------- */

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
      grogu_requirements_json(p_input -> 'requirements', g.id),
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
      requirements_json = grogu_requirements_json(p_input -> 'requirements', g.id),
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

/* -------------------------------------------------------------------------- */
/*  Backfill rows written before this fix                                      */
/* -------------------------------------------------------------------------- */

UPDATE playtests
   SET requirements_json = grogu_requirements_json(requirements_json, game_id)
 WHERE game_id IS NOT NULL
   AND NOT (requirements_json ?& ARRAY[
     'minExperienceLevel', 'platforms', 'preferredGenres',
     'languages', 'minReputation', 'estimatedHours', 'ndaRequired'
   ]);

COMMIT;
