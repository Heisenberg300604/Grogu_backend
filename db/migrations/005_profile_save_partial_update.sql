-- 005_profile_save_partial_update.sql
--
-- Fixes `grogu_profile_save` so it honours PATCH semantics.
--
-- The version in 003 read every field with `coalesce(p_input ->> 'x', current)`,
-- which is only correct for scalars. For the array fields it went through
-- `array_to_string(grogu_jsonb_text_array(...), ',')`, and that returns `''`
-- rather than NULL when the key is absent — so a request that omitted
-- `platforms` or `preferredGenres` silently erased them instead of leaving them
-- alone. `avatarUrl` had the mirror problem: it could be set but never cleared,
-- because an explicit null coalesced back to the stored value.
--
-- Every field is now updated only when its key is actually present in the
-- payload, and the numeric fields are validated rather than being allowed to
-- fail as a cast error (which would surface as a 500).

BEGIN;

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

  IF p_input ? 'name' AND trim(coalesce(p_input ->> 'name', '')) = '' THEN
    RAISE EXCEPTION 'Enter your name.' USING ERRCODE = 'GR005';
  END IF;

  IF p_input ? 'weeklyAvailabilityHours' THEN
    IF (p_input ->> 'weeklyAvailabilityHours') !~ '^\d+$'
       OR (p_input ->> 'weeklyAvailabilityHours')::int NOT BETWEEN 0 AND 168 THEN
      RAISE EXCEPTION 'Weekly availability must be between 0 and 168 hours.'
        USING ERRCODE = 'GR005';
    END IF;
  END IF;

  IF p_input ? 'foundedYear' THEN
    IF (p_input ->> 'foundedYear') !~ '^\d{4}$'
       OR (p_input ->> 'foundedYear')::int NOT BETWEEN 1950 AND extract(year FROM now())::int THEN
      RAISE EXCEPTION 'Enter a founding year between 1950 and %.',
        extract(year FROM now())::int USING ERRCODE = 'GR005';
    END IF;
  END IF;

  UPDATE users SET
    name       = CASE WHEN p_input ? 'name'
                      THEN trim(p_input ->> 'name') ELSE name END,
    location   = CASE WHEN p_input ? 'location'
                      THEN coalesce(p_input ->> 'location', '') ELSE location END,
    bio        = CASE WHEN p_input ? 'bio'
                      THEN coalesce(p_input ->> 'bio', '') ELSE bio END,
    -- Present-but-empty clears the avatar; absent leaves it.
    avatar_url = CASE WHEN p_input ? 'avatarUrl'
                      THEN nullif(trim(coalesce(p_input ->> 'avatarUrl', '')), '')
                      ELSE avatar_url END
   WHERE id = p_user_id
  RETURNING * INTO u;

  IF v_role = 'tester' THEN
    PERFORM grogu_player_id(p_user_id);

    UPDATE players SET
      experience = CASE WHEN p_input ? 'experienceLevel'
                        THEN p_input ->> 'experienceLevel' ELSE experience END,
      platforms  = CASE WHEN p_input ? 'platforms'
                        THEN array_to_string(grogu_jsonb_text_array(p_input -> 'platforms'), ',')
                        ELSE platforms END,
      genres     = CASE WHEN p_input ? 'preferredGenres'
                        THEN array_to_string(grogu_jsonb_text_array(p_input -> 'preferredGenres'), ',')
                        ELSE genres END,
      languages  = CASE WHEN p_input ? 'languages'
                        THEN grogu_jsonb_text_array(p_input -> 'languages')
                        ELSE languages END,
      weekly_availability_hours = CASE WHEN p_input ? 'weeklyAvailabilityHours'
                        THEN (p_input ->> 'weeklyAvailabilityHours')::int
                        ELSE weekly_availability_hours END
     WHERE user_id = p_user_id;

  ELSIF v_role = 'developer' THEN
    PERFORM grogu_studio_id(p_user_id);

    IF p_input ? 'studioName' AND trim(coalesce(p_input ->> 'studioName', '')) = '' THEN
      RAISE EXCEPTION 'Enter a studio name.' USING ERRCODE = 'GR005';
    END IF;

    UPDATE studios SET
      name         = CASE WHEN p_input ? 'studioName'
                          THEN trim(p_input ->> 'studioName') ELSE name END,
      website      = CASE WHEN p_input ? 'website'
                          THEN nullif(trim(coalesce(p_input ->> 'website', '')), '')
                          ELSE website END,
      studio_size  = CASE WHEN p_input ? 'studioSize'
                          THEN p_input ->> 'studioSize' ELSE studio_size END,
      founded_year = CASE WHEN p_input ? 'foundedYear'
                          THEN (p_input ->> 'foundedYear')::int ELSE founded_year END
     WHERE user_id = p_user_id;
  END IF;

  RETURN grogu_user_json(u, p_user_id);
END;
$$;

COMMIT;
