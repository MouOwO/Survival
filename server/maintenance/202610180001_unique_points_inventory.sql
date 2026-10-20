-- Owner-only repair backup ledger. This DDL does not alter any player's save.
-- Use reconcile_unique_points.py: preview first, apply with a reviewed plan,
-- rollback only while the repaired revision and exact saved values still match.
begin;
create table if not exists public.archive_unique_points_backups (
 run_id uuid not null,
 account_id text not null references public.survival_players(account_id),
 migration_id text not null check(migration_id='20261018_unique_lottery_points_v1'),
 config_hash text not null check(config_hash ~ '^[0-9a-f]{64}$'),
 before_revision bigint not null,
 after_revision bigint not null check(after_revision=before_revision+1),
 before_inventory jsonb not null,
 after_inventory jsonb not null,
 before_archive jsonb not null,
 after_archive jsonb not null,
 converted_points bigint not null check(converted_points between 0 and 9007199254740991),
 details jsonb not null,
 created_at timestamptz not null default now(),
 rolled_back_at timestamptz,
 primary key(run_id,account_id)
);
alter table public.archive_unique_points_backups enable row level security;
revoke all on public.archive_unique_points_backups from public,anon,authenticated,service_role,goufayu_app;
commit;
