# SurvivalContent Multiplayer Topology Report

Status: INVESTIGATION COMPLETE / PRODUCTION TOPOLOGY UNKNOWN
Date: 2026-08-25
Decision Gate: MODEL-D for normal published Arcade; candidate MODEL-A for the tested local Workshop topology

## Executive Decision

Current evidence proves only this deployment:

```text
one Windows machine
  Dota/Workshop server-side Lua
          |
          | http://127.0.0.1:8765
          v
  independently started Python ThreadingHTTPServer
          |
          | HTTPS
          v
  Supabase RPC/PostgreSQL
```

This is a candidate `MODEL-A`: Dota server-side Lua and Python are colocated. It is valid for the accepted TASK-001 Workshop Tools scope. No evidence collected here proves that a normal published Dota 2 Arcade lobby uses the lobby owner's process as the game server, that server-side Lua runs on the lobby owner's PC, or that a Valve-allocated server can reach Python on that PC through its own `127.0.0.1`.

Normal Arcade production is therefore `MODEL-D`. Do not implement or extend production Session architecture until the experiment in this report identifies the actual game-server process and the meaning of loopback in a published lobby.

The mission requested `ai/architecture/MULTIPLAYER_TOPOLOGY_REPORT.md`. This repository has no root `ai/` directory; its active AI knowledge base is `docs/ai/`. This report is consequently stored at `docs/ai/architecture/MULTIPLAYER_TOPOLOGY_REPORT.md` to avoid creating a second documentation root.

## Evidence Scale

| Confidence | Meaning |
| --- | --- |
| HIGH | Directly established by current code, configuration, or captured project test evidence |
| MEDIUM | Supported for a limited scenario, but not transferable to normal Arcade without testing |
| LOW | Plausible candidate only; insufficient Dota Arcade-specific evidence |
| UNKNOWN | No reliable evidence currently establishes the claim |

## Topology Candidates

| Candidate | Game server / Lua | Python | Meaning of `127.0.0.1` | Classification |
| --- | --- | --- | --- | --- |
| Local Workshop / local launch | Local Dota process on the developer machine | Manually started on the same machine | Developer machine from the Lua HTTP caller's network namespace | Candidate MODEL-A; Workshop evidence supports this limited scope |
| User-hosted / listen-server or LAN | A nominated user's Dota process, if Dota actually selects this model | Must run on that same host for current config | Nominated host | Candidate MODEL-A; not verified for the current Dota build |
| Valve-allocated game server | Valve/Steam allocated server; all players would connect to it | Current local Python is not known to exist there | Allocated game-server machine/container, not lobby owner's PC | Candidate MODEL-B; likely incompatible with current loopback design, but applicability is unverified |
| Normal published Arcade | UNKNOWN | UNKNOWN | The machine/network namespace running server-side Lua | MODEL-D until a live published-lobby test resolves it |

Steam Datagram Relay or P2P may affect transport, but neither changes loopback semantics: `127.0.0.1` always names the HTTP caller's own network namespace. Relay/P2P evidence does not prove where Lua or Python runs.

## Process And Session Boundaries

```text
Lobby
  Steam coordination object; has a Lobby Owner
  != proven Match
  != proven Game Server

Match
  one launched game instance
  current Survival payload has no authoritative match_id

Game Server
  authoritative Dota process for gameplay and server-side Lua
  current HTTP request originates from its Script VM

Client
  one player's Dota client/Panorama
  does not call Python or Supabase in the current design

Player Session
  Lua state keyed by in-match player_id
  session_id = runtime nonce + process-local sequence + player_id
  persistent account = server-resolved Steam Account ID, HMACed by Python

Backend Session
  Supabase online-time state addressed by account_id + session_id
  request_id provides checkpoint idempotency
  no current lobby_id or match_id is submitted
```

Lobby Owner is a lobby arbitration role. The Steamworks Matchmaking and Lobbies documentation says a lobby has one owner and describes launch paths where users join a game server or connect to a user nominated to host. This proves only that generic Steamworks concepts do not make Lobby Owner and Game Server automatically identical. It is not Dota 2 Arcade-specific evidence and cannot select a Survival production topology.

## Important Claims

| Claim | Evidence | Confidence | Source | What remains unknown |
| --- | --- | --- | --- | --- |
| Python is loopback-only | Default host is `127.0.0.1`; validation rejects non-loopback hosts; `ThreadingHTTPServer` binds that host and port | HIGH | `D:\survival_database\backend\fishing_api\config.py`, `server.py` | Whether this process can or should run beside a published Arcade server |
| Python is not launched by Dota | `start_fishing_api.ps1` imports `.env` and explicitly invokes `backend/run_fishing_api.py`; no Dota launcher was found | HIGH | `D:\survival_database\start_fishing_api.ps1` | Production process supervisor/deployment model |
| Lua calls the local URL configured by CSV | Enabled CSV row contains `http://127.0.0.1:8765`; provider passes that URL to `CreateHTTPRequestScriptVM` | HIGH | `data/csv/玩家档案系统/fishing_system_rules.csv`, `http_fishing_provider.lua` | The physical machine/network namespace of the Script VM in normal Arcade |
| Current Workshop finalization works in its accepted scope | Captured Workshop evidence showed `final=true`, Python HTTP 200, and persisted online-time result | HIGH for that run | `docs/ai/SESSION_LOG.md`, `tasks/TASK-001.md` | Published Arcade, multiple PCs, owner departure, reconnect, server termination |
| Lobby Owner is not necessarily Game Server | Generic Steamworks launch model distinguishes lobby owner/arbitration from joining a game server or nominated host | MEDIUM as a generic distinction; LOW for Dota applicability | Steamworks `Steam Matchmaking & Lobbies` | Dota Arcade's actual allocation rule and owner migration behavior |
| Published Arcade Lua is colocated with the lobby owner's Python | No Dota Arcade-specific documentation or live test establishes this | UNKNOWN | Investigation result | Exact production host, permissions, filesystem, process control, and HTTP reachability |
| Current code has an authoritative Match identity | No `GetMatchID`, lobby ID, or `match_id` is sent; runtime nonce is process-local | HIGH that it is absent | Codebase search; `online_time_service.lua`; Python `application.py` | Which Dota identifier is stable and available at the required lifecycle stage |

The Valve Developer Community page for `CreateHTTPRequestScriptVM` could not be used: its正文 was blocked by an Anubis challenge. No execution-side, localhost, or dedicated-server limitation is inferred from that inaccessible page.

## Fifteen Required Answers

| # | Answer and evidence | Confidence | Source | What remains unknown |
| --- | --- | --- | --- | --- |
| 1 | **Yes.** `FISHING_API_HOST` defaults to `127.0.0.1`; validation permits only loopback names/addresses. | HIGH | Python `config.py`, `server.py` | None for current code; production placement is question 3/4. |
| 2 | **An independently invoked PowerShell/Python process starts it.** The script invokes `backend/run_fishing_api.py`; Dota does not start it. | HIGH | `D:\survival_database\start_fishing_api.ps1`, `backend\run_fishing_api.py` | The future production supervisor/deployment process. |
| 3 | **Current integration expects the developer/Workshop host to start Python.** Commands use local paths and the accepted Workshop run reached local port 8765. | HIGH for local tests | Backend `README.md`; TASK-001 Workshop evidence | Which machine could start Python for a published Arcade server. |
| 4 | **Server-side Lua issues the request, but its production machine is UNKNOWN.** The provider uses server ConVars, `PlayerResource`, and `CreateHTTPRequestScriptVM`. | HIGH for code side; UNKNOWN for host | `http_fishing_provider.lua`, `addon_game_mode.lua` | Physical host/network namespace of the Script VM in normal Arcade. |
| 5 | **No one-player-per-process assumption.** Tables are keyed by `player_id`; several players share one runtime nonce and provider. There is no first-class Match object. | HIGH | `online_time_service.lua`, `player_profile_service.lua` | Live multi-player behavior under a published server. |
| 6 | **Yes.** Finalization assumes Python is reachable on the Lua process's loopback because every checkpoint/final uses the CSV URL. | HIGH | `fishing_system_rules.csv`, `http_fishing_provider.lua` | Whether production Lua and Python can be colocated. |
| 7 | **Two players should receive separate Lua sessions/accounts while sharing one endpoint/runtime.** `HERO_READY` starts by PlayerID; Steam Account ID supplies persistence identity. | HIGH for design; LOW for production behavior | `online_time_service.lua`, `http_fishing_provider.lua` | Two-PC production acceptance and actual server fan-in. |
| 8 | **UNKNOWN for a normal lobby.** No evidence proves owner migration, server survival, or disconnect behavior when the owner leaves. | UNKNOWN | No Dota Arcade-specific evidence | Whether owner is host, whether the match survives, and which sessions finalise. |
| 9 | **Current Lua intends to finalise only the non-owner/player who leaves.** `disconnect(player_id)` moves only that record to finalizing state. | HIGH for code; UNKNOWN for engine delivery | `addon_game_mode.lua`, `online_time_service.lua` | Reliability of the event and behavior in a published lobby. |
| 10 | **The final request can be lost if the Dota server ends first.** There is a 30-second HTTP timeout but no durable Lua outbox or post-VM retry. | HIGH | `http_fishing_provider.lua`, `online_time_service.lua` | Real shutdown grace period and callback behavior on allocated servers. |
| 11 | **UNKNOWN in production.** Current logic creates a new session after disconnect and reloads persistence by Steam Account ID. | MEDIUM for intended Lua behavior | `online_time_service.lua`, profile provider/service | Whether reconnect reaches the same server/Match/runtime and whether Lua state survives. |
| 12 | **No authoritative match identifier exists in this path.** `session_id` is runtime nonce + sequence + PlayerID; no lobby ID or Dota Match ID is read/submitted. | HIGH | Codebase search; `online_time_service.lua`; Python `application.py` | Which engine Match identifier is stable and available at session start. |
| 13 | **PlayerID identifies the local slot; server-resolved Steam Account ID identifies persistent data.** Python HMACs the account ID before RPC. | HIGH | `http_fishing_provider.lua`, Python `application.py` | Published-server availability/timing of the Steam Account ID. |
| 14 | **Server-side identity resolution and account-bound database keys provide isolation.** Snapshot account mismatch is rejected and Python uses a secret-peppered database key. | HIGH for static contract; unverified live | Provider/service code; Python `application.py` | Two-player live isolation; impact of a compromised server token or Lua process. |
| 15 | **Runtime nonce plus account/session/request keys reduce accidental sharing, but there is no match namespace.** Backend idempotency only helps requests that carry those keys. | HIGH for current design | `online_time_service.lua`, Python `application.py`, database integration docs | Process reload/reuse behavior, collision observation, and cross-match semantics without `match_id`. |

## Can Python Safely Stay On Loopback?

| Topology | Answer | Reason |
| --- | --- | --- |
| Local Workshop, Lua and Python on one PC | Yes | This is the tested shape; loopback minimizes exposure |
| Confirmed user-hosted/listen server with Python on the same host | Yes, conditionally | The host must start Python before the match and retain server process ownership; this model is not yet proven |
| Valve-allocated/dedicated game server | No, not with the current deployment | Loopback points to the allocated server, where the developer's desktop Python process does not exist |
| Normal published Arcade | UNKNOWN | Actual server allocation and Script VM host are unresolved |

Do not change Python to `0.0.0.0` as a topology probe. That would expand the credential-bearing API attack surface without proving the correct deployment model.

## Minimum Verification Experiment

No production code change is required. Use a published/unlisted Arcade build and two PCs with different Steam accounts. A third account is useful for owner/non-owner departure separation.

### Minimum Scenario Matrix

| Scenario | Required actors | Required observation | Pass criterion | Current status |
| --- | --- | --- | --- | --- |
| Workshop local | One PC, one account | Local Lua send and local Python receipt | Establish known colocated baseline | Accepted for TASK-001 scope |
| LAN/listen candidate | Two PCs; PC-A hosts, PC-B joins | Authoritative Lua location and which loopback receives HTTP | Identify whether PC-A truly owns the game-server process | NOT RUN |
| Normal published Arcade | Two or three PCs/accounts | Server Lua log location, Match ID, Python receipt location | Select MODEL-A/B/C with process evidence | NOT RUN / BLOCKING |
| Lobby Owner leaves | Owner plus at least one remaining player | Lobby ownership, match continuity, per-player final | Distinguish owner role from server lifetime | NOT RUN |
| Non-Owner leaves/reconnects | Owner plus non-owner | Old final, new session, Match/runtime continuity | Establish per-player isolation and reconnect route | NOT RUN |

### Setup

1. PC-A creates the lobby and is Lobby Owner. Start Python on PC-A only; verify `127.0.0.1:8765/health` locally without exposing port 8765.
2. PC-B joins as a non-owner. For the three-player case, PC-C joins as another non-owner.
3. Enable existing non-secret server logs for `HERO_READY`, `session_id`, `request_id`, `player_id`, checkpoint start/response, disconnect, and finish. Never log the API token, pepper, Supabase key, or raw `.env` values.
4. Record Dota's displayed Match ID and lobby ownership separately from Survival's current runtime session ID.

### Exact Runs

| Run | Action | Observation points | Interpretation |
| --- | --- | --- | --- |
| 1: Workshop baseline | Run locally on PC-A with Python on PC-A | PC-A Dota server log and Python request log | Confirms the known candidate MODEL-A baseline only |
| 2: Published lobby reachability | Launch published lobby with PC-A owner and PC-B joined; wait for first checkpoint | Server-side Lua log location; PC-A and PC-B Python logs | PC-A receives request: evidence for owner-host colocation. Neither receives it while Lua logs a send/failure: evidence of another server host. PC-B receives it: unexpected, investigate process placement |
| 3: Owner departure | With sessions active, PC-A leaves while PC-B remains | Match continuity, Lua disconnect/final logs, Python logs, ownership display | Match survives and only A finalises: owner differs from server lifetime. Match dies: consistent with listen host, but still correlate process evidence |
| 4: Non-owner departure/reconnect | PC-B leaves and reconnects | Same Match ID/server logs, old final, new session ID, Steam account continuity | Establishes whether reconnect returns to same server and whether current new-session semantics hold |
| 5: Server/final race | End the match while a checkpoint is in flight | Final send, Python receipt, callback, persisted response | Quantifies loss window; absence at Python proves no durable delivery guarantee |
| 6: Three players | Repeat with A/B/C and end normally | Three account IDs redacted or hashed, three independent session IDs/finals | Establishes multi-player isolation and one-server/one-Python fan-in |

### Required Captured Facts

- Which machine emits authoritative server-side Lua logs.
- Which machine receives `/v1/profile` and `/v1/online-time/checkpoint` on loopback.
- Lobby Owner before and after owner departure.
- Displayed Dota Match ID, each PlayerID, and each redacted Steam account suffix/hash.
- Whether the match continues after owner and non-owner departures.
- Whether reconnect preserves Match ID and server-side runtime nonce or creates a new runtime.
- Whether every final request is received by Python before the Dota server exits.

### Outcome Mapping

| Observation | Classification |
| --- | --- |
| PC-A runs authoritative Lua and its loopback Python receives all requests | MODEL-A for that published hosting mode |
| Another/allocated server runs Lua and neither player's loopback Python receives requests | MODEL-B production; development is A, therefore overall MODEL-C |
| Different launch modes produce both outcomes | MODEL-C with explicit deployment-mode selection required |
| Process location or request path is still ambiguous | Remain MODEL-D; do not implement Session Foundation |

## TASK-001 Impact

TASK-001's accepted Workshop wall-destruction finalization remains valid for the exact environment tested. No production code needs to be reverted on the basis of this investigation.

However, its architecture assumptions require qualification before further production work:

- Treat loopback colocation as a local Workshop/LAN candidate, not a general Arcade fact.
- Do not assume Lobby Owner, Game Server, Lua host, and Python host are one machine.
- Do not use current `session_id` as a Match ID.
- Do not claim reconnect continuity or owner-leave behavior until the matrix above is executed.
- Do not rely on final HTTP completion after game-server termination; current delivery is best effort.
- Rotate the credential exposed during prior read-only `.env` inspection. No secret value is reproduced in this report.

## Decision Gate

**Current decision: MODEL-D for normal Arcade.** The report is complete as an investigation artifact, but the mission's factual success criterion is not yet met because the normal three-player Arcade server location and reconnect path remain UNKNOWN. Human review should authorize only the topology experiment next. Session Foundation implementation remains blocked until its result selects MODEL-A, MODEL-B, or MODEL-C.

## Sources

- Current Survival code and CSV: `online_time_service.lua`, `http_fishing_provider.lua`, `player_profile_service.lua`, `addon_game_mode.lua`, and `data/csv/玩家档案系统/fishing_system_rules.csv`.
- Current Python backend: `D:\survival_database\backend\fishing_api\config.py`, `application.py`, `server.py`, `backend\run_fishing_api.py`, `start_fishing_api.ps1`, and `README.md`.
- Project evidence: `docs/ai/SESSION_LOG.md`, `docs/ai/tasks/TASK-001.md`, and `docs/ai/MULTIPLAYER_TOPOLOGY_SESSION_MISSION.md`.
- Official general reference: Steamworks Documentation, [Steam Matchmaking & Lobbies](https://partner.steamgames.com/doc/features/multiplayer/matchmaking?l=english). This is not Dota 2 Arcade-specific documentation.
- Attempted Dota API reference: Valve Developer Community `Global.CreateHTTPRequestScriptVM`;正文 unavailable during investigation because of the site's Anubis challenge.