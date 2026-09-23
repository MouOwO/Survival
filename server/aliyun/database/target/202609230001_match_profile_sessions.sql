-- Account saves remain authoritative. A match owns an immutable, durable baseline
-- used only to project bonuses; it never replaces any permanent table contents.
BEGIN;
CREATE TABLE IF NOT EXISTS public.match_profile_sessions (
 account_id text NOT NULL REFERENCES public.survival_players(account_id),
 match_session_id text NOT NULL CHECK (match_session_id ~ '^[A-Za-z0-9_.:-]{8,128}$'),
 mode text NOT NULL CHECK (mode IN ('pure','standard')),
 baseline jsonb NOT NULL CHECK (jsonb_typeof(baseline)='object'),
 defaults jsonb NOT NULL CHECK (jsonb_typeof(defaults)='object'),
 created_at timestamptz NOT NULL DEFAULT now(),
 PRIMARY KEY (account_id,match_session_id)
);
ALTER TABLE public.match_profile_sessions ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.match_profile_sessions FROM PUBLIC,anon,authenticated,service_role,goufayu_app;

CREATE OR REPLACE FUNCTION public.match_profile_context(p_account text,p_session text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path=pg_catalog,public,extensions,pg_temp AS $$
DECLARE s public.match_profile_sessions%rowtype;
BEGIN
 IF p_account IS NULL OR p_account !~ '^[0-9a-f]{64}$' OR p_session IS NULL
   OR p_session !~ '^[A-Za-z0-9_.:-]{8,128}$' THEN RAISE EXCEPTION 'match_session_invalid'; END IF;
 SELECT * INTO s FROM public.match_profile_sessions
  WHERE account_id=p_account AND match_session_id=p_session;
 IF NOT FOUND THEN RETURN jsonb_build_object('ok',false,'error','match_session_missing'); END IF;
 RETURN jsonb_build_object('ok',true,'account_id',s.account_id,
  'match_session_id',s.match_session_id,'mode',s.mode,'baseline',s.baseline,'defaults',s.defaults,
  'created_at',extract(epoch from s.created_at));
END; $$;

CREATE OR REPLACE FUNCTION public.match_profile_login(p_account text,p_session text,p_mode text,p_defaults jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path=pg_catalog,public,extensions,pg_temp AS $$
DECLARE s public.match_profile_sessions%rowtype; current_profile jsonb;
BEGIN
 IF p_account IS NULL OR p_account !~ '^[0-9a-f]{64}$' OR p_session IS NULL
   OR p_session !~ '^[A-Za-z0-9_.:-]{8,128}$' OR p_mode IS NULL OR p_mode NOT IN ('pure','standard')
   OR p_defaults IS NULL OR jsonb_typeof(p_defaults)<>'object' THEN RAISE EXCEPTION 'match_login_invalid'; END IF;
 -- Same lock order as archive commits and online checkpoint. Login must never
 -- capture half of a grant, nor reset a baseline after retries/restarts.
 PERFORM 1 FROM public.player_gameplay_stats WHERE player_id=p_account FOR UPDATE;
 PERFORM 1 FROM public.survival_players WHERE account_id=p_account FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'match_account_missing'; END IF;
 SELECT * INTO s FROM public.match_profile_sessions
  WHERE account_id=p_account AND match_session_id=p_session;
 IF FOUND AND s.mode<>p_mode THEN
  RETURN jsonb_build_object('ok',false,'error','match_mode_locked');
 END IF;
 current_profile:=public.fishing_profile_json(p_account);
 INSERT INTO public.match_profile_sessions(account_id,match_session_id,mode,baseline,defaults)
 VALUES(p_account,p_session,p_mode,current_profile,p_defaults) ON CONFLICT DO NOTHING;
 RETURN public.match_profile_context(p_account,p_session)||jsonb_build_object('profile',current_profile);
END; $$;
REVOKE ALL ON FUNCTION public.match_profile_context(text,text),
 public.match_profile_login(text,text,text,jsonb) FROM PUBLIC,anon,authenticated,service_role,goufayu_app;
GRANT EXECUTE ON FUNCTION public.match_profile_context(text,text),
 public.match_profile_login(text,text,text,jsonb) TO goufayu_app;
COMMIT;
