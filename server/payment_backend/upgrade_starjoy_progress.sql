-- Payment starjoy earned-progress repair. Caller owns transaction; no catalog/order changes.
-- Tier effects remain in the existing archive_starjoy_rewards Lua authority.
DO $prerequisites$
DECLARE source text;
BEGIN
 IF to_regprocedure('payments.apply_effects(text,jsonb,boolean)') IS NULL
  OR NOT EXISTS(SELECT 1 FROM payments.stat_rules WHERE field_id='starjoy_points_earned')
  OR NOT EXISTS(SELECT 1 FROM information_schema.columns WHERE table_schema='public'
   AND table_name='player_gameplay_stats' AND column_name='starjoy_points_earned')
 THEN RAISE EXCEPTION 'payment_starjoy_progress_prerequisite_missing'; END IF;
 SELECT prosrc INTO source FROM pg_proc WHERE oid='payments.apply_effects(text,jsonb,boolean)'::regprocedure;
 IF md5(btrim(replace(source,chr(13),''),chr(10)||chr(9)||' ')) NOT IN ('3ea52ec1171407ed4f50793f1197b86b','c989f8a7d552028306058e6ab7099af2')
 THEN RAISE EXCEPTION 'payment_starjoy_progress_definition_unexpected'; END IF;
END; $prerequisites$;

CREATE OR REPLACE FUNCTION payments.apply_effects(p_account text,p_effects jsonb,p_remove boolean DEFAULT false) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public,pg_temp AS $$
DECLARE k text; delta numeric; old_value numeric; new_value numeric; r payments.stat_rules%rowtype; applied jsonb:='{}';
 old_points numeric; old_earned numeric; earned_value numeric; points_added numeric;
 track_earned boolean:=NOT p_remove AND p_effects ? 'starjoy_points' AND NOT p_effects ? 'starjoy_points_earned';
BEGIN
 -- Delivery already takes this lock; take it here too so the internal helper's
 -- balance/earned baseline cannot race another authenticated account operation.
 IF track_earned THEN
  SELECT starjoy_points,starjoy_points_earned INTO old_points,old_earned
   FROM public.player_gameplay_stats WHERE player_id=p_account FOR UPDATE;
  IF old_points IS NULL OR old_earned IS NULL THEN RAISE EXCEPTION 'gameplay_stats_missing'; END IF;
 END IF;
 FOR k,delta IN SELECT key,value::numeric FROM jsonb_each_text(p_effects) LOOP
  SELECT * INTO r FROM payments.stat_rules WHERE field_id=k;
  IF NOT FOUND OR delta<0 THEN RAISE EXCEPTION 'payment_effect_invalid'; END IF;
  EXECUTE format('SELECT %I FROM public.player_gameplay_stats WHERE player_id=$1',k) INTO old_value USING p_account;
  IF old_value IS NULL THEN RAISE EXCEPTION 'gameplay_stats_missing'; END IF;
  new_value:=greatest(r.minimum,old_value+CASE WHEN p_remove THEN -delta ELSE delta END);
  IF r.maximum IS NOT NULL THEN new_value:=least(r.maximum,new_value); END IF;
  EXECUTE format('UPDATE public.player_gameplay_stats SET %I=$1,updated_at=now() WHERE player_id=$2',k)
   USING new_value,p_account;
  applied:=applied||jsonb_build_object(k,abs(new_value-old_value));
 END LOOP;
 IF track_earned THEN
  points_added:=coalesce((applied->>'starjoy_points')::numeric,0);
  IF points_added>0 THEN
   -- Same earned rule as archive_starjoy_rewards.change, including legacy saves
   -- whose unspent balance predates the earned counter. Spent points never erase
   -- earlier earned credit; the payment's actual applied delta is recorded.
   SELECT * INTO r FROM payments.stat_rules WHERE field_id='starjoy_points_earned';
   IF NOT FOUND THEN RAISE EXCEPTION 'payment_starjoy_progress_prerequisite_missing'; END IF;
   earned_value:=greatest(r.minimum,greatest(old_earned,old_points)+points_added);
   IF r.maximum IS NOT NULL THEN earned_value:=least(r.maximum,earned_value); END IF;
   UPDATE public.player_gameplay_stats SET starjoy_points_earned=earned_value,updated_at=now() WHERE player_id=p_account;
   applied:=applied||jsonb_build_object('starjoy_points_earned',earned_value-old_earned);
  END IF;
 END IF;
 -- A test reset passes this exact applied receipt with p_remove=true, which must
 -- not derive earned credit again. Older receipts without earned remain valid.
 RETURN applied;
END; $$;
REVOKE ALL ON FUNCTION payments.apply_effects(text,jsonb,boolean) FROM PUBLIC,goufayu_payment;
