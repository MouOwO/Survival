WS4 player web authorization sidecar (isolated four-account test only)

Run from the directory containing player_web_auth:
  python3 -B -m player_web_auth.run
Tests:
  python3 -B -m unittest player_web_auth.test_service

Required environment (secrets stay only on the server):
  PLAYER_WEB_AUTH_DATABASE=/var/lib/goufayu-ws4-web/auth.sqlite3
  PLAYER_WEB_AUTH_SECRET=<independent 64+ hexadecimal characters>
  PLAYER_WEB_AUTH_UPSTREAM_BEARER=<new privileged WS4 bearer registered by its SHA256 pin>
  PLAYER_WEB_AUTH_STEAM_IDS=<exactly four comma-separated SteamID64 values>
Defaults:
  PLAYER_WEB_AUTH_BIND=127.0.0.1
  PLAYER_WEB_AUTH_PORT=18767
  PLAYER_WEB_AUTH_PUBLIC_BASE=https://pay.xiaofengnet.com/ws4-web
  PLAYER_WEB_AUTH_UPSTREAM=http://127.0.0.1:18765
  ISOLATED_LOCAL_PROGRESS=0

The state directory must be private (0700 on Linux); SQLite is 0600.
Reverse proxy /ws4-web/ to loopback 18767 and strip the prefix.
Disable access/query logging on this prefix and preserve the original Origin.
The service does not use forwarded headers for authentication or return URLs.
Only the loopback proxy may supply one strictly valid X-Forwarded-For IP for
per-peer rate limiting. The proxy must overwrite it with $remote_addr, never
append client-supplied values. Multiple values are rejected. A separate global
request quota is retained across all peers.
Do not change the public base through an untrusted Host header.

POST /v1/player-auth/start: account_id, match_session_id.
POST /v1/player-auth/poll: the same fields plus private device_code.
Only the public user_code goes in the browser verification URL.
Steam login occurs only at the official Steam Community OpenID endpoint.
An explicit same-origin CSRF-protected confirmation authorizes the local game.
Poll retries after approval reproduce the same token without storing raw tokens.
Sessions expire after four hours. A newer approval revokes older account grants.
Users never receive the WS4 server bearer or signing secret.

User-session routes are restricted to authentication, mode login, own profile,
configuration, catalogue, and inventory snapshot. Payment, arbitrary paths,
leaderboards, and battle mutations are denied by default.
ISOLATED_LOCAL_PROGRESS=1 adds only three existing isolated test mutation
routes: archive/command, archive/endless-batch, online-time/checkpoint.
Their battle claims remain editable by the local host. rewards/grant stays denied.
The authorization page explicitly discloses this. This flag is not an anti-cheat
mechanism and must not be used to admit local results into trusted rankings.
It never enables real payment or leaderboard routes.

No real Steam-login integration is simulated by the production entry point.
Tests inject a verifier only into in-process test objects. Final end-to-end
verification requires one of the four owners to log in on the official page.
