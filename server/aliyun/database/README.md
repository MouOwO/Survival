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
| `goufayu_app` | LOGIN; CONNECT, public schema USAGE, exactly 11 backend RPCs |
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
