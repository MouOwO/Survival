-- Apply once before publishing products with grants.entitlement_days.
-- Replace only delivery helpers; existing products, orders and entitlements are retained.
-- The caller owns the transaction and must first run test_monthly_pass_database.run_checks
-- in an outer rollback transaction. Do not publish the monthly SKU before this upgrade.

CREATE OR REPLACE FUNCTION payments.entitlement_days(p_grants jsonb,p_entitlement text) RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public,pg_temp AS $$
DECLARE days numeric;
BEGIN
 IF NOT (coalesce(p_grants->'entitlement_days','{}'::jsonb) ? p_entitlement) THEN RETURN NULL; END IF;
 days:=(p_grants->'entitlement_days'->>p_entitlement)::numeric;
 IF p_entitlement<>'archive_pass' OR days IS NULL OR days<>trunc(days) OR days NOT BETWEEN 1 AND 365
 THEN RAISE EXCEPTION 'invalid_entitlement_duration'; END IF;
 RETURN days::integer;
END; $$;
REVOKE ALL ON FUNCTION payments.entitlement_days(jsonb,text) FROM PUBLIC,goufayu_payment;

CREATE OR REPLACE FUNCTION payments.product_block(p_account text,p_marker text,p_limit integer,p_grants jsonb,p_effects jsonb) RETURNS text
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public,pg_temp AS $$
DECLARE inventory jsonb; k text; n integer; days integer;
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
  days:=payments.entitlement_days(p_grants,k);
  -- A finite monthly pass can renew. An existing permanent entitlement is never
  -- shortened or sold another redundant month; legacy permanent products retain their rule.
  IF EXISTS(SELECT 1 FROM public.archive_entitlements WHERE account_id=p_account AND entitlement_id=k
    AND active AND (expires_at IS NULL OR (days IS NULL AND starts_at<=now() AND expires_at>now())))
  THEN RETURN 'entitlement_already_owned'; END IF;
 END LOOP;
 IF EXISTS(SELECT 1 FROM public.player_gameplay_stats s CROSS JOIN jsonb_each_text(p_effects) e
  JOIN payments.stat_rules r ON r.field_id=e.key WHERE s.player_id=p_account
  AND r.maximum IS NOT NULL AND (to_jsonb(s)->>e.key)::numeric+e.value::numeric>r.maximum)
 THEN RETURN 'attribute_limit_reached'; END IF;
 RETURN '';
END; $$;

CREATE OR REPLACE FUNCTION payments.deliver(p_order text,p_transaction text,p_amount integer,p_appid text,p_mchid text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public,pg_temp AS $$
DECLARE o payments.orders%rowtype; a text; inventory jsonb; item text; k text; n integer; g bigint; applied jsonb;
 before_stats jsonb; after_stats jsonb; changes jsonb; item_grants jsonb; ent_grants jsonb:='{}'; old_ent jsonb; new_ent jsonb;
 days integer; new_expiry timestamptz; new_start timestamptz;
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
  SELECT to_jsonb(e) INTO old_ent FROM public.archive_entitlements e WHERE account_id=a AND entitlement_id=k FOR UPDATE;
  days:=payments.entitlement_days(o.reward->'grants',k);
  new_start:=now();new_expiry:=NULL;
  IF days IS NOT NULL THEN
   -- Use fixed 24-hour days, independent of the DB session timezone or DST.
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
 applied:=payments.apply_effects(a,o.reward->'effects');
 SELECT to_jsonb(s) INTO after_stats FROM public.player_gameplay_stats s WHERE player_id=a;
 SELECT coalesce(jsonb_object_agg(e.key,jsonb_build_object('before',(before_stats->>e.key)::numeric,
  'after',(after_stats->>e.key)::numeric,'delta',e.value::numeric)),'{}') INTO changes FROM jsonb_each_text(applied) e;
 UPDATE public.survival_players SET profile_revision=profile_revision+1,updated_at=now() WHERE account_id=a;
 -- Receipt reversal walks actual grant order, including renewals which were
 -- queued concurrently or granted inside one database transaction.
 UPDATE payments.orders SET state='delivered',granted_at=clock_timestamp(),applied_effects=applied,effect_changes=changes,
  applied_items=item_grants,applied_entitlements=ent_grants WHERE order_id=p_order;
 RETURN payments.get_order(p_order);
END; $$;
-- CREATE OR REPLACE retains the existing delivery permission; only the service
-- can invoke verified delivery. The two internal helpers remain private.
REVOKE ALL ON FUNCTION payments.product_block(text,text,integer,jsonb,jsonb) FROM PUBLIC,goufayu_payment;
