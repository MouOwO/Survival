"""Run: python3 -B -m player_web_auth.run (from the server/release directory)."""
import os
from pathlib import Path

from .http_api import BoundedServer, handler
from .service import PAYMENT_UPSTREAM, Service, Settings


def settings_from_environment(env):
    progress = env.get("ISOLATED_LOCAL_PROGRESS", "0")
    if progress not in ("0", "1"):
        raise ValueError("isolated_local_progress_invalid")
    relay = env.get("PLAYER_WEB_AUTH_STEAM_TLS_RELAY", "0")
    if relay not in ("0", "1"):
        raise ValueError("steam_tls_relay_invalid")
    payments = env.get("PLAYER_WEB_AUTH_PAYMENTS_ENABLED", "0")
    if payments not in ("0", "1"):
        raise ValueError("payments_enabled_invalid")
    return Settings(
        database=Path(env["PLAYER_WEB_AUTH_DATABASE"]),
        secret=env["PLAYER_WEB_AUTH_SECRET"],
        upstream_bearer=env["PLAYER_WEB_AUTH_UPSTREAM_BEARER"],
        steam_ids=tuple(value.strip() for value in env["PLAYER_WEB_AUTH_STEAM_IDS"].split(",")),
        public_base=env.get("PLAYER_WEB_AUTH_PUBLIC_BASE", "https://pay.xiaofengnet.com/ws4-web"),
        upstream=env.get("PLAYER_WEB_AUTH_UPSTREAM", "http://127.0.0.1:18765"),
        bind=env.get("PLAYER_WEB_AUTH_BIND", "127.0.0.1"),
        port=int(env.get("PLAYER_WEB_AUTH_PORT", "18767")),
        isolated_local_progress=progress == "1",
        steam_tls_relay=relay == "1",
        payments_enabled=payments == "1",
        payment_upstream=env.get("PLAYER_WEB_AUTH_PAYMENT_UPSTREAM", PAYMENT_UPSTREAM),
        payment_bearer=env.get("PLAYER_WEB_AUTH_PAYMENT_BEARER", ""))


def lobby_from_environment(service, env):
    enabled = env.get("PLAYER_WEB_AUTH_LOBBY_ENABLED", "0")
    if enabled not in ("0", "1"):
        raise ValueError("lobby_enabled_invalid")
    if enabled == "0":
        return None
    from lobby_backend.service import LobbyService
    # No worker/readiness adapters or endpoints are assumed by this opt-in.
    return LobbyService.from_auth_service(service)


def main():
    os.umask(0o077)
    try:
        settings = settings_from_environment(os.environ)
        service = Service(settings)
        server = BoundedServer((settings.bind, settings.port),
                               handler(service, lobby=lobby_from_environment(service, os.environ)))
    except Exception:
        print("WS4_PLAYER_WEB_AUTH_STARTUP_ERROR", flush=True)
        return 2
    print("WS4_PLAYER_WEB_AUTH_READY", flush=True)
    try:
        server.serve_forever()
    finally:
        server.server_close()
        service.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
