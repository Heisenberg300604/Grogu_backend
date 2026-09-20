-- 004_demo_accounts.sql
--
-- The two accounts the login form offers as one-click buttons.
--
-- `lib/services/auth.ts` on the frontend hard-codes these addresses in
-- DEMO_ACCOUNTS and renders a "Continue as ..." button for each, so they have
-- to resolve against the database or the buttons 401. Their details match the
-- personas the mock data used, which keeps the demo copy coherent.
--
-- The password is public by design: these are shared demo logins for a
-- portfolio project. They are ordinary accounts with no elevated role, and they
-- own only the demo content created below. Remove this migration, or change the
-- password and the DEMO_ACCOUNTS constant together, before putting real user
-- data in this database.
--
-- Idempotent: re-running refreshes the passwords and leaves everything else.

BEGIN;

INSERT INTO users (email, role, password, name, handle, location, bio)
VALUES
  ('mara@driftwoodgames.dev', 'Studio', crypt('playtest', gen_salt('bf', 10)),
   'Mara Okafor', 'maraokafor', 'Lisbon, PT',
   'Solo developer building cozy systems-driven games. Ex-gameplay engineer.'),
  ('priya.nair@example.com', 'Player', crypt('playtest', gen_salt('bf', 10)),
   'Priya Nair', 'priyaplays', 'Bengaluru, IN',
   'Systems tinkerer. I write bug reports developers actually thank me for.')
ON CONFLICT (email) DO UPDATE SET
  password = excluded.password,
  name     = coalesce(users.name, excluded.name),
  location = CASE WHEN users.location = '' THEN excluded.location ELSE users.location END,
  bio      = CASE WHEN users.bio = '' THEN excluded.bio ELSE users.bio END;

-- Role side tables.
INSERT INTO studios (user_id, name, website, studio_size, founded_year)
SELECT u.id, 'Driftwood Games', 'https://driftwoodgames.dev', 'solo', 2021
  FROM users u WHERE u.email = 'mara@driftwoodgames.dev'
ON CONFLICT (user_id) DO NOTHING;

INSERT INTO players (user_id, age, experience, platforms, genres,
                     languages, weekly_availability_hours, reputation, badges)
SELECT u.id, 29, 'hardcore', 'pc,console', 'rpg,strategy,roguelike',
       ARRAY['English'], 10, 82, ARRAY['Detailed reporter', 'Fast turnaround']
  FROM users u WHERE u.email = 'priya.nair@example.com'
ON CONFLICT (user_id) DO NOTHING;

-- A game and an open playtest, so the demo developer's dashboard and the
-- Discover page are not empty on a fresh database.
INSERT INTO games (developer_user_id, title, tagline, description,
                   genres, platforms, status, accent_hue, build_version)
SELECT u.id,
       'Lanternfall',
       'Tend the light, keep the dark at bay',
       'A cozy systems-driven survival game about maintaining a lighthouse through a long winter.',
       ARRAY['simulation', 'adventure'],
       ARRAY['pc', 'mac'],
       'beta', 34, '0.8.1'
  FROM users u
 WHERE u.email = 'mara@driftwoodgames.dev'
   AND NOT EXISTS (
     SELECT 1 FROM games g
      WHERE g.developer_user_id = u.id AND g.title = 'Lanternfall'
   );

INSERT INTO playtests (
  studio_id, game_id, title, summary, goals, focus_areas, status,
  requirements_json, reward, max_testers, build_url, opens_at, closes_at,
  game_name, genre, platform, requirements, target_players
)
SELECT s.id, g.id,
       'Lanternfall winter build — first impressions',
       'We want to know whether the first hour teaches the lighthouse loop without a tutorial.',
       ARRAY['Confirm the fuel loop is discoverable', 'Find the point players get stuck'],
       ARRAY['onboarding', 'difficulty-balance'],
       'recruiting',
       jsonb_build_object(
         'minExperienceLevel', 'casual',
         'platforms',          to_jsonb(ARRAY['pc', 'mac']),
         'preferredGenres',    to_jsonb(ARRAY['simulation']),
         'languages',          to_jsonb(ARRAY['English']),
         'minReputation',      0,
         'estimatedHours',     3,
         'ndaRequired',        false),
       'Steam key + credit in the shipped game',
       12, '', now(), now() + interval '45 days',
       g.title, 'simulation, adventure', 'pc, mac',
       'Cozy or survival game experience helps but is not required.', 12
  FROM users u
  JOIN studios s ON s.user_id = u.id
  JOIN games   g ON g.developer_user_id = u.id AND g.title = 'Lanternfall'
 WHERE u.email = 'mara@driftwoodgames.dev'
   AND NOT EXISTS (
     SELECT 1 FROM playtests p
      WHERE p.game_id = g.id AND p.title = 'Lanternfall winter build — first impressions'
   );

INSERT INTO playtest_tasks (playtest_id, title, description, type, required, estimated_minutes, position)
SELECT p.id, t.title, t.description, t.type, t.required, t.minutes, t.position
  FROM playtests p
  JOIN games g ON g.id = p.game_id
  CROSS JOIN (VALUES
    ('Survive the first winter night',
     'Play from a new save until dawn. Do not read any outside guidance.',
     'objective', true, 45, 0),
    ('Report where you got stuck',
     'Tell us the first moment you were unsure what the game wanted.',
     'survey', true, 10, 1),
    ('Log any bugs you hit',
     'Crashes, visual glitches, anything that felt broken.',
     'bug-report', false, 15, 2)
  ) AS t(title, description, type, required, minutes, position)
 WHERE g.title = 'Lanternfall'
   AND p.title = 'Lanternfall winter build — first impressions'
   AND NOT EXISTS (SELECT 1 FROM playtest_tasks pt WHERE pt.playtest_id = p.id);

COMMIT;
