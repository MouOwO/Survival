# Fishing Reward Integration

## Architecture

The trust path is fixed:

`Dota server Lua -> loopback authenticated Python API -> Supabase PostgreSQL`

- Panorama and game clients never receive the local API token, Supabase URL, or service-role key.
- Lua derives the persistent identity from server-side `PlayerResource:GetSteamAccountID()`.
- Python binds to loopback only and authenticates every non-health request with a bearer token.
- Python runs from the independent `D:\survival_database` repository, owns Supabase REST/RPC credentials, and synchronizes enabled reward rows from the authoritative addon CSV through `SURVIVAL_ADDON_ROOT`.
- Supabase stores only `HMAC-SHA256(FISHING_ACCOUNT_ID_PEPPER, Steam Account ID)`. Python restores the request's original account ID in the response so the existing Lua account-binding contract remains unchanged.

## Authoritative Data

- `data/csv/玩家档案系统/fishing_system_rules.csv` owns heartbeat, lease, timer range, and definition version.
- `data/csv/玩家档案系统/fishing_reward_definitions.csv` owns stable reward IDs, weights, effect keys, ranges, stacking, caps, and enablement.
- Generated Lua files under `scripts/vscripts/config/generated/` are outputs and must not be edited directly.
- A definition version is immutable. Reusing a version with a different SHA-256 hash is rejected by the database.

The current production CSV intentionally has no enabled rewards. Three recovered but ambiguous definitions remain disabled. The API therefore fails startup with `enabled fishing reward definition missing` until the user confirms the full reward table and those meanings.

## Timer And Transaction Semantics

- A first heartbeat creates a timer without consuming time.
- A later heartbeat consumes only the elapsed time since the previous heartbeat when it is from the same session and within the configured lease.
- Disconnect stops Lua heartbeats. A heartbeat after the lease or from a new session consumes zero offline time, preserving the remaining duration.
- One unique session row exists per Steam Account ID. A different session is rejected while the 15-second lease is active, preventing concurrent sessions from alternating ownership or double-counting. An abrupt disconnect may therefore wait up to one lease before reconnect takeover; the timer remains frozen during that wait.
- Grant history, permanent aggregate update, profile revision increment, next 60-600 second interval, and idempotency response are committed by `heartbeat_fishing_session()` in one transaction.
- `reward_grants` is append-only application data; `player_effect_totals` is its current permanent projection.

## Runtime Projection

`permanent_reward_effect_service.lua` restores `save.permanent_effects` through the existing validated profile snapshot/revision path. Confirmed adapter keys are:

- `hero_all_attributes_flat`
- `hero_attack_flat`
- `lumberjack_attack_speed_pct`
- `gold_mine_income_pct`

Immediate match resources use `immediate_gold`, `immediate_wood`, and `immediate_max_population` through `RESOURCE_ADD_REQUEST`. The current resource account is team-scoped, so player-owned fishing requests fail closed with `player_scoped_resource_unsupported` before mutation. Do not enable immediate production rewards until player-private resource accounts and a persistent delivery outbox/ack are both implemented.

Permanent starting resources are not projected yet because the current resource system is team-scoped, while permanent rewards are player-scoped. Adding them to the shared team account would violate multiplayer isolation.

Every grant is checked again against the local CSV-generated definition, including version, reward/effect identity, scope, enabled state, and integer amount range. A permanent grant publishes `FISHING_REWARD_GRANTED` only after the winning player's profile snapshot and permanent projection are available; an immediate grant publishes it only after its local application succeeds. The per-session `grant_id` set makes retries idempotent. The grant event contains only whitelisted gameplay fields.

The grant subscriber emits `UI_NOTIFICATION` with `audience = "all"`. The announcement is display-only and contains only the server-resolved player name, CSV `display_name`, and validated amount. `ui_request_router.lua` broadcasts only explicit all-player notifications and preserves targeted delivery for every existing notification. The router forwards only `message` and `level`, so account IDs, tokens, profile data, definition hashes, and raw API grants cannot cross this UI boundary.

## Setup

1. Create a Supabase project and run `D:\survival_database\supabase\migrations\202608170001_fishing_rewards.sql` in the SQL editor.
2. Confirm and enable at least one reward in `fishing_reward_definitions.csv`, incrementing `definition_version` whenever definitions change.
3. Regenerate the two Lua configs with the project config generator.
4. Create `D:\survival_database\.env` from `D:\survival_database\.env.example`. Set `SURVIVAL_ADDON_ROOT` to this addon and keep the API token, account-ID pepper, and Supabase key server-only.
5. Start the API from the independent database repository:

```powershell
& 'D:\survival_database\start_fishing_api.ps1'
```

6. Before starting the Dota custom game, set server ConVars:

```text
survival_player_profile_provider http_fishing
survival_fishing_api_token <same-long-random-token-as-FISHING_API_TOKEN>
```

With no Provider override, the existing `local_fixture` profile path remains the default and fishing heartbeats stay disabled.

For isolated Workshop Tools testing, point Python to the fixture CSVs without changing production definitions:

```text
& 'D:\survival_database\start_fishing_api.ps1' -Automation9001
```

The fixture uses definition version `9001`, a fixed 10-second interval, and permanent `hero_attack_flat +5`. Immediate failure-closed behavior is covered by Lua tests rather than the database-backed fixture, so a committed immediate grant cannot block the permanent integration test. Lua accepts the matching test definition only when both `IsInToolsMode()` is true and the server ConVar `survival_fishing_reward_fixture` is exactly `automation_9001`. Never use this ConVar in production.

## Validation Boundary

Python unit tests use a fake RPC client and a real loopback HTTP server. Lua tests use Lua 5.1 mocks. Contract tests inspect SQL and trust boundaries. These checks do not prove that a live Supabase project accepts the migration, nor that Dota Workshop Tools exposes the expected HTTP and connection-state behavior. Both require live validation after credentials and confirmed rewards are available.