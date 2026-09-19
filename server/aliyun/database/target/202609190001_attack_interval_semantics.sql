-- Target-only compatibility: the current authoritative CSV defines this value
-- as an attack-interval REDUCTION, whose valid initial value is zero.
-- The legacy >0 check predates that meaning. Preserve every stored value.
BEGIN;
DO $compatibility$
DECLARE definition text;
BEGIN
 SELECT pg_get_constraintdef(oid) INTO definition FROM pg_constraint
 WHERE conrelid='public.player_gameplay_stats'::regclass
   AND conname='player_gameplay_stats_tower_attack_interval_check';
 IF definition IS NULL THEN
  RAISE EXCEPTION 'attack_interval_constraint_missing_requires_review';
 END IF;
 IF definition ~ 'tower_attack_interval\s*>=' THEN RETURN; END IF;
 IF definition !~ 'tower_attack_interval\s*>' THEN
  RAISE EXCEPTION 'attack_interval_constraint_unexpected_requires_review';
 END IF;
 ALTER TABLE public.player_gameplay_stats
   DROP CONSTRAINT player_gameplay_stats_tower_attack_interval_check;
 ALTER TABLE public.player_gameplay_stats
   ADD CONSTRAINT player_gameplay_stats_tower_attack_interval_check
   CHECK(tower_attack_interval >= 0);
END $compatibility$;
COMMIT;
