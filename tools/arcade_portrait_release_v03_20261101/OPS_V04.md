# v04 operation adapter for the same signed fourteen-path candidate

This is an operation/evidence revision, not runtime sequence1104. Runtime stays
sequence2026110103, source `ceede161d3a009ef5034a5965a1a6c5393930bc2`, package
report SHA `0df36ca48ef617220268bf15d80b2e726a036721112d33226d2379eb45ce090e`,
content `c28c43f6983a1a2f5c086b4c025edfa58ea4b6419186d91edda1c830df2c030a`.
No frozen v03/parent/builder/checks/plan/package file is changed. The original
item, four accounts, HTTP1, cheats0 and non-Tools production entry remain.
The default operation is a static plan, with zero native input, SDK or writes.

## Actual previous failures and the new boundaries

The first transaction requested an external Chinese-path `engine.log` which
never appeared. Its ordinary process and keeper identities were valid. The
same `-condebug -con_logfile ABSOLUTE_PATH` argument form successfully created
ROOT/output/arcade_portrait_perf_20261031/ordinary_logged/
workshop_20261031T180338719924Z_329243a4/game.log for ordinary PID8200: creation
2026-10-31T18:03:42Z followed its18:03:38 launch, length322988B. v04 retains that
observed argument form and routes a new engine-created log to:
`ROOT/output/arcade_portrait_rehearsal_v04_20261101/TRANSACTION/engine.log`.
The dedicated run directory must be NEW. The helper never prewrites, copies,
links or fabricates engine.log. process.json records its native log origin and
exact route. live_record, inspect and publish_v04 all validate the same route.
Absence of the actual native log still refuses inspection/publication.

The previous hold_failed receipt records only a generic error. It does not
prove the exact exception. The inherited lifetime verifier did call
QueryFullProcessImageNameW again after the process object became signaled;
that API can fail after termination. v04 strictly binds creation FILETIME,
CIM microsecond bucket and executable on the live retained process handle.
It rejects an already-exited process at initial binding. Stable observation
uses only WaitForSingleObject(handle,2000). After the same object is signaled,
it requires unchanged native100ns creation and a positive actual exit FILETIME
from GetProcessTimes, without another image query, PID lookup or new handle.
A query failure, altered creation pin or invalid wait still refuses evidence.

The keeper no longer runs a late CIM inventory after it has already observed
that exact process exit. hold_end explicitly records end_no_dota_verified=null
and end_no_dota_check_deferred_to_restore=true. This is not a claim that no
other Dota exists. The unchanged official restore still requires its current
no_clients check, actual keeper exit, ACF item identity and full five-file
backup/CAS/verification before any restoration write. publish_v04 requires the
new exact native exit proof AND successful fully verified restoration.

## Explicit root operations

Run native actions in an elevated context: restricted sandbox CIM returned
failure even while the same fixed read-only script succeeded when elevated.
Never weaken that guard or adopt a PID because the query failed.

```
python -B tools/arcade_portrait_release_v03_20261101/rehearsal_v04.py
python -B tools/arcade_portrait_release_v03_20261101/rehearsal_v04.py stage --transaction run02_candidate14 --report-sha256 0df36ca48ef617220268bf15d80b2e726a036721112d33226d2379eb45ce090e
python -B tools/arcade_portrait_release_v03_20261101/rehearsal_v04.py launch --transaction run02_candidate14 --report-sha256 0df36ca48ef617220268bf15d80b2e726a036721112d33226d2379eb45ce090e
```

All Dota clients must be closed before stage/launch. The original3102 must be
installed and authenticated, Steam online, and the normal release approval must
cover the same signed candidate. The new transaction store is
`D:/Survival_本地排演/20261101_ws4_portrait_perf_teleport_snapshot_v04`, port29048.
Keep the launch terminal alive. Before any ETW sample, root must independently
observe that the actual engine-created local log exists and grows; otherwise
stop this attempt and preserve receipts. Do not repair it by copying another
log or relaxing startup markers. No GUI, login approval or business operation
is automated by this helper.

Use the same command with inspect --label before01 / after01, then close and
restore as separate explicit actions. close still queues only one WM_CLOSE to
the exact owned main window, never force-stops or changes foreground. Successful
keeper exit writes hold_end and releases its five deny-write/delete file holds.
A lifecycle failure now additionally writes keeper_exception.json with a bounded
local exception code, retaining hold_failed. Never call a failed attempt PASS.

publish_v04.py has the same explicit --preflight / --apply contract as the
frozen publish_v03.py, but binds v04 store, native log origin/route and exit
proof. It retains full signed6918/184 authentication, root pixel review,
ordinary foreground ETW>=30s/120frames, mean>=90FPS/P95<=16.7ms, all real fatal
network diagnostics, successful full3102 restore and canonical journal gates.
No root-reviewed evidence means no SDK or update. Final normal Workshop FPS is
still a separate post-upload requirement, never prewritten as passed.

## Cost and regression scope

Live identity binding makes one kernel wait0, one GetProcessTimes and one image
query per process handle. Each stable2s observation makes exactly one kernel
wait and no CIM, image query, file hash or scene scan. Exit makes a constant
number of same-handle wait0/GetProcessTimes calls. All memory is O(1) for this
observer. Stage/full authentication retains the existing linear package I/O;
there is no new game hot path. Log directory initialization is O(1), without a
background log poll or copy loop.

Isolated tests mock all Windows/SDK/launch/input operations. They exercise real
ctypes API declarations and FILETIME by-reference layout, precise native pins,
terminated-image rejection, exit-only proof, wait errors and actual package/
log configuration. Synthetic production-preflight tests exercise the new log/
exit schema plus fatal-network and publication boundaries. These tests are not
native graphics, FPS, client stability or successful Workshop acceptance.
