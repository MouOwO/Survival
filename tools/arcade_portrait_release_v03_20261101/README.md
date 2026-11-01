# v03: snapshot UI-wire, portraits and teleport

This is a new fourteen-path candidate, sequence `2026110103`, revision
`WS4-PORTRAIT-PERF-TELEPORT-SNAPSHOT-03`, native alias `svt_ap1103`.
Its only parent is the officially downloaded 3102 package. The unpublished
signed v02 candidate and all v01/v02 tool bytes and outputs remain unchanged.
The original item stays `3824360109`, Unlisted, with the same four accounts,
production policy and d573 commerce contract. No reward, purchase or redeem
operation belongs to these validation tools.

The fourteen runtime paths are the exact v02 thirteen plus
`scripts/vscripts/systems/archive_service.lua`. The existing renderer,
commerce_actions and combat_stats Git-LF/compiler-input/official-artifact
bindings stay unchanged. There are still 6918 resources and 184 protected
modules. archive_service is ordinary source Lua, outside the protection policy;
none of the 184 modules is transformed again or replaced with raw source.
The full signed manifest and all five VPK files are still authenticated.

`trusted_review_pins` has seventeen entries: the original sixteen admission
sources remain byte-identical to 3102 and the seventeenth is the new archive
source from the same immutable commit as the fourteen payloads. The separate
`archive_source_review` records a UI-wire source review only, not an assertion
that every package feature has passed native execution.

## Required freeze before a plan

`ARCHIVE_SOURCE_SHA256` is now pinned to root-reviewed Git-LF source
`6a50c80d15ba98374d8a7df31aa664112070a8ffb4e8b71867a0fd1ae2cddec4`.
The reviewed physical CRLF source is69271B, SHA
`51b554d203485c1ccad6fa9d91cd197cf91ff6400e572e3cdf8c7455f617cd4b`.
`ARCHIVE_SOURCE_REVIEW_STATUS` is `ROOT_REVIEWED_UI_WIRE_ONLY`. This is source
review, not native acceptance. The target Lua bytes are the exact committed
Git-LF blob, not the CRLF worktree bytes. Missing pins reject collection, plan, unsigned preparation
and signing before any private key operation. An explicit forty-character
immutable `--source-revision` is mandatory. The two operation adapters also
start with `RUNTIME_SOURCE_REVISION` / `SOURCE_REVISION` unset; they cannot run
a real action until root pins the final commit. Operation-source pins are
separate from the runtime source identity and the frozen build plan.

Default `build_release.py` prints a static plan and performs zero Git, OS,
Steam, key, write or package action. `--scope` is only a read-only worktree
inventory, not a release plan or acceptance. After the source freeze, root can
create a new plan beneath `output/arcade_portrait_release_v03_20261101`, review
its exact SHA and use `--prepare` for an unsigned review. Unsigned output is
marked `UNSIGNED_DO_NOT_INSTALL_OR_UPLOAD` and contains no signature. `--build`
is separately explicit and requires the reviewed plan SHA and an existing key;
this preparation task does not authorize or execute it. No tool here reads a
key by default or publishes during building.

All external candidate/overlay/trusted/unsigned/output names use the new
`20261101_ws4_portrait_perf_teleport_snapshot_v03` prefix. Directory disjointness
includes the 3102 parent and v01/v02 outputs. Final directories and reports are
exclusive NEW paths. Unknown or pending canonical journal state is preserved
and rejected; no history is cleared.

## Operation and evidence path

See [OPS.md](OPS.md). Ordinary signed-candidate local rehearsal is distinct from
an official download and from final Workshop acceptance. No development or
synthetic-profile evidence can qualify as production evidence. A known snapshot
disconnect, CustomGameEvent serialization failure or oversized reliable payload
in the actual engine log blocks publication even when root marked the client
responsive. New cold-native and ordinary portrait/FPS/stability evidence must
come from this exact signed fourteen-path candidate.

## Costs and isolated checks

Static import reads a fixed set of tool files only. Planning is one manifest
projection/index of 6918 rows plus fourteen immutable payloads and three source
bindings, O(N+K) time and O(N) memory. There is no game refresh loop. Full local
authentication is O(total package bytes + N); the parent five volumes contain
about 3.79 GB. Rotation recalculates the changed archive set rather than assuming
the old two-volume result. Build writes changed resources, new metadata and only
changed archive volumes; unchanged payloads and volumes use immutable hardlinks.
Rehearsal physically backs up all original five files and stages all candidate
five files before optimistic compare/replace; this is not atomic against Steam.
The stable keeper uses only a read-only owned-process wait, with no repeated
hashes or CIM scan during ETW. Evidence parsing is off the game path: fixed refs
and O(F log F) bounded frame sorting, not a gameplay performance measurement.

Run the four `test_*.py` scripts with the pinned crypto Python and `-B`. Tests
mock Git, keys, SDK, Windows and game actions and use disposable synthetic local
files. Their pass is not native gameplay, visual, FPS or network acceptance.
