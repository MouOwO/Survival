-- Add a second gateway while retaining every existing order and reward receipt.
CREATE TABLE payments.providers (
 provider text PRIMARY KEY CHECK(provider IN ('wechat','alipay')),
 appid text NOT NULL, mchid text NOT NULL, enabled boolean NOT NULL DEFAULT false,
 CHECK((provider='wechat' AND appid='wx164e25a570fb636a' AND mchid='1117928493') OR
       (provider='alipay' AND appid='2021007102660118' AND mchid ~ '^2088[0-9]{12}$')),
 UNIQUE(provider,appid,mchid)
);
ALTER TABLE payments.providers ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON payments.providers FROM PUBLIC,goufayu_payment;
INSERT INTO payments.providers VALUES('wechat','wx164e25a570fb636a','1117928493',true);
INSERT INTO payments.providers VALUES('alipay','2021007102660118',current_setting('payments.alipay_seller'),true);
ALTER TABLE payments.orders ADD COLUMN provider text NOT NULL DEFAULT 'wechat';
ALTER TABLE payments.orders DROP CONSTRAINT orders_order_id_check;
ALTER TABLE payments.orders DROP CONSTRAINT orders_appid_check;
ALTER TABLE payments.orders DROP CONSTRAINT orders_mchid_check;
ALTER TABLE payments.orders ADD CONSTRAINT orders_provider_identity FOREIGN KEY(provider,appid,mchid) REFERENCES payments.providers(provider,appid,mchid);
ALTER TABLE payments.orders ADD CHECK((provider='wechat' AND order_id ~ '^WX[0-9a-f]{30}$') OR (provider='alipay' AND order_id ~ '^AL[0-9a-f]{30}$'));
ALTER TABLE payments.orders DROP CONSTRAINT orders_transaction_id_key;
CREATE UNIQUE INDEX orders_provider_transaction ON payments.orders(provider,transaction_id) WHERE transaction_id IS NOT NULL;

CREATE FUNCTION payments.create_order_channel(p_account text,p_session text,p_order text,p_sku text,p_provider text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public,pg_temp AS $$
DECLARE o payments.orders%rowtype; p payments.products%rowtype; channel payments.providers%rowtype; c jsonb; g bigint; blocked text;
BEGIN
 PERFORM 1 FROM public.player_gameplay_stats WHERE player_id=p_account FOR UPDATE;
 PERFORM 1 FROM public.survival_players WHERE account_id=p_account FOR UPDATE;
 c:=payments.catalog(p_account,p_session); IF c ? 'error' THEN RETURN c; END IF;
 SELECT * INTO channel FROM payments.providers WHERE provider=p_provider AND enabled;
 IF NOT FOUND THEN RETURN jsonb_build_object('error','payment_channel_unavailable'); END IF;
 SELECT * INTO p FROM payments.products WHERE sku=p_sku AND enabled;
 IF NOT FOUND THEN RETURN jsonb_build_object('error','product_unavailable'); END IF;
 IF EXISTS(SELECT 1 FROM payments.test_accounts WHERE account_id=p_account AND reset_request IS NOT NULL)
 THEN RETURN jsonb_build_object('error','reset_in_progress'); END IF;
 -- One active intent per product across both providers prevents accidental double payment.
 SELECT * INTO o FROM payments.orders WHERE account_id=p_account AND sku=p_sku
  AND (state IN ('created','pending') OR (state='paid_review' AND cleared_at IS NULL)) ORDER BY created_at DESC LIMIT 1;
 IF FOUND THEN RETURN to_jsonb(o); END IF;
 blocked:=payments.product_block(p_account,p.item_id,p.purchase_limit,p.grants,p.effects);
 IF blocked<>'' THEN RETURN jsonb_build_object('error',blocked); END IF;
 SELECT generation INTO g FROM payments.test_accounts WHERE account_id=p_account;
 INSERT INTO payments.orders(order_id,account_id,sku,amount,reward,generation,provider,appid,mchid)
 VALUES(p_order,p_account,p.sku,p.amount,jsonb_build_object('item_id',p.item_id,'quantity',1,'version',4,
   'title',p.title,'description',p.description,'effects',p.effects,'grants',p.grants,'purchase_limit',p.purchase_limit,
   'catalog_hash',c->>'catalog_hash'),coalesce(g,0),channel.provider,channel.appid,channel.mchid) RETURNING * INTO o;
 RETURN to_jsonb(o);
END; $$;
-- Older clients/services keep their WeChat default and the same active order.
CREATE OR REPLACE FUNCTION payments.create_order(p_account text,p_session text,p_order text,p_sku text) RETURNS jsonb
LANGUAGE sql SECURITY DEFINER SET search_path=pg_catalog,public,pg_temp AS $$
 SELECT payments.create_order_channel(p_account,p_session,p_order,p_sku,'wechat');
$$;

CREATE OR REPLACE FUNCTION payments.update_gateway(p_order text,p_state text,p_code text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public,pg_temp AS $$
DECLARE channel text;
BEGIN
 IF p_state NOT IN ('checked','pending','closed') THEN RAISE EXCEPTION 'gateway_state_invalid'; END IF;
 SELECT provider INTO channel FROM payments.orders WHERE order_id=p_order;
 IF p_state='pending' AND (p_code IS NULL OR length(p_code)>2048 OR NOT
   ((channel='wechat' AND p_code ~ '^weixin://wxpay/bizpayurl\?') OR (channel='alipay' AND p_code='alipay:page_pay')))
 THEN RAISE EXCEPTION 'code_url_invalid'; END IF;
 UPDATE payments.orders SET checked_at=now(),state=CASE WHEN p_state='checked' THEN state ELSE p_state END,
  code_url=CASE WHEN p_state='pending' THEN p_code ELSE code_url END
 WHERE order_id=p_order AND state IN ('created','pending');
 RETURN payments.get_order(p_order);
END; $$;
REVOKE ALL ON FUNCTION payments.create_order_channel(text,text,text,text,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION payments.create_order_channel(text,text,text,text,text) TO goufayu_payment;
