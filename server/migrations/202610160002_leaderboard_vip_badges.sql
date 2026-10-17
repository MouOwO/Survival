-- Only extend the public ranking projection. Recharge and ownership stay private.
BEGIN;
CREATE OR REPLACE FUNCTION public.archive_endless_leaderboard()
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER
SET search_path=pg_catalog,public,extensions,pg_temp AS $$
 SELECT jsonb_build_object('ok',true,'entries',coalesce(jsonb_agg(
  jsonb_build_object('entry_id',ranking.entry_id::text,
   'steam_id',coalesce((76561197960265728::bigint+ranking.public_account_id::bigint)::text,''),
   'best_floor',ranking.best_floor,'endless_score',ranking.endless_score,
   'vip_level',coalesce((SELECT max(level) FROM payments.vip_recharge_levels
     WHERE required_fen<=coalesce(stats.vip_recharge_total_fen,0)),0),
   'vip_medal_level',coalesce((SELECT max(tier) FROM generate_series(1,10) tier
     WHERE ranking.archive->'vip_claimed'->('vip_medal_'||lpad(tier::text,2,'0'))='true'::jsonb
       OR public.archive_leaderboard_integer(ranking.content_inventory->('vip_medal_'||lpad(tier::text,2,'0')))>0),0))
  ORDER BY ranking.best_floor DESC,ranking.endless_score DESC,ranking.entry_id),'[]'::jsonb))
 FROM (
  SELECT saved.account_id,identity.entry_id,identity.public_account_id,saved.archive,saved.content_inventory,
   public.archive_leaderboard_integer(saved.archive->'endless_best_wave') AS best_floor,
   public.archive_leaderboard_integer(saved.archive->'endless_score') AS endless_score
  FROM public.player_archive_state saved
  LEFT JOIN public.archive_leaderboard_identities identity USING(account_id)
  WHERE public.archive_leaderboard_integer(saved.archive->'endless_best_wave')>0
  ORDER BY best_floor DESC,endless_score DESC,identity.entry_id
  LIMIT 100
 ) ranking
 LEFT JOIN public.player_gameplay_stats stats ON stats.player_id=ranking.account_id;
$$;
REVOKE ALL ON FUNCTION public.archive_endless_leaderboard()
 FROM PUBLIC,anon,authenticated,service_role,goufayu_app;
GRANT EXECUTE ON FUNCTION public.archive_endless_leaderboard() TO goufayu_app;
COMMIT;
