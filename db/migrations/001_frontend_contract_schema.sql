-- 001_frontend_contract_schema.sql
--
-- Brings the Grogu database up to the domain model the frontend defines in
-- `Project-Grogu-Frontend/lib/types.ts`.
--
-- Additive and idempotent: every existing table, column, function and row is
-- preserved so the legacy `/api/*` endpoints keep working. New columns are
-- nullable or defaulted, and legacy rows are backfilled at the end so the
-- frontend's joins (which silently drop a playtest with no game/developer)
-- still see the seeded demo content.
--
-- Enum-ish values are stored exactly as the frontend spells them
-- ("in-development", "rpg", "pc", "recruiting", ...) so no mapping is needed.
-- The two exceptions are `users.role` and `applications.status`, whose existing
-- CHECK constraints and rows use the backend's own vocabulary; those are mapped
-- in the API layer (tester<->Player, developer<->Studio, accepted<->Selected).

BEGIN;

CREATE EXTENSION IF NOT EXISTS pgcrypto;

/* -------------------------------------------------------------------------- */
/*  users — the frontend's `User`                                              */
/* -------------------------------------------------------------------------- */

ALTER TABLE users ADD COLUMN IF NOT EXISTS name       varchar(255);
ALTER TABLE users ADD COLUMN IF NOT EXISTS handle     varchar(64);
ALTER TABLE users ADD COLUMN IF NOT EXISTS location   varchar(255) NOT NULL DEFAULT '';
ALTER TABLE users ADD COLUMN IF NOT EXISTS bio        text         NOT NULL DEFAULT '';
ALTER TABLE users ADD COLUMN IF NOT EXISTS avatar_url text;

-- Derive a display name + handle for the rows that predate these columns.
UPDATE users
   SET name = initcap(replace(split_part(email, '@', 1), '.', ' '))
 WHERE name IS NULL;

UPDATE users u
   SET handle = base.handle || CASE WHEN base.rn = 1 THEN '' ELSE base.rn::text END
  FROM (
    SELECT id,
           left(regexp_replace(lower(split_part(email, '@', 1)), '[^a-z0-9]', '', 'g'), 16) AS handle,
           row_number() OVER (
             PARTITION BY left(regexp_replace(lower(split_part(email, '@', 1)), '[^a-z0-9]', '', 'g'), 16)
             ORDER BY id
           ) AS rn
      FROM users
     WHERE handle IS NULL
  ) base
 WHERE u.id = base.id;

CREATE UNIQUE INDEX IF NOT EXISTS users_handle_key ON users (handle);

/* -------------------------------------------------------------------------- */
/*  passwords — plaintext -> bcrypt                                            */
/* -------------------------------------------------------------------------- */
-- `register_user` stored the password verbatim and `verify_user_login`
-- compared it verbatim. Hash every existing credential in place. A bcrypt
-- digest always starts with `$2`, so re-running this is a no-op.

UPDATE users
   SET password = crypt(password, gen_salt('bf', 10))
 WHERE password IS NOT NULL
   AND password NOT LIKE '$2%';

/* -------------------------------------------------------------------------- */
/*  players — the frontend's `TesterProfile`                                   */
/* -------------------------------------------------------------------------- */

ALTER TABLE players ADD COLUMN IF NOT EXISTS languages                  text[] NOT NULL DEFAULT ARRAY['English'];
ALTER TABLE players ADD COLUMN IF NOT EXISTS weekly_availability_hours  integer NOT NULL DEFAULT 5;
ALTER TABLE players ADD COLUMN IF NOT EXISTS reputation                 integer NOT NULL DEFAULT 50;
ALTER TABLE players ADD COLUMN IF NOT EXISTS badges                     text[] NOT NULL DEFAULT ARRAY['New tester'];

-- `experience` held free text; the frontend's ExperienceLevel union is
-- casual | regular | hardcore | professional.
UPDATE players
   SET experience = CASE lower(coalesce(experience, ''))
                      WHEN 'beginner'     THEN 'casual'
                      WHEN 'intermediate' THEN 'regular'
                      WHEN 'advanced'     THEN 'hardcore'
                      WHEN 'expert'       THEN 'professional'
                      WHEN 'pro'          THEN 'professional'
                      ELSE lower(coalesce(experience, 'casual'))
                    END
 WHERE experience IS NULL
    OR lower(experience) NOT IN ('casual', 'regular', 'hardcore', 'professional');

ALTER TABLE players DROP CONSTRAINT IF EXISTS players_experience_check;
ALTER TABLE players ADD  CONSTRAINT players_experience_check
  CHECK (experience IN ('casual', 'regular', 'hardcore', 'professional'));

CREATE UNIQUE INDEX IF NOT EXISTS players_user_id_key ON players (user_id);

/* -------------------------------------------------------------------------- */
/*  studios — the frontend's `DeveloperProfile`                                */
/* -------------------------------------------------------------------------- */

ALTER TABLE studios ADD COLUMN IF NOT EXISTS studio_size  varchar(16) NOT NULL DEFAULT 'solo';
ALTER TABLE studios ADD COLUMN IF NOT EXISTS founded_year integer     NOT NULL DEFAULT extract(year FROM now())::int;

ALTER TABLE studios DROP CONSTRAINT IF EXISTS studios_studio_size_check;
ALTER TABLE studios ADD  CONSTRAINT studios_studio_size_check
  CHECK (studio_size IN ('solo', 'small', 'mid', 'large'));

CREATE UNIQUE INDEX IF NOT EXISTS studios_user_id_key ON studios (user_id);

/* -------------------------------------------------------------------------- */
/*  games — new; the frontend's `Game`                                         */
/* -------------------------------------------------------------------------- */
-- The old model inlined `game_name` on the playtest, so one studio testing two
-- builds of the same game had no way to say so. The frontend treats a Game as a
-- first-class entity a developer owns and attaches playtests to.

CREATE TABLE IF NOT EXISTS games (
  id                serial PRIMARY KEY,
  developer_user_id integer      NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  title             varchar(255) NOT NULL,
  tagline           text         NOT NULL DEFAULT '',
  description       text         NOT NULL DEFAULT '',
  genres            text[]       NOT NULL DEFAULT '{}',
  platforms         text[]       NOT NULL DEFAULT '{}',
  status            varchar(32)  NOT NULL DEFAULT 'in-development',
  cover_image_url   text,
  accent_hue        integer      NOT NULL DEFAULT 210,
  build_version     varchar(64)  NOT NULL DEFAULT '0.1.0',
  created_at        timestamptz  NOT NULL DEFAULT now(),
  updated_at        timestamptz  NOT NULL DEFAULT now(),
  CONSTRAINT games_status_check
    CHECK (status IN ('in-development', 'alpha', 'beta', 'released')),
  CONSTRAINT games_accent_hue_check
    CHECK (accent_hue BETWEEN 0 AND 360)
);

CREATE INDEX IF NOT EXISTS games_developer_user_id_idx ON games (developer_user_id);

/* -------------------------------------------------------------------------- */
/*  playtests — the frontend's `Playtest`                                      */
/* -------------------------------------------------------------------------- */

ALTER TABLE playtests ADD COLUMN IF NOT EXISTS game_id     integer REFERENCES games(id) ON DELETE CASCADE;
ALTER TABLE playtests ADD COLUMN IF NOT EXISTS title       varchar(255);
ALTER TABLE playtests ADD COLUMN IF NOT EXISTS summary     text        NOT NULL DEFAULT '';
ALTER TABLE playtests ADD COLUMN IF NOT EXISTS goals       text[]      NOT NULL DEFAULT '{}';
ALTER TABLE playtests ADD COLUMN IF NOT EXISTS focus_areas text[]      NOT NULL DEFAULT '{}';
ALTER TABLE playtests ADD COLUMN IF NOT EXISTS status      varchar(32) NOT NULL DEFAULT 'recruiting';
ALTER TABLE playtests ADD COLUMN IF NOT EXISTS reward      text        NOT NULL DEFAULT '';
ALTER TABLE playtests ADD COLUMN IF NOT EXISTS cash_reward integer;
ALTER TABLE playtests ADD COLUMN IF NOT EXISTS max_testers integer     NOT NULL DEFAULT 10;
ALTER TABLE playtests ADD COLUMN IF NOT EXISTS build_url   text        NOT NULL DEFAULT '';
ALTER TABLE playtests ADD COLUMN IF NOT EXISTS opens_at    timestamptz NOT NULL DEFAULT now();
ALTER TABLE playtests ADD COLUMN IF NOT EXISTS closes_at   timestamptz;

-- `requirements` already existed as free text. The frontend needs the
-- structured `TesterRequirements` object, so the structured form lands in a new
-- jsonb column and the legacy text column is left untouched for `/api/*`.
ALTER TABLE playtests ADD COLUMN IF NOT EXISTS requirements_json jsonb NOT NULL DEFAULT '{}'::jsonb;

ALTER TABLE playtests DROP CONSTRAINT IF EXISTS playtests_status_check;
ALTER TABLE playtests ADD  CONSTRAINT playtests_status_check
  CHECK (status IN ('draft', 'recruiting', 'in-progress', 'review', 'completed', 'closed', 'archived'));

CREATE INDEX IF NOT EXISTS playtests_game_id_idx ON playtests (game_id);
CREATE INDEX IF NOT EXISTS playtests_status_idx  ON playtests (status);

/* -------------------------------------------------------------------------- */
/*  playtest_tasks — new; the frontend's `PlaytestTask`                        */
/* -------------------------------------------------------------------------- */

CREATE TABLE IF NOT EXISTS playtest_tasks (
  id                serial PRIMARY KEY,
  playtest_id       integer      NOT NULL REFERENCES playtests(id) ON DELETE CASCADE,
  title             varchar(255) NOT NULL,
  description       text         NOT NULL DEFAULT '',
  type              varchar(32)  NOT NULL DEFAULT 'objective',
  required          boolean      NOT NULL DEFAULT true,
  estimated_minutes integer      NOT NULL DEFAULT 15,
  position          integer      NOT NULL DEFAULT 0,
  CONSTRAINT playtest_tasks_type_check
    CHECK (type IN ('objective', 'survey', 'bug-report', 'free-play'))
);

CREATE INDEX IF NOT EXISTS playtest_tasks_playtest_id_idx ON playtest_tasks (playtest_id, position);

/* -------------------------------------------------------------------------- */
/*  applications — the frontend's `Application`                                */
/* -------------------------------------------------------------------------- */

ALTER TABLE applications ADD COLUMN IF NOT EXISTS message         text NOT NULL DEFAULT '';
ALTER TABLE applications ADD COLUMN IF NOT EXISTS device          text NOT NULL DEFAULT '';
ALTER TABLE applications ADD COLUMN IF NOT EXISTS experience_note text NOT NULL DEFAULT '';
ALTER TABLE applications ADD COLUMN IF NOT EXISTS decided_at      timestamptz;
ALTER TABLE applications ADD COLUMN IF NOT EXISTS decision_note   text;

-- The frontend can withdraw an application; the old CHECK had no such value.
ALTER TABLE applications DROP CONSTRAINT IF EXISTS applications_status_check;
ALTER TABLE applications ADD  CONSTRAINT applications_status_check
  CHECK (status IN ('Pending', 'Selected', 'Rejected', 'Completed', 'Withdrawn'));

/* -------------------------------------------------------------------------- */
/*  feedback — the frontend's `Feedback`                                       */
/* -------------------------------------------------------------------------- */
-- The old model captured one 1-5 rating and a comment. The frontend's feedback
-- form produces five rating axes plus structured highlights / pain points /
-- bugs / per-task answers. Legacy `rating` and `comment` are kept and
-- backfilled on write so `/api/feedback` keeps returning what it always did.

ALTER TABLE feedback ADD COLUMN IF NOT EXISTS rating_fun         integer;
ALTER TABLE feedback ADD COLUMN IF NOT EXISTS rating_difficulty  integer;
ALTER TABLE feedback ADD COLUMN IF NOT EXISTS rating_clarity     integer;
ALTER TABLE feedback ADD COLUMN IF NOT EXISTS rating_performance integer;
ALTER TABLE feedback ADD COLUMN IF NOT EXISTS rating_polish      integer;
ALTER TABLE feedback ADD COLUMN IF NOT EXISTS sentiment          varchar(16) NOT NULL DEFAULT 'neutral';
ALTER TABLE feedback ADD COLUMN IF NOT EXISTS summary            text        NOT NULL DEFAULT '';
ALTER TABLE feedback ADD COLUMN IF NOT EXISTS highlights         text[]      NOT NULL DEFAULT '{}';
ALTER TABLE feedback ADD COLUMN IF NOT EXISTS pain_points        text[]      NOT NULL DEFAULT '{}';
ALTER TABLE feedback ADD COLUMN IF NOT EXISTS bugs               text[]      NOT NULL DEFAULT '{}';
ALTER TABLE feedback ADD COLUMN IF NOT EXISTS answers            jsonb       NOT NULL DEFAULT '[]'::jsonb;
ALTER TABLE feedback ADD COLUMN IF NOT EXISTS would_recommend    boolean     NOT NULL DEFAULT true;
ALTER TABLE feedback ADD COLUMN IF NOT EXISTS hours_played       numeric(6,2) NOT NULL DEFAULT 0;

ALTER TABLE feedback DROP CONSTRAINT IF EXISTS feedback_sentiment_check;
ALTER TABLE feedback ADD  CONSTRAINT feedback_sentiment_check
  CHECK (sentiment IN ('positive', 'neutral', 'negative'));

-- Seed the new axes from the single legacy rating so existing feedback still
-- renders in the developer analytics charts.
UPDATE feedback
   SET rating_fun         = coalesce(rating_fun, rating, 3),
       rating_difficulty  = coalesce(rating_difficulty, rating, 3),
       rating_clarity     = coalesce(rating_clarity, rating, 3),
       rating_performance = coalesce(rating_performance, rating, 3),
       rating_polish      = coalesce(rating_polish, rating, 3),
       summary            = CASE WHEN summary = '' THEN coalesce(comment, '') ELSE summary END
 WHERE rating_fun IS NULL;

ALTER TABLE feedback ALTER COLUMN rating_fun         SET DEFAULT 3;
ALTER TABLE feedback ALTER COLUMN rating_difficulty  SET DEFAULT 3;
ALTER TABLE feedback ALTER COLUMN rating_clarity     SET DEFAULT 3;
ALTER TABLE feedback ALTER COLUMN rating_performance SET DEFAULT 3;
ALTER TABLE feedback ALTER COLUMN rating_polish      SET DEFAULT 3;

CREATE UNIQUE INDEX IF NOT EXISTS feedback_playtest_player_key ON feedback (playtest_id, player_id);

/* -------------------------------------------------------------------------- */
/*  test_progress — new; the frontend's `TestProgress`                         */
/* -------------------------------------------------------------------------- */
-- Drives the tester workspace (download build -> tick tasks -> submit
-- feedback). The old backend had nowhere to record any of it.

CREATE TABLE IF NOT EXISTS test_progress (
  id                 serial PRIMARY KEY,
  playtest_id        integer     NOT NULL REFERENCES playtests(id) ON DELETE CASCADE,
  tester_user_id     integer     NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  stage              varchar(32) NOT NULL DEFAULT 'not-started',
  completed_task_ids integer[]   NOT NULL DEFAULT '{}',
  build_downloaded   boolean     NOT NULL DEFAULT false,
  started_at         timestamptz,
  completed_at       timestamptz,
  feedback_id        integer     REFERENCES feedback(id) ON DELETE SET NULL,
  CONSTRAINT test_progress_stage_check
    CHECK (stage IN ('not-started', 'in-progress', 'tasks-complete', 'feedback-submitted', 'completed')),
  CONSTRAINT test_progress_unique UNIQUE (playtest_id, tester_user_id)
);

/* -------------------------------------------------------------------------- */
/*  notifications — new; the frontend's `Notification`                         */
/* -------------------------------------------------------------------------- */

CREATE TABLE IF NOT EXISTS notifications (
  id         serial PRIMARY KEY,
  user_id    integer     NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  type       varchar(48) NOT NULL,
  title      text        NOT NULL,
  body       text        NOT NULL DEFAULT '',
  href       text,
  read       boolean     NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT notifications_type_check
    CHECK (type IN ('application-accepted', 'application-rejected', 'application-received',
                    'feedback-received', 'playtest-published', 'test-reminder', 'system'))
);

CREATE INDEX IF NOT EXISTS notifications_user_id_idx ON notifications (user_id, created_at DESC);

/* -------------------------------------------------------------------------- */
/*  Backfill legacy playtests                                                  */
/* -------------------------------------------------------------------------- */
-- `joinPlaytest` in the frontend drops any playtest whose game or developer is
-- missing, so every pre-existing playtest needs a games row before it will be
-- visible in Discover. Genre/platform were free text ("Action / Flight
-- Combat", "PC / Mac") and are normalised onto the frontend's unions here.

-- Free-text genre/platform strings are matched against synonyms, not just
-- against the union members themselves: "Android, iOS" is `mobile`, not `pc`,
-- and "Cozy Farming" is `simulation`, not `action`.
CREATE TEMP TABLE genre_synonyms (needle text, genre text) ON COMMIT DROP;
INSERT INTO genre_synonyms VALUES
  ('action','action'), ('fight','action'), ('combat','action'), ('beat em up','action'),
  ('adventure','adventure'), ('metroidvania','adventure'), ('point and click','adventure'),
  ('rpg','rpg'), ('role-playing','rpg'), ('role playing','rpg'), ('jrpg','rpg'), ('crpg','rpg'),
  ('strategy','strategy'), ('tactic','strategy'), ('4x','strategy'), ('rts','strategy'), ('tower defense','strategy'), ('deck-building','strategy'),
  ('puzzle','puzzle'), ('match-3','puzzle'), ('sokoban','puzzle'),
  ('simulation','simulation'), ('sim','simulation'), ('farming','simulation'), ('tycoon','simulation'), ('management','simulation'), ('builder','simulation'), ('sandbox','simulation'), ('cozy','simulation'),
  ('roguelike','roguelike'), ('roguelite','roguelike'), ('rogue-like','roguelike'),
  ('platformer','platformer'), ('platform','platformer'), ('runner','platformer'),
  ('shooter','shooter'), ('fps','shooter'), ('shmup','shooter'), ('shooting','shooter'), ('battle royale','shooter'),
  ('horror','horror'), ('survival horror','horror'), ('thriller','horror');

CREATE TEMP TABLE platform_synonyms (needle text, platform text) ON COMMIT DROP;
INSERT INTO platform_synonyms VALUES
  ('pc','pc'), ('windows','pc'), ('win','pc'), ('steam','pc'), ('desktop','pc'),
  ('mac','mac'), ('macos','mac'), ('osx','mac'), ('os x','mac'),
  ('linux','linux'), ('ubuntu','linux'), ('steam deck','linux'), ('steamdeck','linux'), ('proton','linux'),
  ('web','web'), ('browser','web'), ('html5','web'), ('webgl','web'),
  ('mobile','mobile'), ('android','mobile'), ('ios','mobile'), ('iphone','mobile'), ('ipad','mobile'), ('phone','mobile'), ('tablet','mobile'),
  ('console','console'), ('playstation','console'), ('ps4','console'), ('ps5','console'),
  ('xbox','console'), ('switch','console'), ('nintendo','console');

INSERT INTO games (developer_user_id, title, tagline, description, genres, platforms, status, accent_hue, build_version, created_at, updated_at)
SELECT s.user_id,
       p.game_name,
       '',
       coalesce(p.requirements, ''),
       -- An unmatchable string falls back to a sane single value so the game is
       -- still filterable in Discover rather than invisible.
       coalesce(NULLIF((SELECT array_agg(DISTINCT gs.genre)
                          FROM genre_synonyms gs
                         WHERE lower(coalesce(p.genre, '')) LIKE '%' || gs.needle || '%'), '{}'),
                ARRAY['action']),
       coalesce(NULLIF((SELECT array_agg(DISTINCT ps.platform)
                          FROM platform_synonyms ps
                         WHERE lower(coalesce(p.platform, '')) LIKE '%' || ps.needle || '%'), '{}'),
                ARRAY['pc']),
       'beta',
       (p.id * 47) % 360,
       '0.1.0',
       p.created_at,
       p.created_at
  FROM playtests p
  JOIN studios s ON s.id = p.studio_id
 WHERE p.game_id IS NULL
   AND NOT EXISTS (
     SELECT 1 FROM games g2
      WHERE g2.developer_user_id = s.user_id AND g2.title = p.game_name
   );

UPDATE playtests p
   SET game_id = g.id
  FROM games g
  JOIN studios s ON s.user_id = g.developer_user_id
 WHERE p.game_id IS NULL
   AND p.studio_id = s.id
   AND g.title = p.game_name;

UPDATE playtests
   SET title             = coalesce(title, game_name || ' playtest'),
       summary           = CASE WHEN summary = '' THEN coalesce(requirements, '') ELSE summary END,
       max_testers       = CASE WHEN max_testers = 10 THEN coalesce(target_players, 10) ELSE max_testers END,
       closes_at         = coalesce(closes_at, created_at + interval '60 days'),
       opens_at          = coalesce(opens_at, created_at),
       reward            = CASE WHEN reward = '' THEN 'Build access + credit' ELSE reward END,
       requirements_json = CASE
         WHEN requirements_json = '{}'::jsonb THEN jsonb_build_object(
           'minExperienceLevel', 'casual',
           'platforms',          (SELECT to_jsonb(g.platforms) FROM games g WHERE g.id = playtests.game_id),
           'preferredGenres',    (SELECT to_jsonb(g.genres)    FROM games g WHERE g.id = playtests.game_id),
           'languages',          to_jsonb(ARRAY['English']),
           'minReputation',      0,
           'estimatedHours',     4,
           'ndaRequired',        false
         )
         ELSE requirements_json
       END
 WHERE game_id IS NOT NULL;

-- Legacy playtests carry no structured tasks; give each one a single free-play
-- task so the tester workspace has something to render.
INSERT INTO playtest_tasks (playtest_id, title, description, type, required, estimated_minutes, position)
SELECT p.id,
       'Play through the build',
       'Spend time with the build and note anything that stands out.',
       'free-play',
       true,
       60,
       0
  FROM playtests p
 WHERE NOT EXISTS (SELECT 1 FROM playtest_tasks t WHERE t.playtest_id = p.id);

/* -------------------------------------------------------------------------- */
/*  Sequence sync                                                              */
/* -------------------------------------------------------------------------- */
-- Some rows were loaded with explicit ids, which leaves the identity sequences
-- behind the data: `studios_id_seq` sat at 3 against a max id of 5 in
-- production, so the next insert collided on the primary key. Every sequence is
-- pushed past its table's high-water mark here.

DO $$
DECLARE
  r record;
  v_max bigint;
BEGIN
  FOR r IN
    SELECT c.relname AS table_name,
           a.attname AS column_name,
           pg_get_serial_sequence(c.relname, a.attname) AS seq
      FROM pg_class c
      JOIN pg_namespace n ON n.oid = c.relnamespace
      JOIN pg_attribute a ON a.attrelid = c.oid
     WHERE n.nspname = 'public'
       AND c.relkind = 'r'
       AND a.attnum > 0
       AND NOT a.attisdropped
       AND pg_get_serial_sequence(c.relname, a.attname) IS NOT NULL
  LOOP
    EXECUTE format('SELECT coalesce(max(%I), 0) FROM public.%I', r.column_name, r.table_name)
       INTO v_max;
    -- `is_called = true` so the next value is v_max + 1, and never below 1.
    PERFORM setval(r.seq, greatest(v_max, 1), true);
  END LOOP;
END $$;

COMMIT;
