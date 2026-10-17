-- Exact prerequisite from formal player_gameplay_stats.csv: integer, default0,
-- minimum0, no maximum. Add only this internal accounting rule, no player data.
DO $earned_rule$
BEGIN
 IF EXISTS(SELECT 1 FROM payments.stat_rules WHERE field_id='starjoy_points_earned'
    AND (minimum IS DISTINCT FROM 0 OR maximum IS NOT NULL OR default_value IS DISTINCT FROM 0))
 THEN RAISE EXCEPTION 'earned_payment_rule_unexpected'; END IF;
 INSERT INTO payments.stat_rules(field_id,minimum,maximum,default_value)
 VALUES('starjoy_points_earned',0,NULL,0) ON CONFLICT(field_id) DO NOTHING;
END; $earned_rule$;
