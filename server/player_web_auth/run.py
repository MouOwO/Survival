"""Run: python3 -B -m player_web_auth.run (from the server/release directory)."""
import os
from pathlib import Path

from .http_api import BoundedServer, handler
from .service import Service, Settings


def settings_from_environment(env):
    progress = env.get("ISOLATED_LOCAL_PROGRESS", "0")
    if progress not in ("0", "1"):
        raise ValueError("isolated_local_progress_invalid")
    return Settings(
        database=Path(env["PLAYER_WEB_AUTH_DATABASE"]),
        secret=env["PLAYER_WEB_AUTH_SECRET"],
        upstream_bearer=env["PLAYER_WEB_AUTH_UPSTREAM_BEARER"],
        steam_ids=tuple(value.strip() for value in env["PLAYER_WEB_AUTH_STEAM_IDS"].split(",")),
        public_base=env.get("PLAYER_WEB_AUTH_PUBLIC_BASE", "https://pay.xiaofengnet.com/ws4-web"),
        upstream=env.get("PLAYER_WEB_AUTH_UPSTREAM", "http://127.0.0.1:18765"),
        bind=env.get("PLAYER_WEB_AUTH_BIND", "127.0.0.1"),
        port=int(env.get("PLAYER_WEB_AUTH_PORT", "18767")),
        isolated_local_progress=progress == "1")


def main():
    os.umask(0o077)
    try:
        settings = settings_from_environment(os.environ)
        service = Service(settings)
        server = BoundedServer((settings.bind, settings.port), handler(service))
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
