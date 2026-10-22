-- Apply with the matching archive service release. Keeps all existing session
-- rows and private baselines; it does not migrate/relabel any clear counters.
BEGIN;
ALTER TABLE public.match_profile_sessions DROP CONSTRAINT IF EXISTS match_profile_sessions_mode_check;
ALTER TABLE public.match_profile_sessions ADD CONSTRAINT match_profile_sessions_mode_check
 CHECK (mode IN ('pure','standard','rich','cold','scourge','ruins','celestial'));

CREATE OR REPLACE FUNCTION public.match_profile_login(p_account text,p_session text,p_mode text,p_defaults jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path=pg_catalog,public,extensions,pg_temp AS $$
DECLARE s public.match_profile_sessions%rowtype; current_profile jsonb; archive jsonb;
 required_clear text; source_mode text; wins jsonb; clear_value jsonb;
 admitted boolean := false;
BEGIN
 IF p_account IS NULL OR p_account !~ '^[0-9a-f]{64}$' OR p_session IS NULL
   OR p_session !~ '^[A-Za-z0-9_.:-]{8,128}$' OR p_mode IS NULL
   OR p_mode NOT IN ('pure','standard','rich','cold','scourge','ruins','celestial')
   OR p_defaults IS NULL OR jsonb_typeof(p_defaults)<>'object' THEN RAISE EXCEPTION 'match_login_invalid'; END IF;
 -- The established lock order prevents capturing half of an archive grant.
 PERFORM 1 FROM public.player_gameplay_stats WHERE player_id=p_account FOR UPDATE;
 PERFORM 1 FROM public.survival_players WHERE account_id=p_account FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'match_account_missing'; END IF;
 SELECT * INTO s FROM public.match_profile_sessions WHERE account_id=p_account AND match_session_id=p_session;
 IF FOUND AND s.mode<>p_mode THEN RETURN jsonb_build_object('ok',false,'error','match_mode_locked'); END IF;
 -- Context/settlement still accepts previously authenticated closed sessions;
 -- login never creates a new session for an unreleased gameplay mode.
 IF p_mode NOT IN ('pure','standard','rich','cold') THEN
  RETURN jsonb_build_object('ok',false,'error','mode_not_released');
 END IF;
 current_profile:=public.fishing_profile_json(p_account);
 archive:=current_profile->'save'->'archive';
 required_clear:=CASE p_mode WHEN 'rich' THEN 'n3' WHEN 'cold' THEN 'n5'
   WHEN 'scourge' THEN 'n9' WHEN 'ruins' THEN 'n9' WHEN 'celestial' THEN 'n11' END;
 IF required_clear IS NOT NULL THEN
  -- Match Lua mode_progression.counts and Python's normalized account view.
  -- Explicit standard maps replace mixed legacy history, including when empty.
  -- Pure requires proven session scope; advanced modes use their named maps.
  FOREACH source_mode IN ARRAY ARRAY['pure','standard','rich','cold','scourge','ruins','celestial'] LOOP
   wins:=CASE source_mode
    WHEN 'pure' THEN archive->'mode_clear_counts'->'pure'
    WHEN 'standard' THEN CASE WHEN archive ? 'standard_clear_counts'
      THEN archive->'standard_clear_counts' ELSE archive->'clear_counts' END
    ELSE archive->(source_mode||'_clear_counts') END;
   clear_value:=wins->required_clear;
   IF jsonb_typeof(clear_value)='number' THEN
    IF (clear_value::text)::numeric >= 1 AND trunc((clear_value::text)::numeric)=(clear_value::text)::numeric THEN admitted:=true; END IF;
   END IF;
  END LOOP;
  IF NOT admitted THEN RETURN jsonb_build_object('ok',false,'error',p_mode||'_mode_locked'); END IF;
 END IF;
 INSERT INTO public.match_profile_sessions(account_id,match_session_id,mode,baseline,defaults)
 VALUES(p_account,p_session,p_mode,current_profile,p_defaults) ON CONFLICT DO NOTHING;
 RETURN public.match_profile_context(p_account,p_session)||jsonb_build_object('profile',current_profile);
END; $$;
REVOKE ALL ON FUNCTION public.match_profile_login(text,text,text,jsonb) FROM PUBLIC,anon,authenticated,service_role,goufayu_app;
GRANT EXECUTE ON FUNCTION public.match_profile_login(text,text,text,jsonb) TO goufayu_app;
COMMIT;
