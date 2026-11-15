-- Indexed online-session lifecycle. New isolated candidate only; no production apply.
-- Initialization: O(existing online rows) one backfill. Normal checkpoint adds
-- indexed O(log sessions) lookups, fixed per-account locking, no polling/scan.
CREATE TABLE public.online_time_session_lifecycle (
 account_id text NOT NULL REFERENCES public.survival_players(account_id) ON DELETE CASCADE,
 session_id text NOT NULL,
 first_seen_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 closed_at timestamptz,
 PRIMARY KEY(account_id,session_id)
);
ALTER TABLE public.online_time_session_lifecycle ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.online_time_session_lifecycle FROM PUBLIC,anon,authenticated,goufayu_app;
DO $ownership$
DECLARE owner_name text;
BEGIN
 SELECT pg_get_userbyid(relowner) INTO owner_name FROM pg_class
 WHERE oid='public.online_time_sessions'::regclass;
 EXECUTE format('ALTER TABLE public.online_time_session_lifecycle OWNER TO %I',owner_name);
END
$ownership$;
INSERT INTO public.online_time_session_lifecycle(account_id,session_id,first_seen_at)
 SELECT account_id,session_id,last_checkpoint_at FROM public.online_time_sessions;
ALTER TABLE public.online_time_idempotency
 ADD COLUMN online_checkpoint_session_id text,
 ADD COLUMN online_checkpoint_final boolean;
ALTER TABLE public.online_time_idempotency ADD CONSTRAINT online_checkpoint_binding_pair
 CHECK((online_checkpoint_session_id IS NULL)=(online_checkpoint_final IS NULL));

CREATE OR REPLACE FUNCTION public.checkpoint_online_time(
 p_account_id text,p_session_id text,p_request_id text,p_lease_seconds integer,
 p_definition_version integer,p_interval_min_seconds integer,p_interval_max_seconds integer,p_final boolean
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
 SET search_path TO 'pg_catalog','public','extensions','pg_temp'
AS $lifecycle$
DECLARE
 v_response jsonb; v_bound_session text; v_bound_final boolean;
 v_current text; v_total bigint; v_known boolean; v_closed timestamptz;
BEGIN
 IF p_account_id IS NULL OR p_account_id !~ '^[0-9a-f]{64}$'
  OR p_session_id IS NULL OR length(p_session_id)<8
  OR p_request_id IS NULL OR length(p_request_id)<8
  OR p_lease_seconds IS NULL OR p_lease_seconds<1
  OR p_definition_version IS NULL OR p_definition_version<1
  OR p_interval_min_seconds IS NULL OR p_interval_min_seconds<1
  OR p_interval_max_seconds IS NULL OR p_interval_max_seconds<p_interval_min_seconds
  OR p_final IS NULL THEN RAISE EXCEPTION 'online_time_payload_invalid'; END IF;
 SELECT response,online_checkpoint_session_id,online_checkpoint_final
 INTO v_response,v_bound_session,v_bound_final
 FROM public.online_time_idempotency WHERE request_id=p_request_id AND account_id=p_account_id;
 IF FOUND AND v_bound_session IS NOT NULL THEN
  IF v_bound_session<>p_session_id OR v_bound_final<>p_final THEN
   RAISE EXCEPTION 'online_time_request_conflict' USING ERRCODE='22023';
  END IF;
  RETURN v_response;
 ELSIF FOUND AND NOT p_final THEN
  RETURN public.archive_finalize_fishing_checkpoint(p_account_id,p_request_id,v_response);
 END IF;

 -- Same stats-first lock order as the retained checkpoint/archive functions.
 SELECT online_seconds_total INTO v_total FROM public.player_gameplay_stats
 WHERE player_id=p_account_id FOR UPDATE;
 IF NOT FOUND THEN
    insert into public.survival_players(account_id) values (p_account_id)
        on conflict (account_id) do nothing;
    insert into public.player_gameplay_stats(
        player_id, initial_wood, initial_gold, wood_per_second,
        lumberjack_attack_efficiency, gold_per_second, gold_mine_efficiency_pct,
        initial_population_cap, starjoy_points, hero_initial_attack,
        hero_damage_attack_growth, hero_basic_attack_growth,
        hero_final_damage_bonus_pct, hero_attack_armor_reduction,
        hero_attribute_growth, hero_critical_damage_bonus_pct, hero_attack_bonus_pct,
        hero_health_bonus_pct, hero_armor_bonus_pct, hero_damage_reduction_pct,
        tower_attack_bonus_pct, tower_attack_speed_bonus_pct,
        tower_attack_armor_reduction, tower_critical_chance_pct, tower_attack_interval,
        tower_final_damage_bonus_pct, wall_damage_block, wall_damage_reduction_pct,
        wall_armor_bonus_pct, wall_health_regen_per_second, wall_initial_health,
        wall_armor, wall_health_bonus_pct, wall_health_per_second,
        lumberjack_attack_growth, lumberjack_attack_speed_bonus_pct
    ) select p_account_id, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
    where not exists (select 1 from public.player_gameplay_stats where player_id = p_account_id);


  SELECT online_seconds_total INTO v_total FROM public.player_gameplay_stats
  WHERE player_id=p_account_id FOR UPDATE;
 END IF;
 -- A concurrent same-ID request may have committed while this request waited.
 SELECT response,online_checkpoint_session_id,online_checkpoint_final
 INTO v_response,v_bound_session,v_bound_final FROM public.online_time_idempotency
 WHERE request_id=p_request_id AND account_id=p_account_id;
 IF FOUND THEN
  IF v_bound_session IS NOT NULL AND(v_bound_session<>p_session_id OR v_bound_final<>p_final) THEN
   RAISE EXCEPTION 'online_time_request_conflict' USING ERRCODE='22023';
  END IF;
  IF p_final THEN
   INSERT INTO public.online_time_session_lifecycle(account_id,session_id,closed_at)
   VALUES(p_account_id,p_session_id,clock_timestamp())
   ON CONFLICT(account_id,session_id) DO UPDATE
    SET closed_at=coalesce(online_time_session_lifecycle.closed_at,EXCLUDED.closed_at);
   DELETE FROM public.online_time_sessions WHERE account_id=p_account_id AND session_id=p_session_id;
  END IF;
  RETURN public.archive_finalize_fishing_checkpoint(p_account_id,p_request_id,v_response);
 END IF;
 SELECT session_id INTO v_current FROM public.online_time_sessions WHERE account_id=p_account_id FOR UPDATE;
 SELECT closed_at INTO v_closed FROM public.online_time_session_lifecycle
 WHERE account_id=p_account_id AND session_id=p_session_id;
 v_known:=FOUND;
 IF v_closed IS NOT NULL OR(v_known AND v_current IS DISTINCT FROM p_session_id)
  OR(p_final AND v_current IS DISTINCT FROM p_session_id) THEN
  -- Closed/old sessions cannot reopen themselves or replace a newer session.
  v_response:=jsonb_build_object('ok',true,'elapsed_seconds',0,
    'online_seconds_total',coalesce(v_total,0),'grants','[]'::jsonb);
  INSERT INTO public.online_time_idempotency(request_id,account_id,response,
   online_checkpoint_session_id,online_checkpoint_final)
  VALUES(p_request_id,p_account_id,v_response,p_session_id,p_final);
  INSERT INTO public.online_time_session_lifecycle(account_id,session_id,closed_at)
  VALUES(p_account_id,p_session_id,clock_timestamp())
  ON CONFLICT(account_id,session_id) DO UPDATE
   SET closed_at=coalesce(online_time_session_lifecycle.closed_at,EXCLUDED.closed_at);
  RETURN public.archive_finalize_fishing_checkpoint(p_account_id,p_request_id,v_response);
 END IF;
 IF v_current IS NOT NULL AND v_current<>p_session_id THEN
  INSERT INTO public.online_time_session_lifecycle(account_id,session_id,closed_at)
  VALUES(p_account_id,v_current,clock_timestamp())
  ON CONFLICT(account_id,session_id) DO UPDATE
   SET closed_at=coalesce(online_time_session_lifecycle.closed_at,EXCLUDED.closed_at);
 END IF;
 INSERT INTO public.online_time_session_lifecycle(account_id,session_id)
 VALUES(p_account_id,p_session_id) ON CONFLICT DO NOTHING;
 v_response:=public.checkpoint_online_time_before_daily_limits(
  p_account_id,p_session_id,p_request_id,p_lease_seconds,p_definition_version,
  p_interval_min_seconds,p_interval_max_seconds,p_final);
 UPDATE public.online_time_idempotency SET online_checkpoint_session_id=p_session_id,
  online_checkpoint_final=p_final WHERE request_id=p_request_id AND account_id=p_account_id;
 IF p_final THEN
  UPDATE public.online_time_session_lifecycle SET closed_at=clock_timestamp()
  WHERE account_id=p_account_id AND session_id=p_session_id;
 END IF;
 RETURN public.archive_finalize_fishing_checkpoint(p_account_id,p_request_id,v_response);
END
$lifecycle$;
