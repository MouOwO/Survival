-- Apply after 202610030001_vip_rewards.sql and the existing v4 payment upgrade.
-- New verified deliveries only; historical test receipts are not backfilled here.
begin;
alter table public.player_gameplay_stats add column if not exists vip_recharge_total_fen bigint not null default 0;
alter table public.player_gameplay_stats drop constraint if exists player_gameplay_stats_vip_recharge_total_fen_check;
alter table public.player_gameplay_stats add constraint player_gameplay_stats_vip_recharge_total_fen_check
 check(vip_recharge_total_fen between 0 and 9007199254740991);
create table if not exists payments.vip_recharge_levels (
 level integer primary key check(level between 1 and 12),
 required_fen bigint unique not null check(required_fen>0)
);
insert into payments.vip_recharge_levels(level,required_fen) values
-- BEGIN VIP LEVEL VALUES (generated from vip_recharge_levels.json)
(1,5000),
(2,10000),
(3,25000),
(4,50000),
(5,100000),
(6,150000),
(7,250000),
(8,400000),
(9,600000),
(10,750000),
(11,1000000),
(12,1250000)
-- END VIP LEVEL VALUES
on conflict(level) do update set required_fen=excluded.required_fen;
create table if not exists payments.vip_recharge_credits (
 order_id text primary key references payments.orders(order_id),
 transaction_id text unique not null,
 account_id text not null references public.survival_players(account_id),
 amount_fen bigint not null check(amount_fen>0),
 credited_at timestamptz not null default now()
);
revoke all on payments.vip_recharge_levels,payments.vip_recharge_credits from public,anon,authenticated;
create or replace function payments.credit_vip_recharge() returns trigger
language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$
declare inserted integer; total bigint; tier integer;
begin
 -- payments.deliver verifies gateway transaction, merchant and exact amount before
 -- changing state. Pending orders, review holds and repeat callbacks cannot credit.
 if new.state<>'delivered' or old.state='delivered' or new.cleared_at is not null then return new; end if;
 if new.currency<>'CNY' or new.amount<=0 or new.transaction_id is null
   or new.transaction_id !~ '^[0-9]{20,64}$' then raise exception 'vip_recharge_receipt_invalid'; end if;
 insert into payments.vip_recharge_credits(order_id,transaction_id,account_id,amount_fen)
 values(new.order_id,new.transaction_id,new.account_id,new.amount)
 on conflict(order_id) do nothing;
 get diagnostics inserted=row_count;
 if inserted=0 then return new; end if;
 update public.player_gameplay_stats set vip_recharge_total_fen=vip_recharge_total_fen+new.amount,updated_at=now()
 where player_id=new.account_id returning vip_recharge_total_fen into total;
 if total is null then raise exception 'vip_recharge_profile_missing'; end if;
 select coalesce(max(level),0) into tier from payments.vip_recharge_levels where required_fen<=total;
 update public.player_gameplay_stats set vip_level=tier where player_id=new.account_id;
 -- Any paid member may open VIP; tier 1 rewards still require 50 yuan in total.
 insert into public.archive_entitlements(account_id,entitlement_id,active,starts_at,expires_at)
 values(new.account_id,'vip',true,now(),null)
 on conflict(account_id,entitlement_id) do update set active=true,starts_at=least(archive_entitlements.starts_at,excluded.starts_at),expires_at=null;
 return new;
end; $$;
revoke all on function payments.credit_vip_recharge() from public,anon,authenticated;
drop trigger if exists credit_vip_recharge on payments.orders;
create trigger credit_vip_recharge after update of state on payments.orders
 for each row when (new.state='delivered' and old.state is distinct from new.state)
 execute function payments.credit_vip_recharge();
commit;
