-- Catalog configuration and immutable bundle receipts; retain all prior orders.
ALTER TABLE payments.products DROP CONSTRAINT products_amount_check;
ALTER TABLE payments.products ADD CHECK(amount BETWEEN 1 AND 1000000);
ALTER TABLE payments.orders DROP CONSTRAINT orders_amount_check;
ALTER TABLE payments.orders ADD CHECK(amount BETWEEN 1 AND 1000000);
ALTER TABLE payments.products ADD COLUMN grants jsonb NOT NULL DEFAULT '{"items":{},"item_limits":{},"entitlements":[],"lines":[]}';
ALTER TABLE payments.products ADD COLUMN category_id text NOT NULL DEFAULT 'technology';
ALTER TABLE payments.products ADD COLUMN product_type text NOT NULL DEFAULT 'single';
ALTER TABLE payments.products ADD COLUMN icon text NOT NULL DEFAULT '';
ALTER TABLE payments.products ADD COLUMN purchase_limit integer NOT NULL DEFAULT 1 CHECK(purchase_limit>=0);
ALTER TABLE payments.orders ADD COLUMN applied_items jsonb NOT NULL DEFAULT '{}';
ALTER TABLE payments.orders ADD COLUMN applied_entitlements jsonb NOT NULL DEFAULT '{}';
CREATE TABLE payments.catalog_state(singleton boolean PRIMARY KEY DEFAULT true CHECK(singleton),catalog_hash text NOT NULL,categories jsonb NOT NULL,updated_at timestamptz NOT NULL DEFAULT now());
ALTER TABLE payments.catalog_state ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON payments.catalog_state FROM PUBLIC,goufayu_payment;

CREATE FUNCTION payments.product_block(p_account text,p_marker text,p_limit integer,p_grants jsonb,p_effects jsonb) RETURNS text
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public,pg_temp AS $$
DECLARE inventory jsonb; k text; n integer;
BEGIN
 SELECT content_inventory INTO inventory FROM public.player_archive_state WHERE account_id=p_account;
 IF p_limit>0 AND coalesce((inventory->>p_marker)::integer,0)>=p_limit THEN RETURN 'already_owned'; END IF;
 IF p_limit>0 AND NOT payments.is_test_account(p_account) AND
  (SELECT count(*) FROM payments.orders WHERE account_id=p_account AND reward->>'item_id'=p_marker AND state='delivered')>=p_limit
 THEN RETURN 'purchase_limit_reached'; END IF;
 FOR k,n IN SELECT key,value::integer FROM jsonb_each_text(p_grants->'items') LOOP
  IF coalesce((inventory->>k)::integer,0)+n>coalesce((p_grants->'item_limits'->>k)::integer,0) THEN RETURN 'component_already_owned'; END IF;
 END LOOP;
 FOR k IN SELECT jsonb_array_elements_text(p_grants->'entitlements') LOOP
  IF EXISTS(SELECT 1 FROM public.archive_entitlements WHERE account_id=p_account AND entitlement_id=k
    AND active AND starts_at<=now() AND (expires_at IS NULL OR expires_at>now())) THEN RETURN 'entitlement_already_owned'; END IF;
 END LOOP;
 IF EXISTS(SELECT 1 FROM public.player_gameplay_stats s CROSS JOIN jsonb_each_text(p_effects) e
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
  'enabled',payments.product_block(p_account,p.item_id,p.purchase_limit,p.grants,p.effects)='',
  'disabled_reason',payments.product_block(p_account,p.item_id,p.purchase_limit,p.grants,p.effects),
  'stat_preview',coalesce((SELECT jsonb_agg(jsonb_build_object('field_id',e.key,'value',(stats->>e.key)::numeric,
   'delta',e.value::numeric,'after',CASE WHEN r.maximum IS NULL THEN (stats->>e.key)::numeric+e.value::numeric
     ELSE least(r.maximum,(stats->>e.key)::numeric+e.value::numeric) END) ORDER BY e.key)
   FROM jsonb_each_text(p.effects) e JOIN payments.stat_rules r ON r.field_id=e.key),'[]')) ORDER BY p.sort_order,p.sku)
 INTO products FROM payments.products p WHERE p.enabled;
 RETURN jsonb_build_object('ok',true,'products',coalesce(products,'[]'),'categories',meta.categories,
  'catalog_hash',meta.catalog_hash,'test_reset_enabled',payments.is_test_account(p_account));
END; $$;

CREATE OR REPLACE FUNCTION payments.create_order(p_account text,p_session text,p_order text,p_sku text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public,pg_temp AS $$
DECLARE o payments.orders%rowtype; p payments.products%rowtype; c jsonb; g bigint; blocked text;
BEGIN
 PERFORM 1 FROM public.player_gameplay_stats WHERE player_id=p_account FOR UPDATE;
 PERFORM 1 FROM public.survival_players WHERE account_id=p_account FOR UPDATE;
 c:=payments.catalog(p_account,p_session); IF c ? 'error' THEN RETURN c; END IF;
 SELECT * INTO p FROM payments.products WHERE sku=p_sku AND enabled;
 IF NOT FOUND THEN RETURN jsonb_build_object('error','product_unavailable'); END IF;
 IF EXISTS(SELECT 1 FROM payments.test_accounts WHERE account_id=p_account AND reset_request IS NOT NULL)
 THEN RETURN jsonb_build_object('error','reset_in_progress'); END IF;
 SELECT * INTO o FROM payments.orders WHERE account_id=p_account AND sku=p_sku
  AND (state IN ('created','pending') OR (state='paid_review' AND cleared_at IS NULL)) ORDER BY created_at DESC LIMIT 1;
 IF FOUND THEN RETURN to_jsonb(o); END IF;
 blocked:=payments.product_block(p_account,p.item_id,p.purchase_limit,p.grants,p.effects);
 IF blocked<>'' THEN RETURN jsonb_build_object('error',blocked); END IF;
 SELECT generation INTO g FROM payments.test_accounts WHERE account_id=p_account;
 INSERT INTO payments.orders(order_id,account_id,sku,amount,reward,generation)
 VALUES(p_order,p_account,p.sku,p.amount,jsonb_build_object('item_id',p.item_id,'quantity',1,'version',4,
   'title',p.title,'description',p.description,'effects',p.effects,'grants',p.grants,'purchase_limit',p.purchase_limit,
   'catalog_hash',c->>'catalog_hash'),coalesce(g,0)) RETURNING * INTO o;
 RETURN to_jsonb(o);
END; $$;

ALTER FUNCTION payments.deliver(text,text,integer,text,text) RENAME TO deliver_v3;
CREATE FUNCTION payments.deliver(p_order text,p_transaction text,p_amount integer,p_appid text,p_mchid text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public,pg_temp AS $$
DECLARE o payments.orders%rowtype; a text; inventory jsonb; item text; k text; n integer; g bigint; applied jsonb;
 before_stats jsonb; after_stats jsonb; changes jsonb; item_grants jsonb; ent_grants jsonb:='{}'; old_ent jsonb; new_ent jsonb;
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
 SELECT content_inventory INTO inventory FROM public.player_archive_state WHERE account_id=a;
 inventory:=coalesce(inventory,'{}'); item:=o.reward->>'item_id';
 item_grants:=coalesce(o.reward#>'{grants,items}','{}')||jsonb_build_object(item,1);
 FOR k,n IN SELECT key,value::integer FROM jsonb_each_text(item_grants) LOOP
  IF n<=0 THEN RAISE EXCEPTION 'invalid_item_quantity'; END IF;
  inventory:=jsonb_set(inventory,ARRAY[k],to_jsonb(coalesce((inventory->>k)::integer,0)+n));
 END LOOP;
 INSERT INTO public.player_archive_state(account_id,content_inventory) VALUES(a,inventory)
 ON CONFLICT(account_id) DO UPDATE SET content_inventory=excluded.content_inventory;
 FOR k IN SELECT jsonb_array_elements_text(o.reward#>'{grants,entitlements}') LOOP
  IF k NOT IN ('vip','archive_pass') THEN RAISE EXCEPTION 'entitlement_not_supported'; END IF;
  SELECT to_jsonb(e) INTO old_ent FROM public.archive_entitlements e WHERE account_id=a AND entitlement_id=k;
  INSERT INTO public.archive_entitlements(account_id,entitlement_id,active,starts_at,expires_at) VALUES(a,k,true,now(),NULL)
  ON CONFLICT(account_id,entitlement_id) DO UPDATE SET active=true,starts_at=excluded.starts_at,expires_at=NULL;
  SELECT to_jsonb(e) INTO new_ent FROM public.archive_entitlements e WHERE account_id=a AND entitlement_id=k;
  ent_grants:=ent_grants||jsonb_build_object(k,jsonb_build_object('before',old_ent,'after',new_ent));
 END LOOP;
 SELECT to_jsonb(s) INTO before_stats FROM public.player_gameplay_stats s WHERE player_id=a;
 applied:=payments.apply_effects(a,o.reward->'effects');
 SELECT to_jsonb(s) INTO after_stats FROM public.player_gameplay_stats s WHERE player_id=a;
 SELECT coalesce(jsonb_object_agg(e.key,jsonb_build_object('before',(before_stats->>e.key)::numeric,
  'after',(after_stats->>e.key)::numeric,'delta',e.value::numeric)),'{}') INTO changes FROM jsonb_each_text(applied) e;
 UPDATE public.survival_players SET profile_revision=profile_revision+1,updated_at=now() WHERE account_id=a;
 UPDATE payments.orders SET state='delivered',granted_at=now(),applied_effects=applied,effect_changes=changes,
  applied_items=item_grants,applied_entitlements=ent_grants WHERE order_id=p_order;
 RETURN payments.get_order(p_order);
END; $$;

ALTER FUNCTION payments.finish_reset(text,text,text,text) RENAME TO finish_reset_v3;
CREATE FUNCTION payments.finish_reset(p_account text,p_session text,p_kind text,p_request text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public,pg_temp AS $$
DECLARE started jsonb; o payments.orders%rowtype; inventory jsonb; k text; n integer; change jsonb; current_ent jsonb; prior jsonb;
 m record; b jsonb; entitlements jsonb;
BEGIN
 started:=payments.begin_reset(p_account,p_session,p_kind,p_request);
 IF started ? 'error' OR (started->>'completed')::boolean THEN RETURN started; END IF;
 IF EXISTS(SELECT 1 FROM payments.orders WHERE account_id=p_account AND state IN ('created','pending'))
 THEN RETURN jsonb_build_object('error','pending_payment_unresolved'); END IF;
 IF p_kind='refreshmoney' THEN
  FOR o IN SELECT * FROM payments.orders WHERE account_id=p_account AND state='delivered' AND cleared_at IS NULL ORDER BY granted_at DESC LOOP
   FOR k,n IN SELECT key,value::integer FROM jsonb_each_text(o.applied_items) WHERE key<>o.reward->>'item_id' LOOP
    SELECT content_inventory INTO inventory FROM public.player_archive_state WHERE account_id=p_account;
    inventory:=jsonb_set(inventory,ARRAY[k],to_jsonb(greatest(0,coalesce((inventory->>k)::integer,0)-n)));
    IF (inventory->>k)::integer=0 THEN inventory:=inventory-k; END IF;
    UPDATE public.player_archive_state SET content_inventory=inventory WHERE account_id=p_account;
    FOR m IN SELECT match_session_id,baseline FROM public.match_profile_sessions WHERE account_id=p_account LOOP
     b:=m.baseline;inventory:=coalesce(b#>'{save,content_inventory}','{}');
     inventory:=jsonb_set(inventory,ARRAY[k],to_jsonb(greatest(0,coalesce((inventory->>k)::integer,0)-n)));
     IF (inventory->>k)::integer=0 THEN inventory:=inventory-k; END IF;
     UPDATE public.match_profile_sessions SET baseline=jsonb_set(b,'{save,content_inventory}',inventory)
      WHERE account_id=p_account AND match_session_id=m.match_session_id;
    END LOOP;
   END LOOP;
   FOR k,change IN SELECT key,value FROM jsonb_each(o.applied_entitlements) LOOP
    SELECT to_jsonb(e) INTO current_ent FROM public.archive_entitlements e WHERE account_id=p_account AND entitlement_id=k;
    IF current_ent IS NOT DISTINCT FROM change->'after' THEN
     prior:=change->'before';
     IF prior IS NULL OR prior='null'::jsonb THEN DELETE FROM public.archive_entitlements WHERE account_id=p_account AND entitlement_id=k;
     ELSE UPDATE public.archive_entitlements SET active=(prior->>'active')::boolean,starts_at=(prior->>'starts_at')::timestamptz,
      expires_at=(prior->>'expires_at')::timestamptz WHERE account_id=p_account AND entitlement_id=k; END IF;
     entitlements:=public.fishing_profile_json(p_account)->'entitlements';
     FOR m IN SELECT match_session_id,baseline FROM public.match_profile_sessions WHERE account_id=p_account LOOP
      b:=coalesce(m.baseline->'entitlements','{}')-k;
      IF entitlements ? k THEN b:=b||jsonb_build_object(k,entitlements->k); END IF;
      UPDATE public.match_profile_sessions SET baseline=jsonb_set(m.baseline,'{entitlements}',b)
       WHERE account_id=p_account AND match_session_id=m.match_session_id;
     END LOOP;
    END IF;
   END LOOP;
  END LOOP;
 END IF;
 RETURN payments.finish_reset_v3(p_account,p_session,p_kind,p_request);
END; $$;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA payments FROM PUBLIC,goufayu_payment;
GRANT EXECUTE ON FUNCTION payments.catalog(text,text),payments.create_order(text,text,text,text),payments.get_order(text),payments.pending(),
 payments.update_gateway(text,text,text),payments.deliver(text,text,integer,text,text),payments.begin_reset(text,text,text,text),payments.finish_reset(text,text,text,text) TO goufayu_payment;
