-- Retire the three temporary +1 defaults; keep earned growth above the baseline.
begin;
create table if not exists public.survival_data_migrations (
 migration_id text primary key, applied_at timestamptz not null default now()
);
revoke all on public.survival_data_migrations from public,anon,authenticated;
-- Lock out profile initialization and reward writes until defaults and rows agree.
lock table public.player_gameplay_stats in share row exclusive mode;
alter table public.player_gameplay_stats alter column hero_damage_attack_growth set default 0;
alter table public.player_gameplay_stats alter column hero_basic_attack_growth set default 0;
alter table public.player_gameplay_stats alter column hero_attribute_growth set default 0;
do $$
begin
 insert into public.survival_data_migrations(migration_id)
 values('20260914_remove_default_attack_growth') on conflict do nothing;
 if not found then return; end if;
 -- Same lock order as gameplay writes: stats first, player revision second.
 with changed as (
  update public.player_gameplay_stats
  set hero_damage_attack_growth=greatest(0,hero_damage_attack_growth-1),
      hero_basic_attack_growth=greatest(0,hero_basic_attack_growth-1),
      hero_attribute_growth=greatest(0,hero_attribute_growth-1),updated_at=now()
  where hero_damage_attack_growth>0 or hero_basic_attack_growth>0 or hero_attribute_growth>0
  returning player_id
 )
 update public.survival_players p set profile_revision=profile_revision+1,updated_at=now()
 from changed c where p.account_id=c.player_id;
end; $$;
commit;
