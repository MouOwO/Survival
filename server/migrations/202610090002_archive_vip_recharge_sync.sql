-- Connect future verified payment deliveries to VIP archive progression.
-- Existing orders, product prices, purchased rewards and player values are untouched.
-- Test/reset accounts and historical deliveries are deliberately not backfilled.
begin;

create table if not exists payments.vip_recharge_levels (
 level integer primary key check(level between 1 and 12),
 required_fen bigint unique not null check(required_fen>0)
);
insert into payments.vip_recharge_levels(level,required_fen) values
 (1,5000),(2,10000),(3,25000),(4,50000),(5,100000),(6,150000),
 (7,250000),(8,400000),(9,600000),(10,750000),(11,1000000),(12,1250000)
on conflict(level) do nothing;
do $levels$
begin
 if (select count(*) from payments.vip_recharge_levels)<>12 or exists (
  select 1 from (values (1,5000),(2,10000),(3,25000),(4,50000),(5,100000),(6,150000),
   (7,250000),(8,400000),(9,600000),(10,750000),(11,1000000),(12,1250000)) expected(level,required_fen)
   left join payments.vip_recharge_levels actual using(level)
   where actual.required_fen is distinct from expected.required_fen
 ) then raise exception 'archive_vip_recharge_levels_mismatch'; end if;
end;
$levels$;

create table if not exists payments.vip_recharge_credits (
 order_id text primary key references payments.orders(order_id),
 provider text not null references payments.providers(provider),
 transaction_id text not null check(transaction_id ~ '^[0-9]{20,64}$'),
 account_id text not null references public.survival_players(account_id),
 amount_fen bigint not null check(amount_fen>0),
 credited_at timestamptz not null default now(),
 unique(provider,transaction_id)
);
alter table payments.vip_recharge_levels enable row level security;
alter table payments.vip_recharge_credits enable row level security;
revoke all on payments.vip_recharge_levels,payments.vip_recharge_credits
 from public,anon,authenticated,goufayu_app,goufayu_payment;

create or replace function payments.credit_vip_recharge() returns trigger
language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$
declare inserted integer; total bigint; tier integer;
begin
 -- The unchanged delivery RPC verifies the gateway identity and exact amount.
 -- These timestamps are written only after that RPC applies the purchased reward.
 if new.state<>'delivered' or old.state='delivered' or new.cleared_at is not null
    or new.paid_at is null or new.granted_at is null
    or payments.is_test_account(new.account_id) then return new; end if;
 if new.currency<>'CNY' or new.amount<=0 or new.transaction_id is null
    or new.transaction_id !~ '^[0-9]{20,64}$' then raise exception 'vip_recharge_receipt_invalid'; end if;
 insert into payments.vip_recharge_credits(order_id,provider,transaction_id,account_id,amount_fen)
 values(new.order_id,new.provider,new.transaction_id,new.account_id,new.amount)
 on conflict(order_id) do nothing;
 get diagnostics inserted=row_count;
 if inserted=0 then return new; end if;
 update public.player_gameplay_stats set vip_recharge_total_fen=vip_recharge_total_fen+new.amount,updated_at=now()
 where player_id=new.account_id returning vip_recharge_total_fen into total;
 if total is null then raise exception 'vip_recharge_profile_missing'; end if;
 select coalesce(max(level),0) into tier from payments.vip_recharge_levels where required_fen<=total;
 update public.player_gameplay_stats set vip_level=tier where player_id=new.account_id;
 -- Membership depends on an actual verified recharge; tier rewards still use
 -- the configured cumulative thresholds. A wallet debit does not lower the tier.
 insert into public.archive_entitlements(account_id,entitlement_id,active,starts_at,expires_at)
 values(new.account_id,'vip',true,now(),null)
 on conflict(account_id,entitlement_id) do update
 set active=true,starts_at=least(archive_entitlements.starts_at,excluded.starts_at),expires_at=null;
 return new;
end; $$;
revoke all on function payments.credit_vip_recharge()
 from public,anon,authenticated,goufayu_app,goufayu_payment;

-- Install only this additive trigger; delivery, review and reset functions retain
-- their existing ownership, permissions and gateway validation behavior.
drop trigger if exists credit_vip_recharge on payments.orders;
create trigger credit_vip_recharge after update of state on payments.orders
 for each row when (new.state='delivered' and old.state is distinct from new.state)
 execute function payments.credit_vip_recharge();

commit;
