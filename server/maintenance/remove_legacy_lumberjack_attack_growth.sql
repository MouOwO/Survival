-- Remove only the old fixed +1 baseline, retaining earned per-hit growth.
begin;
create table if not exists public.survival_data_migrations (
 migration_id text primary key, applied_at timestamptz not null default now()
);
revoke all on public.survival_data_migrations from public,anon,authenticated;
lock table public.player_gameplay_stats in share row exclusive mode;
alter table public.player_gameplay_stats alter column lumberjack_attack_growth set default 0;
do $$
begin
 insert into public.survival_data_migrations(migration_id)
 values('20260928_remove_default_lumberjack_attack_growth') on conflict do nothing;
 if not found then return; end if;
 with changed as (
  update public.player_gameplay_stats
  set lumberjack_attack_growth=greatest(0,lumberjack_attack_growth-1),updated_at=now()
  where lumberjack_attack_growth>0
  returning player_id
 )
 update public.survival_players p set profile_revision=profile_revision+1,updated_at=now()
 from changed c where p.account_id=c.player_id;
end; $$;
commit;
