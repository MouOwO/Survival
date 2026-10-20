-- Add the requested predecessor chain without changing applied migrations,
-- existing session identity, historical counters, or the live daily limits.
BEGIN;
CREATE OR REPLACE FUNCTION public.match_profile_login(p_account text,p_session text,p_mode text,p_defaults jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path=pg_catalog,public,extensions,pg_temp AS $$
DECLARE s public.match_profile_sessions%rowtype; current_profile jsonb; archive jsonb; wins jsonb;
BEGIN
 IF p_account IS NULL OR p_account !~ '^[0-9a-f]{64}$' OR p_session IS NULL
   OR p_session !~ '^[A-Za-z0-9_.:-]{8,128}$' OR p_mode IS NULL
   OR p_mode NOT IN ('pure','standard','rich','cold','scourge')
   OR p_defaults IS NULL OR jsonb_typeof(p_defaults)<>'object' THEN RAISE EXCEPTION 'match_login_invalid'; END IF;
 -- Retain the established account lock order, baseline and retry semantics.
 PERFORM 1 FROM public.player_gameplay_stats WHERE player_id=p_account FOR UPDATE;
 PERFORM 1 FROM public.survival_players WHERE account_id=p_account FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'match_account_missing'; END IF;
 SELECT * INTO s FROM public.match_profile_sessions WHERE account_id=p_account AND match_session_id=p_session;
 IF FOUND AND s.mode<>p_mode THEN RETURN jsonb_build_object('ok',false,'error','match_mode_locked'); END IF;
 current_profile:=public.fishing_profile_json(p_account);
 archive:=current_profile->'save'->'archive';
 IF p_mode IN ('rich','cold','scourge') THEN
  wins:=CASE p_mode
   WHEN 'rich' THEN CASE WHEN archive ? 'standard_clear_counts' THEN archive->'standard_clear_counts' ELSE archive->'clear_counts' END
   WHEN 'cold' THEN archive->'rich_clear_counts'
   WHEN 'scourge' THEN archive->'cold_clear_counts' END;
  IF jsonb_typeof(wins->'n10') IS DISTINCT FROM 'number' THEN
   RETURN jsonb_build_object('ok',false,'error',p_mode||'_mode_locked');
  END IF;
  IF (wins->>'n10')::numeric < 1 OR trunc((wins->>'n10')::numeric)<>(wins->>'n10')::numeric THEN
   RETURN jsonb_build_object('ok',false,'error',p_mode||'_mode_locked');
  END IF;
 END IF;
 INSERT INTO public.match_profile_sessions(account_id,match_session_id,mode,baseline,defaults)
 VALUES(p_account,p_session,p_mode,current_profile,p_defaults) ON CONFLICT DO NOTHING;
 RETURN public.match_profile_context(p_account,p_session)||jsonb_build_object('profile',current_profile);
END; $$;
REVOKE ALL ON FUNCTION public.match_profile_login(text,text,text,jsonb) FROM PUBLIC,anon,authenticated,service_role,goufayu_app;
GRANT EXECUTE ON FUNCTION public.match_profile_login(text,text,text,jsonb) TO goufayu_app;
COMMIT;
