-- Account creation is the authority: existing players remain legacy; only an
-- INSERT after this migration creates a required tutorial. No history guesses,
-- old-account bulk updates, gameplay-stat changes or reward grants are made.
BEGIN;
CREATE TABLE IF NOT EXISTS public.player_onboarding_state (
 account_id text PRIMARY KEY REFERENCES public.survival_players(account_id),
 version integer NOT NULL DEFAULT 1 CHECK(version=1),
 status text NOT NULL DEFAULT 'required' CHECK(status IN ('required','completed','skipped')),
 created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 finished_at timestamptz
);
ALTER TABLE public.player_onboarding_state ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.player_onboarding_state FROM PUBLIC,anon,authenticated,service_role,goufayu_app;

CREATE OR REPLACE FUNCTION public.initialize_player_onboarding()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER
SET search_path=pg_catalog,public,extensions,pg_temp AS $$
BEGIN
 INSERT INTO public.player_onboarding_state(account_id) VALUES(NEW.account_id)
 ON CONFLICT(account_id) DO NOTHING;
 RETURN NEW;
END; $$;
REVOKE ALL ON FUNCTION public.initialize_player_onboarding() FROM PUBLIC,anon,authenticated,service_role,goufayu_app;
DROP TRIGGER IF EXISTS initialize_player_onboarding ON public.survival_players;
CREATE TRIGGER initialize_player_onboarding AFTER INSERT ON public.survival_players
 FOR EACH ROW EXECUTE FUNCTION public.initialize_player_onboarding();

CREATE OR REPLACE FUNCTION public.onboarding_state(p_account text,p_session text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path=pg_catalog,public,extensions,pg_temp AS $$
DECLARE saved public.player_onboarding_state%ROWTYPE;
BEGIN
 IF p_account IS NULL OR p_account !~ '^[0-9a-f]{64}$' OR p_session IS NULL
  OR p_session !~ '^[A-Za-z0-9_.:-]{8,128}$' THEN RAISE EXCEPTION 'onboarding_identity_invalid'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.match_profile_sessions WHERE account_id=p_account AND match_session_id=p_session) THEN
  RETURN jsonb_build_object('ok',false,'error','match_session_missing');
 END IF;
 SELECT * INTO saved FROM public.player_onboarding_state WHERE account_id=p_account;
 IF NOT FOUND THEN
  RETURN jsonb_build_object('ok',true,'version',1,'required',false,'status','legacy');
 END IF;
 RETURN jsonb_build_object('ok',true,'version',saved.version,'required',saved.status='required','status',saved.status);
END; $$;

CREATE OR REPLACE FUNCTION public.onboarding_finish(p_account text,p_session text,p_outcome text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path=pg_catalog,public,extensions,pg_temp AS $$
DECLARE saved public.player_onboarding_state%ROWTYPE;
BEGIN
 IF p_account IS NULL OR p_account !~ '^[0-9a-f]{64}$' OR p_session IS NULL
  OR p_session !~ '^[A-Za-z0-9_.:-]{8,128}$' OR p_outcome IS NULL
  OR p_outcome NOT IN ('completed','skipped') THEN RAISE EXCEPTION 'onboarding_finish_invalid'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.match_profile_sessions WHERE account_id=p_account AND match_session_id=p_session) THEN
  RETURN jsonb_build_object('ok',false,'error','match_session_missing');
 END IF;
 SELECT * INTO saved FROM public.player_onboarding_state WHERE account_id=p_account FOR UPDATE;
 IF NOT FOUND THEN RETURN jsonb_build_object('ok',false,'error','onboarding_not_required'); END IF;
 -- First terminal result wins. Retries and concurrent matches cannot reset it.
 IF saved.status='required' THEN
  UPDATE public.player_onboarding_state SET status=p_outcome,finished_at=clock_timestamp()
   WHERE account_id=p_account RETURNING * INTO saved;
 END IF;
 RETURN jsonb_build_object('ok',true,'version',saved.version,'required',false,'status',saved.status);
END; $$;
REVOKE ALL ON FUNCTION public.onboarding_state(text,text),public.onboarding_finish(text,text,text)
 FROM PUBLIC,anon,authenticated,service_role,goufayu_app;
GRANT EXECUTE ON FUNCTION public.onboarding_state(text,text),public.onboarding_finish(text,text,text) TO goufayu_app;
COMMIT;
