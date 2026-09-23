# Lottery upgrade acceptance

These checks use the deployed HTTP API and its real Lua reducer. Local unit
tests use fakes; passing those alone is **not** server acceptance.

## Scope and prerequisites

- Deploy the matching Python backend, content bundle, PostgreSQL lottery RPC,
  and runtime EXECUTE grants first. The live backend must pass `/ready`.
- Live write mode accepts only PostgreSQL 17 on `127.0.0.1:5432` (or `::1`),
  database `goufayu_test`. Run the separate rollback SQL checks on restore
  clones before changing this test database.
- The runtime uses `goufayu_app`; fixture setup uses the existing
  `goufayu_admin` service with `/etc/goufayu/admin.pgpass`. The password file
  must be private and owned by root or the executing user. Only its pathname
  goes on the command line; never print the file or pass its contents.
- Fixture `passfile` is passed only to that libpq connection. The application's
  `PGPASSFILE=/etc/goufayu/app.pgpass` is unchanged.
- Every invocation creates two fresh random `900`-prefixed synthetic accounts.
  Only those accounts receive 20 ordinary map tickets and one sentinel content
  item. No special tickets or payments are involved. Inventory and revision
  updates follow the application's lock order and verify the original revision.
- Test records remain in the test database for inspection. Never delete old
  accounts or tables to run this test again. Reports contain only synthetic IDs,
  hashes and test results, never raw saves, passwords or authentication tokens.

## Server: write test

Run under an administrator account that can read the existing private environment
and the fixture password file. This does not change the service's non-root user.
The following wrapper reads the environment using the deployment script's parser;
it does not source arbitrary environment text as shell code.

```sh
/opt/goufayu/releases/current/.venv/bin/python - <<'PY'
import os
from pathlib import Path
import subprocess
import sys

release = Path('/opt/goufayu/releases/current').resolve()
sys.path.insert(0, str(release / 'deploy'))
from manage import read_environment
env = {**os.environ, **read_environment(Path('/etc/goufayu/api.env'))}
env.update(GOUFAYU_ACCEPTANCE='local-test', FISHING_BACKEND_ROOT=str(release / 'backend'))
raise SystemExit(subprocess.call([
    str(release / '.venv/bin/python'),
    str(release / 'tests/lottery_upgrade_acceptance.py'),
    '--confirm-test-writes', '--fixture-service', 'goufayu_admin',
    '--fixture-passfile', '/etc/goufayu/admin.pgpass',
    '--report', '/var/lib/goufayu/acceptance/lottery-write.json',
], env=env))
PY
```

Check the release manifest for the actual packaged test script location; if it
differs from `tests/`, use that location. Reports are exclusively created, so use
a new report filename for another run. Do not overwrite the original evidence.

The write test verifies authenticated snapshots, a real ten-draw with the
configured ticket cost, two retries of the identical operation/request without
another debit or award, account isolation including the same operation ID on
another player, preservation of permanent content, and rejection of raw old-save
uploads. Idempotency is scoped to the existing game contract's full command ID
(`session:kind:request_id`), not unrelated requests from a new game session.

## Server: restart and persistence check

Record `systemctl show goufayu-api.service -p MainPID -p ActiveState`, restart
the service, wait for authenticated readiness, and record the new PID. This is
separate evidence of a real restart; a fresh HTTP connection alone proves none.

```sh
systemctl restart goufayu-api.service
/opt/goufayu/releases/current/.venv/bin/python /opt/goufayu/releases/current/tests/lottery_upgrade_acceptance.py \
  --verify-report /var/lib/goufayu/acceptance/lottery-write.json \
  --report /var/lib/goufayu/acceptance/lottery-after-restart.json
```

Verify mode needs no runtime database configuration and rejects fixture-service
or fixture-passfile arguments. It reads the private token file and rereads the
same two profiles and snapshots, comparing their full-save hashes and revisions.
It submits no new business commands. The profile API may still ensure/upsert or
drain pending settlements as in normal game reentry; it is not a read-only SQL
transaction. A changed bundle hash is rejected rather than silently comparing
incompatible versions.

## Other required checks

Run existing `http_acceptance.py` for archive, online-time and replay behavior.
Run `test_postgres_acceptance.py --focused-current --confirm-test-writes` with
the same runtime environment and **without** `GOUFAYU_TEST_ADMIN_SERVICE` for
old-revision permanent-reward protection and failed-database HTTP behavior.
The latter uses a deliberately unreachable local port on a separate test HTTP
instance and checks the real healthy database afterward. It does not stop the
existing database or claim to have tested a database service outage.

Use the upgrade's rollback SQL acceptance separately to verify direct lottery
commit idempotency, stale inventory/revision rejection and function permissions.
Game-client play, real payments and offsite backup recovery are outside this
script's claims.

## Local: offline script regression

```text
python -B -m unittest discover -s server/aliyun/tests -v
```

Leave `GOUFAYU_ACCEPTANCE` unset locally. The database tests then skip explicitly.
