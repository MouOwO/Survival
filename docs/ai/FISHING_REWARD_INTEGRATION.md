# Star Blessing Reward Integration

## Architecture

The trust path is fixed:

`Dota server Lua -> loopback authenticated Python API -> Supabase PostgreSQL`

- Panorama and game clients never receive the local API token, Supabase URL, or service-role key.
- Lua derives the persistent identity from server-side `PlayerResource:GetSteamAccountID()`.
- Python binds to loopback only and authenticates every non-health request with a bearer token.
- Python runs from the independent `D:\survival_database` repository, owns Supabase REST/RPC credentials, and synchronizes enabled reward rows from the authoritative addon CSV through `SURVIVAL_ADDON_ROOT`.
- Supabase stores only `HMAC-SHA256(FISHING_ACCOUNT_ID_PEPPER, Steam Account ID)`. Python restores the request's original account ID in the response so the existing Lua account-binding contract remains unchanged.

## Authoritative Data

- `data/csv/玩家档案系统/fishing_system_rules.csv` owns checkpoint timing, lease, reward interval, and definition version.
- `data/csv/玩家档案系统/star_blessing_reward_definitions.csv` owns stable star blessing IDs, weights, effect keys, ranges, stacking, caps, and enablement.
- Generated Lua files under `scripts/vscripts/config/generated/` are outputs and must not be edited directly.
- A definition version is immutable. Reusing a version with a different SHA-256 hash is rejected by the database.

The current production CSV intentionally has no enabled rewards. Three recovered but ambiguous definitions remain disabled. The API therefore fails startup with `enabled fishing reward definition missing` until the user confirms the full reward table and those meanings.

## Timer And Transaction Semantics

- A first online checkpoint establishes the current session without consuming time.
- A later checkpoint increments `online_seconds_total` only for the same session within the configured lease. New sessions, expired leases, and offline gaps add zero seconds.
- `checkpoint_online_time()` owns `online_time_sessions` and `online_time_idempotency`, grants each crossed reward milestone, and records an idempotent response in one transaction.
- The retired in-match fishing path (`fishing_states`, `fishing_sessions`, `fishing_idempotency`, `heartbeat_fishing_session()`, and `/v1/fishing/heartbeat`) is removed by the latest cleanup migration. It is not part of online timing.
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

1. Create a Supabase project and run the baseline migrations, then apply `D:\survival_database\supabase\migrations\202608230001_star_blessing_reward_definitions.sql` after the existing reward-grant and checkpoint migrations.
2. Confirm and enable at least one reward in `star_blessing_reward_definitions.csv`, incrementing `definition_version` whenever definitions change.
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

The fixture uses definition version `9001`, a fixed 10-second interval, and permanent `hero_all_attributes_flat +5`. The Tools-only command `survival_online_checkpoint_now [player_id]` can trigger the existing checkpoint path immediately after HERO_READY. It requires Tools Mode, the exact `automation_9001` fixture, the `http_fishing` provider, and an existing player session. It does not bypass the Python API, Supabase RPC, profile refresh, permanent projection, or announcement path. Never use this ConVar or command in production.

The API logs only checkpoint timing totals, grant count, and reward IDs. Lua logs the sequence `checkpoint_response`, `profile_refresh_started`, `profile_refresh_completed`, `grant_published`, and `reward_announced`; account IDs, tokens, and grant IDs are excluded from diagnostics.

## Validation Boundary

Python unit tests use a fake RPC client and a real loopback HTTP server. Lua tests use Lua 5.1 mocks. Contract tests inspect SQL and trust boundaries. A live Supabase/Python API integration passed on 2026-08-20 with the Automation 9001 fixture, including profile initialization, 36 gameplay fields, adjacent heartbeat accumulation, idempotency, lease takeover, revision, and public-data isolation. This does not prove that Dota Workshop Tools exposes the expected HTTP and connection-state behavior; Workshop Tools still requires live validation with the `http_fishing` override and server-only token.
