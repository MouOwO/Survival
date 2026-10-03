-- VIP grade is assigned only after verified recharge and configured thresholds.
-- Wallet starts empty. This migration never grants preview accounts paid currency.
begin;
alter table public.player_gameplay_stats add column if not exists vip_level bigint not null default 0;
alter table public.player_gameplay_stats add column if not exists shop_paid_currency bigint not null default 0;
alter table public.player_gameplay_stats drop constraint if exists player_gameplay_stats_vip_level_check;
alter table public.player_gameplay_stats add constraint player_gameplay_stats_vip_level_check check (vip_level between 0 and 12);
alter table public.player_gameplay_stats drop constraint if exists player_gameplay_stats_shop_paid_currency_check;
alter table public.player_gameplay_stats add constraint player_gameplay_stats_shop_paid_currency_check check (shop_paid_currency between 0 and 2147483647);
commit;
