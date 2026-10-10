-- Derive public progress from the existing account archive. No saved rows,
-- reward receipts, entitlements or reward-grant visibility rules are changed.
begin;
do $migration$
declare
    v_definition text;
    v_expected text := replace($expected$CREATE OR REPLACE FUNCTION public.fishing_profile_json(p_account_id text)
 RETURNS jsonb
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'extensions', 'pg_temp'
AS $function$
    select jsonb_build_object(
        'schema_version', 1,
        'account_id', p.account_id,
        'revision', p.profile_revision,
        'entitlements', coalesce((
   select jsonb_object_agg(e.entitlement_id,jsonb_build_object('active',e.active and e.starts_at<=now(),
    'expires_at',case when e.expires_at is null then null else extract(epoch from e.expires_at)::bigint end))
    from public.archive_entitlements e where e.account_id=p_account_id),'{}'::jsonb),
        'achievements', '{}'::jsonb,
        'save', jsonb_build_object(
   'archive', coalesce((select a.archive from public.player_archive_state a where a.account_id=p_account_id),'{}'::jsonb),
   'content_inventory', coalesce((select a.content_inventory from public.player_archive_state a where a.account_id=p_account_id),'{}'::jsonb),

   'fishing_inventory', coalesce((select jsonb_object_agg(x.reward_id,x.n) from (
    select reward_id,count(*) n FROM (SELECT rg.* FROM public.reward_grants rg WHERE NOT EXISTS (SELECT 1 FROM payments.cleared_reward_grants cleared WHERE cleared.grant_id=rg.grant_id)) visible_grants where account_id=p_account_id
     and effect_scope='permanent' and reward_id ~ '^star_blessing_(00[1-9]|01[0-9]|02[0-6])$' group by reward_id
   )x),'{}'::jsonb),

            'permanent_effects', coalesce((
                select jsonb_object_agg(e.effect_key, e.total_value)
                from public.player_effect_totals e where e.account_id = p.account_id
            ), '{}'::jsonb),
            'gameplay_stats', coalesce((
                select to_jsonb(gs) - 'player_id' - 'created_at' - 'updated_at'
                from public.player_gameplay_stats gs where gs.player_id = p.account_id
            ), '{}'::jsonb)
        ),
        'public', '{}'::jsonb
    )
    from public.survival_players p
    where p.account_id = p_account_id;
$function$
$expected$, E'\n\n', E'\n  \n');
    v_marker text := $marker$'public', '{}'::jsonb$marker$;
    v_public text := $projection$'public', (
            select jsonb_build_object(
                'highest_difficulty', 'N' || coalesce((
                    select max(case
                        when progress.key ~ '^n([1-9]|1[0-9]|20)$'
                            and jsonb_typeof(progress.value) = 'number'
                        then case when (progress.value #>> '{}')::numeric > 0
                            then substring(progress.key from 2)::integer end
                    end)
                    from jsonb_each(case
                        when jsonb_typeof(saved.archive->'clear_counts') = 'object'
                        then saved.archive->'clear_counts' else '{}'::jsonb end) progress
                ), 1)::text,
                'title_id', case
                    when jsonb_typeof(saved.archive->'equipped_title') = 'string'
                    then saved.archive->>'equipped_title' else '' end
            )
            from (select coalesce((select a.archive
                from public.player_archive_state a where a.account_id=p_account_id),
                '{}'::jsonb) as archive) saved
        )$projection$;
    v_updated text;
begin
    select pg_get_functiondef('public.fishing_profile_json(text)'::regprocedure)
        into v_definition;
    v_updated := replace(v_expected, v_marker, v_public);
    if v_updated = v_expected then
        raise exception 'archive_public_progress_marker_missing';
    end if;
    -- Reapplying this exact migration is safe. Any unrelated function drift
    -- requires review instead of replacing its visibility or security rules.
    if v_definition = v_updated then
        return;
    end if;
    if v_definition <> v_expected then
        raise exception 'archive_public_profile_layout_unexpected';
    end if;
    execute v_updated;
end;
$migration$;
commit;
