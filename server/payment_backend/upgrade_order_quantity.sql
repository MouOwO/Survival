-- Apply after upgrade_commerce_bundles.sql. Caller owns the transaction.
-- Validate with rollback-only quantity fixtures before publication. Existing
-- orders/rewards/QRs are never rewritten. No gateway is called by this migration.
DO $prerequisites$
BEGIN
 IF to_regprocedure('payments.validate_commerce_bundle(jsonb,jsonb)') IS NULL
    OR to_regprocedure('payments.create_order_channel(text,text,text,text,text)') IS NULL
 THEN RAISE EXCEPTION 'order_quantity_prerequisite_missing'; END IF;
END; $prerequisites$;

CREATE OR REPLACE FUNCTION payments.receipt_quantity(p_reward jsonb) RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public,pg_temp AS $$
DECLARE n numeric;
BEGIN
 IF coalesce((p_reward->>'version')::integer,1)<5 THEN RETURN 1; END IF;
 IF jsonb_typeof(p_reward->'quantity') IS DISTINCT FROM 'number' THEN RAISE EXCEPTION 'quantity_snapshot_invalid'; END IF;
 n:=(p_reward->>'quantity')::numeric;
 IF n<>trunc(n) OR n NOT BETWEEN 1 AND 100 THEN RAISE EXCEPTION 'quantity_snapshot_invalid'; END IF;
 RETURN n::integer;
END; $$;

CREATE OR REPLACE FUNCTION payments.validate_order_quantity_snapshot(p_reward jsonb,p_amount integer) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public,pg_temp AS $$
DECLARE n integer; unit_amount numeric; pricing jsonb; unit_pricing jsonb;
BEGIN
 n:=payments.receipt_quantity(p_reward);
 IF coalesce((p_reward->>'version')::integer,1)<5 THEN RETURN; END IF;
 IF jsonb_typeof(p_reward->'unit_amount_fen') IS DISTINCT FROM 'number'
 THEN RAISE EXCEPTION 'quantity_snapshot_invalid'; END IF;
 unit_amount:=(p_reward->>'unit_amount_fen')::numeric;
 IF unit_amount<>trunc(unit_amount) OR unit_amount NOT BETWEEN 1 AND 1000000
    OR unit_amount*n<>p_amount THEN RAISE EXCEPTION 'quantity_snapshot_invalid'; END IF;
 pricing:=p_reward#>'{grants,pricing}';unit_pricing:=p_reward->'unit_pricing';
 IF jsonb_typeof(pricing) IS DISTINCT FROM 'object' OR jsonb_typeof(unit_pricing) IS DISTINCT FROM 'object'
    OR pricing-'u_coin_price'-'u_coin_per_yuan'-'original_u_coin_price'<>'{}'::jsonb
    OR unit_pricing-'u_coin_price'-'u_coin_per_yuan'-'original_u_coin_price'<>'{}'::jsonb
    OR unit_pricing->'u_coin_price' IS DISTINCT FROM to_jsonb(unit_amount*10)
    OR pricing->'u_coin_price' IS DISTINCT FROM to_jsonb(p_amount::numeric*10)
    OR pricing->'u_coin_per_yuan' IS DISTINCT FROM '1000'::jsonb
    OR unit_pricing->'u_coin_per_yuan' IS DISTINCT FROM '1000'::jsonb
 THEN RAISE EXCEPTION 'quantity_snapshot_invalid'; END IF;
 IF unit_pricing ? 'original_u_coin_price' THEN
  IF jsonb_typeof(unit_pricing->'original_u_coin_price') IS DISTINCT FROM 'number'
    OR (unit_pricing->>'original_u_coin_price')::numeric<>trunc((unit_pricing->>'original_u_coin_price')::numeric)
    OR (unit_pricing->>'original_u_coin_price')::numeric<unit_amount*10
    OR (unit_pricing->>'original_u_coin_price')::numeric>100000000
    OR pricing->'original_u_coin_price' IS DISTINCT FROM to_jsonb((unit_pricing->>'original_u_coin_price')::numeric*n)
  THEN RAISE EXCEPTION 'quantity_snapshot_invalid'; END IF;
 ELSIF pricing ? 'original_u_coin_price' THEN RAISE EXCEPTION 'quantity_snapshot_invalid'; END IF;
END; $$;

CREATE OR REPLACE FUNCTION payments.purchased_units(p_account text,p_item text) RETURNS bigint
LANGUAGE sql SECURITY DEFINER SET search_path=pg_catalog,public,pg_temp AS $$
 SELECT coalesce(sum(CASE WHEN o.reward->>'item_id'=p_item THEN payments.receipt_quantity(o.reward)
  ELSE coalesce((o.applied_items->>p_item)::integer,0) END),0)
 FROM payments.orders o WHERE o.account_id=p_account AND o.state='delivered'
  AND (o.reward->>'item_id'=p_item OR o.applied_items ? p_item);
$$;

DO $save_helpers$
BEGIN
 IF to_regprocedure('payments.product_block_pre_quantity(text,text,integer,jsonb,jsonb)') IS NULL THEN
  ALTER FUNCTION payments.product_block(text,text,integer,jsonb,jsonb) RENAME TO product_block_pre_quantity;
 END IF;
 IF to_regprocedure('payments.catalog_pre_quantity(text,text)') IS NULL THEN
  ALTER FUNCTION payments.catalog(text,text) RENAME TO catalog_pre_quantity;
 END IF;
END; $save_helpers$;

CREATE OR REPLACE FUNCTION payments.product_block_quantity(p_account text,p_marker text,p_limit integer,p_grants jsonb,p_effects jsonb,p_quantity integer) RETURNS text
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public,pg_temp AS $$
DECLARE blocked text; inventory jsonb; c jsonb; held bigint; remaining bigint;
BEGIN
 blocked:=payments.product_block_pre_quantity(p_account,p_marker,p_limit,p_grants,p_effects);
 IF blocked<>'' THEN RETURN blocked; END IF;
 IF p_quantity IS NULL OR p_quantity NOT BETWEEN 1 AND 100 THEN RETURN 'quantity_invalid'; END IF;
 SELECT content_inventory INTO inventory FROM public.player_archive_state WHERE account_id=p_account;
 held:=coalesce((inventory->>p_marker)::bigint,0);
 IF held+p_quantity>100000000 THEN RETURN 'quantity_limit_exceeded'; END IF;
 IF p_limit>0 THEN
  IF NOT payments.is_test_account(p_account) THEN held:=greatest(held,payments.purchased_units(p_account,p_marker)); END IF;
  IF held+p_quantity>p_limit THEN RETURN 'purchase_limit_reached'; END IF;
 END IF;
 FOR c IN SELECT value FROM jsonb_array_elements(coalesce(p_grants->'components','[]')) LOOP
  IF (c->>'purchase_limit')::integer>0 THEN
   held:=coalesce((inventory->>(c->>'item_id'))::bigint,0);
   IF NOT payments.is_test_account(p_account) THEN held:=greatest(held,payments.purchased_units(p_account,c->>'item_id')); END IF;
   IF held+(c->>'quantity')::integer>(c->>'purchase_limit')::integer THEN RETURN 'component_already_owned'; END IF;
  END IF;
 END LOOP;
 RETURN '';
END; $$;

CREATE OR REPLACE FUNCTION payments.product_block(p_account text,p_marker text,p_limit integer,p_grants jsonb,p_effects jsonb) RETURNS text
LANGUAGE sql SECURITY DEFINER SET search_path=pg_catalog,public,pg_temp AS $$
 SELECT payments.product_block_quantity(p_account,p_marker,p_limit,p_grants,p_effects,1);
$$;

CREATE OR REPLACE FUNCTION payments.max_order_quantity(p_account text,p_marker text,p_limit integer,p_grants jsonb,p_effects jsonb,p_unit_amount integer) RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public,pg_temp AS $$
DECLARE result numeric:=100; inventory jsonb; stats jsonb; c jsonb; k text; n numeric; held numeric; days integer; maximum numeric;
BEGIN
 IF p_unit_amount IS NULL OR p_unit_amount NOT BETWEEN 1 AND 1000000
    OR payments.product_block_quantity(p_account,p_marker,p_limit,p_grants,p_effects,1)<>'' THEN RETURN 0; END IF;
 result:=least(result,floor(1000000::numeric/p_unit_amount));
 SELECT s.content_inventory,to_jsonb(g) INTO inventory,stats FROM public.player_gameplay_stats g
  LEFT JOIN public.player_archive_state s ON s.account_id=g.player_id WHERE g.player_id=p_account;
 held:=coalesce((inventory->>p_marker)::numeric,0);
 result:=least(result,100000000-held);
 IF p_limit>0 THEN
  IF NOT payments.is_test_account(p_account) THEN held:=greatest(held,payments.purchased_units(p_account,p_marker)); END IF;
  result:=least(result,p_limit-held);
 END IF;
 FOR k,n IN SELECT key,value::numeric FROM jsonb_each_text(p_grants->'items') LOOP
  result:=least(result,floor(((p_grants#>>ARRAY['item_limits',k])::numeric-coalesce((inventory->>k)::numeric,0))/n));
 END LOOP;
 FOR c IN SELECT value FROM jsonb_array_elements(coalesce(p_grants->'components','[]')) LOOP
  n:=(c->>'quantity')::numeric;
  result:=least(result,floor(10000/n)); -- Existing bundle validator's per-entry bound.
  IF (c->>'purchase_limit')::integer>0 THEN
   held:=coalesce((inventory->>(c->>'item_id'))::numeric,0);
   IF NOT payments.is_test_account(p_account) THEN held:=greatest(held,payments.purchased_units(p_account,c->>'item_id')); END IF;
   result:=least(result,floor(((c->>'purchase_limit')::numeric-held)/n));
  END IF;
 END LOOP;
 FOR k IN SELECT jsonb_array_elements_text(p_grants->'entitlements') LOOP
  days:=payments.entitlement_days(p_grants,k);
  IF days IS NULL THEN result:=least(result,1); ELSE result:=least(result,floor(365::numeric/days)); END IF;
 END LOOP;
 IF jsonb_array_length(coalesce(p_grants->'vip_claims','[]'))>0 THEN result:=least(result,1); END IF;
 FOR k,n IN SELECT key,value::numeric FROM jsonb_each_text(payments.commerce_bundle_effects(p_account,p_grants,p_effects)) LOOP
  SELECT r.maximum INTO maximum FROM payments.stat_rules r WHERE r.field_id=k;
  IF maximum IS NOT NULL AND n>0 THEN result:=least(result,floor((maximum-(stats->>k)::numeric)/n)); END IF;
 END LOOP;
 RETURN greatest(0,result)::integer;
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
 unit_pricing:=coalesce(p_grants->'pricing',jsonb_build_object('u_coin_price',p_unit_amount::bigint*10,'u_coin_per_yuan',1000));
 IF jsonb_typeof(unit_pricing) IS DISTINCT FROM 'object'
    OR unit_pricing->'u_coin_price' IS DISTINCT FROM to_jsonb(p_unit_amount::bigint*10)
    OR unit_pricing->'u_coin_per_yuan' IS DISTINCT FROM '1000'::jsonb
 THEN RAISE EXCEPTION 'quantity_snapshot_invalid'; END IF;
 pricing:=jsonb_set(unit_pricing,'{u_coin_price}',to_jsonb(p_unit_amount::bigint*10*p_quantity));
 IF unit_pricing ? 'original_u_coin_price' THEN
  pricing:=jsonb_set(pricing,'{original_u_coin_price}',to_jsonb((unit_pricing->>'original_u_coin_price')::numeric*p_quantity));
 END IF;
 grants:=jsonb_set(grants,'{pricing}',pricing);
 PERFORM payments.validate_commerce_bundle(grants,effects);
 RETURN jsonb_build_object('grants',grants,'effects',effects,'unit_pricing',unit_pricing);
END; $$;

CREATE OR REPLACE FUNCTION payments.catalog(p_account text,p_session text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public,pg_temp AS $$
DECLARE result jsonb; products jsonb;
BEGIN
 result:=payments.catalog_pre_quantity(p_account,p_session);
 IF result ? 'error' THEN RETURN result; END IF;
 SELECT coalesce(jsonb_agg(e.product||jsonb_build_object('max_quantity',q.maximum,'unit_amount_fen',p.amount,
   'unit_u_coin_price',p.amount::bigint*10,'unit_pricing',coalesce(p.grants->'pricing',jsonb_build_object('u_coin_price',p.amount::bigint*10,'u_coin_per_yuan',1000)),
   'enabled',q.maximum>0,'disabled_reason',CASE WHEN q.maximum=0 AND e.product->>'disabled_reason'='' THEN 'quantity_limit_exceeded' ELSE e.product->>'disabled_reason' END)
   ORDER BY e.ordinality),'[]') INTO products
 FROM jsonb_array_elements(result->'products') WITH ORDINALITY e(product,ordinality)
 JOIN payments.products p ON p.sku=e.product->>'sku'
 CROSS JOIN LATERAL (SELECT payments.max_order_quantity(p_account,p.item_id,p.purchase_limit,p.grants,p.effects,p.amount) AS maximum OFFSET 0) q;
 RETURN jsonb_set(result,'{products}',products);
END; $$;

CREATE OR REPLACE FUNCTION payments.create_order_quantity(p_account text,p_session text,p_order text,p_sku text,p_provider text,p_quantity integer) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public,pg_temp AS $$
DECLARE o payments.orders%rowtype; p payments.products%rowtype; channel payments.providers%rowtype; c jsonb; g bigint; expanded jsonb; blocked text; reward jsonb;
BEGIN
 IF p_quantity IS NULL OR p_quantity NOT BETWEEN 1 AND 100 THEN RETURN jsonb_build_object('error','quantity_invalid'); END IF;
 PERFORM 1 FROM public.player_gameplay_stats WHERE player_id=p_account FOR UPDATE;
 PERFORM 1 FROM public.survival_players WHERE account_id=p_account FOR UPDATE;
 c:=payments.catalog(p_account,p_session);IF c ? 'error' THEN RETURN c; END IF;
 IF EXISTS(SELECT 1 FROM payments.test_accounts WHERE account_id=p_account AND reset_request IS NOT NULL)
 THEN RETURN jsonb_build_object('error','reset_in_progress'); END IF;
 -- Recover the authenticated account's existing intent even after catalog or
 -- channel edits. Never overwrite its quantity, price, snapshot or QR.
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
 blocked:=payments.product_block(p_account,p.item_id,p.purchase_limit,p.grants,p.effects);
 IF blocked<>'' THEN RETURN jsonb_build_object('error',blocked); END IF;
 IF p_quantity>payments.max_order_quantity(p_account,p.item_id,p.purchase_limit,p.grants,p.effects,p.amount)
 THEN RETURN jsonb_build_object('error','quantity_limit_exceeded'); END IF;
 expanded:=payments.scale_order_quantity(p.grants,p.effects,p.amount,p_quantity);
 reward:=jsonb_build_object('item_id',p.item_id,'quantity',p_quantity,'version',5,'unit_amount_fen',p.amount,'unit_pricing',expanded->'unit_pricing',
  'title',p.title,'description',p.description,'effects',expanded->'effects','grants',expanded->'grants','purchase_limit',p.purchase_limit,'catalog_hash',c->>'catalog_hash');
 PERFORM payments.validate_order_quantity_snapshot(reward,p.amount*p_quantity);
 SELECT generation INTO g FROM payments.test_accounts WHERE account_id=p_account;
 INSERT INTO payments.orders(order_id,account_id,sku,amount,reward,generation,provider,appid,mchid)
 VALUES(p_order,p_account,p.sku,p.amount*p_quantity,reward,coalesce(g,0),channel.provider,channel.appid,channel.mchid) RETURNING * INTO o;
 RETURN to_jsonb(o);
END; $$;

CREATE OR REPLACE FUNCTION payments.create_order_channel(p_account text,p_session text,p_order text,p_sku text,p_provider text) RETURNS jsonb
LANGUAGE sql SECURITY DEFINER SET search_path=pg_catalog,public,pg_temp AS $$
 SELECT payments.create_order_quantity(p_account,p_session,p_order,p_sku,p_provider,1);
$$;
CREATE OR REPLACE FUNCTION payments.create_order(p_account text,p_session text,p_order text,p_sku text) RETURNS jsonb
LANGUAGE sql SECURITY DEFINER SET search_path=pg_catalog,public,pg_temp AS $$
 SELECT payments.create_order_quantity(p_account,p_session,p_order,p_sku,'wechat',1);
$$;

-- Preserve the deployed gateway, VIP, medal, entitlement, reset-generation and
-- receipt logic verbatim. Only quantity validation, quantity-aware eligibility
-- and the root ownership increment change. Fail closed on an unknown definition.
DO $delivery$
DECLARE definition text; old_guard text; new_guard text; old_marker text; new_marker text; locked_select text; snapshot_check text;
BEGIN
 SELECT pg_get_functiondef('payments.deliver(text,text,integer,text,text)'::regprocedure) INTO definition;
 old_guard:='payments.product_block(a,o.reward->>''item_id'',(o.reward->>''purchase_limit'')::integer,o.reward->''grants'',o.reward->''effects'')';
 new_guard:='payments.product_block_quantity(a,o.reward->>''item_id'',(o.reward->>''purchase_limit'')::integer,o.reward->''grants'',o.reward->''effects'',payments.receipt_quantity(o.reward))';
 old_marker:='jsonb_build_object(item,1)';new_marker:='jsonb_build_object(item,payments.receipt_quantity(o.reward))';
 locked_select:='SELECT * INTO o FROM payments.orders WHERE order_id=p_order FOR UPDATE;';
 snapshot_check:=locked_select||chr(10)||' PERFORM payments.validate_order_quantity_snapshot(o.reward,o.amount);';
 IF position(new_guard in definition)>0 AND position(new_marker in definition)>0 AND position(snapshot_check in definition)>0 THEN RETURN; END IF;
 IF position(old_guard in definition)=0 OR position(old_marker in definition)=0 OR position(locked_select in definition)=0
 THEN RAISE EXCEPTION 'order_quantity_delivery_definition_unexpected'; END IF;
 definition:=replace(replace(replace(definition,old_guard,new_guard),old_marker,new_marker),locked_select,snapshot_check);
 EXECUTE definition;
END; $delivery$;

REVOKE ALL ON FUNCTION payments.receipt_quantity(jsonb),payments.validate_order_quantity_snapshot(jsonb,integer),payments.purchased_units(text,text),
 payments.product_block_pre_quantity(text,text,integer,jsonb,jsonb),payments.product_block_quantity(text,text,integer,jsonb,jsonb,integer),
 payments.max_order_quantity(text,text,integer,jsonb,jsonb,integer),payments.scale_order_quantity(jsonb,jsonb,integer,integer),
 payments.catalog_pre_quantity(text,text),payments.product_block(text,text,integer,jsonb,jsonb) FROM PUBLIC,goufayu_payment;
REVOKE ALL ON FUNCTION payments.create_order_quantity(text,text,text,text,text,integer),payments.catalog(text,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION payments.create_order_quantity(text,text,text,text,text,integer),payments.catalog(text,text),
 payments.create_order_channel(text,text,text,text,text),payments.create_order(text,text,text,text) TO goufayu_payment;
