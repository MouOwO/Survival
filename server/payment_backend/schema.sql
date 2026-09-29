-- Run as goufayu_owner; the payment login has no direct table privileges.
-- This schema deliberately does not change the existing game RPC allowlist.
CREATE SCHEMA IF NOT EXISTS payments AUTHORIZATION goufayu_owner;
REVOKE ALL ON SCHEMA payments FROM PUBLIC;
CREATE TABLE payments.orders (
 order_id text PRIMARY KEY CHECK(order_id ~ '^WX[0-9a-f]{30}$'),
 account_id text NOT NULL REFERENCES public.survival_players(account_id),
 sku text NOT NULL DEFAULT 'monkey_test_010_v1' CHECK(sku='monkey_test_010_v1'),
 amount integer NOT NULL DEFAULT 10 CHECK(amount=10),
 currency text NOT NULL DEFAULT 'CNY' CHECK(currency='CNY'),
 appid text NOT NULL DEFAULT 'wx164e25a570fb636a' CHECK(appid='wx164e25a570fb636a'),
 mchid text NOT NULL DEFAULT '1117928493' CHECK(mchid='1117928493'),
 reward jsonb NOT NULL DEFAULT '{"item_id":"lottery_monkey_king","quantity":1,"version":1}',
 state text NOT NULL DEFAULT 'created' CHECK(state IN ('created','pending','delivered','paid_review','closed')),
 code_url text, transaction_id text UNIQUE,
 created_at timestamptz NOT NULL DEFAULT now(), expires_at timestamptz NOT NULL DEFAULT now()+interval '30 minutes',
 checked_at timestamptz, paid_at timestamptz, granted_at timestamptz
);
CREATE UNIQUE INDEX one_open_monkey_order ON payments.orders(account_id,sku)
 WHERE state IN ('created','pending','paid_review');
ALTER TABLE payments.orders ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON ALL TABLES IN SCHEMA payments FROM PUBLIC;

CREATE FUNCTION payments.catalog(p_account text,p_session text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public,pg_temp AS $$
BEGIN
 IF NOT EXISTS(SELECT 1 FROM public.match_profile_sessions WHERE account_id=p_account AND match_session_id=p_session)
 THEN RETURN jsonb_build_object('error','match_session_missing'); END IF;
 RETURN jsonb_build_object('ok',true,'owned',coalesce((SELECT (content_inventory->>'lottery_monkey_king')::integer
   FROM public.player_archive_state WHERE account_id=p_account),0));
END; $$;

CREATE FUNCTION payments.create_order(p_account text,p_session text,p_order text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public,pg_temp AS $$
DECLARE o payments.orders%rowtype; c jsonb;
BEGIN
 -- Same lock order as archive_commit_lottery and online checkpoints.
 PERFORM 1 FROM public.player_gameplay_stats WHERE player_id=p_account FOR UPDATE;
 PERFORM 1 FROM public.survival_players WHERE account_id=p_account FOR UPDATE;
 c:=payments.catalog(p_account,p_session);
 IF c ? 'error' THEN RETURN c; END IF;
 SELECT * INTO o FROM payments.orders WHERE account_id=p_account AND state IN ('created','pending','paid_review') ORDER BY created_at DESC LIMIT 1;
 IF FOUND THEN RETURN to_jsonb(o); END IF;
 IF (c->>'owned')::integer>=1 THEN RETURN jsonb_build_object('error','already_owned'); END IF;
 INSERT INTO payments.orders(order_id,account_id) VALUES(p_order,p_account) RETURNING * INTO o;
 RETURN to_jsonb(o);
END; $$;

CREATE FUNCTION payments.get_order(p_order text) RETURNS jsonb
LANGUAGE sql SECURITY DEFINER SET search_path=pg_catalog,public,pg_temp AS $$
 SELECT coalesce((SELECT to_jsonb(o) FROM payments.orders o WHERE order_id=p_order),'{"error":"order_missing"}'::jsonb);
$$;

CREATE FUNCTION payments.pending() RETURNS jsonb
LANGUAGE sql SECURITY DEFINER SET search_path=pg_catalog,public,pg_temp AS $$
 SELECT coalesce(jsonb_agg(to_jsonb(o)),'[]'::jsonb) FROM (
  SELECT * FROM payments.orders WHERE state IN ('created','pending')
   AND (checked_at IS NULL OR checked_at<now()-interval '15 seconds') ORDER BY checked_at NULLS FIRST,created_at LIMIT 20
 ) o;
$$;

CREATE FUNCTION payments.update_gateway(p_order text,p_state text,p_code text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public,pg_temp AS $$
BEGIN
 IF p_state NOT IN ('checked','pending','closed') THEN RAISE EXCEPTION 'gateway_state_invalid'; END IF;
 IF p_state='pending' AND (p_code IS NULL OR p_code !~ '^weixin://wxpay/bizpayurl\?' OR length(p_code)>2048)
 THEN RAISE EXCEPTION 'code_url_invalid'; END IF;
 UPDATE payments.orders SET checked_at=now(),
   state=CASE WHEN p_state='checked' THEN state ELSE p_state END,
   code_url=CASE WHEN p_state='pending' THEN p_code ELSE code_url END
 WHERE order_id=p_order AND state IN ('created','pending');
 RETURN payments.get_order(p_order);
END; $$;

CREATE FUNCTION payments.deliver(p_order text,p_transaction text,p_amount integer,p_appid text,p_mchid text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public,pg_temp AS $$
DECLARE o payments.orders%rowtype; a text; inventory jsonb;
BEGIN
 SELECT account_id INTO a FROM payments.orders WHERE order_id=p_order;
 IF a IS NULL THEN RETURN jsonb_build_object('error','order_missing'); END IF;
 PERFORM 1 FROM public.player_gameplay_stats WHERE player_id=a FOR UPDATE;
 PERFORM 1 FROM public.survival_players WHERE account_id=a FOR UPDATE;
 SELECT * INTO o FROM payments.orders WHERE order_id=p_order FOR UPDATE;
 IF p_amount IS DISTINCT FROM o.amount OR p_appid IS DISTINCT FROM o.appid OR p_mchid IS DISTINCT FROM o.mchid
   OR p_transaction IS NULL OR p_transaction !~ '^[0-9]{20,64}$'
 THEN RAISE EXCEPTION 'payment_mismatch'; END IF;
 IF o.transaction_id IS NOT NULL AND o.transaction_id<>p_transaction THEN RAISE EXCEPTION 'transaction_conflict'; END IF;
 IF o.state IN ('delivered','paid_review') THEN RETURN to_jsonb(o); END IF;
 SELECT content_inventory INTO inventory FROM public.player_archive_state WHERE account_id=a;
 inventory:=coalesce(inventory,'{}'::jsonb);
 UPDATE payments.orders SET transaction_id=p_transaction,paid_at=now(),checked_at=now() WHERE order_id=p_order;
 -- A player can obtain this maximum-one item while a QR is open. Preserve the
 -- payment receipt for manual refund; never charge again or silently substitute.
 IF coalesce((inventory->>'lottery_monkey_king')::integer,0)>=1 THEN
  UPDATE payments.orders SET state='paid_review' WHERE order_id=p_order;
  RETURN payments.get_order(p_order);
 END IF;
 INSERT INTO public.player_archive_state(account_id,content_inventory)
 VALUES(a,jsonb_set(inventory,'{lottery_monkey_king}','1'))
 ON CONFLICT(account_id) DO UPDATE SET content_inventory=excluded.content_inventory;
 -- Version 1: exact existing lottery item effects, including map-level effects
 -- and CSV bounds. Only these fields change; archive/other inventory survive.
 UPDATE public.player_gameplay_stats SET
  hero_attack_armor_reduction=hero_attack_armor_reduction+10,
  hero_basic_attack_growth=hero_basic_attack_growth+10,
  hero_attribute_growth=hero_attribute_growth+20,
  hero_attack_bonus_pct=least(10000,hero_attack_bonus_pct+10),
  hero_final_damage_bonus_pct=least(10000,hero_final_damage_bonus_pct+10),
  map_level=map_level+1,wall_initial_health=wall_initial_health+100,
  wall_health_regen_per_second=wall_health_regen_per_second+5,updated_at=now()
 WHERE player_id=a;
 IF NOT FOUND THEN RAISE EXCEPTION 'gameplay_stats_missing'; END IF;
 UPDATE public.survival_players SET profile_revision=profile_revision+1,updated_at=now() WHERE account_id=a;
 UPDATE payments.orders SET state='delivered',granted_at=now() WHERE order_id=p_order;
 RETURN payments.get_order(p_order);
END; $$;

REVOKE ALL ON ALL FUNCTIONS IN SCHEMA payments FROM PUBLIC;
GRANT USAGE ON SCHEMA payments TO goufayu_payment;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA payments TO goufayu_payment;
