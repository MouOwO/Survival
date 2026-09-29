-- Additive upgrade. Keep every real receipt; reset only upon an authenticated
-- player's explicit command. The payment login never receives table privileges.
CREATE TABLE payments.products (
 sku text PRIMARY KEY, item_id text NOT NULL, title text NOT NULL,
 description text NOT NULL, amount integer NOT NULL CHECK(amount IN (10,5000)),
 effects jsonb NOT NULL, enabled boolean NOT NULL DEFAULT false, sort_order integer NOT NULL DEFAULT 0
);
CREATE TABLE payments.stat_rules (
 field_id text PRIMARY KEY CHECK(field_id ~ '^[a-z][a-z0-9_]*$'),
 default_value numeric NOT NULL, minimum numeric NOT NULL, maximum numeric
);
-- TODO(PAYMENT_TEST_ONLY): turn enabled off and remove reset permissions before launch.
CREATE TABLE payments.test_settings (singleton boolean PRIMARY KEY DEFAULT true CHECK(singleton), enabled boolean NOT NULL DEFAULT false);
INSERT INTO payments.test_settings(singleton,enabled) VALUES(true,false);
CREATE TABLE payments.test_accounts (
 account_id text PRIMARY KEY REFERENCES public.survival_players(account_id),
 enabled boolean NOT NULL DEFAULT false, generation bigint NOT NULL DEFAULT 0,
 reset_request text, reset_kind text
);
CREATE TABLE payments.test_resets (
 account_id text NOT NULL, request_id text NOT NULL, kind text NOT NULL,
 result jsonb NOT NULL, created_at timestamptz NOT NULL DEFAULT now(),
 PRIMARY KEY(account_id,request_id)
);
CREATE TABLE payments.cleared_reward_grants (
 grant_id uuid PRIMARY KEY REFERENCES public.reward_grants(grant_id),
 cleared_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE payments.orders DROP CONSTRAINT orders_sku_check;
ALTER TABLE payments.orders DROP CONSTRAINT orders_amount_check;
ALTER TABLE payments.orders ADD CONSTRAINT orders_amount_check CHECK(amount IN (10,5000));
ALTER TABLE payments.orders ADD COLUMN generation bigint NOT NULL DEFAULT 0;
ALTER TABLE payments.orders ADD COLUMN applied_effects jsonb NOT NULL DEFAULT '{}';
ALTER TABLE payments.orders ADD COLUMN cleared_at timestamptz;
DROP INDEX payments.one_open_monkey_order;
CREATE UNIQUE INDEX one_open_product_order ON payments.orders(account_id,sku)
 WHERE state IN ('created','pending') OR (state='paid_review' AND cleared_at IS NULL);

CREATE FUNCTION payments.is_test_account(p_account text) RETURNS boolean
LANGUAGE sql SECURITY DEFINER SET search_path=pg_catalog,public,pg_temp AS $$
 SELECT coalesce((SELECT s.enabled AND a.enabled FROM payments.test_settings s
  JOIN payments.test_accounts a ON a.account_id=p_account WHERE s.singleton),false);
$$;

CREATE OR REPLACE FUNCTION payments.catalog(p_account text,p_session text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public,pg_temp AS $$
DECLARE inventory jsonb; products jsonb;
BEGIN
 IF NOT EXISTS(SELECT 1 FROM public.match_profile_sessions WHERE account_id=p_account AND match_session_id=p_session)
 THEN RETURN jsonb_build_object('error','match_session_missing'); END IF;
 SELECT content_inventory INTO inventory FROM public.player_archive_state WHERE account_id=p_account;
 SELECT jsonb_agg(jsonb_build_object('sku',p.sku,'item_id',p.item_id,'title',p.title,
  'description',p.description,'amount_fen',p.amount,'owned',coalesce((inventory->>p.item_id)::integer,0),
  'enabled',coalesce((inventory->>p.item_id)::integer,0)<1 AND
    (payments.is_test_account(p_account) OR NOT EXISTS(SELECT 1 FROM payments.orders o
      WHERE o.account_id=p_account AND o.reward->>'item_id'=p.item_id AND o.state='delivered')))
  ORDER BY p.sort_order) INTO products FROM payments.products p WHERE p.enabled;
 RETURN jsonb_build_object('ok',true,'products',coalesce(products,'[]'),
  'test_reset_enabled',payments.is_test_account(p_account));
END; $$;

DROP FUNCTION payments.create_order(text,text,text);
CREATE FUNCTION payments.create_order(p_account text,p_session text,p_order text,p_sku text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public,pg_temp AS $$
DECLARE o payments.orders%rowtype; p payments.products%rowtype; c jsonb; g bigint;
BEGIN
 PERFORM 1 FROM public.player_gameplay_stats WHERE player_id=p_account FOR UPDATE;
 PERFORM 1 FROM public.survival_players WHERE account_id=p_account FOR UPDATE;
 c:=payments.catalog(p_account,p_session);
 IF c ? 'error' THEN RETURN c; END IF;
 SELECT * INTO p FROM payments.products WHERE sku=p_sku AND enabled;
 IF NOT FOUND THEN RETURN jsonb_build_object('error','product_unavailable'); END IF;
 IF EXISTS(SELECT 1 FROM payments.test_accounts WHERE account_id=p_account AND reset_request IS NOT NULL)
 THEN RETURN jsonb_build_object('error','reset_in_progress'); END IF;
 SELECT * INTO o FROM payments.orders WHERE account_id=p_account AND sku=p_sku
  AND (state IN ('created','pending') OR (state='paid_review' AND cleared_at IS NULL)) ORDER BY created_at DESC LIMIT 1;
 IF FOUND THEN RETURN to_jsonb(o); END IF;
 IF EXISTS(SELECT 1 FROM public.player_archive_state WHERE account_id=p_account
   AND coalesce((content_inventory->>p.item_id)::integer,0)>=1)
 THEN RETURN jsonb_build_object('error','already_owned'); END IF;
 -- TODO(PAYMENT_TEST_ONLY): the explicit test gate alone permits repurchase.
 IF NOT payments.is_test_account(p_account) AND EXISTS(SELECT 1 FROM payments.orders
  WHERE account_id=p_account AND reward->>'item_id'=p.item_id AND state='delivered')
 THEN RETURN jsonb_build_object('error','purchase_limit_reached'); END IF;
 SELECT generation INTO g FROM payments.test_accounts WHERE account_id=p_account;
 INSERT INTO payments.orders(order_id,account_id,sku,amount,reward,generation)
 VALUES(p_order,p_account,p.sku,p.amount,jsonb_build_object('item_id',p.item_id,'quantity',1,
  'version',2,'title',p.title,'description',p.description,'effects',p.effects),coalesce(g,0)) RETURNING * INTO o;
 RETURN to_jsonb(o);
END; $$;

-- Internal helper: exact applied deltas are recorded, including clamped stats.
-- Never grant the payment role EXECUTE on this generic mutation routine.
CREATE FUNCTION payments.apply_effects(p_account text,p_effects jsonb,p_remove boolean DEFAULT false) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public,pg_temp AS $$
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
END; $$;

CREATE OR REPLACE FUNCTION payments.deliver(p_order text,p_transaction text,p_amount integer,p_appid text,p_mchid text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public,pg_temp AS $$
DECLARE o payments.orders%rowtype; a text; inventory jsonb; item text; applied jsonb; g bigint;
BEGIN
 SELECT account_id INTO a FROM payments.orders WHERE order_id=p_order;
 IF a IS NULL THEN RETURN jsonb_build_object('error','order_missing'); END IF;
 PERFORM 1 FROM public.player_gameplay_stats WHERE player_id=a FOR UPDATE;
 PERFORM 1 FROM public.survival_players WHERE account_id=a FOR UPDATE;
 SELECT * INTO o FROM payments.orders WHERE order_id=p_order FOR UPDATE;
 IF p_amount IS DISTINCT FROM o.amount OR p_appid IS DISTINCT FROM o.appid OR p_mchid IS DISTINCT FROM o.mchid
   OR p_transaction IS NULL OR p_transaction !~ '^[0-9]{20,64}$' THEN RAISE EXCEPTION 'payment_mismatch'; END IF;
 IF o.transaction_id IS NOT NULL AND o.transaction_id<>p_transaction THEN RAISE EXCEPTION 'transaction_conflict'; END IF;
 -- Historical callbacks must never restore a cleared reward.
 IF o.state IN ('delivered','paid_review') THEN RETURN to_jsonb(o); END IF;
 SELECT content_inventory INTO inventory FROM public.player_archive_state WHERE account_id=a;
 inventory:=coalesce(inventory,'{}'); item:=o.reward->>'item_id';
 SELECT generation INTO g FROM payments.test_accounts WHERE account_id=a;
 UPDATE payments.orders SET transaction_id=p_transaction,paid_at=now(),checked_at=now() WHERE order_id=p_order;
 IF o.generation<>coalesce(g,0) OR coalesce((inventory->>item)::integer,0)>=1 THEN
  UPDATE payments.orders SET state='paid_review',cleared_at=CASE WHEN o.generation<>coalesce(g,0) THEN now() ELSE NULL END WHERE order_id=p_order;
  RETURN payments.get_order(p_order);
 END IF;
 IF jsonb_typeof(o.reward->'effects') IS DISTINCT FROM 'object' THEN RAISE EXCEPTION 'payment_effects_missing'; END IF;
 INSERT INTO public.player_archive_state(account_id,content_inventory)
 VALUES(a,jsonb_set(inventory,ARRAY[item],'1'))
 ON CONFLICT(account_id) DO UPDATE SET content_inventory=excluded.content_inventory;
 applied:=payments.apply_effects(a,o.reward->'effects');
 UPDATE public.survival_players SET profile_revision=profile_revision+1,updated_at=now() WHERE account_id=a;
 UPDATE payments.orders SET state='delivered',granted_at=now(),applied_effects=applied WHERE order_id=p_order;
 RETURN payments.get_order(p_order);
END; $$;

CREATE FUNCTION payments.begin_reset(p_account text,p_session text,p_kind text,p_request text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public,pg_temp AS $$
DECLARE c jsonb; previous payments.test_resets%rowtype; a payments.test_accounts%rowtype;
BEGIN
 IF NOT payments.is_test_account(p_account) THEN RETURN jsonb_build_object('error','test_reset_disabled'); END IF;
 IF p_kind NOT IN ('refreshdata','refreshmoney') OR p_request !~ '^[A-Za-z0-9_.:-]{8,128}$'
 THEN RETURN jsonb_build_object('error','reset_invalid'); END IF;
 PERFORM 1 FROM public.player_gameplay_stats WHERE player_id=p_account FOR UPDATE;
 PERFORM 1 FROM public.survival_players WHERE account_id=p_account FOR UPDATE;
 c:=payments.catalog(p_account,p_session); IF c ? 'error' THEN RETURN c; END IF;
 SELECT * INTO previous FROM payments.test_resets WHERE account_id=p_account AND request_id=p_request;
 IF FOUND THEN
  IF previous.kind<>p_kind THEN RETURN jsonb_build_object('error','reset_request_conflict'); END IF;
  RETURN previous.result||jsonb_build_object('completed',true);
 END IF;
 SELECT * INTO a FROM payments.test_accounts WHERE account_id=p_account FOR UPDATE;
 IF a.reset_request IS NOT NULL AND (a.reset_request<>p_request OR a.reset_kind<>p_kind)
 THEN RETURN jsonb_build_object('error','reset_in_progress'); END IF;
 UPDATE payments.test_accounts SET reset_request=p_request,reset_kind=p_kind WHERE account_id=p_account;
 RETURN jsonb_build_object('ok',true,'completed',false,'orders',coalesce((SELECT jsonb_agg(to_jsonb(o))
  FROM payments.orders o WHERE account_id=p_account AND state IN ('created','pending')),'[]'));
END; $$;

CREATE FUNCTION payments.finish_reset(p_account text,p_session text,p_kind text,p_request text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public,pg_temp AS $$
DECLARE start_result jsonb; o payments.orders%rowtype; r payments.stat_rules%rowtype;
 result jsonb; revision bigint; reset_items jsonb:='[]'; next_baseline jsonb; m record; k text; v numeric;
BEGIN
 start_result:=payments.begin_reset(p_account,p_session,p_kind,p_request);
 IF start_result ? 'error' OR (start_result->>'completed')::boolean THEN RETURN start_result; END IF;
 IF EXISTS(SELECT 1 FROM payments.orders WHERE account_id=p_account AND state IN ('created','pending'))
 THEN RETURN jsonb_build_object('error','pending_payment_unresolved'); END IF;
 FOR o IN SELECT * FROM payments.orders WHERE account_id=p_account AND state='delivered' AND cleared_at IS NULL LOOP
  reset_items:=reset_items||jsonb_build_array(o.reward->>'item_id');
  IF p_kind='refreshmoney' THEN
   UPDATE public.player_archive_state SET content_inventory=content_inventory-(o.reward->>'item_id') WHERE account_id=p_account;
   PERFORM payments.apply_effects(p_account,o.applied_effects,true);
   -- Pure-mode baselines lose only the cleared contribution; other match gains survive.
   FOR m IN SELECT match_session_id,baseline FROM public.match_profile_sessions WHERE account_id=p_account LOOP
    next_baseline:=m.baseline;
    next_baseline:=jsonb_set(next_baseline,'{save,content_inventory}',coalesce(next_baseline#>'{save,content_inventory}','{}')-(o.reward->>'item_id'));
    FOR k,v IN SELECT key,value::numeric FROM jsonb_each_text(o.applied_effects) LOOP
     SELECT * INTO r FROM payments.stat_rules WHERE field_id=k;
     next_baseline:=jsonb_set(next_baseline,ARRAY['save','gameplay_stats',k],to_jsonb(greatest(r.default_value,
      coalesce((next_baseline#>>ARRAY['save','gameplay_stats',k])::numeric,r.default_value)-v)));
    END LOOP;
    UPDATE public.match_profile_sessions s SET baseline=next_baseline WHERE s.account_id=p_account AND s.match_session_id=m.match_session_id;
   END LOOP;
  END IF;
 END LOOP;
 IF p_kind='refreshdata' THEN
  UPDATE public.player_archive_state SET archive='{}',content_inventory='{}' WHERE account_id=p_account;
  DELETE FROM public.archive_entitlements WHERE account_id=p_account;
  DELETE FROM public.player_effect_totals WHERE account_id=p_account;
  INSERT INTO payments.cleared_reward_grants(grant_id) SELECT grant_id FROM public.reward_grants WHERE account_id=p_account ON CONFLICT DO NOTHING;
  FOR r IN SELECT * FROM payments.stat_rules LOOP
   EXECUTE format('UPDATE public.player_gameplay_stats SET %I=$1,updated_at=now() WHERE player_id=$2',r.field_id) USING r.default_value,p_account;
  END LOOP;
  DELETE FROM public.archive_online_outbox WHERE account_id=p_account;
  UPDATE public.archive_operations SET done=true,error='test_account_reset',response=NULL WHERE account_id=p_account AND NOT done;
  -- Retain idempotency tombstones and online cursors so delayed retries cannot regrant old rewards.
 END IF;
 UPDATE payments.orders SET cleared_at=now() WHERE account_id=p_account AND state IN ('delivered','paid_review') AND cleared_at IS NULL;
 UPDATE payments.test_accounts SET generation=generation+1,reset_request=NULL,reset_kind=NULL WHERE account_id=p_account;
 UPDATE public.survival_players SET profile_revision=profile_revision+1,updated_at=now() WHERE account_id=p_account RETURNING profile_revision INTO revision;
 IF p_kind='refreshdata' THEN
  UPDATE public.match_profile_sessions SET baseline=public.fishing_profile_json(p_account) WHERE account_id=p_account;
 END IF;
 result:=jsonb_build_object('ok',true,'kind',p_kind,'request_id',p_request,'revision',revision,'cleared_items',reset_items);
 INSERT INTO payments.test_resets(account_id,request_id,kind,result) VALUES(p_account,p_request,p_kind,result);
 RETURN result;
END; $$;

ALTER TABLE payments.products ENABLE ROW LEVEL SECURITY;
ALTER TABLE payments.stat_rules ENABLE ROW LEVEL SECURITY;
ALTER TABLE payments.test_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE payments.test_accounts ENABLE ROW LEVEL SECURITY;
ALTER TABLE payments.test_resets ENABLE ROW LEVEL SECURITY;
ALTER TABLE payments.cleared_reward_grants ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON ALL TABLES IN SCHEMA payments FROM PUBLIC,goufayu_payment;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA payments FROM PUBLIC,goufayu_payment;
GRANT EXECUTE ON FUNCTION payments.catalog(text,text),payments.create_order(text,text,text,text),
 payments.get_order(text),payments.pending(),payments.update_gateway(text,text,text),payments.deliver(text,text,integer,text,text),
 payments.begin_reset(text,text,text,text),payments.finish_reset(text,text,text,text) TO goufayu_payment;
