# Fifth approved account, four-player matches

This independent release adds SteamID64 `76561198296534615` (account `336268887`)
to the original four approved accounts. It preserves four simultaneous players,
Steam OpenID authentication, session roster binding, server ownership, cheats0,
payment authorization, d573 and the original Unlisted item `3824360109`.

The only runtime replacements are `config/test_access`, `core/test_access_policy`,
`core/commerce_release_policy`, `systems/native_cloud_handoff`,
`systems/native_cloud_roster` and `systems/native_transport_probe`. All184
protected modules and all other6911 resources remain byte-identical to verified
3102. The parent is `318491d5...b45352`,6917 files, actual Steam manifest
`2484609663754935010`. The unpublished14-path0103 candidate is immutable and is
never an input. Once this0104 release is published, that old four-account0103
cannot be used to overwrite the newly approved roster; a future combined release
requires a fresh sequence and new review.

The operator applies exact reviewed admission changes to frozen3102. Five
payloads must equal their immutable Git-LF source in full. The policy payload
retains exactly three old `offline_onboarding` blocks already shipped in3102;
removing only those three blocks must reproduce the new Git-LF policy exactly.
This is explicit source projection, not a claim of whole-file Git equality.
No tutorial removal or other development change is carried in this account fix.
The plan includes both hashes and the entire six-file normalized diff.

The original16 trusted-review snapshots are preserved. Four reviewed admission
snapshots are replaced in the new independent trusted directory, and explicit
commerce/probe reviews are added (18 total). Candidate-only contexts accept
exactly the approved five literal IDs and two new handoff/roster pins; all old
parsers/pins are restored in `finally`. Parent validation always uses its
original four-account context, even when nested inside official download.
No historical builder, review or signature is edited.

Use the existing crypto Python, with `-B -X utf8`:

```powershell
python build_release.py                         # static, no external action
python build_release.py --scope --report <NEW scope.json>  # unsigned worktree diff
python build_release.py --plan --source-revision <40char-commit> --report <NEW plan.json>
python build_release.py --build --source-revision <same-commit> --reviewed-plan <plan.json> --reviewed-plan-sha256 <reviewed-SHA> --key <existing-external-key> --report <NEW package.json>
```

Planning and signing are separate. Every output directory is NEW; existing
partial or failed artifacts are preserved. Signing never uploads or deploys.
Use sequence `2026110104 / WS4-FIVE-ACCOUNT-ADMISSION-01` and the new
`20261101_ws4_five_account_admission_v01` directories only. Unknown/pending
canonical journal states reject the plan and are never cleared automatically.

`native.py install --report-sha256 <package-SHA>` validates the signed inventory,
copies only6917 authenticated resources to `svt_f1104`, then writes a truthful
five-account/four-player receipt. The old helper is used only for dry validation,
whose static count4 is never written as this install's receipt. `launch`,
`query`, `collect`, `close` are separate explicit actions, bound to the owned
PID/addon/creation time. Query only sends `sv_cheats` and
`survival_archive_http_enabled`, without Lua injection. Startup evidence does
not claim that the new player authenticated or that multiplayer was tested.

`publish.py` defaults to preflight. It requires exact package, native-proof and
server-proof SHA values. Server proof must establish active exact-five web and
archive policies, preservation of all old accounts, unchanged payments/d573,
unchanged Unlisted visibility and explicit no-real-login claim, with raw backup,
activate and verify receipts. `--apply` updates the original item only.
`verify_download.py --report-sha256 <same> --download` then requires a successful
same-release upload and the unchanged official1313/3406/fresh-query/full-VPK
protocol. Unknown submission state stops the flow and preserves its journal.

Planning is one O(N+K) inventory projection (N6917,K6), with O(N) metadata memory.
Authentication/packing/installation are explicit one-shot byte-stream integrity
passes over3.79GB. No scene loops, recurring native/API/network calls or gameplay
timers are introduced. Native query is two read-only commands plus one nonce.

The frozen SDK still uses an old four-account phrase in its automatic changelog prefix. It is historical wording, not admission authority: this release’s actual listing, signed roster and installation receipt contain exactly five approved accounts with four player slots. The SDK’s authentication/publishing code is retained unchanged.
