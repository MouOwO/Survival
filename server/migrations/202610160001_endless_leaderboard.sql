-- Public Steam identity is separated from private HMAC account keys. No
-- historical archive, reward, order, currency or profile revision is changed.
BEGIN;
SELECT pg_advisory_xact_lock(hashtextextended('survival:endless-leaderboard:v1',0));
-- Close the seed/trigger installation gap while concurrent waves are saved.
LOCK TABLE public.player_archive_state IN SHARE ROW EXCLUSIVE MODE;

CREATE TABLE IF NOT EXISTS public.archive_leaderboard_identities (
 account_id text PRIMARY KEY REFERENCES public.survival_players(account_id),
 entry_id uuid NOT NULL UNIQUE DEFAULT gen_random_uuid(),
 public_account_id text UNIQUE
  CHECK(public_account_id ~ '^[1-9][0-9]{0,9}$'
    AND public_account_id::bigint BETWEEN 1 AND 4294967295),
 created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.archive_leaderboard_identities ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.archive_leaderboard_identities
 FROM PUBLIC,anon,authenticated,service_role,goufayu_app;

-- Seed public row keys for every historical save, including identities whose
-- one-way private HMAC cannot be converted back into a Steam account ID.
INSERT INTO public.archive_leaderboard_identities(account_id)
 SELECT account_id FROM public.player_archive_state ON CONFLICT(account_id) DO NOTHING;

CREATE OR REPLACE FUNCTION public.archive_seed_leaderboard_identity()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER
SET search_path=pg_catalog,public,extensions,pg_temp AS $$
BEGIN
 INSERT INTO public.archive_leaderboard_identities(account_id) VALUES(NEW.account_id)
 ON CONFLICT(account_id) DO NOTHING;
 RETURN NEW;
END; $$;
DROP TRIGGER IF EXISTS archive_seed_leaderboard_identity ON public.player_archive_state;
CREATE TRIGGER archive_seed_leaderboard_identity AFTER INSERT ON public.player_archive_state
 FOR EACH ROW EXECUTE FUNCTION public.archive_seed_leaderboard_identity();

CREATE OR REPLACE FUNCTION public.archive_leaderboard_integer(p_value jsonb)
RETURNS bigint LANGUAGE plpgsql IMMUTABLE PARALLEL SAFE
SET search_path=pg_catalog,public,extensions,pg_temp AS $$
DECLARE n numeric;
BEGIN
 IF jsonb_typeof(p_value) IS DISTINCT FROM 'number' THEN RETURN 0; END IF;
 n:=(p_value #>> '{}')::numeric;
 IF n<0 OR n>9007199254740991 OR n<>trunc(n) THEN RETURN 0; END IF;
 RETURN n::bigint;
END; $$;

-- Indexed authoritative values: no trigger, score mirror, per-frame polling
-- or cache invalidation job is needed when a completed wave is committed.
CREATE INDEX IF NOT EXISTS player_archive_endless_leaderboard_idx
 ON public.player_archive_state
 (public.archive_leaderboard_integer(archive->'endless_best_wave') DESC,
  public.archive_leaderboard_integer(archive->'endless_score') DESC, account_id)
 WHERE public.archive_leaderboard_integer(archive->'endless_best_wave')>0;

CREATE OR REPLACE FUNCTION public.archive_bind_leaderboard_identity(
 p_account text,p_public_account_id text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path=pg_catalog,public,extensions,pg_temp AS $$
DECLARE previous text;
BEGIN
 IF p_account IS NULL OR p_account !~ '^[0-9a-f]{64}$'
  OR p_public_account_id IS NULL OR p_public_account_id !~ '^[1-9][0-9]{0,9}$'
  OR p_public_account_id::bigint NOT BETWEEN 1 AND 4294967295
 THEN RAISE EXCEPTION 'leaderboard_identity_invalid'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.survival_players WHERE account_id=p_account)
 THEN RAISE EXCEPTION 'leaderboard_account_missing'; END IF;
 INSERT INTO public.archive_leaderboard_identities(account_id,public_account_id)
 VALUES(p_account,p_public_account_id) ON CONFLICT(account_id) DO UPDATE
 SET public_account_id=EXCLUDED.public_account_id
 WHERE public.archive_leaderboard_identities.public_account_id IS NULL;
 SELECT public_account_id INTO previous FROM public.archive_leaderboard_identities
 WHERE account_id=p_account;
 IF previous IS DISTINCT FROM p_public_account_id
 THEN RAISE EXCEPTION 'leaderboard_identity_immutable'; END IF;
 RETURN jsonb_build_object('ok',true);
END; $$;

CREATE OR REPLACE FUNCTION public.archive_endless_leaderboard()
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER
SET search_path=pg_catalog,public,extensions,pg_temp AS $$
 SELECT jsonb_build_object('ok',true,'entries',coalesce(jsonb_agg(
  jsonb_build_object('entry_id',ranking.entry_id::text,
   'steam_id',coalesce((76561197960265728::bigint+ranking.public_account_id::bigint)::text,''),
   'best_floor',ranking.best_floor,'endless_score',ranking.endless_score)
  ORDER BY ranking.best_floor DESC,ranking.endless_score DESC,ranking.entry_id),'[]'::jsonb))
 FROM (
  SELECT identity.entry_id,identity.public_account_id,
   public.archive_leaderboard_integer(saved.archive->'endless_best_wave') AS best_floor,
   public.archive_leaderboard_integer(saved.archive->'endless_score') AS endless_score
  FROM public.player_archive_state saved
  LEFT JOIN public.archive_leaderboard_identities identity USING(account_id)
  WHERE public.archive_leaderboard_integer(saved.archive->'endless_best_wave')>0
  ORDER BY best_floor DESC,endless_score DESC,identity.entry_id
  LIMIT 100
 ) ranking;
$$;
REVOKE ALL ON FUNCTION public.archive_leaderboard_integer(jsonb),public.archive_seed_leaderboard_identity(),
 public.archive_bind_leaderboard_identity(text,text),public.archive_endless_leaderboard()
 FROM PUBLIC,anon,authenticated,service_role,goufayu_app;
GRANT EXECUTE ON FUNCTION public.archive_bind_leaderboard_identity(text,text),
 public.archive_endless_leaderboard() TO goufayu_app;
COMMIT;
