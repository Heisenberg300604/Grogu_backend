-- 000_base_schema.sql
--
-- The original Grogu schema: the nine tables and the legacy `/api/*` stored
-- functions that existed before the frontend integration.
--
-- This file was reconstructed from the deployed Neon database, which until now
-- was the only place the base schema existed — migrations 001+ begin with
-- `ALTER TABLE users ...`, so a fresh clone had nothing to alter and could not
-- stand up a working database at all. Committing it makes the repo
-- self-contained: an empty PostgreSQL instance plus `db/migrations/*.sql` in
-- filename order now produces a complete, current database.
--
-- Schema only — it contains no rows, and no user data. Applying it to the
-- existing production database is a no-op, because every statement is
-- conditional.
--
-- NOTE: the two auth functions defined here (`register_user`,
-- `verify_user_login`) are the originals, which handled passwords in
-- plaintext. Migration 002 replaces both with bcrypt-aware versions. Never run
-- this file on its own against a live database and stop there.

BEGIN;

\restrict vOi4yvGknsushq9iRbS0Xqfu07TRx1efI0y7s10EgufddymKeSkfl9D85fDFgZj

--
-- Name: admin_delete_user(integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE OR REPLACE FUNCTION public.admin_delete_user(p_id integer) RETURNS boolean
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_rows INT;
BEGIN
    DELETE FROM users WHERE users.id = p_id;
    GET DIAGNOSTICS v_rows = ROW_COUNT;
    RETURN v_rows > 0;
END;
$$;

--
-- Name: admin_get_playtests(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE OR REPLACE FUNCTION public.admin_get_playtests() RETURNS TABLE(id integer, studio_id integer, game_name character varying, genre character varying, platform character varying, requirements text, target_players integer, created_at timestamp with time zone)
    LANGUAGE plpgsql
    AS $$
BEGIN
    RETURN QUERY SELECT p.id, p.studio_id, p.game_name, p.genre, p.platform, p.requirements, p.target_players, p.created_at FROM playtests p;
END;
$$;

--
-- Name: admin_get_users(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE OR REPLACE FUNCTION public.admin_get_users() RETURNS TABLE(id integer, email character varying, role character varying, created_at timestamp with time zone)
    LANGUAGE plpgsql
    AS $$
BEGIN
    RETURN QUERY SELECT u.id, u.email, u.role, u.created_at FROM users u;
END;
$$;

--
-- Name: admin_logs_get(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE OR REPLACE FUNCTION public.admin_logs_get() RETURNS TABLE(id integer, admin_user_id integer, action character varying, target_entity character varying, target_id integer, created_at timestamp with time zone)
    LANGUAGE plpgsql
    AS $$
BEGIN
    RETURN QUERY SELECT l.id, l.admin_user_id, l.action, l.target_entity, l.target_id, l.created_at FROM admin l ORDER BY l.created_at DESC;
END;
$$;

--
-- Name: admin_stats_get(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE OR REPLACE FUNCTION public.admin_stats_get(OUT total_users bigint, OUT total_players bigint, OUT total_studios bigint, OUT total_playtests bigint, OUT total_applications bigint, OUT total_feedback bigint) RETURNS record
    LANGUAGE plpgsql
    AS $$
BEGIN
    SELECT COUNT(*) INTO total_users FROM users;
    SELECT COUNT(*) INTO total_players FROM players;
    SELECT COUNT(*) INTO total_studios FROM studios;
    SELECT COUNT(*) INTO total_playtests FROM playtests;
    SELECT COUNT(*) INTO total_applications FROM applications;
    SELECT COUNT(*) INTO total_feedback FROM feedback;
END;
$$;

--
-- Name: application_delete(integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE OR REPLACE FUNCTION public.application_delete(p_id integer) RETURNS boolean
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_rows INT;
BEGIN
    DELETE FROM applications WHERE id = p_id;
    GET DIAGNOSTICS v_rows = ROW_COUNT;
    RETURN v_rows > 0;
END;
$$;

--
-- Name: application_get(integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE OR REPLACE FUNCTION public.application_get(p_id integer) RETURNS TABLE(id integer, player_id integer, playtest_id integer, status character varying, created_at timestamp with time zone)
    LANGUAGE plpgsql
    AS $$
BEGIN
    RETURN QUERY 
    SELECT a.id, a.player_id, a.playtest_id, a.status, a.created_at 
    FROM applications a 
    WHERE a.id = p_id;
END;
$$;

--
-- Name: application_status_update(integer, character varying); Type: FUNCTION; Schema: public; Owner: -
--

CREATE OR REPLACE FUNCTION public.application_status_update(p_id integer, p_status character varying) RETURNS boolean
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_rows INT;
BEGIN
    UPDATE applications 
    SET status = COALESCE(p_status, status)
    WHERE id = p_id;
    
    GET DIAGNOSTICS v_rows = ROW_COUNT;
    RETURN v_rows > 0;
END;
$$;

--
-- Name: feedback_delete(integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE OR REPLACE FUNCTION public.feedback_delete(p_id integer) RETURNS boolean
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_rows INT;
BEGIN
    DELETE FROM feedback WHERE id = p_id;
    GET DIAGNOSTICS v_rows = ROW_COUNT;
    RETURN v_rows > 0;
END;
$$;

--
-- Name: feedback_get(integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE OR REPLACE FUNCTION public.feedback_get(p_id integer) RETURNS TABLE(id integer, playtest_id integer, player_id integer, rating integer, comments text, created_at timestamp with time zone)
    LANGUAGE plpgsql
    AS $$
BEGIN
    RETURN QUERY 
    SELECT f.id, f.playtest_id, f.player_id, f.rating, f.comment, f.created_at 
    FROM feedback f 
    WHERE f.id = p_id;
END;
$$;

--
-- Name: feedback_get_by_playtest(integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE OR REPLACE FUNCTION public.feedback_get_by_playtest(p_playtest_id integer) RETURNS TABLE(id integer, playtest_id integer, player_id integer, rating integer, comments text, created_at timestamp with time zone)
    LANGUAGE plpgsql
    AS $$
BEGIN
    RETURN QUERY 
    SELECT f.id, f.playtest_id, f.player_id, f.rating, f.comment, f.created_at 
    FROM feedback f 
    WHERE f.playtest_id = p_playtest_id;
END;
$$;

--
-- Name: feedback_submit(integer, integer, integer, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE OR REPLACE FUNCTION public.feedback_submit(p_playtest_id integer, p_player_id integer, p_rating integer, p_comments text) RETURNS integer
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_feedback_id INTEGER;
BEGIN
    INSERT INTO feedback (playtest_id, player_id, rating, comment)
    VALUES (p_playtest_id, p_player_id, p_rating, p_comments)
    RETURNING id INTO v_feedback_id;
    
    RETURN v_feedback_id;
END;
$$;

--
-- Name: get_all_playtests(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE OR REPLACE FUNCTION public.get_all_playtests() RETURNS TABLE(id integer, studio_id integer, game_name character varying, genre character varying, platform character varying, requirements text, target_players integer, created_at timestamp with time zone)
    LANGUAGE plpgsql
    AS $$
BEGIN
    RETURN QUERY SELECT p.id, p.studio_id, p.game_name, p.genre, p.platform, p.requirements, p.target_players, p.created_at FROM playtests p;
END;
$$;

--
-- Name: player_apply_playtest(integer, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE OR REPLACE FUNCTION public.player_apply_playtest(p_player_id integer, p_playtest_id integer) RETURNS integer
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_app_id INTEGER;
BEGIN
    INSERT INTO applications (player_id, playtest_id, status)
    VALUES (p_player_id, p_playtest_id, 'Pending')
    RETURNING id INTO v_app_id;
    
    RETURN v_app_id;
END;
$$;

--
-- Name: player_delete(integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE OR REPLACE FUNCTION public.player_delete(p_id integer) RETURNS boolean
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_rows INT;
BEGIN
    DELETE FROM players WHERE id = p_id;
    GET DIAGNOSTICS v_rows = ROW_COUNT;
    RETURN v_rows > 0;
END;
$$;

--
-- Name: player_get(integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE OR REPLACE FUNCTION public.player_get(p_id integer) RETURNS TABLE(id integer, user_id integer, age integer, experience character varying, platforms text, genres text, created_at timestamp with time zone)
    LANGUAGE plpgsql
    AS $$
BEGIN
    RETURN QUERY 
    SELECT p.id, p.user_id, p.age, p.experience, p.platforms, p.genres, p.created_at 
    FROM players p 
    WHERE p.id = p_id;
END;
$$;

--
-- Name: player_save(integer, integer, character varying, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE OR REPLACE FUNCTION public.player_save(p_user_id integer, p_age integer, p_experience character varying, p_platforms text, p_genres text) RETURNS integer
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_player_id INTEGER;
    v_user_exists BOOLEAN;
BEGIN
    -- Check if the user ID exists in the users table
    SELECT EXISTS (SELECT 1 FROM users WHERE id = p_user_id) INTO v_user_exists;
    
    IF NOT v_user_exists THEN
        RAISE EXCEPTION 'User does not exist.';
    END IF;

    -- Check if a player profile already exists for this user_id
    SELECT id INTO v_player_id FROM players WHERE user_id = p_user_id;
    
    IF FOUND THEN
        -- Update existing profile
        UPDATE players 
        SET age = p_age,
            experience = p_experience,
            platforms = p_platforms,
            genres = p_genres
        WHERE id = v_player_id;
    ELSE
        -- Insert new profile since user exists
        INSERT INTO players (user_id, age, experience, platforms, genres)
        VALUES (p_user_id, p_age, p_experience, p_platforms, p_genres)
        RETURNING id INTO v_player_id;
    END IF;
    
    RETURN v_player_id;
END;
$$;

--
-- Name: player_update(integer, integer, character varying, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE OR REPLACE FUNCTION public.player_update(p_id integer, p_age integer, p_experience character varying, p_platforms text, p_genres text) RETURNS boolean
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_rows INT;
BEGIN
    UPDATE players 
    SET age = COALESCE(p_age, age),
        experience = COALESCE(p_experience, experience),
        platforms = COALESCE(p_platforms, platforms),
        genres = COALESCE(p_genres, genres)
    WHERE id = p_id;
    
    GET DIAGNOSTICS v_rows = ROW_COUNT;
    RETURN v_rows > 0;
END;
$$;

--
-- Name: playtest_applications(integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE OR REPLACE FUNCTION public.playtest_applications(p_playtest_id integer) RETURNS TABLE(application_id integer, player_id integer, user_id integer, email character varying, age integer, experience character varying, platforms text, genres text, status character varying, applied_at timestamp with time zone)
    LANGUAGE plpgsql
    AS $$
BEGIN
    RETURN QUERY 
    SELECT 
        a.id AS application_id,
        pl.id AS player_id,
        u.id AS user_id,
        u.email,
        pl.age,
        pl.experience,
        pl.platforms,
        pl.genres,
        a.status,
        a.created_at AS applied_at
    FROM applications a
    JOIN players pl ON a.player_id = pl.id
    JOIN users u ON pl.user_id = u.id
    WHERE a.playtest_id = p_playtest_id;
END;
$$;

--
-- Name: playtest_create(integer, character varying, character varying, character varying, text, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE OR REPLACE FUNCTION public.playtest_create(p_studio_id integer, p_game_name character varying, p_genre character varying, p_platform character varying, p_requirements text, p_target_players integer) RETURNS integer
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_playtest_id INTEGER;
BEGIN
    INSERT INTO playtests (studio_id, game_name, genre, platform, requirements, target_players)
    VALUES (p_studio_id, p_game_name, p_genre, p_platform, p_requirements, p_target_players)
    RETURNING id INTO v_playtest_id;
    
    RETURN v_playtest_id;
END;
$$;

--
-- Name: playtest_get(integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE OR REPLACE FUNCTION public.playtest_get(p_id integer) RETURNS TABLE(id integer, studio_id integer, game_name character varying, genre character varying, platform character varying, requirements text, target_players integer, created_at timestamp with time zone)
    LANGUAGE plpgsql
    AS $$
BEGIN
    RETURN QUERY 
    SELECT p.id, p.studio_id, p.game_name, p.genre, p.platform, p.requirements, p.target_players, p.created_at 
    FROM playtests p 
    WHERE p.id = p_id;
END;
$$;

--
-- Name: register_user(character varying, character varying, character varying); Type: FUNCTION; Schema: public; Owner: -
--

CREATE OR REPLACE FUNCTION public.register_user(p_email character varying, p_role character varying, p_password character varying) RETURNS integer
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_new_id INTEGER;
BEGIN
    INSERT INTO users (email, role, password)
    VALUES (p_email, p_role, p_password)
    RETURNING id INTO v_new_id;
    
    RETURN v_new_id;
END;
$$;

--
-- Name: studio_delete(integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE OR REPLACE FUNCTION public.studio_delete(p_id integer) RETURNS boolean
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_rows INT;
BEGIN
    DELETE FROM studios WHERE id = p_id;
    GET DIAGNOSTICS v_rows = ROW_COUNT;
    RETURN v_rows > 0;
END;
$$;

--
-- Name: studio_get(integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE OR REPLACE FUNCTION public.studio_get(p_id integer) RETURNS TABLE(id integer, user_id integer, name character varying, website character varying, created_at timestamp with time zone)
    LANGUAGE plpgsql
    AS $$
BEGIN
    RETURN QUERY 
    SELECT s.id, s.user_id, s.name, s.website, s.created_at 
    FROM studios s 
    WHERE s.id = p_id;
END;
$$;

--
-- Name: studio_get_by_playtest(integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE OR REPLACE FUNCTION public.studio_get_by_playtest(p_studio_id integer) RETURNS TABLE(id integer, studio_id integer, game_name character varying, genre character varying, platform character varying, requirements text, target_players integer, created_at timestamp with time zone)
    LANGUAGE plpgsql
    AS $$
BEGIN
    RETURN QUERY 
    SELECT p.id, p.studio_id, p.game_name, p.genre, p.platform, p.requirements, p.target_players, p.created_at 
    FROM playtests p 
    WHERE p.studio_id = p_studio_id;
END;
$$;

--
-- Name: studio_playtest(integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE OR REPLACE FUNCTION public.studio_playtest(p_studio_id integer) RETURNS TABLE(id integer, studio_id integer, game_name character varying, genre character varying, platform character varying, requirements text, target_players integer, created_at timestamp with time zone)
    LANGUAGE plpgsql
    AS $$
BEGIN
    RETURN QUERY 
    SELECT p.id, p.studio_id, p.game_name, p.genre, p.platform, p.requirements, p.target_players, p.created_at 
    FROM playtests p 
    WHERE p.studio_id = p_studio_id;
END;
$$;

--
-- Name: studio_update(integer, character varying, character varying); Type: FUNCTION; Schema: public; Owner: -
--

CREATE OR REPLACE FUNCTION public.studio_update(p_id integer, p_name character varying, p_website character varying) RETURNS boolean
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_rows INT;
BEGIN
    UPDATE studios 
    SET name = COALESCE(p_name, name),
        website = COALESCE(p_website, website)
    WHERE id = p_id;
    
    GET DIAGNOSTICS v_rows = ROW_COUNT;
    RETURN v_rows > 0;
END;
$$;

--
-- Name: user_delete(integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE OR REPLACE FUNCTION public.user_delete(p_id integer) RETURNS boolean
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_rows INT;
BEGIN
    DELETE FROM users WHERE id = p_id;
    GET DIAGNOSTICS v_rows = ROW_COUNT;
    RETURN v_rows > 0;
END;
$$;

--
-- Name: user_get_by_id(integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE OR REPLACE FUNCTION public.user_get_by_id(p_id integer) RETURNS TABLE(id integer, email character varying, role character varying, created_at timestamp with time zone)
    LANGUAGE plpgsql
    AS $$
BEGIN
    RETURN QUERY 
    SELECT u.id, u.email, u.role, u.created_at 
    FROM users u 
    WHERE u.id = p_id;
END;
$$;

--
-- Name: user_update(integer, character varying, character varying); Type: FUNCTION; Schema: public; Owner: -
--

CREATE OR REPLACE FUNCTION public.user_update(p_id integer, p_email character varying, p_role character varying) RETURNS boolean
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_rows INT;
BEGIN
    UPDATE users 
    SET email = COALESCE(p_email, email),
        role = COALESCE(p_role, role)
    WHERE id = p_id;
    
    GET DIAGNOSTICS v_rows = ROW_COUNT;
    RETURN v_rows > 0;
END;
$$;

--
-- Name: verify_user_login(character varying, character varying); Type: FUNCTION; Schema: public; Owner: -
--

CREATE OR REPLACE FUNCTION public.verify_user_login(p_email character varying, p_password character varying) RETURNS TABLE(id integer, email character varying, role character varying)
    LANGUAGE plpgsql
    AS $$
BEGIN
    RETURN QUERY 
    SELECT u.id, u.email, u.role 
    FROM users u 
    WHERE u.email = p_email AND u.password = p_password;
END;
$$;

--
-- Name: admin; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE IF NOT EXISTS public.admin (
    id integer NOT NULL,
    admin_user_id integer NOT NULL,
    action character varying(255) NOT NULL,
    target_entity character varying(100),
    target_id integer,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP
);

--
-- Name: admin_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE IF NOT EXISTS public.admin_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

--
-- Name: admin_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.admin_id_seq OWNED BY public.admin.id;

--
-- Name: ai_analysis; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE IF NOT EXISTS public.ai_analysis (
    id integer NOT NULL,
    feedback_id integer NOT NULL,
    sentiment character varying(50),
    topics text,
    summary text,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT ai_analysis_sentiment_check CHECK (((sentiment)::text = ANY ((ARRAY['Positive'::character varying, 'Neutral'::character varying, 'Negative'::character varying])::text[])))
);

--
-- Name: ai_analysis_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE IF NOT EXISTS public.ai_analysis_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

--
-- Name: ai_analysis_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.ai_analysis_id_seq OWNED BY public.ai_analysis.id;

--
-- Name: applications; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE IF NOT EXISTS public.applications (
    id integer NOT NULL,
    player_id integer NOT NULL,
    playtest_id integer NOT NULL,
    status character varying(50) DEFAULT 'Pending'::character varying,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT applications_status_check CHECK (((status)::text = ANY ((ARRAY['Pending'::character varying, 'Selected'::character varying, 'Rejected'::character varying, 'Completed'::character varying])::text[])))
);

--
-- Name: applications_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE IF NOT EXISTS public.applications_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

--
-- Name: applications_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.applications_id_seq OWNED BY public.applications.id;

--
-- Name: feedback; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE IF NOT EXISTS public.feedback (
    id integer NOT NULL,
    player_id integer NOT NULL,
    playtest_id integer NOT NULL,
    rating integer,
    comment text,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT feedback_rating_check CHECK (((rating >= 1) AND (rating <= 5)))
);

--
-- Name: feedback_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE IF NOT EXISTS public.feedback_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

--
-- Name: feedback_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.feedback_id_seq OWNED BY public.feedback.id;

--
-- Name: match_score; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE IF NOT EXISTS public.match_score (
    id integer NOT NULL,
    application_id integer NOT NULL,
    score real NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP
);

--
-- Name: match_score_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE IF NOT EXISTS public.match_score_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

--
-- Name: match_score_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.match_score_id_seq OWNED BY public.match_score.id;

--
-- Name: players; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE IF NOT EXISTS public.players (
    id integer NOT NULL,
    user_id integer NOT NULL,
    age integer,
    experience character varying(50),
    platforms text,
    genres text,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP
);

--
-- Name: players_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE IF NOT EXISTS public.players_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

--
-- Name: players_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.players_id_seq OWNED BY public.players.id;

--
-- Name: playtests; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE IF NOT EXISTS public.playtests (
    id integer NOT NULL,
    studio_id integer NOT NULL,
    game_name character varying(255) NOT NULL,
    genre character varying(100) NOT NULL,
    platform character varying(100) NOT NULL,
    requirements text,
    target_players integer,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP
);

--
-- Name: playtests_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE IF NOT EXISTS public.playtests_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

--
-- Name: playtests_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.playtests_id_seq OWNED BY public.playtests.id;

--
-- Name: studios; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE IF NOT EXISTS public.studios (
    id integer NOT NULL,
    user_id integer NOT NULL,
    name character varying(255) NOT NULL,
    website character varying(255),
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP
);

--
-- Name: studios_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE IF NOT EXISTS public.studios_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

--
-- Name: studios_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.studios_id_seq OWNED BY public.studios.id;

--
-- Name: users; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE IF NOT EXISTS public.users (
    id integer NOT NULL,
    email character varying(255) NOT NULL,
    role character varying(50) NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    password character varying(255),
    CONSTRAINT users_role_check CHECK (((role)::text = ANY ((ARRAY['Player'::character varying, 'Studio'::character varying, 'Admin'::character varying])::text[])))
);

--
-- Name: users_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE IF NOT EXISTS public.users_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

--
-- Name: users_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.users_id_seq OWNED BY public.users.id;

--
-- Name: admin id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.admin ALTER COLUMN id SET DEFAULT nextval('public.admin_id_seq'::regclass);

--
-- Name: ai_analysis id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ai_analysis ALTER COLUMN id SET DEFAULT nextval('public.ai_analysis_id_seq'::regclass);

--
-- Name: applications id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.applications ALTER COLUMN id SET DEFAULT nextval('public.applications_id_seq'::regclass);

--
-- Name: feedback id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.feedback ALTER COLUMN id SET DEFAULT nextval('public.feedback_id_seq'::regclass);

--
-- Name: match_score id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.match_score ALTER COLUMN id SET DEFAULT nextval('public.match_score_id_seq'::regclass);

--
-- Name: players id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.players ALTER COLUMN id SET DEFAULT nextval('public.players_id_seq'::regclass);

--
-- Name: playtests id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.playtests ALTER COLUMN id SET DEFAULT nextval('public.playtests_id_seq'::regclass);

--
-- Name: studios id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.studios ALTER COLUMN id SET DEFAULT nextval('public.studios_id_seq'::regclass);

--
-- Name: users id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users ALTER COLUMN id SET DEFAULT nextval('public.users_id_seq'::regclass);

--
-- Name: admin admin_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

DO $guard$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'admin_pkey') THEN
    ALTER TABLE ONLY public.admin
        ADD CONSTRAINT admin_pkey PRIMARY KEY (id);
  END IF;
END $guard$;

--
-- Name: ai_analysis ai_analysis_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

DO $guard$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'ai_analysis_pkey') THEN
    ALTER TABLE ONLY public.ai_analysis
        ADD CONSTRAINT ai_analysis_pkey PRIMARY KEY (id);
  END IF;
END $guard$;

--
-- Name: applications applications_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

DO $guard$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'applications_pkey') THEN
    ALTER TABLE ONLY public.applications
        ADD CONSTRAINT applications_pkey PRIMARY KEY (id);
  END IF;
END $guard$;

--
-- Name: applications applications_player_id_playtest_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

DO $guard$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'applications_player_id_playtest_id_key') THEN
    ALTER TABLE ONLY public.applications
        ADD CONSTRAINT applications_player_id_playtest_id_key UNIQUE (player_id, playtest_id);
  END IF;
END $guard$;

--
-- Name: feedback feedback_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

DO $guard$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'feedback_pkey') THEN
    ALTER TABLE ONLY public.feedback
        ADD CONSTRAINT feedback_pkey PRIMARY KEY (id);
  END IF;
END $guard$;

--
-- Name: match_score match_score_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

DO $guard$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'match_score_pkey') THEN
    ALTER TABLE ONLY public.match_score
        ADD CONSTRAINT match_score_pkey PRIMARY KEY (id);
  END IF;
END $guard$;

--
-- Name: players players_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

DO $guard$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'players_pkey') THEN
    ALTER TABLE ONLY public.players
        ADD CONSTRAINT players_pkey PRIMARY KEY (id);
  END IF;
END $guard$;

--
-- Name: playtests playtests_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

DO $guard$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'playtests_pkey') THEN
    ALTER TABLE ONLY public.playtests
        ADD CONSTRAINT playtests_pkey PRIMARY KEY (id);
  END IF;
END $guard$;

--
-- Name: studios studios_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

DO $guard$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'studios_pkey') THEN
    ALTER TABLE ONLY public.studios
        ADD CONSTRAINT studios_pkey PRIMARY KEY (id);
  END IF;
END $guard$;

--
-- Name: users users_email_key; Type: CONSTRAINT; Schema: public; Owner: -
--

DO $guard$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'users_email_key') THEN
    ALTER TABLE ONLY public.users
        ADD CONSTRAINT users_email_key UNIQUE (email);
  END IF;
END $guard$;

--
-- Name: users users_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

DO $guard$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'users_pkey') THEN
    ALTER TABLE ONLY public.users
        ADD CONSTRAINT users_pkey PRIMARY KEY (id);
  END IF;
END $guard$;

--
-- Name: admin admin_admin_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

DO $guard$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'admin_admin_user_id_fkey') THEN
    ALTER TABLE ONLY public.admin
        ADD CONSTRAINT admin_admin_user_id_fkey FOREIGN KEY (admin_user_id) REFERENCES public.users(id) ON DELETE CASCADE;
  END IF;
END $guard$;

--
-- Name: ai_analysis ai_analysis_feedback_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

DO $guard$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'ai_analysis_feedback_id_fkey') THEN
    ALTER TABLE ONLY public.ai_analysis
        ADD CONSTRAINT ai_analysis_feedback_id_fkey FOREIGN KEY (feedback_id) REFERENCES public.feedback(id) ON DELETE CASCADE;
  END IF;
END $guard$;

--
-- Name: applications applications_player_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

DO $guard$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'applications_player_id_fkey') THEN
    ALTER TABLE ONLY public.applications
        ADD CONSTRAINT applications_player_id_fkey FOREIGN KEY (player_id) REFERENCES public.players(id) ON DELETE CASCADE;
  END IF;
END $guard$;

--
-- Name: applications applications_playtest_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

DO $guard$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'applications_playtest_id_fkey') THEN
    ALTER TABLE ONLY public.applications
        ADD CONSTRAINT applications_playtest_id_fkey FOREIGN KEY (playtest_id) REFERENCES public.playtests(id) ON DELETE CASCADE;
  END IF;
END $guard$;

--
-- Name: feedback feedback_player_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

DO $guard$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'feedback_player_id_fkey') THEN
    ALTER TABLE ONLY public.feedback
        ADD CONSTRAINT feedback_player_id_fkey FOREIGN KEY (player_id) REFERENCES public.players(id) ON DELETE CASCADE;
  END IF;
END $guard$;

--
-- Name: feedback feedback_playtest_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

DO $guard$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'feedback_playtest_id_fkey') THEN
    ALTER TABLE ONLY public.feedback
        ADD CONSTRAINT feedback_playtest_id_fkey FOREIGN KEY (playtest_id) REFERENCES public.playtests(id) ON DELETE CASCADE;
  END IF;
END $guard$;

--
-- Name: match_score match_score_application_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

DO $guard$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'match_score_application_id_fkey') THEN
    ALTER TABLE ONLY public.match_score
        ADD CONSTRAINT match_score_application_id_fkey FOREIGN KEY (application_id) REFERENCES public.applications(id) ON DELETE CASCADE;
  END IF;
END $guard$;

--
-- Name: players players_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

DO $guard$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'players_user_id_fkey') THEN
    ALTER TABLE ONLY public.players
        ADD CONSTRAINT players_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;
  END IF;
END $guard$;

--
-- Name: playtests playtests_studio_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

DO $guard$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'playtests_studio_id_fkey') THEN
    ALTER TABLE ONLY public.playtests
        ADD CONSTRAINT playtests_studio_id_fkey FOREIGN KEY (studio_id) REFERENCES public.studios(id) ON DELETE CASCADE;
  END IF;
END $guard$;

--
-- Name: studios studios_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

DO $guard$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'studios_user_id_fkey') THEN
    ALTER TABLE ONLY public.studios
        ADD CONSTRAINT studios_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;
  END IF;
END $guard$;

\unrestrict vOi4yvGknsushq9iRbS0Xqfu07TRx1efI0y7s10EgufddymKeSkfl9D85fDFgZj

COMMIT;
