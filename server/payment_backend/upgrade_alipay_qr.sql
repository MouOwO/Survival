-- Accept signed Alipay precreate codes while retaining existing page-pay orders.
CREATE OR REPLACE FUNCTION payments.update_gateway(p_order text,p_state text,p_code text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public,pg_temp AS $$
DECLARE channel text;
BEGIN
 IF p_state NOT IN ('checked','pending','closed') THEN RAISE EXCEPTION 'gateway_state_invalid'; END IF;
 SELECT provider INTO channel FROM payments.orders WHERE order_id=p_order;
 IF p_state='pending' AND (p_code IS NULL OR length(p_code)>2048 OR NOT
   ((channel='wechat' AND p_code ~ '^weixin://wxpay/bizpayurl\?') OR
    (channel='alipay' AND (p_code='alipay:page_pay' OR p_code ~ '^https://qr\.alipay\.com/[A-Za-z0-9_-]{1,192}$'))))
 THEN RAISE EXCEPTION 'code_url_invalid'; END IF;
 UPDATE payments.orders SET checked_at=now(),state=CASE WHEN p_state='checked' THEN state ELSE p_state END,
  code_url=CASE WHEN p_state='pending' THEN p_code ELSE code_url END
 WHERE order_id=p_order AND state IN ('created','pending');
 RETURN payments.get_order(p_order);
END; $$;
