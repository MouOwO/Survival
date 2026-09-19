-- Change defaults only; existing player values remain unchanged.
begin;
alter table public.player_gameplay_stats alter column hero_damage_attack_growth set default 0;
alter table public.player_gameplay_stats alter column hero_basic_attack_growth set default 0;
alter table public.player_gameplay_stats alter column hero_attribute_growth set default 0;
commit;
