-- Incremental migration: no historical order, inventory or player stat is rewritten.
ALTER TABLE payments.orders ADD COLUMN effect_changes jsonb NOT NULL DEFAULT '{}';

CREATE OR REPLACE FUNCTION payments.catalog(p_account text,p_session text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public,pg_temp AS $$
DECLARE inventory jsonb; products jsonb; stats jsonb;
BEGIN
 IF NOT EXISTS(SELECT 1 FROM public.match_profile_sessions WHERE account_id=p_account AND match_session_id=p_session)
 THEN RETURN jsonb_build_object('error','match_session_missing'); END IF;
 SELECT content_inventory INTO inventory FROM public.player_archive_state WHERE account_id=p_account;
 SELECT to_jsonb(s) INTO stats FROM public.player_gameplay_stats s WHERE player_id=p_account;
 SELECT jsonb_agg(jsonb_build_object('sku',p.sku,'item_id',p.item_id,'title',p.title,
  'description',p.description,'amount_fen',p.amount,'owned',coalesce((inventory->>p.item_id)::integer,0),
  'stat_preview',(SELECT jsonb_agg(jsonb_build_object('field_id',e.key,'value',(stats->>e.key)::numeric,
     'delta',e.value::numeric,'after',CASE WHEN r.maximum IS NULL THEN (stats->>e.key)::numeric+e.value::numeric
       ELSE least(r.maximum,(stats->>e.key)::numeric+e.value::numeric) END) ORDER BY e.key)
    FROM jsonb_each_text(p.effects) e JOIN payments.stat_rules r ON r.field_id=e.key),
  'enabled',coalesce((inventory->>p.item_id)::integer,0)<1 AND
    (payments.is_test_account(p_account) OR NOT EXISTS(SELECT 1 FROM payments.orders o
      WHERE o.account_id=p_account AND o.reward->>'item_id'=p.item_id AND o.state='delivered')))
  ORDER BY p.sort_order) INTO products FROM payments.products p WHERE p.enabled;
 RETURN jsonb_build_object('ok',true,'products',coalesce(products,'[]'),
  'test_reset_enabled',payments.is_test_account(p_account));
END; $$;

CREATE OR REPLACE FUNCTION payments.deliver(p_order text,p_transaction text,p_amount integer,p_appid text,p_mchid text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public,pg_temp AS $$
DECLARE o payments.orders%rowtype; a text; inventory jsonb; item text; applied jsonb; g bigint; before_stats jsonb; after_stats jsonb; changes jsonb;
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
 SELECT to_jsonb(s) INTO before_stats FROM public.player_gameplay_stats s WHERE player_id=a;
 applied:=payments.apply_effects(a,o.reward->'effects');
 SELECT to_jsonb(s) INTO after_stats FROM public.player_gameplay_stats s WHERE player_id=a;
 SELECT jsonb_object_agg(e.key,jsonb_build_object('before',(before_stats->>e.key)::numeric,
  'after',(after_stats->>e.key)::numeric,'delta',e.value::numeric)) INTO changes FROM jsonb_each_text(applied) e;
 UPDATE public.survival_players SET profile_revision=profile_revision+1,updated_at=now() WHERE account_id=a;
 UPDATE payments.orders SET state='delivered',granted_at=now(),applied_effects=applied,effect_changes=coalesce(changes,'{}') WHERE order_id=p_order;
 RETURN payments.get_order(p_order);
END; $$;
