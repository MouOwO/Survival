-- Apply after upgrade_order_quantity.sql, inside the operator's transaction.
-- Only the fixed recharge SKU gets the larger count/amount. Existing products,
-- orders, gateway identities and archived reward snapshots are never rewritten.
DO $prerequisites$
BEGIN
 IF to_regprocedure('payments.validate_order_quantity_snapshot(jsonb,integer)') IS NULL
    OR to_regprocedure('payments.catalog_pre_quantity(text,text)') IS NULL
    OR to_regclass('payments.vip_recharge_credits') IS NULL
 THEN RAISE EXCEPTION 'ucoin_recharge_prerequisite_missing'; END IF;
END; $prerequisites$;

ALTER TABLE payments.orders DROP CONSTRAINT IF EXISTS orders_amount_check;
ALTER TABLE payments.orders ADD CONSTRAINT orders_amount_check CHECK(
 (sku='u_coin_recharge' AND amount BETWEEN 100 AND 99999900)
 OR (sku<>'u_coin_recharge' AND amount BETWEEN 1 AND 1000000));

DO $save_helpers$
BEGIN
 IF to_regprocedure('payments.receipt_quantity_pre_recharge(jsonb)') IS NULL THEN
  ALTER FUNCTION payments.receipt_quantity(jsonb) RENAME TO receipt_quantity_pre_recharge;
  ALTER FUNCTION payments.validate_order_quantity_snapshot(jsonb,integer) RENAME TO validate_order_quantity_snapshot_pre_recharge;
  ALTER FUNCTION payments.catalog(text,text) RENAME TO catalog_pre_recharge;
  ALTER FUNCTION payments.create_order_quantity(text,text,text,text,text,integer) RENAME TO create_order_quantity_pre_recharge;
  ALTER FUNCTION payments.deliver(text,text,integer,text,text) RENAME TO deliver_pre_recharge;
 END IF;
END; $save_helpers$;

CREATE OR REPLACE FUNCTION payments.receipt_quantity(p_reward jsonb) RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public,pg_temp AS $$
DECLARE n numeric;
BEGIN
 IF p_reward->'version' IS DISTINCT FROM '6'::jsonb THEN RETURN payments.receipt_quantity_pre_recharge(p_reward); END IF;
 IF jsonb_typeof(p_reward->'quantity') IS DISTINCT FROM 'number' THEN RAISE EXCEPTION 'quantity_snapshot_invalid'; END IF;
 n:=(p_reward->>'quantity')::numeric;
 IF n<>trunc(n) OR n NOT BETWEEN 1 AND 999999 THEN RAISE EXCEPTION 'quantity_snapshot_invalid'; END IF;
 RETURN n::integer;
END; $$;

CREATE OR REPLACE FUNCTION payments.validate_order_quantity_snapshot(p_reward jsonb,p_amount integer) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public,pg_temp AS $$
DECLARE n integer; expected jsonb;
BEGIN
 IF p_reward->>'item_id'='u_coin_recharge_receipt' AND p_reward->'version' IS DISTINCT FROM '6'::jsonb
 THEN RAISE EXCEPTION 'quantity_snapshot_invalid'; END IF;
 IF p_reward->'version' IS DISTINCT FROM '6'::jsonb THEN
  PERFORM payments.validate_order_quantity_snapshot_pre_recharge(p_reward,p_amount); RETURN;
 END IF;
 n:=payments.receipt_quantity(p_reward);
 expected:=jsonb_build_object('items','{}'::jsonb,'item_limits','{}'::jsonb,'entitlements','[]'::jsonb,'effect_labels','{}'::jsonb,
  'lines',jsonb_build_array(jsonb_build_object('kind','wallet','id','u_coin','quantity',n::bigint*100,'label','U币')),
  'pricing',jsonb_build_object('u_coin_price',n::bigint*1000,'u_coin_per_yuan',1000),'recharge_u_coin_per_unit',100);
 IF p_reward->>'item_id' IS DISTINCT FROM 'u_coin_recharge_receipt'
  OR p_reward->>'product_type' IS DISTINCT FROM 'recharge'
  OR p_reward->'recharge_u_coin_per_unit' IS DISTINCT FROM '100'::jsonb
  OR p_reward->'unit_amount_fen' IS DISTINCT FROM '100'::jsonb
  OR p_reward->'purchase_limit' IS DISTINCT FROM '0'::jsonb
  OR p_reward->'effects' IS DISTINCT FROM '{}'::jsonb
  OR p_reward->'unit_pricing' IS DISTINCT FROM '{"u_coin_price":1000,"u_coin_per_yuan":1000}'::jsonb
  OR p_reward->'grants' IS DISTINCT FROM expected
  OR p_amount IS NULL OR p_amount<>n::bigint*100
 THEN RAISE EXCEPTION 'quantity_snapshot_invalid'; END IF;
END; $$;

CREATE OR REPLACE FUNCTION payments.recharge_wallet_balance(p_account text) RETURNS bigint
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public,pg_temp AS $$
DECLARE archive jsonb; wallet jsonb; n numeric;
BEGIN
 SELECT a.archive INTO archive FROM public.player_archive_state a WHERE account_id=p_account;
 archive:=coalesce(archive,'{}');
 IF jsonb_typeof(archive) IS DISTINCT FROM 'object'
  OR (archive ? 'commerce' AND jsonb_typeof(archive->'commerce') IS DISTINCT FROM 'object')
  OR (archive#>'{commerce,balances}' IS NOT NULL AND jsonb_typeof(archive#>'{commerce,balances}') IS DISTINCT FROM 'object')
 THEN RAISE EXCEPTION 'commerce_wallet_invalid'; END IF;
 wallet:=archive#>'{commerce,balances,u_coin}';
 IF wallet IS NULL THEN RETURN 0; END IF;
 IF jsonb_typeof(wallet) IS DISTINCT FROM 'number' THEN RAISE EXCEPTION 'commerce_wallet_invalid'; END IF;
 n:=(wallet#>>'{}')::numeric;
 IF n<>trunc(n) OR n NOT BETWEEN 0 AND 9007199254740991 THEN RAISE EXCEPTION 'commerce_wallet_invalid'; END IF;
 RETURN n::bigint;
END; $$;

CREATE OR REPLACE FUNCTION payments.catalog(p_account text,p_session text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public,pg_temp AS $$
DECLARE result jsonb; products jsonb; maximum integer;
BEGIN
 result:=payments.catalog_pre_recharge(p_account,p_session);
 IF result ? 'error' THEN RETURN result; END IF;
 maximum:=greatest(0,least(999999,(9007199254740991-payments.recharge_wallet_balance(p_account))/100))::integer;
 SELECT coalesce(jsonb_agg(CASE WHEN e.product->>'sku'='u_coin_recharge' THEN
  e.product||jsonb_build_object('product_type','recharge','recharge_u_coin_per_unit',100,'max_quantity',maximum,
   'enabled',maximum>0,'disabled_reason',CASE WHEN maximum=0 THEN 'wallet_limit_reached' ELSE '' END)
  ELSE e.product END ORDER BY e.ordinality),'[]') INTO products
 FROM jsonb_array_elements(result->'products') WITH ORDINALITY e(product,ordinality);
 RETURN jsonb_set(result,'{products}',products);
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
  '{"items":{},"item_limits":{},"entitlements":[],"effect_labels":{},"lines":[{"kind":"wallet","id":"u_coin","quantity":100,"label":"U币"}],"pricing":{"u_coin_price":1000,"u_coin_per_yuan":1000},"recharge_u_coin_per_unit":100}'::jsonb
 THEN RETURN jsonb_build_object('error','product_unavailable'); END IF;
 wallet:=payments.recharge_wallet_balance(p_account);
 IF wallet+p_quantity::bigint*100>9007199254740991 THEN RETURN jsonb_build_object('error','wallet_limit_reached'); END IF;
 grants:=jsonb_set(p.grants,'{lines,0,quantity}',to_jsonb(p_quantity::bigint*100));
 grants:=jsonb_set(grants,'{pricing,u_coin_price}',to_jsonb(p_quantity::bigint*1000));
 reward:=jsonb_build_object('item_id',p.item_id,'quantity',p_quantity,'version',6,'unit_amount_fen',100,
  'unit_pricing',p.grants->'pricing','product_type','recharge','recharge_u_coin_per_unit',100,
  'title',p.title,'description',p.description,'effects','{}'::jsonb,'grants',grants,'purchase_limit',0,'catalog_hash',c->>'catalog_hash');
 PERFORM payments.validate_order_quantity_snapshot(reward,p_quantity*100);
 SELECT generation INTO g FROM payments.test_accounts WHERE account_id=p_account;
 INSERT INTO payments.orders(order_id,account_id,sku,amount,reward,generation,provider,appid,mchid)
 VALUES(p_order,p_account,p.sku,p_quantity*100,reward,coalesce(g,0),channel.provider,channel.appid,channel.mchid) RETURNING * INTO o;
 RETURN to_jsonb(o);
END; $$;

CREATE OR REPLACE FUNCTION payments.deliver(p_order text,p_transaction text,p_amount integer,p_appid text,p_mchid text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public,pg_temp AS $$
DECLARE o payments.orders%rowtype; a text; g bigint; archive jsonb; commerce jsonb; balances jsonb; before_balance bigint; after_balance bigint; delta bigint;
BEGIN
 SELECT * INTO o FROM payments.orders WHERE order_id=p_order;
 IF NOT FOUND THEN RETURN jsonb_build_object('error','order_missing'); END IF;
 IF o.sku<>'u_coin_recharge' THEN RETURN payments.deliver_pre_recharge(p_order,p_transaction,p_amount,p_appid,p_mchid); END IF;
 a:=o.account_id;
 PERFORM 1 FROM public.player_gameplay_stats WHERE player_id=a FOR UPDATE;
 PERFORM 1 FROM public.survival_players WHERE account_id=a FOR UPDATE;
 SELECT * INTO o FROM payments.orders WHERE order_id=p_order FOR UPDATE;
 PERFORM payments.validate_order_quantity_snapshot(o.reward,o.amount);
 IF o.reward->'version' IS DISTINCT FROM '6'::jsonb OR o.currency<>'CNY'
  OR p_amount IS DISTINCT FROM o.amount OR p_appid IS DISTINCT FROM o.appid OR p_mchid IS DISTINCT FROM o.mchid
  OR p_transaction IS NULL OR p_transaction !~ '^[0-9]{20,64}$' THEN RAISE EXCEPTION 'payment_mismatch'; END IF;
 IF o.transaction_id IS NOT NULL AND o.transaction_id<>p_transaction THEN RAISE EXCEPTION 'transaction_conflict'; END IF;
 IF o.state IN ('delivered','paid_review') THEN RETURN to_jsonb(o); END IF;
 SELECT generation INTO g FROM payments.test_accounts WHERE account_id=a;
 UPDATE payments.orders SET transaction_id=p_transaction,paid_at=now(),checked_at=now() WHERE order_id=p_order;
 IF o.generation<>coalesce(g,0) THEN
  UPDATE payments.orders SET state='paid_review',cleared_at=now() WHERE order_id=p_order;
  RETURN payments.get_order(p_order);
 END IF;
 SELECT s.archive INTO archive FROM public.player_archive_state s WHERE account_id=a FOR UPDATE;
 before_balance:=payments.recharge_wallet_balance(a);delta:=payments.receipt_quantity(o.reward)::bigint*100;
 IF before_balance+delta>9007199254740991 THEN
  UPDATE payments.orders SET state='paid_review' WHERE order_id=p_order;RETURN payments.get_order(p_order);
 END IF;
 archive:=coalesce(archive,'{}');commerce:=coalesce(archive->'commerce','{}');balances:=coalesce(commerce->'balances','{}');
 after_balance:=before_balance+delta;
 balances:=balances||jsonb_build_object('u_coin',after_balance);
 commerce:=commerce||jsonb_build_object('balances',balances);
 archive:=archive||jsonb_build_object('commerce',commerce);
 INSERT INTO public.player_archive_state(account_id,archive) VALUES(a,archive)
 ON CONFLICT(account_id) DO UPDATE SET archive=excluded.archive;
 UPDATE public.survival_players SET profile_revision=profile_revision+1,updated_at=now() WHERE account_id=a;
 UPDATE payments.orders SET state='delivered',granted_at=clock_timestamp(),applied_effects='{}',effect_changes='{}',
  applied_items='{}',applied_entitlements='{}',
  applied_archive=jsonb_build_object('u_coin_recharge',jsonb_build_object('before',before_balance,'after',after_balance,'delta',delta))
 WHERE order_id=p_order;
 RETURN payments.get_order(p_order);
END; $$;

-- Test-only money resets subtract unspent recharge value once; preserve other
-- currencies and unrelated archive fields. Real accounts cannot invoke resets.
DO $save_reset$
BEGIN
 IF to_regprocedure('payments.finish_reset_pre_recharge(text,text,text,text)') IS NULL THEN
  ALTER FUNCTION payments.finish_reset(text,text,text,text) RENAME TO finish_reset_pre_recharge;
 END IF;
END; $save_reset$;
CREATE OR REPLACE FUNCTION payments.finish_reset(p_account text,p_session text,p_kind text,p_request text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public,pg_temp AS $$
DECLARE started jsonb; delta bigint; new_archive jsonb; wallet bigint; m record; new_baseline jsonb; old_wallet bigint;
BEGIN
 started:=payments.begin_reset(p_account,p_session,p_kind,p_request);
 IF started ? 'error' OR (started->>'completed')::boolean THEN RETURN started; END IF;
 IF EXISTS(SELECT 1 FROM payments.orders WHERE account_id=p_account AND state IN ('created','pending'))
 THEN RETURN jsonb_build_object('error','pending_payment_unresolved'); END IF;
 IF p_kind='refreshmoney' THEN
  SELECT coalesce(sum((o.applied_archive#>>'{u_coin_recharge,delta}')::bigint),0) INTO delta
  FROM payments.orders o WHERE o.account_id=p_account AND o.state='delivered' AND o.cleared_at IS NULL
   AND o.sku='u_coin_recharge';
  IF delta>0 THEN
   wallet:=payments.recharge_wallet_balance(p_account);
   SELECT s.archive INTO new_archive FROM public.player_archive_state s WHERE account_id=p_account FOR UPDATE;
   new_archive:=jsonb_set(new_archive,'{commerce,balances,u_coin}',to_jsonb(greatest(0,wallet-delta)));
   UPDATE public.player_archive_state SET archive=new_archive WHERE account_id=p_account;
   FOR m IN SELECT match_session_id,baseline FROM public.match_profile_sessions WHERE account_id=p_account LOOP
    new_baseline:=m.baseline;old_wallet:=coalesce((new_baseline#>>'{save,archive,commerce,balances,u_coin}')::bigint,0);
    IF new_baseline#>'{save,archive,commerce,balances,u_coin}' IS NOT NULL THEN
     new_baseline:=jsonb_set(new_baseline,'{save,archive,commerce,balances,u_coin}',to_jsonb(greatest(0,old_wallet-delta)));
     UPDATE public.match_profile_sessions SET baseline=new_baseline WHERE account_id=p_account AND match_session_id=m.match_session_id;
    END IF;
   END LOOP;
  END IF;
 END IF;
 RETURN payments.finish_reset_pre_recharge(p_account,p_session,p_kind,p_request);
END; $$;

REVOKE ALL ON FUNCTION payments.receipt_quantity_pre_recharge(jsonb),payments.validate_order_quantity_snapshot_pre_recharge(jsonb,integer),
 payments.catalog_pre_recharge(text,text),payments.create_order_quantity_pre_recharge(text,text,text,text,text,integer),
 payments.deliver_pre_recharge(text,text,integer,text,text),payments.finish_reset_pre_recharge(text,text,text,text),
 payments.recharge_wallet_balance(text),payments.receipt_quantity(jsonb),payments.validate_order_quantity_snapshot(jsonb,integer)
 FROM PUBLIC,goufayu_payment;
REVOKE ALL ON FUNCTION payments.catalog(text,text),payments.create_order_quantity(text,text,text,text,text,integer),
 payments.deliver(text,text,integer,text,text),payments.finish_reset(text,text,text,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION payments.catalog(text,text),payments.create_order_quantity(text,text,text,text,text,integer),
 payments.deliver(text,text,integer,text,text),payments.finish_reset(text,text,text,text) TO goufayu_payment;
