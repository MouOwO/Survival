# SurvivalContent Multiplayer Topology Validation

Status: BLOCKED / LIVE MULTIPLAYER EVIDENCE INCOMPLETE  
Date: 2026-08-25  
Scope: TASK-000; documentation and evidence validation only

## 1. Test Setup

### 1.1 Environment inspected

| Item | Observed value |
| --- | --- |
| Primary workstation | `E:\steam\steamapps\common\dota 2 beta\game\dota_addons\Survival` |
| Local Dota process at inspection time | Not running (`dota2`/`source2` not observed) |
| Local Python API at inspection time | Not running; no listener on `127.0.0.1:8765` |
| Configured API endpoint | `http://127.0.0.1:8765` |
| Python implementation | Independently started `ThreadingHTTPServer` application in `D:\survival_database` |
| Authoritative configuration source | `data/csv/玩家档案系统/fishing_system_rules.csv` |
| Generated configuration | `scripts/vscripts/config/generated/fishing_system_rules.lua` |
| Second/third PC and real Steam accounts | Not available to this execution |

The configured endpoint was read from the authoritative CSV. The generated Lua contains the same endpoint; no configuration was changed for this validation.

### 1.2 Required real test roles

The requested B-E tests require at least two PCs and two real Steam accounts. Test E requires a third player/account. The test operator must start Python only on the candidate host being tested and must collect redacted identifiers, never raw Steam IDs or credentials.

## 2. Test Steps

### Test A - Existing Workshop Baseline

1. Start the Python API on the same Windows machine as Workshop Tools.
2. Confirm the API readiness line and `GET /health` on `127.0.0.1:8765`.
3. Start the local Workshop game and trigger the existing profile/checkpoint path.
4. Correlate the Dota server Lua log with the Python request log using redacted `PlayerID`, `session_id`, and `request_id`.
5. Stop the API and Dota processes after capturing logs.

### Test B - Two-PC Published Arcade

1. PC-A creates the normal published Arcade lobby and is recorded as Lobby Owner.
2. PC-B joins with a different Steam account.
3. On both PCs, record hostname, Dota process/log location, and whether Python is running.
4. Record only redacted Steam identity, PlayerID, displayed Match ID, `session_id`, `request_id`, and checkpoint events.
5. Identify the machine that emits authoritative server-side Lua logs and the machine whose loopback receives the corresponding HTTP requests.

### Test C - Owner Leaves

1. Repeat Test B with a stable checkpoint already observed.
2. PC-A leaves while PC-B remains in the match.
3. Record whether the match, server-side Lua runtime, and Python request flow continue.
4. Record whether A receives a final request and whether B remains active.

### Test D - Non-owner Disconnect/Reconnect

1. Repeat Test B and record PC-B's Match ID, PlayerID, account pseudonym, runtime nonce, and session.
2. Disconnect PC-B without ending the match.
3. Record disconnect/final events and whether the old session is finalized.
4. Rejoin with PC-B and record Match ID, Game Server identity, PlayerID, account pseudonym, and new session.
5. Determine whether reconnect resumes the same match/server and whether the old session is distinct from the new one.

### Test E - Two/Three Player Isolation

1. Run the same published match with players A/B/C.
2. Compare redacted persistent account pseudonyms, PlayerIDs, sessions, checkpoints, and final requests.
3. Confirm that no player's checkpoint, reward, or finalization is attributed to another player.

## 3. Observed Results

### Test A - Existing Workshop Baseline: PARTIALLY VERIFIED (historical evidence)

The repository contains prior Workshop evidence showing the following limited path:

```text
Workshop Dota server-side Lua
        -> http://127.0.0.1:8765
        -> Python ThreadingHTTPServer
        -> Supabase RPC/PostgreSQL
```

The captured API log contains `FISHING_API_READY http://127.0.0.1:8765`, health responses with HTTP 200, and a checkpoint response with `elapsed_seconds=11`, `online_seconds_total=11`, and `grant_count=1`. Project session records also document a user-accepted Workshop wall-destruction final with `final=true` and API HTTP 200.

This establishes the local same-host baseline for the tested Workshop path. It does not establish normal published Arcade topology. At the time of this validation, neither Dota nor Python was running, so no new live baseline run was performed.

### Test B - Two-PC Multiplayer: NOT EXECUTED

No second PC, second live Steam account, published Arcade lobby, Match ID, or paired host logs were available. Therefore Game Server host, Lua host, Python recipient, PlayerID mapping, and account mapping remain UNKNOWN.

### Test C - Owner Leaves: NOT EXECUTED

No live owner-departure observation exists. Match continuation, Lua lifetime, Python delivery, owner finalization, and remaining-player behavior remain UNKNOWN.

### Test D - Non-owner Disconnect/Reconnect: NOT EXECUTED

No live disconnect/reconnect observation exists. Same-match continuity, same-server continuity, old-session finalization, new-session creation, and persistent-account continuity remain UNKNOWN.

### Test E - Player Isolation: NOT EXECUTED

No two-player or three-player live run was captured. Independent persistent accounts, PlayerIDs, sessions, checkpoints, and finalization have not been proven in a published match.

## 4. Evidence

| Evidence | Level | What it proves | What it does not prove |
| --- | --- | --- | --- |
| `data/csv/玩家档案系统/fishing_system_rules.csv` | HIGH / STATIC | Current Lua API endpoint is loopback | Where normal Arcade Lua executes |
| `scripts/vscripts/config/generated/fishing_system_rules.lua` | HIGH / STATIC | Generated endpoint matches CSV | Runtime host or lobby behavior |
| `D:\survival_database\fishing_api.stdout.log` | HIGH / HISTORICAL | Python previously bound to `127.0.0.1:8765` | That a published game server can reach this process |
| `D:\survival_database\fishing_api.stderr.log` | HIGH / HISTORICAL | Prior health/checkpoint requests reached Python | Published Arcade, owner migration, or reconnect |
| `docs/ai/SESSION_LOG.md` and `docs/ai/tasks/TASK-001.md` | HIGH / WORKSHOP RECORD | Limited Workshop checkpoint/final evidence | Normal published multiplayer topology |
| Current process/socket inspection | HIGH / CURRENT STATIC | No Dota/Python/8765 listener during this validation | What happens during a live match |
| No Test B-E capture | HIGH / CURRENT | The required live evidence is absent | Any topology classification other than UNKNOWN |

Sensitive values were not copied into this report. No raw Steam Account ID, credential, or secret is recorded.

## 5. Topology Diagram

### Verified local Workshop candidate

```text
One Windows host
  Dota authoritative Workshop process
    server-side Lua runtime
      HTTP: 127.0.0.1:8765
        Python ThreadingHTTPServer
          HTTPS
            Supabase
```

Classification for this limited environment: candidate `MODEL-A`.

### Normal published Arcade: unresolved

```text
PC-A: Lobby Owner                  PC-B: Player
          \                         /
           \                       /
             [UNKNOWN Game Server]
                [UNKNOWN Lua host]
                       |
                 [UNKNOWN Python host]
```

`127.0.0.1` can only mean the loopback namespace of the process issuing the request. Without identifying the Lua/Game Server host, it cannot be mapped to PC-A, PC-B, or an allocated server.

## 6. Final Classification

**Normal published Arcade: `MODEL-D`.**

The local Workshop candidate is `MODEL-A`, but the required published two-PC and owner/reconnect experiments were not executed. There is no evidence that permits selecting `MODEL-A`, `MODEL-B`, or `MODEL-C` for normal Arcade.

## 7. Impact on Python Loopback

The current `127.0.0.1:8765` design is valid only when Python shares the network namespace of the Dota server-side Lua caller. It is not yet a deployment basis for normal Arcade. Do not change the bind address or expose the API as a topology workaround in this task; first identify the authoritative Game Server host and its reachability boundary.

## 8. Impact on Session Architecture

Production Session Foundation remains paused. In particular, the system must not yet assign Match identity, Lua runtime ownership, Python ownership, or process lifetime based on Lobby Owner assumptions. Existing local Workshop behavior remains valid only within its accepted scope.

## 9. Impact on Reconnect

Reconnect semantics remain unverified. The project must not claim same-match continuity, same-server continuity, or finalization of an old session until Test D records Match ID, Game Server identity, old/new `session_id`, redacted account identity, and final delivery.

## 10. Impact on Finalization

The prior Workshop finalization acceptance remains limited to the tested local path. Published owner departure, non-owner disconnect, server termination, and final-request delivery before process exit are unknown. A Python HTTP 200 in a local test cannot establish a published server's final-request delivery guarantee.

## 11. Remaining Unknowns

- Which process runs the authoritative Dota Game Server in a normal published Arcade match.
- Which machine runs server-side Lua and whether all players share one Lua runtime.
- Which machine's `127.0.0.1:8765` can receive Lua requests.
- Whether Lobby Owner equals Game Server Host.
- Whether the match and Lua runtime survive Lobby Owner departure.
- Whether a non-owner reconnects to the same Match/Game Server.
- Whether old sessions finalize and new sessions are created on reconnect.
- Whether persistent account identity remains stable across reconnect.
- Whether two or three players have isolated sessions, checkpoints, and finalization.
- Whether the current Python loopback architecture can support normal Arcade deployment.

## Stop Condition

No production Session, HTTP, Database, Reconnect, Finalization, or Purchase code was changed. Because Test B-E are not executed, this validation artifact intentionally stops at `MODEL-D`; the next action is the real two-PC or three-PC published-Arcade experiment.

**SurvivalContent 当前真实多人拓扑是 MODEL-D：正常发布 Arcade 的 Game Server、server-side Lua、Python loopback 和 Lobby Owner 关系仍未通过真实多人实验确认。**