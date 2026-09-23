# PostgreSQL 17 migration and recovery

These tools prepare a new database and test migration without altering the
existing Supabase project or its data. They never initialize, delete, or replace
the existing `goufayu-db` container, its volume, or a PostgreSQL cluster.

## Roles and credentials

Use PostgreSQL 17 client tools and Python with `requirements.txt` installed.
All connection options come from a restricted `PGSERVICEFILE` plus `PGPASSFILE`.
Only service names appear in process arguments. Do not put a password or DSN
on the command line. The program never reads `.env` and suppresses raw database
exceptions/client stderr because those can contain account data or credentials.

An administrator first creates a **new, dedicated empty database** named
`goufayu_test` or `goufayu_restore_<lowercase_id>` and executes
`init_roles.sql` there using `psql -X -v ON_ERROR_STOP=1 -f init_roles.sql`.
The bootstrap refuses a target containing business relations. Existing roles
must already have the expected safe attributes; it does not silently demote or
replace them. Provision login passwords separately with the deployment helper.

| Role | Access |
|---|---|
| `goufayu_owner` | NOLOGIN; owns business schema/tables/SECURITY DEFINER routines |
| `goufayu_migrator` | LOGIN; can explicitly SET ROLE owner; migration/backup only |
| `goufayu_app` | LOGIN; CONNECT, public schema USAGE, exactly 12 backend RPCs |
| `anon`, `authenticated`, `service_role` | NOLOGIN compatibility roles; no app membership |

The app has no database CREATE/TEMP, schema CREATE, table privileges, privileged
role membership, or BYPASSRLS. All business tables have RLS enabled. Owner-run
SECURITY DEFINER functions retain the original transaction semantics and use
`pg_catalog,public,extensions,pg_temp`; the temporary schema is explicitly last.
Bootstrap revokes database privileges from PUBLIC. Never use the migration
service or the administrator password for the running HTTP server.

## Collect and replay original migrations

```text
python dbtool.py collect --legacy-root D:/survival_database --addon-root <addon> --destination <release>/database
python dbtool.py migrate --bundle <release>/database --target-service goufayu_migrator
```

The release contains all **16 original SQL files** byte for byte, ordered as
12 legacy migrations, 3 archive migrations, then the manual inventory patch
(already absorbed by archive migration, so it is a no-op), followed by one
explicit target compatibility migration. A manifest records
SHA-256 for each file. Each file and its ledger entry commit together. Only the
outer BEGIN/COMMIT wrappers are removed at execution time; original stored files
are not rewritten. Final hardening has its own checksum/ledger entry. A repeated
run validates checksums and applies no historical SQL twice. A new target with
existing business objects and no tool ledger is refused.

### Upgrade the existing test03 database (2026-09-20)

Do **not** rerun `init_roles.sql`, create or replace `goufayu_test`, remove
`/data/postgres17`, or reset credentials. Test03 already has a valid 18-entry
ledger (17 schema migrations and `security/harden.sql`). The collector freezes
those filenames, order, bytes, and hashes, even though the external repository
now also contains copies of the archive migrations. It appends four reviewed
game migrations under new `target/202609200001` through `202609200004` IDs:

The old target compatibility SQL and `harden.sql` were deployed with LF line
endings. Windows Git may check them out as CRLF; collection restores LF only
after checking their pinned test03 SHA-256. A substantive edit refuses
collection. It never changes a historical ledger hash to accept new SQL.

| Migration | Existing data effects |
|---|---|
| HTTP lottery | Adds operation response and lottery commit RPC; rewrites resume function to include response |
| Gameplay CSV bounds | Adds missing stat columns and refreshes defaults/checks; invalid existing values cause a failure, never silent clamping |
| Remove default wood income | **Once**, subtracts 1 from positive `wood_per_second`, floored at 0, and increments affected player revisions; leaves reward grants/definitions unchanged |
| Remove default attack growth | Changes three defaults from 1 to 0; all existing stat values remain unchanged |

The wood migration's `survival_data_migrations` marker prevents a second
subtraction, including after recovery. The marker table is included in backup
inventory, fingerprints, restoration, and RLS hardening. Do not delete its
marker or replay an edited copy to “fix” values. Existing earned values above
the old baseline remain; this is a gameplay baseline adjustment, not recovery
of previously missing data. A rollback of the new application alone does not
reverse this data adjustment.

The historical `harden.sql` is unchanged. `harden_lottery.sql` runs immediately
after it in the same transaction, grants only the 12th runtime RPC, enables RLS
on the marker table, and is recorded separately. New hardened installations
have 21 schema entries plus 2 security entries. Repeating `migrate` executes
zero schema migrations and reapplies the same reviewed hardening.

Perform these operations while the HTTP backend is stopped, using private
libpq service/pass files and existing login credentials:

```text
python dbtool.py plan-upgrade --bundle <new-release>/database --target-service goufayu_migrator
python dbtool.py --pg-bin <PG17-bin> export --source-service goufayu_migrator --source-role goufayu_owner --output <new-private-backup>
# Copy this backup off the ECS and verify file hashes before proceeding.
# Administrator creates only a separately named empty clone and bootstraps its ACLs.
python dbtool.py --pg-bin <PG17-bin> trial-restore --target-service goufayu_restore_trial --backup <new-private-backup>
python dbtool.py plan-upgrade --bundle <new-release>/database --target-service goufayu_restore_trial
python dbtool.py migrate --bundle <new-release>/database --target-service goufayu_restore_trial
python integration_test.py --app-service goufayu_restore_app --addon-root <new-release>/addon
python dbtool.py migrate --bundle <new-release>/database --target-service goufayu_restore_trial
# Only after clone checks pass:
python dbtool.py migrate --bundle <new-release>/database --target-service goufayu_migrator
python integration_test.py --app-service goufayu_app --addon-root <new-release>/addon
```

For the clone and actual upgrade, use this audited wrapper in place of each
`migrate` invocation (give every run a new report filename):

```text
python verify_upgrade.py --target-service <migration-service> --bundle <new-release>/database --report <private-new-report.json>
```

It takes read-only owner snapshots before and after migration. All historical
reward rows, archive state/inventory, outbox and other immutable history must
retain their original-column fingerprints; player rows can only receive the
reviewed one-time wood decrement, matching revision increment and timestamps.
Old ledger rows/markers cannot change. A repeat invocation permits no business
row changes at all. Reports contain only counts, booleans, and migration IDs;
no account IDs or row values are printed. Reports are never overwritten.
The backend must stay stopped throughout. An audit failure stops deployment,
but does not automatically roll back already committed SQL; use the verified
pre-upgrade backup recovery procedure below.

The clone's service must select the clone database; `goufayu_restore_app` must
log in as `goufayu_app`. The `addon` path is the packaged directory containing
`data/csv/玩家档案系统/player_gameplay_stats.csv`. Service names shown are examples;
use the actual configured names. `plan-upgrade` is read-only and reports only
aggregate counts/IDs, including how many rows the wood adjustment will affect.

For a backup of **this tool-managed test03 database**, restoration preserves
the 18-entry ledger, so use `migrate` on the restored clone, **not `reconcile`**.
`reconcile` remains the stricter adoption path for a legacy Supabase backup:
its original-column fingerprints forbid changes to old rows, so a source that
still needs the wood subtraction will roll back with
`existing_data_modified_during_reconcile`. Do not disable that guard; such an
adoption needs a separately reviewed data-change plan.

For database rollback, restore the verified pre-upgrade backup into a new
`goufayu_restore_*` database and validate it with the retained test03 tooling;
repoint the stopped backend to that verified database. Never restore over the
populated test database or delete the new/old data directories. Preserve any
post-upgrade test writes separately if they need retention.

The target compatibility migration fixes a confirmed historical mismatch:
`tower_attack_interval` is now a CSV-defined reduction with initial value zero,
but the old table check required `>0`. The new migration changes that constraint
to `>=0` without changing stored values. A real PostgreSQL 17 run reproduced the
old `23514` failure and verified all 97 current CSV defaults after this fix.

Keep the entire history: the star-blessing and online-grant migrations rewrite
prior function bodies, remove legacy tables, and seed immutable version 3. A
random subset is not a valid fresh schema. The latest checkpoint has **both** a
7-argument core and an 8-argument wrapper; runtime uses the latter (`p_final`).
The old in-match fishing heartbeat and its three tables are retired.

## Read-only source inventory and consistent export

```text
python dbtool.py audit --source-service legacy_read --output <new-audit-directory>
python dbtool.py --pg-bin <PG17-bin> export --source-service legacy_read --output <new-backup-directory>
python dbtool.py --pg-bin <PG17-bin> export --source-service goufayu_backup --source-role goufayu_owner --output <new-backup-directory>
```

The last form uses a migration/backup service that is permitted to SET ROLE
owner. A service tied to the app role cannot back up tables. No SQL writes occur
on the source. A repeatable-read, read-only transaction exports one snapshot;
`pg_dump --snapshot` and every table count/content fingerprint use that same
snapshot. The connection remains alive until both complete.

Artifacts are `database.dump` (custom format, public/extensions, pgcrypto),
`schema.sql` (reviewable functions/DDL, no row data), `inventory.json` (tables,
columns, functions, triggers, extension and role flags), and
`backup_manifest.json` (file hashes and per-table row counts/content hashes).
The tool does not export role passwords or copy provider auth/storage schemas.
Unknown business objects, cross-schema dependencies, RLS policies, and exported
extensions other than pgcrypto fail closed for manual review. The current
business schema has **no sequences**; a new sequence refuses export until its
non-MVCC state has an explicit consistent-copy strategy.

Backups include account pseudonyms and game state. Keep the directory private,
encrypt off-host copies, and retain the stable `FISHING_ACCOUNT_ID_PEPPER`
separately in the secret store. Changing that pepper makes existing accounts
unreachable; this tool neither reads nor generates it.

## Trial recovery, without touching the current database

An administrator creates a new database named `goufayu_restore_<lowercase_id>`
and runs role bootstrap there. Give it a separate service entry, then:

```text
python dbtool.py --pg-bin <PG17-bin> trial-restore --target-service goufayu_restore_trial --backup <backup-directory>
```

The **actual connected database name** must be `goufayu_test` or start with
`goufayu_restore_`, and contain no business relations/functions. Prefer a fresh
`goufayu_restore_*` database; the existing `goufayu_test` is never an implicit
target and a populated one is refused. Recovery uses `--no-owner --no-acl
--role=goufayu_owner --single-transaction --exit-on-error`; there is no
`--clean`, database deletion, TRUNCATE, or source mutation.

If the reviewed archive explicitly recreates `public`, recovery first removes
only the target's empty bootstrap `public` schema after the database-wide empty
guard. The drop has no CASCADE; any dependency refuses it. A failed transactional
restore recreates the empty schema with app access denied. No source schema or
nonempty target schema is removed.

A complete archive naturally restores pre-data, data, then post-data. This
matters because `archive_capture_online` must not run while historical
`online_time_idempotency` rows are copied: otherwise it could regenerate outbox
rows. The trial checks all counts/content fingerprints, function definitions,
and trigger definitions against the export. It writes a target-specific PASS
report only after those checks pass. It intentionally does **not** enable the
restored DB for runtime: source ACLs are not imported. Apply reviewed target
hardening/schema upgrades in a separate explicit deployment step.

```text
python dbtool.py reconcile --target-service goufayu_restore_trial --backup <backup-directory> --bundle <release>/database
```

`reconcile` requires that target's successful restore report and rechecks its
data against the exported snapshot. It applies only the additive archive
extensions, inventory patch, target compatibility, and hardening, in one
transaction. It never replays legacy destructive migrations or immutable reward
seeds on restored data. Original tables are locked against concurrent writes;
their original-column projections must retain exactly the same row hashes after
the upgrade. The tool records the source dump hash and refuses a later fresh
migration command on this adopted restored database. Schema USAGE is denied to
the app during trial restoration and granted only with the final RPC allowlist.

## Validation

```text
python -m unittest discover -s server/aliyun/database -p test_dbtool.py -v
python server/aliyun/database/integration_test.py --app-service <isolated-app-service> --addon-root <addon>
```

Offline tests cover safety gates and artifact integrity. Real PostgreSQL tests
must use a newly created isolated database; no production connection is implied.
The integration test uses a single rollback-only transaction to check current
CSV defaults, permission denials, reward/command idempotency, final checkpoint,
and exactly-once online outbox creation. It commits no test rows.

Known inherited behavior: `grant_out_of_match_reward` locks player then stats,
while checkpoint/archive lock stats then player. Concurrent conflicting calls
can deadlock; the migration preserves that existing business code. Runtime must
rollback a failed transaction rather than automatically retry a write.

PostgreSQL references: [pg_dump snapshot and schema scope](https://www.postgresql.org/docs/17/app-pgdump.html),
[pg_restore transaction and ownership options](https://www.postgresql.org/docs/17/app-pgrestore.html),
[role inheritance](https://www.postgresql.org/docs/17/role-attributes.html).
