-- Apply after upgrade_monthly_pass.sql and upgrade_vip_recharge.sql, before
-- publishing commerce bundles. The caller owns the transaction: run the paired
-- rollback-only database checks before committing. No products/orders are seeded.
-- Prices, effects and grants still enter only through the server-owned catalog
-- snapshot in create_order[_channel]; no new client-facing grant RPC is added.

DO $prerequisites$
BEGIN
 IF to_regprocedure('payments.entitlement_days(jsonb,text)') IS NULL
    OR to_regclass('payments.vip_recharge_levels') IS NULL
    OR to_regprocedure('payments.finish_reset_v3(text,text,text,text)') IS NULL
 THEN RAISE EXCEPTION 'commerce_bundles_prerequisite_missing'; END IF;
END;
$prerequisites$;

ALTER TABLE payments.orders ADD COLUMN IF NOT EXISTS applied_archive jsonb NOT NULL DEFAULT '{}';
CREATE INDEX IF NOT EXISTS delivered_component_receipts ON payments.orders(account_id,(reward->>'item_id'))
 WHERE state='delivered';

CREATE OR REPLACE FUNCTION payments.validate_commerce_bundle(p_grants jsonb,p_effects jsonb) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public,pg_temp AS $$
DECLARE c jsonb; n numeric; limit_n numeric; k text; claim text; maximum_level integer:=0;
 seen jsonb:='{}'; claim_effects jsonb; effect_total numeric;
BEGIN
 IF jsonb_typeof(p_grants) IS DISTINCT FROM 'object' OR jsonb_typeof(p_effects) IS DISTINCT FROM 'object'
 THEN RAISE EXCEPTION 'commerce_bundle_grants_invalid'; END IF;
 IF p_grants ? 'components' THEN
  IF jsonb_typeof(p_grants->'components') IS DISTINCT FROM 'array'
  THEN RAISE EXCEPTION 'commerce_bundle_components_invalid'; END IF;
  FOR c IN SELECT value FROM jsonb_array_elements(p_grants->'components') LOOP
   IF jsonb_typeof(c) IS DISTINCT FROM 'object'
     OR coalesce(c->>'sku','') !~ '^[a-z][a-z0-9_]{2,63}$'
     OR coalesce(c->>'item_id','') !~ '^[a-z][a-z0-9_]{2,63}$'
     OR jsonb_typeof(c->'quantity') IS DISTINCT FROM 'number'
     OR jsonb_typeof(c->'purchase_limit') IS DISTINCT FROM 'number'
   THEN RAISE EXCEPTION 'commerce_bundle_component_invalid'; END IF;
   n:=(c->>'quantity')::numeric;limit_n:=(c->>'purchase_limit')::numeric;k:=c->>'item_id';
   IF n<>trunc(n) OR n NOT BETWEEN 1 AND 10000 OR limit_n<>trunc(limit_n)
     OR limit_n NOT BETWEEN 0 AND 10000 OR (limit_n>0 AND n>limit_n) OR seen ? k
     OR jsonb_typeof(p_grants#>ARRAY['items',k]) IS DISTINCT FROM 'number'
     OR (p_grants#>>ARRAY['items',k])::numeric<>n
   THEN RAISE EXCEPTION 'commerce_bundle_component_invalid'; END IF;
   seen:=seen||jsonb_build_object(k,true);
  END LOOP;
 END IF;
 IF p_grants ? 'required_vip_level' THEN
  IF jsonb_typeof(p_grants->'required_vip_level') IS DISTINCT FROM 'number'
  THEN RAISE EXCEPTION 'commerce_bundle_vip_level_invalid'; END IF;
  n:=(p_grants->>'required_vip_level')::numeric;
  IF n<>trunc(n) OR n NOT BETWEEN 1 AND 12 THEN RAISE EXCEPTION 'commerce_bundle_vip_level_invalid'; END IF;
 END IF;
 IF p_grants ? 'vip_claims' THEN
  IF jsonb_typeof(p_grants->'vip_claims') IS DISTINCT FROM 'array'
    OR jsonb_typeof(p_grants->'vip_claim_effects') IS DISTINCT FROM 'object'
    OR NOT (p_grants ? 'required_vip_level')
  THEN RAISE EXCEPTION 'commerce_bundle_vip_claims_invalid'; END IF;
  seen:='{}';
  FOR c IN SELECT value FROM jsonb_array_elements(p_grants->'vip_claims') LOOP
   IF jsonb_typeof(c) IS DISTINCT FROM 'string' THEN RAISE EXCEPTION 'commerce_bundle_vip_claims_invalid'; END IF;
   claim:=c#>>'{}';
   IF claim !~ '^vip_(package|medal)_(0[1-9]|1[0-2])$' OR seen ? claim
   THEN RAISE EXCEPTION 'commerce_bundle_vip_claims_invalid'; END IF;
   seen:=seen||jsonb_build_object(claim,true);
   IF claim LIKE 'vip_package_%' THEN maximum_level:=greatest(maximum_level,right(claim,2)::integer);
   ELSE
    IF NOT ((p_grants->'vip_claims') ? replace(claim,'vip_medal_','vip_package_'))
      OR jsonb_typeof(p_grants#>ARRAY['vip_claim_effects',claim]) IS DISTINCT FROM 'object'
    THEN RAISE EXCEPTION 'commerce_bundle_vip_medal_invalid'; END IF;
   END IF;
  END LOOP;
  IF maximum_level=0 OR maximum_level<>(p_grants->>'required_vip_level')::integer
  THEN RAISE EXCEPTION 'commerce_bundle_vip_level_invalid'; END IF;
  FOR claim,claim_effects IN SELECT key,value FROM jsonb_each(p_grants->'vip_claim_effects') LOOP
   IF claim NOT LIKE 'vip_medal_%' OR NOT (seen ? claim) OR jsonb_typeof(claim_effects) IS DISTINCT FROM 'object'
   THEN RAISE EXCEPTION 'commerce_bundle_vip_medal_invalid'; END IF;
   FOR k,c IN SELECT key,value FROM jsonb_each(claim_effects) LOOP
    IF jsonb_typeof(c) IS DISTINCT FROM 'number' OR (c#>>'{}')::numeric<=0
    THEN RAISE EXCEPTION 'commerce_bundle_vip_effects_invalid'; END IF;
   END LOOP;
  END LOOP;
  -- The catalog expands all effects once. Per-medal metadata identifies only
  -- the portion which may have been granted by the legacy VIP archive route.
  FOR k,effect_total IN
   SELECT e.key,sum((e.value#>>'{}')::numeric)
   FROM jsonb_each(p_grants->'vip_claim_effects') m CROSS JOIN LATERAL jsonb_each(m.value) e GROUP BY e.key
  LOOP
   IF jsonb_typeof(p_effects->k) IS DISTINCT FROM 'number' OR (p_effects->>k)::numeric<effect_total
   THEN RAISE EXCEPTION 'commerce_bundle_vip_effects_invalid'; END IF;
  END LOOP;
 ELSIF p_grants ? 'vip_claim_effects' THEN RAISE EXCEPTION 'commerce_bundle_vip_claims_invalid';
 END IF;
END; $$;

CREATE OR REPLACE FUNCTION payments.commerce_bundle_effects(p_account text,p_grants jsonb,p_effects jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public,pg_temp AS $$
DECLARE claims jsonb; inventory jsonb; result jsonb:=p_effects; claim text; details jsonb; k text; n numeric; remaining numeric;
BEGIN
 PERFORM payments.validate_commerce_bundle(p_grants,p_effects);
 SELECT archive->'vip_claimed',content_inventory INTO claims,inventory FROM public.player_archive_state WHERE account_id=p_account;
 FOR claim,details IN SELECT key,value FROM jsonb_each(coalesce(p_grants->'vip_claim_effects','{}')) LOOP
  IF claims->claim='true'::jsonb OR coalesce((inventory->>claim)::integer,0)>0 THEN
   FOR k,n IN SELECT key,value::numeric FROM jsonb_each_text(details) LOOP
    remaining:=(result->>k)::numeric-n;
    IF remaining<0 THEN RAISE EXCEPTION 'commerce_bundle_vip_effects_invalid'; END IF;
    IF remaining=0 THEN result:=result-k; ELSE result:=jsonb_set(result,ARRAY[k],to_jsonb(remaining)); END IF;
   END LOOP;
  END IF;
 END LOOP;
 RETURN result;
END; $$;

CREATE OR REPLACE FUNCTION payments.product_block(p_account text,p_marker text,p_limit integer,p_grants jsonb,p_effects jsonb) RETURNS text
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public,pg_temp AS $$
DECLARE inventory jsonb; archive jsonb; k text; n integer; days integer; c jsonb; historical bigint; actual_effects jsonb;
 tier integer; claim text; is_test boolean;
BEGIN
 actual_effects:=payments.commerce_bundle_effects(p_account,p_grants,p_effects);
 SELECT s.content_inventory,s.archive INTO inventory,archive FROM public.player_archive_state s WHERE account_id=p_account;
 is_test:=payments.is_test_account(p_account);
 IF p_grants ? 'required_vip_level' THEN
  SELECT coalesce(max(l.level),0) INTO tier FROM payments.vip_recharge_levels l
   JOIN public.player_gameplay_stats s ON s.player_id=p_account AND s.vip_recharge_total_fen>=l.required_fen;
  IF tier<(p_grants->>'required_vip_level')::integer THEN RETURN 'vip_level_required'; END IF;
 END IF;
 FOR claim IN SELECT jsonb_array_elements_text(coalesce(p_grants->'vip_claims','[]')) LOOP
  IF claim LIKE 'vip_package_%' AND (archive#>ARRAY['vip_claimed',claim]='true'::jsonb
    OR coalesce((inventory->>claim)::integer,0)>0 OR (NOT is_test AND EXISTS(
     SELECT 1 FROM payments.orders o WHERE o.account_id=p_account AND o.state='delivered'
      AND (o.reward->>'item_id'=claim OR (o.reward#>'{grants,vip_claims}') ? claim))))
  THEN RETURN 'already_owned'; END IF;
 END LOOP;
 IF p_limit>0 AND coalesce((inventory->>p_marker)::integer,0)>=p_limit THEN RETURN 'already_owned'; END IF;
 IF p_limit>0 AND NOT is_test AND
  (SELECT coalesce(sum(CASE WHEN reward->>'item_id'=p_marker THEN 1 ELSE (applied_items->>p_marker)::integer END),0)
   FROM payments.orders WHERE account_id=p_account AND state='delivered'
    AND (reward->>'item_id'=p_marker OR applied_items ? p_marker))>=p_limit
 THEN RETURN 'purchase_limit_reached'; END IF;
 FOR c IN SELECT value FROM jsonb_array_elements(coalesce(p_grants->'components','[]')) LOOP
  k:=c->>'item_id';n:=(c->>'quantity')::integer;
  IF (c->>'purchase_limit')::integer>0 THEN
   IF coalesce((inventory->>k)::integer,0)+n>(c->>'purchase_limit')::integer THEN RETURN 'component_already_owned'; END IF;
   IF NOT is_test THEN
    SELECT coalesce(sum(CASE WHEN o.reward->>'item_id'=k THEN 1 ELSE coalesce((o.applied_items->>k)::integer,0) END),0)
     INTO historical FROM payments.orders o WHERE o.account_id=p_account AND o.state='delivered'
      AND (o.reward->>'item_id'=k OR o.applied_items ? k);
    IF historical+n>(c->>'purchase_limit')::integer THEN RETURN 'component_already_owned'; END IF;
   END IF;
  END IF;
 END LOOP;
 FOR k,n IN SELECT key,value::integer FROM jsonb_each_text(p_grants->'items') LOOP
  IF coalesce((inventory->>k)::integer,0)+n>coalesce((p_grants->'item_limits'->>k)::integer,0) THEN RETURN 'component_already_owned'; END IF;
 END LOOP;
 FOR k IN SELECT jsonb_array_elements_text(p_grants->'entitlements') LOOP
  days:=payments.entitlement_days(p_grants,k);
  IF EXISTS(SELECT 1 FROM public.archive_entitlements WHERE account_id=p_account AND entitlement_id=k
    AND active AND (expires_at IS NULL OR (days IS NULL AND starts_at<=now() AND expires_at>now())))
  THEN RETURN 'entitlement_already_owned'; END IF;
 END LOOP;
 IF EXISTS(SELECT 1 FROM public.player_gameplay_stats s CROSS JOIN jsonb_each_text(actual_effects) e
  JOIN payments.stat_rules r ON r.field_id=e.key WHERE s.player_id=p_account
  AND r.maximum IS NOT NULL AND (to_jsonb(s)->>e.key)::numeric+e.value::numeric>r.maximum)
 THEN RETURN 'attribute_limit_reached'; END IF;
 RETURN '';
END; $$;

CREATE OR REPLACE FUNCTION payments.catalog(p_account text,p_session text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public,pg_temp AS $$
DECLARE inventory jsonb; stats jsonb; products jsonb; meta payments.catalog_state%rowtype;
BEGIN
 IF NOT EXISTS(SELECT 1 FROM public.match_profile_sessions WHERE account_id=p_account AND match_session_id=p_session)
 THEN RETURN jsonb_build_object('error','match_session_missing'); END IF;
 SELECT content_inventory INTO inventory FROM public.player_archive_state WHERE account_id=p_account;
 SELECT to_jsonb(s) INTO stats FROM public.player_gameplay_stats s WHERE player_id=p_account;
 SELECT * INTO meta FROM payments.catalog_state WHERE singleton;
 SELECT jsonb_agg(jsonb_build_object('sku',p.sku,'item_id',p.item_id,'title',p.title,'description',p.description,
  'amount_fen',p.amount,'category_id',p.category_id,'product_type',p.product_type,'icon',p.icon,'purchase_limit',p.purchase_limit,
  'reward_lines',p.grants->'lines','effect_labels',p.grants->'effect_labels','owned',coalesce((inventory->>p.item_id)::integer,0),
  'original_u_coin_price',p.grants#>'{pricing,original_u_coin_price}',
  'required_vip_level',p.grants->'required_vip_level',
  'enabled',eligibility.blocked='','disabled_reason',eligibility.blocked,
  'stat_preview',coalesce((SELECT jsonb_agg(jsonb_build_object('field_id',e.key,'value',(stats->>e.key)::numeric,
   'delta',e.value::numeric,'after',CASE WHEN r.maximum IS NULL THEN (stats->>e.key)::numeric+e.value::numeric
     ELSE least(r.maximum,(stats->>e.key)::numeric+e.value::numeric) END) ORDER BY e.key)
   FROM jsonb_each_text(payments.commerce_bundle_effects(p_account,p.grants,p.effects)) e
   JOIN payments.stat_rules r ON r.field_id=e.key),'[]')) ORDER BY p.sort_order,p.sku)
 INTO products FROM payments.products p CROSS JOIN LATERAL
  (SELECT payments.product_block(p_account,p.item_id,p.purchase_limit,p.grants,p.effects) AS blocked OFFSET 0) eligibility
 WHERE p.enabled;
 RETURN jsonb_build_object('ok',true,'products',coalesce(products,'[]'),'categories',meta.categories,
  'catalog_hash',meta.catalog_hash,'test_reset_enabled',payments.is_test_account(p_account));
END; $$;

CREATE OR REPLACE FUNCTION payments.deliver(p_order text,p_transaction text,p_amount integer,p_appid text,p_mchid text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public,pg_temp AS $$
DECLARE o payments.orders%rowtype; a text; inventory jsonb; item text; k text; n integer; g bigint; applied jsonb;
 before_stats jsonb; after_stats jsonb; changes jsonb; item_grants jsonb; ent_grants jsonb:='{}'; old_ent jsonb; new_ent jsonb;
 days integer; new_expiry timestamptz; new_start timestamptz; archive jsonb; claims jsonb; claim text;
 archive_changes jsonb:='{}'; prior jsonb; actual_effects jsonb; had_claims boolean;
BEGIN
 SELECT * INTO o FROM payments.orders WHERE order_id=p_order;
 IF NOT FOUND THEN RETURN jsonb_build_object('error','order_missing'); END IF;
 IF coalesce((o.reward->>'version')::integer,1)<4 THEN RETURN payments.deliver_v3(p_order,p_transaction,p_amount,p_appid,p_mchid); END IF;
 a:=o.account_id;
 PERFORM 1 FROM public.player_gameplay_stats WHERE player_id=a FOR UPDATE;
 PERFORM 1 FROM public.survival_players WHERE account_id=a FOR UPDATE;
 SELECT * INTO o FROM payments.orders WHERE order_id=p_order FOR UPDATE;
 IF p_amount IS DISTINCT FROM o.amount OR p_appid IS DISTINCT FROM o.appid OR p_mchid IS DISTINCT FROM o.mchid
  OR p_transaction IS NULL OR p_transaction !~ '^[0-9]{20,64}$' THEN RAISE EXCEPTION 'payment_mismatch'; END IF;
 IF o.transaction_id IS NOT NULL AND o.transaction_id<>p_transaction THEN RAISE EXCEPTION 'transaction_conflict'; END IF;
 IF o.state IN ('delivered','paid_review') THEN RETURN to_jsonb(o); END IF;
 SELECT generation INTO g FROM payments.test_accounts WHERE account_id=a;
 UPDATE payments.orders SET transaction_id=p_transaction,paid_at=now(),checked_at=now() WHERE order_id=p_order;
 IF o.generation<>coalesce(g,0) OR payments.product_block(a,o.reward->>'item_id',(o.reward->>'purchase_limit')::integer,o.reward->'grants',o.reward->'effects')<>'' THEN
  UPDATE payments.orders SET state='paid_review',cleared_at=CASE WHEN o.generation<>coalesce(g,0) THEN now() ELSE NULL END WHERE order_id=p_order;
  RETURN payments.get_order(p_order);
 END IF;
 SELECT s.content_inventory,s.archive INTO inventory,archive FROM public.player_archive_state s WHERE account_id=a FOR UPDATE;
 inventory:=coalesce(inventory,'{}');archive:=coalesce(archive,'{}');item:=o.reward->>'item_id';
 actual_effects:=payments.commerce_bundle_effects(a,o.reward->'grants',o.reward->'effects');
 -- Component markers were already compiled into items. Add only the product's
 -- own marker here, exactly as in the original immutable bundle delivery.
 item_grants:=coalesce(o.reward#>'{grants,items}','{}')||jsonb_build_object(item,1);
 FOR k,n IN SELECT key,value::integer FROM jsonb_each_text(item_grants) LOOP
  IF n<=0 THEN RAISE EXCEPTION 'invalid_item_quantity'; END IF;
  inventory:=jsonb_set(inventory,ARRAY[k],to_jsonb(coalesce((inventory->>k)::integer,0)+n));
 END LOOP;
 had_claims:=archive ? 'vip_claimed';claims:=coalesce(archive->'vip_claimed','{}');
 IF jsonb_typeof(claims) IS DISTINCT FROM 'object' THEN RAISE EXCEPTION 'commerce_bundle_archive_invalid'; END IF;
 FOR claim IN SELECT jsonb_array_elements_text(coalesce(o.reward#>'{grants,vip_claims}','[]')) LOOP
  IF claims->claim IS DISTINCT FROM 'true'::jsonb THEN
   prior:=claims->claim;
   archive_changes:=archive_changes||jsonb_build_object(claim,jsonb_build_object('before',prior,'after',true));
   claims:=claims||jsonb_build_object(claim,true);
  END IF;
 END LOOP;
 IF archive_changes<>'{}'::jsonb THEN archive:=jsonb_set(archive,'{vip_claimed}',claims); END IF;
 INSERT INTO public.player_archive_state(account_id,content_inventory,archive) VALUES(a,inventory,archive)
 ON CONFLICT(account_id) DO UPDATE SET content_inventory=excluded.content_inventory,archive=excluded.archive;
 FOR k IN SELECT jsonb_array_elements_text(o.reward#>'{grants,entitlements}') LOOP
  IF k NOT IN ('vip','archive_pass') THEN RAISE EXCEPTION 'entitlement_not_supported'; END IF;
  SELECT to_jsonb(e) INTO old_ent FROM public.archive_entitlements e WHERE account_id=a AND entitlement_id=k FOR UPDATE;
  days:=payments.entitlement_days(o.reward->'grants',k);
  new_start:=now();new_expiry:=NULL;
  IF days IS NOT NULL THEN
   new_expiry:=now()+days*interval '86400 seconds';
   IF (old_ent->>'active')::boolean AND (old_ent->>'starts_at')::timestamptz<=now()
     AND (old_ent->>'expires_at')::timestamptz>now() THEN
    new_start:=(old_ent->>'starts_at')::timestamptz;
    new_expiry:=(old_ent->>'expires_at')::timestamptz+days*interval '86400 seconds';
   END IF;
  END IF;
  INSERT INTO public.archive_entitlements(account_id,entitlement_id,active,starts_at,expires_at) VALUES(a,k,true,new_start,new_expiry)
  ON CONFLICT(account_id,entitlement_id) DO UPDATE SET active=true,starts_at=excluded.starts_at,expires_at=excluded.expires_at;
  SELECT to_jsonb(e) INTO new_ent FROM public.archive_entitlements e WHERE account_id=a AND entitlement_id=k;
  ent_grants:=ent_grants||jsonb_build_object(k,jsonb_build_object('before',old_ent,'after',new_ent));
 END LOOP;
 SELECT to_jsonb(s) INTO before_stats FROM public.player_gameplay_stats s WHERE player_id=a;
 applied:=payments.apply_effects(a,actual_effects);
 SELECT to_jsonb(s) INTO after_stats FROM public.player_gameplay_stats s WHERE player_id=a;
 SELECT coalesce(jsonb_object_agg(e.key,jsonb_build_object('before',(before_stats->>e.key)::numeric,
  'after',(after_stats->>e.key)::numeric,'delta',e.value::numeric)),'{}') INTO changes FROM jsonb_each_text(applied) e;
 UPDATE public.survival_players SET profile_revision=profile_revision+1,updated_at=now() WHERE account_id=a;
 UPDATE payments.orders SET state='delivered',granted_at=clock_timestamp(),applied_effects=applied,effect_changes=changes,
  applied_items=item_grants,applied_entitlements=ent_grants,
  applied_archive=CASE WHEN archive_changes='{}'::jsonb THEN '{}'::jsonb
   ELSE jsonb_build_object('vip_claimed',archive_changes,'vip_claimed_before_present',had_claims) END WHERE order_id=p_order;
 RETURN payments.get_order(p_order);
END; $$;

-- Keep the existing receipt-aware item/entitlement/stat reversal, including the
-- monthly-pass chain. This wrapper reverses only newly written VIP archive flags.
DO $reset_wrapper$
BEGIN
 IF to_regprocedure('payments.finish_reset_pre_commerce_bundles(text,text,text,text)') IS NULL THEN
  ALTER FUNCTION payments.finish_reset(text,text,text,text) RENAME TO finish_reset_pre_commerce_bundles;
 END IF;
END;
$reset_wrapper$;

CREATE OR REPLACE FUNCTION payments.finish_reset(p_account text,p_session text,p_kind text,p_request text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public,pg_temp AS $$
DECLARE started jsonb; o payments.orders%rowtype; current_archive jsonb; claims jsonb; k text; change jsonb; prior jsonb;
 m record; baseline_archive jsonb; baseline_claims jsonb;
BEGIN
 started:=payments.begin_reset(p_account,p_session,p_kind,p_request);
 IF started ? 'error' OR (started->>'completed')::boolean THEN RETURN started; END IF;
 IF EXISTS(SELECT 1 FROM payments.orders WHERE account_id=p_account AND state IN ('created','pending'))
 THEN RETURN jsonb_build_object('error','pending_payment_unresolved'); END IF;
 IF p_kind='refreshmoney' THEN
  FOR o IN SELECT * FROM payments.orders WHERE account_id=p_account AND state='delivered' AND cleared_at IS NULL
    AND applied_archive ? 'vip_claimed' ORDER BY granted_at DESC,order_id DESC LOOP
   SELECT s.archive INTO current_archive FROM public.player_archive_state s WHERE account_id=p_account FOR UPDATE;
   claims:=coalesce(current_archive->'vip_claimed','{}');
   FOR k,change IN SELECT key,value FROM jsonb_each(o.applied_archive->'vip_claimed') LOOP
    prior:=change->'before';
    IF claims->k IS NOT DISTINCT FROM change->'after' THEN
     IF prior IS NULL OR prior='null'::jsonb THEN claims:=claims-k; ELSE claims:=jsonb_set(claims,ARRAY[k],prior); END IF;
    END IF;
    FOR m IN SELECT match_session_id,baseline FROM public.match_profile_sessions WHERE account_id=p_account LOOP
     baseline_archive:=coalesce(m.baseline#>'{save,archive}','{}');
     baseline_claims:=coalesce(baseline_archive->'vip_claimed','{}');
     IF baseline_claims->k IS NOT DISTINCT FROM change->'after' THEN
      IF prior IS NULL OR prior='null'::jsonb THEN baseline_claims:=baseline_claims-k;
      ELSE baseline_claims:=jsonb_set(baseline_claims,ARRAY[k],prior); END IF;
      baseline_archive:=jsonb_set(baseline_archive,'{vip_claimed}',baseline_claims);
      IF baseline_claims='{}'::jsonb AND NOT (o.applied_archive->>'vip_claimed_before_present')::boolean
      THEN baseline_archive:=baseline_archive-'vip_claimed'; END IF;
      UPDATE public.match_profile_sessions SET baseline=jsonb_set(m.baseline,'{save,archive}',baseline_archive)
       WHERE account_id=p_account AND match_session_id=m.match_session_id;
     END IF;
    END LOOP;
   END LOOP;
   current_archive:=jsonb_set(current_archive,'{vip_claimed}',claims);
   IF claims='{}'::jsonb AND NOT (o.applied_archive->>'vip_claimed_before_present')::boolean THEN current_archive:=current_archive-'vip_claimed'; END IF;
   UPDATE public.player_archive_state SET archive=current_archive WHERE account_id=p_account;
  END LOOP;
 END IF;
 RETURN payments.finish_reset_pre_commerce_bundles(p_account,p_session,p_kind,p_request);
END; $$;

-- Only verified order delivery/reset remain callable by the payment service.
-- Catalog reads can inspect eligibility but cannot execute any grant helper.
REVOKE ALL ON FUNCTION payments.validate_commerce_bundle(jsonb,jsonb),payments.commerce_bundle_effects(text,jsonb,jsonb),
 payments.product_block(text,text,integer,jsonb,jsonb),payments.finish_reset_pre_commerce_bundles(text,text,text,text)
 FROM PUBLIC,goufayu_payment;
REVOKE ALL ON FUNCTION payments.deliver(text,text,integer,text,text),payments.finish_reset(text,text,text,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION payments.deliver(text,text,integer,text,text),payments.finish_reset(text,text,text,text) TO goufayu_payment;
