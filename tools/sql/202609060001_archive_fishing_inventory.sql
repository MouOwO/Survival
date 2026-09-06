-- Run once in the existing Supabase project's SQL editor.
-- Extend the existing profile JSON without changing reward grants, effects, or timers.
begin;
do $$
declare
    v_definition text;
    v_marker text := '''save'', jsonb_build_object(';
    v_inventory text := $insert$
            'fishing_inventory', coalesce((
                select jsonb_object_agg(x.reward_id, x.owned_count)
                from (
                    select g.reward_id, count(*) as owned_count
                    from public.reward_grants g
                    where g.account_id = p_account_id
                      and g.effect_scope = 'permanent'
                      and g.reward_id ~ '^star_blessing_(00[1-9]|01[0-9]|02[0-6])$'
                    group by g.reward_id
                ) x
            ), '{}'::jsonb),
    $insert$;
begin
    select pg_get_functiondef('public.fishing_profile_json(text)'::regprocedure) into v_definition;
    if position('''fishing_inventory''' in v_definition) > 0 then
        raise notice 'fishing_inventory already included; no change';
        return;
    end if;
    if position(v_marker in v_definition) = 0 then
        raise exception 'Unexpected fishing_profile_json layout; review function before applying';
    end if;
    execute replace(v_definition, v_marker, v_marker || v_inventory);
end;
$$;
commit;
