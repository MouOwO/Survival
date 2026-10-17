-- Code rollback only. Existing applied receipts/earned values are intentionally retained.
-- Caller owns transaction. Refuse overwriting any third-party function revision.
DO $guard$
DECLARE source text;
BEGIN
 SELECT prosrc INTO source FROM pg_proc WHERE oid='payments.apply_effects(text,jsonb,boolean)'::regprocedure;
 IF source IS NULL OR md5(btrim(replace(source,chr(13),''),chr(10)||chr(9)||' ')) NOT IN ('3ea52ec1171407ed4f50793f1197b86b','c989f8a7d552028306058e6ab7099af2')
 THEN RAISE EXCEPTION 'payment_starjoy_rollback_definition_unexpected'; END IF;
END; $guard$;
CREATE OR REPLACE FUNCTION payments.apply_effects(p_account text, p_effects jsonb, p_remove boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pg_temp'
AS $function$
DECLARE k text; delta numeric; old_value numeric; new_value numeric; r payments.stat_rules%rowtype; applied jsonb:='{}';
BEGIN
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
 RETURN applied;
END; $function$;

REVOKE ALL ON FUNCTION payments.apply_effects(text,jsonb,boolean) FROM PUBLIC,goufayu_payment;
