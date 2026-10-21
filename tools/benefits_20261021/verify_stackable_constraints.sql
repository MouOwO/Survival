-- Read-only checks: run after the 202610210002 migration as the schema owner.
-- No real account rows or rewards are read or written.
DO $verification$
DECLARE inventory jsonb;
BEGIN
 IF public.archive_unique_points_20261019_valid('{}',
     '{"lottery_ember_of_legacy":1600,"welfare_zongzi":150}') IS DISTINCT FROM true THEN
  RAISE EXCEPTION 'stackable_copies_rejected_by_unique_whitelist';
 END IF;
 IF public.archive_unique_points_20261019_valid('{}','{"lottery_nature_crystal":2}') IS DISTINCT FROM false
    OR public.archive_unique_points_20261019_valid('{}',
        '{"lottery_nature_crystal":1,"lottery_flame_crystal":1}') IS DISTINCT FROM false
    OR public.archive_unique_points_20261019_valid(
        '{"daily_rewards":{"item_counts":{"daily_growth_gem":2}}}','{}') IS DISTINCT FROM false THEN
  RAISE EXCEPTION 'existing_unique_or_daily_ownership_weakened';
 END IF;
 FOREACH inventory IN ARRAY ARRAY['{}'::jsonb,'{"welfare_zongzi":0}'::jsonb,
     '{"welfare_zongzi":150,"lottery_ember_of_legacy":1600}'::jsonb,
     '{"lottery_ember_of_legacy":9007199254740991}'::jsonb] LOOP
  IF public.archive_stackable_items_20261021_valid(inventory) IS DISTINCT FROM true THEN
   RAISE EXCEPTION 'valid_stackable_inventory_rejected';
  END IF;
 END LOOP;
 FOREACH inventory IN ARRAY ARRAY['{"welfare_zongzi":151}'::jsonb,'{"welfare_zongzi":-1}'::jsonb,
     '{"welfare_zongzi":1.5}'::jsonb,'{"lottery_ember_of_legacy":9007199254740992}'::jsonb,
     '{"lottery_ember_of_legacy":-1}'::jsonb,'{"lottery_ember_of_legacy":"2"}'::jsonb,
     '{"lottery_ember_of_legacy":true}'::jsonb,'{"welfare_zongzi":null}'::jsonb] LOOP
  IF public.archive_stackable_items_20261021_valid(inventory) IS DISTINCT FROM false THEN
   RAISE EXCEPTION 'invalid_stackable_inventory_accepted';
  END IF;
 END LOOP;
END;
$verification$;
