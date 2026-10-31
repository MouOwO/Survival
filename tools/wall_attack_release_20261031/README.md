# 3101 game-package update

Base: verified Workshop item `3824360109`, sequence `2026103004`, content `5cdb3ad487e7f70ad22ba37658a4a10c14d56ad96ed566a223b787d058f87913`.
New identity: `2026103101 / WS4-WALL-ATTACK-PERF-01`. The original item remains Unlisted with the original four-account admission, payments and d573 backend bytes. These tools never deploy a server.

The current state is **pending_wall_fix**. No signed3101 candidate, VPK output, native acceptance, upload or download exists yet. The external `*_pending_wall_fix` directory contains eleven approved runtime replacements plus an explicit blocker marker. It has no release manifest/signature and cannot pass the publisher.

## Frozen scope

| Input | Fixed source | Runtime effect |
|---|---|---|
| Blademaster scene | `deadad5a3` | One new map and `monster_portrait_scenes.vjs_c`; the old already-shipped map remains unused |
| Query portrait, performance, daily availability | `753de9888` (includes `fb44509f4`) | Four UI scripts, one stylesheet, performance clock and two grid Lua modules |
| Protected asset catalog | Historic production plaintext, single `hero_permanent_hero_blademaster.model_skin: 1→0` | Exactly one protected generated table rebuilt with the pinned private-RNG pipeline; all other values/aliases exact |
| Wall repair | Not yet supplied | Requires a nonempty explicit committed-path approval and an actual difference from3004 |

The known scope adds two files (one map and `core/performance_clock.lua`):6915 total runtime files,189 packaged portrait maps,188 active scene identities after deduplication. Exactly183 protected modules remain byte-identical and one catalog module is rebuilt. The current Git catalog has historical name/notes differences, so it is deliberately not copied wholesale.

## Commands

Use `D:\Survival_安全工具\venv\Scripts\python.exe`; the ordinary Python314 environment lacks cryptography. All external artifact paths must be new. SDK operations need the reviewed local Steam environment and unchanged owner/app guards.

Read-only plan, already performed:

```powershell
& $releasePython tools/wall_attack_release_20261031/build_release.py --report output/wall_attack_release_20261031/plan_pending_wall_fix.json
```

Unsigned pending preparation, already performed once; rerunning the same path refuses overwrite:

```powershell
& $releasePython tools/wall_attack_release_20261031/build_release.py --prepare --report output/wall_attack_release_20261031/pending_artifacts.json
```

After a confirmed committed repair, supply a NEW reviewed JSON:

```json
{
  "source_revision": "<full wall-fix commit>",
  "paths": ["scripts/vscripts/systems/<actual_confirmed_wall_module>.lua"],
  "reason": "<confirmed cause and repair>",
  "fix_confirmed": true
}
```

Only1–6 narrow systems/modifiers/UI Lua paths are accepted. Config, account/auth, archive, commerce/payment and profile authority cannot be added this way. Existing fixed performance inputs cannot be replaced by the wall approval. Every wall path must actually change relative to3004. This is an explicit source-scope approval, not native gameplay acceptance.

```powershell
& $releasePython tools/wall_attack_release_20261031/build_release.py --wall-approval <wall_approval.json> --report output/wall_attack_release_20261031/plan_final.json
& $releasePython tools/wall_attack_release_20261031/build_release.py --build --wall-approval <wall_approval.json> --reviewed-plan output/wall_attack_release_20261031/plan_final.json --key <existing_external_private_key> --report output/wall_attack_release_20261031/package.json
```

The builder authenticates all baseline bytes, copies sixteen trusted admission reviews, applies only pinned replacements, signs a complete new view, independently verifies it, rebuilds affected native-safe volumes and checks that the old base/journal/inputs did not change. It neither uploads nor starts Dota. No selected protected module ever falls back to plaintext.

Coordinate a separate native test addon `svt_m3101` through `tools/publish_test_release.py` under this builder's `scene_maps()` and `inc.trusted_source(TRUSTED)` contexts. Keep the original four testers and update item3824360109. Installation/startup is distinct from uploading and must not affect a user's current game.

Publisher proof interfaces:

- `native_smoke.json`: same package content SHA, status `PASS_NATIVE_SIGNED_PRODUCTION_STARTUP_ONLY`, `cheats:false`, and exact `signed_resources_verified` count.
- `wall_acceptance.json`: the explicit composite schema below. The candidate SHA binds the publication target; it does **not** claim that the older developer test used the same complete production bundle. Every reference is SHA256 checked and checked again after validation. Missing, draft, failed or changed evidence refuses publication.

```json
{
  "schema": 1,
  "scope": "OFFLINE_NATIVE_COMBAT_MODULE_EQUIVALENCE",
  "candidate_content_sha256": "<actual signed candidate content SHA256>",
  "online_multiplayer_acceptance": false,
  "raw_acceptance": {"path": "<four-mode native acceptance JSON>", "sha256": "<SHA256>"},
  "raw_timeline": {"path": "<unaltered native timeline JSON>", "sha256": "<SHA256>"},
  "loaded_proof": {"path": "<fresh VM loaded_proof.json>", "sha256": "<SHA256>"},
  "equivalence_proof": {"path": "<combat_equivalence_proof.json>", "sha256": "<SHA256>"}
}
```

The raw four-mode proof retains its original PID/world: standard/pure/rich/cold N1, completed legal wall, autonomous native attack records, observed damage events and positive wall health loss in every case. The raw timeline SHA and explicit restored single-cohort/no post-spawn actor intervention scope are verified. This is offline Tools evidence, not online multiplayer acceptance.

The separate loaded-source proof requires a newly started VM after the candidate input freeze. It binds exactly the two plain wall repair files to signed-view source hashes, checks actual native transport identity, every captured live function dump against the frozen source compilation, scalar upvalues and unchanged real class/module bindings. Frozen files and bytecode captures are explicit hash references. The scoped equivalence proof separately verifies the source dependency closure, exact plain bytes or protected deep values/original protection provenance, precise known exceptions, unchanged spawn/completed-wall function projections and N1/KV inputs. Its status must be `PASS_SCOPED_COMBAT_EQUIVALENCE` with `passed:true`; it explicitly makes no whole-module, whole-bundle or online claim. The building tutorial gate removal and wave overflow/defeat-policy differences remain documented exceptions; a single N1 cohort stays below their triggering limits.

An optional `fresh_replay` hash reference may accompany the composite. Its PID/world/session and loaded-proof ID must match the new VM. It never rewrites or rebinds the older four-mode evidence. Signing can finish before native evidence is available; publication cannot.

Each equivalence `fix2` row also records `candidate_binding`: immutable `source_revision`, `normalization:"CRLF_TO_LF_ONLY"`, `candidate_git_sha256`, `native_dev_raw_sha256` and `normalized_native_dev_sha256`. The guard reads both raw files, requires the signed candidate to contain LF only and to equal the development file after replacing CRLF with LF, and checks the actual immutable Git blob. Raw development hashes remain raw; no other whitespace or source changes are accepted by this normalization.

If the VM starts while the full bundle is still being signed, the eventual candidate input manifest keeps its real later creation time and adds an explicit `approved_source_freeze` path/SHA256 reference. That earlier manifest must predate the process, name the package's exact approved immutable commit, and contain exactly the two fix files whose frozen bytes equal both the real Git blobs and the final signed manifest hashes. This permits an honestly recorded source freeze before launch; it never backdates a candidate or relaxes exact live-source equality.

After reviewing the actual completed `package.json` SHA:

```powershell
& $releasePython tools/wall_attack_release_20261031/publish.py --report-sha256 <actual_completed_report_sha> --native-proof <native_smoke.json> --wall-proof <wall_acceptance.json>
& $releasePython tools/wall_attack_release_20261031/publish.py --report-sha256 <actual_completed_report_sha> --native-proof <native_smoke.json> --wall-proof <wall_acceptance.json> --apply
& $releasePython tools/wall_attack_release_20261031/verify_download.py --report-sha256 <same_actual_completed_report_sha> --download
```

The publisher defaults to preflight. Apply delegates to the unchanged SDK publisher with `--update-existing` and the original publication lock/journal. Unknown `SUBMIT_REQUEST_PENDING` results stop the process; do not clear or resend automatically. The verifier reuses the frozen official fresh-query,1313 and3406 protocol, requires a successful same-release upload, validates all five files/CRC/dual hashes/signature and records the actual decimal-string ACF manifest. It does not edit the upload journal. Close only coordinated test processes holding the Workshop install before the official download.

## Cost and isolation

This is an explicit offline operator, not a game timer. Immutable Git blobs and the197-entry scene inventory are indexed once per invocation. A plan processes6915 manifest rows inO(N log N) canonical sort plusO(K) small replacement data. Protection processes exactly one table with full deep-value/alias/RNG checks. Explicit authentication/packing phases each stream the necessary signed inventory/3.78GB archives; those are intentional one-shot integrity passes, not polling or scene hot-path scans. The pending overlay copies onlyK replacements; the final complete view and unchanged volumes reuse hard links that are never opened for writing. Shared base files, developer runtime, backend, payment state, visibility, account list and canonical journal remain unchanged during preparation/build.
