-- Exact rate upgrade after the already deployed quantity + recharge capability.
-- Run once inside the operator transaction, after checking live function hashes.
-- Publish the matching catalog in the SAME transaction. No order/player row is
-- rewritten. Historical order rates 1000 and 100 remain valid; new quotes use 100.
-- This file intentionally does not replay upgrade_order_quantity/recharge.sql,
-- change delivery/VIP/reset routines, rename functions, or issue gateway calls.
DO $prerequisites$
BEGIN
 IF to_regprocedure('payments.create_order_quantity_pre_recharge(text,text,text,text,text,integer)') IS NULL
 OR to_regprocedure('payments.validate_order_quantity_snapshot_pre_recharge(jsonb,integer)') IS NULL
 OR to_regprocedure('payments.catalog_pre_recharge(text,text)') IS NULL
 OR to_regprocedure('payments.catalog_pre_quantity(text,text)') IS NULL
 OR to_regprocedure('payments.recharge_wallet_balance(text)') IS NULL
 THEN RAISE EXCEPTION 'ucoin_rate_100_prerequisite_missing'; END IF;
END; $prerequisites$;

CREATE OR REPLACE FUNCTION payments.validate_order_quantity_snapshot_pre_recharge(p_reward jsonb,p_amount integer) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public,pg_temp AS $$
DECLARE n integer; unit_amount numeric; pricing jsonb; unit_pricing jsonb; rate numeric;
BEGIN
 n:=payments.receipt_quantity(p_reward);
 IF coalesce((p_reward->>'version')::integer,1)<5 THEN RETURN; END IF;
 IF jsonb_typeof(p_reward->'unit_amount_fen') IS DISTINCT FROM 'number'
 THEN RAISE EXCEPTION 'quantity_snapshot_invalid'; END IF;
 unit_amount:=(p_reward->>'unit_amount_fen')::numeric;
 IF unit_amount<>trunc(unit_amount) OR unit_amount NOT BETWEEN 1 AND 1000000
    OR unit_amount*n<>p_amount THEN RAISE EXCEPTION 'quantity_snapshot_invalid'; END IF;
 pricing:=p_reward#>'{grants,pricing}';unit_pricing:=p_reward->'unit_pricing';
 IF unit_pricing->'u_coin_per_yuan' NOT IN ('100'::jsonb,'1000'::jsonb)
    OR unit_pricing->'u_coin_per_yuan' IS NULL
 THEN RAISE EXCEPTION 'quantity_snapshot_invalid'; END IF;
 rate:=(unit_pricing->>'u_coin_per_yuan')::numeric;
 IF jsonb_typeof(pricing) IS DISTINCT FROM 'object' OR jsonb_typeof(unit_pricing) IS DISTINCT FROM 'object'
    OR pricing-'u_coin_price'-'u_coin_per_yuan'-'original_u_coin_price'<>'{}'::jsonb
    OR unit_pricing-'u_coin_price'-'u_coin_per_yuan'-'original_u_coin_price'<>'{}'::jsonb
    OR unit_pricing->'u_coin_price' IS DISTINCT FROM to_jsonb(unit_amount*rate/100)
    OR pricing->'u_coin_price' IS DISTINCT FROM to_jsonb(p_amount::numeric*rate/100)
    OR pricing->'u_coin_per_yuan' IS DISTINCT FROM unit_pricing->'u_coin_per_yuan'
 THEN RAISE EXCEPTION 'quantity_snapshot_invalid'; END IF;
 IF unit_pricing ? 'original_u_coin_price' THEN
  IF jsonb_typeof(unit_pricing->'original_u_coin_price') IS DISTINCT FROM 'number'
    OR (unit_pricing->>'original_u_coin_price')::numeric<>trunc((unit_pricing->>'original_u_coin_price')::numeric)
    OR (unit_pricing->>'original_u_coin_price')::numeric<unit_amount*rate/100
    OR (unit_pricing->>'original_u_coin_price')::numeric>100000000
    OR pricing->'original_u_coin_price' IS DISTINCT FROM to_jsonb((unit_pricing->>'original_u_coin_price')::numeric*n)
  THEN RAISE EXCEPTION 'quantity_snapshot_invalid'; END IF;
 ELSIF pricing ? 'original_u_coin_price' THEN RAISE EXCEPTION 'quantity_snapshot_invalid'; END IF;
END; $$;

CREATE OR REPLACE FUNCTION payments.scale_order_quantity(p_grants jsonb,p_effects jsonb,p_unit_amount integer,p_quantity integer) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public,pg_temp AS $$
DECLARE grants jsonb:=p_grants; effects jsonb; components jsonb:='[]'; lines jsonb:='[]'; c jsonb; k text; days integer;
 unit_pricing jsonb; pricing jsonb;
BEGIN
 IF p_quantity IS NULL OR p_quantity NOT BETWEEN 1 AND 100 OR p_unit_amount IS NULL
    OR p_unit_amount NOT BETWEEN 1 AND 1000000 OR p_unit_amount::bigint*p_quantity>1000000
 THEN RAISE EXCEPTION 'quantity_invalid'; END IF;
 PERFORM payments.validate_commerce_bundle(p_grants,p_effects);
 IF p_quantity>1 AND jsonb_array_length(coalesce(p_grants->'vip_claims','[]'))>0 THEN RAISE EXCEPTION 'quantity_limit_exceeded'; END IF;
 SELECT coalesce(jsonb_object_agg(key,to_jsonb(value::numeric*p_quantity)),'{}') INTO effects FROM jsonb_each_text(p_effects);
 grants:=jsonb_set(grants,'{items}',(SELECT coalesce(jsonb_object_agg(key,to_jsonb(value::numeric*p_quantity)),'{}') FROM jsonb_each_text(p_grants->'items')));
 IF p_grants ? 'components' THEN
  FOR c IN SELECT value FROM jsonb_array_elements(p_grants->'components') LOOP
   components:=components||jsonb_build_array(jsonb_set(c,'{quantity}',to_jsonb((c->>'quantity')::numeric*p_quantity)));
  END LOOP;
  grants:=jsonb_set(grants,'{components}',components);
 END IF;
 FOR k IN SELECT jsonb_array_elements_text(p_grants->'entitlements') LOOP
  days:=payments.entitlement_days(p_grants,k);
  IF days IS NULL AND p_quantity>1 THEN RAISE EXCEPTION 'quantity_limit_exceeded'; END IF;
  IF days IS NOT NULL THEN
   IF days*p_quantity>365 THEN RAISE EXCEPTION 'quantity_limit_exceeded'; END IF;
   grants:=jsonb_set(grants,ARRAY['entitlement_days',k],to_jsonb(days*p_quantity));
  END IF;
 END LOOP;
 FOR c IN SELECT value FROM jsonb_array_elements(coalesce(p_grants->'lines','[]')) LOOP
  IF c ? 'quantity' THEN c:=jsonb_set(c,'{quantity}',to_jsonb((c->>'quantity')::numeric*p_quantity)); END IF;
  IF c ? 'duration_days' THEN c:=jsonb_set(c,'{duration_days}',to_jsonb((c->>'duration_days')::integer*p_quantity)); END IF;
  lines:=lines||jsonb_build_array(c);
 END LOOP;
 grants:=jsonb_set(grants,'{lines}',lines);
 unit_pricing:=coalesce(p_grants->'pricing',jsonb_build_object('u_coin_price',p_unit_amount::bigint,'u_coin_per_yuan',100));
 IF jsonb_typeof(unit_pricing) IS DISTINCT FROM 'object'
    OR unit_pricing->'u_coin_price' IS DISTINCT FROM to_jsonb(p_unit_amount::bigint)
    OR unit_pricing->'u_coin_per_yuan' IS DISTINCT FROM '100'::jsonb
 THEN RAISE EXCEPTION 'quantity_snapshot_invalid'; END IF;
 pricing:=jsonb_set(unit_pricing,'{u_coin_price}',to_jsonb(p_unit_amount::bigint*p_quantity));
 IF unit_pricing ? 'original_u_coin_price' THEN
  pricing:=jsonb_set(pricing,'{original_u_coin_price}',to_jsonb((unit_pricing->>'original_u_coin_price')::numeric*p_quantity));
 END IF;
 grants:=jsonb_set(grants,'{pricing}',pricing);
 PERFORM payments.validate_commerce_bundle(grants,effects);
 RETURN jsonb_build_object('grants',grants,'effects',effects,'unit_pricing',unit_pricing);
END; $$;

CREATE OR REPLACE FUNCTION payments.catalog_pre_recharge(p_account text,p_session text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public,pg_temp AS $$
DECLARE result jsonb; products jsonb;
BEGIN
 result:=payments.catalog_pre_quantity(p_account,p_session);
 IF result ? 'error' THEN RETURN result; END IF;
 SELECT coalesce(jsonb_agg(e.product||jsonb_build_object('max_quantity',q.maximum,'unit_amount_fen',p.amount,
   'unit_u_coin_price',p.amount::bigint,'unit_pricing',coalesce(p.grants->'pricing',jsonb_build_object('u_coin_price',p.amount::bigint,'u_coin_per_yuan',100)),
   'enabled',q.maximum>0,'disabled_reason',CASE WHEN q.maximum=0 AND e.product->>'disabled_reason'='' THEN 'quantity_limit_exceeded' ELSE e.product->>'disabled_reason' END)
   ORDER BY e.ordinality),'[]') INTO products
 FROM jsonb_array_elements(result->'products') WITH ORDINALITY e(product,ordinality)
 JOIN payments.products p ON p.sku=e.product->>'sku'
 CROSS JOIN LATERAL (SELECT payments.max_order_quantity(p_account,p.item_id,p.purchase_limit,p.grants,p.effects,p.amount) AS maximum OFFSET 0) q;
 RETURN jsonb_set(result,'{products}',products);
END; $$;

CREATE OR REPLACE FUNCTION payments.validate_order_quantity_snapshot(p_reward jsonb,p_amount integer) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public,pg_temp AS $$
DECLARE n integer; expected jsonb; rate integer;
BEGIN
 IF p_reward->>'item_id'='u_coin_recharge_receipt' AND p_reward->'version' IS DISTINCT FROM '6'::jsonb
 THEN RAISE EXCEPTION 'quantity_snapshot_invalid'; END IF;
 IF p_reward->'version' IS DISTINCT FROM '6'::jsonb THEN
  PERFORM payments.validate_order_quantity_snapshot_pre_recharge(p_reward,p_amount); RETURN;
 END IF;
 n:=payments.receipt_quantity(p_reward);
 IF p_reward#>'{unit_pricing,u_coin_per_yuan}' NOT IN ('100'::jsonb,'1000'::jsonb)
    OR p_reward#>'{unit_pricing,u_coin_per_yuan}' IS NULL
 THEN RAISE EXCEPTION 'quantity_snapshot_invalid'; END IF;
 rate:=(p_reward#>>'{unit_pricing,u_coin_per_yuan}')::integer;
 expected:=jsonb_build_object('items','{}'::jsonb,'item_limits','{}'::jsonb,'entitlements','[]'::jsonb,'effect_labels','{}'::jsonb,
  'lines',jsonb_build_array(jsonb_build_object('kind','wallet','id','u_coin','quantity',n::bigint*100,'label','U币')),
  'pricing',jsonb_build_object('u_coin_price',n::bigint*rate,'u_coin_per_yuan',rate),'recharge_u_coin_per_unit',100);
 IF p_reward->>'item_id' IS DISTINCT FROM 'u_coin_recharge_receipt'
  OR p_reward->>'product_type' IS DISTINCT FROM 'recharge'
  OR p_reward->'recharge_u_coin_per_unit' IS DISTINCT FROM '100'::jsonb
  OR p_reward->'unit_amount_fen' IS DISTINCT FROM '100'::jsonb
  OR p_reward->'purchase_limit' IS DISTINCT FROM '0'::jsonb
  OR p_reward->'effects' IS DISTINCT FROM '{}'::jsonb
  OR p_reward->'unit_pricing' IS DISTINCT FROM jsonb_build_object('u_coin_price',rate,'u_coin_per_yuan',rate)
  OR p_reward->'grants' IS DISTINCT FROM expected
  OR p_amount IS NULL OR p_amount<>n::bigint*100
 THEN RAISE EXCEPTION 'quantity_snapshot_invalid'; END IF;
END; $$;

CREATE OR REPLACE FUNCTION payments.create_order_quantity(p_account text,p_session text,p_order text,p_sku text,p_provider text,p_quantity integer) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public,pg_temp AS $$
DECLARE o payments.orders%rowtype; p payments.products%rowtype; channel payments.providers%rowtype; c jsonb; g bigint;
 reward jsonb; grants jsonb; wallet bigint;
BEGIN
 IF p_sku IS DISTINCT FROM 'u_coin_recharge' THEN
  RETURN payments.create_order_quantity_pre_recharge(p_account,p_session,p_order,p_sku,p_provider,p_quantity);
 END IF;
 IF p_quantity IS NULL OR p_quantity NOT BETWEEN 1 AND 999999 THEN RETURN jsonb_build_object('error','quantity_invalid'); END IF;
 PERFORM 1 FROM public.player_gameplay_stats WHERE player_id=p_account FOR UPDATE;
 PERFORM 1 FROM public.survival_players WHERE account_id=p_account FOR UPDATE;
 c:=payments.catalog(p_account,p_session);IF c ? 'error' THEN RETURN c; END IF;
 IF EXISTS(SELECT 1 FROM payments.test_accounts WHERE account_id=p_account AND reset_request IS NOT NULL)
 THEN RETURN jsonb_build_object('error','reset_in_progress'); END IF;
 SELECT * INTO o FROM payments.orders WHERE account_id=p_account AND sku=p_sku
  AND (state IN ('created','pending') OR (state='paid_review' AND cleared_at IS NULL)) ORDER BY created_at DESC LIMIT 1;
 IF FOUND THEN
  IF payments.receipt_quantity(o.reward)<>p_quantity THEN RETURN to_jsonb(o)||jsonb_build_object('warning','order_quantity_conflict'); END IF;
  IF o.provider IS DISTINCT FROM p_provider THEN RETURN to_jsonb(o)||jsonb_build_object('warning','order_provider_conflict'); END IF;
  RETURN to_jsonb(o);
 END IF;
 SELECT * INTO channel FROM payments.providers WHERE provider=p_provider AND enabled;
 IF NOT FOUND THEN RETURN jsonb_build_object('error','payment_channel_unavailable'); END IF;
 SELECT * INTO p FROM payments.products WHERE sku=p_sku AND enabled;
 IF NOT FOUND THEN RETURN jsonb_build_object('error','product_unavailable'); END IF;
 -- The operator-published fixed product is an authority, never client fields.
 IF p.item_id<>'u_coin_recharge_receipt' OR p.product_type<>'recharge' OR p.amount<>100 OR p.purchase_limit<>0
  OR p.effects<>'{}'::jsonb OR p.grants IS DISTINCT FROM
  '{"items":{},"item_limits":{},"entitlements":[],"effect_labels":{},"lines":[{"kind":"wallet","id":"u_coin","quantity":100,"label":"U币"}],"pricing":{"u_coin_price":100,"u_coin_per_yuan":100},"recharge_u_coin_per_unit":100}'::jsonb
 THEN RETURN jsonb_build_object('error','product_unavailable'); END IF;
 wallet:=payments.recharge_wallet_balance(p_account);
 IF wallet+p_quantity::bigint*100>9007199254740991 THEN RETURN jsonb_build_object('error','wallet_limit_reached'); END IF;
 grants:=jsonb_set(p.grants,'{lines,0,quantity}',to_jsonb(p_quantity::bigint*100));
 grants:=jsonb_set(grants,'{pricing,u_coin_price}',to_jsonb(p_quantity::bigint*100));
 reward:=jsonb_build_object('item_id',p.item_id,'quantity',p_quantity,'version',6,'unit_amount_fen',100,
  'unit_pricing',p.grants->'pricing','product_type','recharge','recharge_u_coin_per_unit',100,
  'title',p.title,'description',p.description,'effects','{}'::jsonb,'grants',grants,'purchase_limit',0,'catalog_hash',c->>'catalog_hash');
 PERFORM payments.validate_order_quantity_snapshot(reward,p_quantity*100);
 SELECT generation INTO g FROM payments.test_accounts WHERE account_id=p_account;
 INSERT INTO payments.orders(order_id,account_id,sku,amount,reward,generation,provider,appid,mchid)
 VALUES(p_order,p_account,p.sku,p_quantity*100,reward,coalesce(g,0),channel.provider,channel.appid,channel.mchid) RETURNING * INTO o;
 RETURN to_jsonb(o);
END; $$;
-- CREATE OR REPLACE preserves each existing owner and ACL. Private helpers stay
-- private even if a previous deployment accidentally exposed them.
REVOKE ALL ON FUNCTION payments.scale_order_quantity(jsonb,jsonb,integer,integer),
 payments.catalog_pre_recharge(text,text),
 payments.validate_order_quantity_snapshot_pre_recharge(jsonb,integer),
 payments.validate_order_quantity_snapshot(jsonb,integer)
 FROM PUBLIC,goufayu_payment;
REVOKE ALL ON FUNCTION payments.create_order_quantity(text,text,text,text,text,integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION payments.create_order_quantity(text,text,text,text,text,integer) TO goufayu_payment;
