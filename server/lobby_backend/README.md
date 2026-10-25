# Isolated four-account lobby

This module stores lobby state in process memory and never imports or forwards
to archive, commerce, payment or database APIs. It does not start Dota, discover
servers, publish a site, or claim that remote hosting works. Process restart
loses rooms, leases and tickets. Battle profiles remain the Dota worker's
separate session-memory responsibility.

Run the closed developer HTTP service from `server` with
`python -B -m lobby_backend.run`. It binds only `127.0.0.1:18769`. Its default
has no identity adapter and no workers: player/worker actions are rejected and
available capacity is zero. There are no fake-authentication or auto-ready
command-line options.

Run tests from `server` with `python -B -m unittest lobby_backend.test_service`.
Tests use temporary authentication state, injected test identities/readiness,
and real loopback HTTP. They do not access Steam, Dota, cloud APIs or real data.

## Integration

Construct `LobbyService.from_auth_service(auth_service, build_sha256=sha, ...)`.
The adapter calls the existing `auth_service.principal(bearer, payload)`, then
resolves the returned account through `auth_service.settings.accounts` and its
exact four-account allowlist. Expired, revoked and mismatched existing pwa1
grants fail. No client SteamID is accepted as an identity. This reuses verified
Steam login and does not extend a grant or inherit any cloud proxy permission.

In the existing authenticated HTTP process, explicitly intercept the exact
`/v1/lobby/<action>` routes and call:

```python
from lobby_backend.http_api import post
response = post(lobby, path, authorization_header, parsed_json_body)
```

Catch `LobbyError` and return its `status` and `{"ok":false,"error":code}`.
Do not expand the existing web-auth proxy whitelist. Its existing routes,
cookies, grants and cloud forwarding remain independent. The standalone
`Server` supplies bounded JSON parsing, no access logging and a concurrency
limit; an integrated handler must retain those body/header limits.

The existing web-auth runner now accepts only
`PLAYER_WEB_AUTH_LOBBY_ENABLED=0|1`, default `0`. `1` composes
`handler(auth_service, lobby=LobbyService.from_auth_service(auth_service))`.
This permits verified login and room operations, but registers no workers and
has no build configured. Starting a room therefore returns `no_ready_worker`;
it does not pretend that a game host is deployed. The existing cloud proxy
allowlist is unchanged. Worker installation/readiness remains an explicit later
integration, with a signed build and the separate callbacks described below.

Every player POST includes `account_id` and `match_session_id` for the existing
principal verification. They refer to the source authorization session, not
the lobby's newly generated `match_id`. Every mutation also includes a fresh
`request_id` (8–128 characters from letters, digits, `_`, `-`). An exact retry
returns the original response; changing its action or payload returns 409.
Read actions may omit `request_id`. Responses always use `ok: true` on success.
Every player success and lobby error includes top-level `worker_available`
(boolean) and `build_sha256` (the configured SHA, or JSON null while no build is
configured). Availability is refreshed even on an idempotent response; clients
must still honor room state/version and validate the build before connecting.
For a member's allocated room, its own live `READY`/`RUNNING` worker also counts
as available for reconnect. A stale generation, changed lease/build or expired
heartbeat/lease makes that room unavailable even if another idle worker exists.

| Action | Additional JSON fields | Result |
|---|---|---|
| `rooms` | none | Own rooms only |
| `create` | none | `room` with version 1 and self member ID |
| `room` | `room_id` | Current member-visible room |
| `invite` | `room_id`, `expected_version` | Owner-only single-use invite code, 10 minute expiry |
| `join` | `invite_code` | Add authenticated self to an open room, maximum four |
| `ready` | `room_id`, `expected_version`, boolean `ready` | Update self readiness and increment version |
| `start` | `room_id`, `expected_version` | Owner-only, every member ready, assign one validated idle worker |
| `leave` | `room_id`, `expected_version` | Non-owner leaves an open room |
| `close` | `room_id`, `expected_version` | Owner closes an open/interrupted room |
| `ticket` | `room_id` | Own join ticket, 60 second expiry |
| `reconnect` | `room_id` | Replace own ticket for the same live match |
| `redeem` | `room_id`, `ticket` | Consume own ticket and return the configured connect address |

Rooms expose opaque member IDs, readiness and ownership, rather than SteamIDs.
All mutating membership actions use a room version comparison. `start` returns
503 `no_ready_worker` without changing the room when no verified idle worker
exists. Room states are `OPEN`, `ALLOCATING`, `READY`, `RUNNING`, `INTERRUPTED`,
`CLOSED`. Ticket/connection actions require `READY` or `RUNNING`.

Tickets are stored by hash and bound to account, room, fresh match, worker,
worker generation, lease and signed build. A replacement invalidates previous
tickets for that account/match. A different request cannot consume a used
ticket. Redeem explicitly reports `native_connection_verified: false`: lobby
admission is not evidence that Dota connected. The real worker must still
check engine-resolved Steam account IDs against its immutable assignment.
No ticket, bearer, callback, body or exception should enter logs or URLs.

## Worker contract

Workers and addresses come only from trusted configuration:

```python
WorkerSpec("local-worker-1", "127.0.0.1:27015", signed_build_sha256)
```

No player endpoint can register an address or select an arbitrary worker.
Inject `worker_verifier(bearer) -> configured_worker_id` with its own worker
credential policy. Inject `readiness_verifier(worker_id, evidence, state) ->
True` only after checking real host/native evidence. A payload flag alone is
not proof; a missing verifier always rejects readiness. Keep worker credentials
out of game/client packages and separate from player pwa1 grants.

Worker actions use the same fixed POST prefix and a worker Bearer header,
without player `account_id` or `match_session_id`:

- `worker-heartbeat`: `request_id`, integer `generation`, `lease_id` (initially
  `null`), `state`, and `evidence`. Initial generation is 0. State is one of
  `idle`, `starting`, `ready`, `running`, `stopped`.
- `worker-claim`: empty JSON object. Returns the current assignment to that
  worker, or 404 `worker_no_assignment`. Repeated claims return the same lease.

All evidence must state the exact build SHA, `mode: session_memory_only`,
integer `sv_cheats: 0`, `cloud_archive_enabled: false`, `commerce_enabled:
false`. For `ready`/`running`, also require `native_ready: true`, `map:
template_map` and a positive integer `game_pid`; the injected verifier must
independently check these claims. No worker is available before an authenticated,
verified `idle` heartbeat. Allocation increments generation and creates a fresh
lease/match; the worker polls claim, then uses the returned generation/lease in
subsequent heartbeats. Tickets stay unavailable while it is `starting`.

Assignment includes the immutable account-ID roster, map, build SHA and strict
memory-only/no-commerce/cheats-off flags. It contains no cloud credential.
Send fresh heartbeats every 5 seconds. Missing heartbeats for 15 seconds or an
expired 30 second lease interrupts the room and invalidates future admission.
Old generations/leases are rejected. Heartbeats renew the lease; replaying an
old cached heartbeat cannot resurrect an expired worker. `stopped` closes the
match and returns the worker to offline until a new verified idle heartbeat.

Reconnect issues a fresh ticket only while the same match/worker lease remains
live. It does not restore a dead Dota process or a lost in-memory battle.

Bounds: 32 rooms per process, 64 active invites, 128 active tickets, 1024
idempotency entries, and 120 authenticated requests per actor per minute.
No unauthenticated request allocates room/worker state.
