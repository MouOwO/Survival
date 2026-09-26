"""Per-user local Hammer authentication bridge; never starts or reloads a map.

Only a verified survival/template_map Tools server may receive the existing
test credential. The credential transport is owned by aliyun_game_test_auth.
No credential is stored in this daemon's state, arguments, or rotating log.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import logging
from logging.handlers import RotatingFileHandler
import os
from pathlib import Path
import shutil
import subprocess
import time

import aliyun_game_test_auth as auth
import aliyun_test_connection as tunnel
import aliyun_local_config as local_config

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "output/hammer_backend"
STATUS = OUTPUT / "bridge_status.json"
STOP = OUTPUT / "bridge.stop"
ENVIRONMENT = Path("D:/survival_database/.env")
TUNNEL_STATE = ROOT / "output/ecs_backend_work/test_tunnel.json"
KNOWN_HOSTS = ROOT / "output/ecs_backend_work/ecs_hostkey_candidate.pub"
PREFIX = "GOUFAYU_HAMMER_STATE:"
HIDDEN = getattr(subprocess, "CREATE_NO_WINDOW", 0)
STOP_WAIT_SECONDS = 55.0


def inspection_lua() -> str:
    # The source is constant: polling reuses one ignored, credential-free Lua
    # file rather than creating unbounded nonce-named scripts every few seconds.
    return """
local result = {status='waiting_for_map'}
local function inspect()
""" + auth.capabilities() + """
  local profiles = package.loaded['systems/player_profile_service']
  local setup = package.loaded['systems/match_setup_service']
  local loading = package.loaded['systems/startup_loading_service']
  if not profiles or not setup or not loading or not PlayerResource
    or type(setup.get_session_id) ~= 'function'
    or type(profiles.is_authenticated_for_account) ~= 'function' then return end
  local session = setup.get_session_id()
  if type(session) ~= 'string' or #session < 8 then return end
  result.session = session
  if type(loading.is_party_waiting) == 'function' and loading.is_party_waiting() then
    result.status = 'waiting_for_party'
    return
  end
  result.status = Convars:GetStr('survival_fishing_api_token') == ''
    and 'authentication_required' or 'configured'
  result.players, result.authenticated, result.loaded = 0, 0, 0
  for id=0,(DOTA_MAX_TEAM_PLAYERS or 24)-1 do
    if PlayerResource:IsValidPlayerID(id) and not PlayerResource:IsFakeClient(id)
      and PlayerResource:GetTeam(id) ~= (DOTA_TEAM_SPECTATOR or 1)
      and PlayerResource:GetPlayer(id) ~= nil then
      local account = tonumber(PlayerResource:GetSteamAccountID(id) or 0)
      if account and account > 0 then
        result.players = result.players + 1
        if profiles.is_authenticated_for_account(id, string.format('%.0f', account)) then
          result.authenticated = result.authenticated + 1
        end
        if profiles.get_profile(id) then result.loaded = result.loaded + 1 end
      end
    end
  end
end
inspect()
if result.session then
  print('GOUFAYU_HAMMER_STATE:' .. require('core/json_encoder').encode(result))
else
  print('GOUFAYU_HAMMER_STATE:{"status":"waiting_for_map"}')
end
"""


def inspect_game() -> dict:
    # Let the protocol-aware client handle connection failures. A separate
    # connect/close probe creates an incomplete VConsole session every poll,
    # including while Hammer is open without a running game.
    node = shutil.which("node.exe") or shutil.which("node")
    if not node:
        raise auth.AuthError("node_unavailable")
    request = OUTPUT / "bridge_probe.json"
    auth.no_reparse(request)
    auth.ignored(request)
    request.parent.mkdir(parents=True, exist_ok=True)
    request.write_text(json.dumps([{"name": "dota_run_lua", "arguments": {
        "code": inspection_lua()}}]), encoding="utf-8")
    try:
        completed = subprocess.run([node, str(ROOT / "tools/map_c6/console.cjs"),
            "--file", str(request), "--timeout-ms", "2500"], capture_output=True,
            timeout=15, creationflags=HIDDEN)
    finally:
        request.unlink(missing_ok=True)
    # Never forward console output: history can contain unrelated credentials.
    if completed.returncode != 0:
        return {"status": "waiting_for_workshop"}
    for line in reversed(completed.stdout.decode("utf-8", errors="replace").splitlines()):
        if not line.startswith(PREFIX):
            continue
        try:
            value = json.loads(line[len(PREFIX):])
            if value.get("status") == "waiting_for_map":
                return {"status": "waiting_for_map"}
            session = value.get("session")
            if value.get("status") not in {"configured", "authentication_required", "waiting_for_party"} \
                    or not isinstance(session, str) or not 8 <= len(session) <= 512:
                continue
            counts = {key: value.get(key, 0) for key in ("players", "authenticated", "loaded")}
            if any(type(n) is not int or not 0 <= n <= 64 for n in counts.values()):
                continue
            return {"status": value["status"], "session": hashlib.sha256(
                session.encode("utf-8")).hexdigest(), **counts}
        except (ValueError, AttributeError, TypeError):
            continue
    return {"status": "waiting_for_map"}


class Bridge:
    def __init__(self, *, key: Path, environment: Path = ENVIRONMENT,
                 state: Path = TUNNEL_STATE, known_hosts: Path = KNOWN_HOSTS):
        self.key, self.environment, self.state, self.known_hosts = key, environment, state, known_hosts
        self.session = None
        self.next_health = 0.0

    def step(self) -> dict:
        game = inspect_game()
        if game["status"] not in {"configured", "authentication_required"}:
            self.session = None
            return {"ok": True, "status": game["status"]}
        current = time.monotonic()
        needs_auth = game["session"] != self.session or game["status"] == "authentication_required"
        if needs_auth or current >= self.next_health:
            with tunnel.state_lock(self.state):
                connected = tunnel.connect(self.state, self.key, self.known_hosts)
            if not connected.get("ok"):
                raise tunnel.TunnelError("ssh_tunnel_or_backend_unavailable")
            self.next_health = current + 20
        if needs_auth:
            auth.inject(self.state, self.environment)
            self.session = game["session"]
            return {"ok": True, "status": "authentication_applied"}
        return {"ok": True, "status": "connected", "players": game["players"],
                "authenticated_players": game["authenticated"], "loaded_profiles": game["loaded"]}


def safe_step(bridge: Bridge) -> dict:
    try:
        return bridge.step()
    except (auth.AuthError, tunnel.TunnelError) as exc:
        # These classes expose fixed public status codes only.
        return {"ok": False, "status": "retrying", "error": str(exc)}
    except (OSError, ValueError, subprocess.SubprocessError):
        return {"ok": False, "status": "retrying", "error": "local_bridge_operation_failed"}
    except Exception:
        return {"ok": False, "status": "retrying", "error": "unexpected_bridge_error"}


def publish(value: dict) -> dict:
    auth.no_reparse(STATUS)
    auth.no_reparse(STATUS.with_suffix(".new"))
    result = {**value, "updated_at": time.time(), "pid": os.getpid(), "version": 1}
    temporary = STATUS.with_suffix(".new")
    temporary.write_text(json.dumps(result) + "\n", encoding="utf-8")
    temporary.replace(STATUS)
    return result


def stop() -> dict:
    """Pause future runs and wait for any in-flight injection to finish safely."""
    deadline = time.monotonic() + STOP_WAIT_SECONDS
    instance = OUTPUT / "bridge_instance.json"
    for path in (OUTPUT, STOP, STATUS, instance, instance.with_suffix(".lock")):
        auth.no_reparse(path)
    for path in (STOP, STATUS, instance.with_suffix(".lock")):
        auth.ignored(path)
    OUTPUT.mkdir(parents=True, exist_ok=True)
    STOP.write_text("stop\n", encoding="ascii")
    # The resident and one-shot bridge both hold this lock across safe_step(),
    # including auth.inject's credential-file finally block. Observing a PID or
    # scheduled task alone cannot establish that the injection has finished.
    while True:
        try:
            with tunnel.state_lock(instance):
                return publish({"ok": True, "status": "stopped", "stop_confirmed": True})
        except tunnel.TunnelError as exc:
            if str(exc) != "tunnel_operation_in_progress":
                raise
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                # Leave STOP set. The worker still cleans up normally; callers
                # must not restart/reload a game on an unconfirmed stop.
                raise auth.AuthError("bridge_stop_timeout") from None
            time.sleep(min(0.25, remaining))


def _run_locked(bridge: Bridge, *, once: bool = False) -> dict:
    auth.no_reparse(OUTPUT)
    OUTPUT.mkdir(parents=True, exist_ok=True)
    auth.ignored(STATUS)
    # Separate from the short-lived SSH state lock. Multiple bridge startup
    # attempts must not race to inspect/inject into the same game.
    instance = OUTPUT / "bridge_instance.json"
    auth.no_reparse(instance)
    auth.no_reparse(instance.with_suffix(".lock"))
    auth.ignored(instance.with_suffix(".lock"))
    try:
        with tunnel.state_lock(instance):
            auth.no_reparse(STOP)
            logger = logging.getLogger("hammer_backend")
            auth.no_reparse(OUTPUT / "bridge.log")
            handler = RotatingFileHandler(OUTPUT / "bridge.log", maxBytes=65536,
                                         backupCount=2, encoding="utf-8")
            logger.setLevel(logging.INFO)
            logger.addHandler(handler)
            previous, retry_delay = None, 2
            try:
                while True:
                    if STOP.exists():
                        return publish({"ok": True, "status": "stopped"})
                    value = safe_step(bridge)
                    publish(value)
                    summary = json.dumps(value, sort_keys=True)
                    if summary != previous:
                        logger.info(summary)
                        previous = summary
                    if once:
                        return value
                    retry_delay = (5 if value["status"] in {"connected", "waiting_for_map"} else 2) \
                        if value["ok"] else min(30, retry_delay * 2)
                    deadline = time.monotonic() + retry_delay
                    while time.monotonic() < deadline:
                        if STOP.exists():
                            return publish({"ok": True, "status": "stopped"})
                        time.sleep(0.25)
            finally:
                logger.removeHandler(handler)
                handler.close()
    except tunnel.TunnelError:
        raise


def run(bridge: Bridge, *, once: bool = False) -> dict:
    while True:
        try:
            return _run_locked(bridge, once=once)
        except tunnel.TunnelError as exc:
            if str(exc) != "tunnel_operation_in_progress":
                raise
            if once:
                return {"ok": True, "status": "already_running"}
            # A one-shot diagnostic may win the lock while Task Scheduler is
            # starting us. Wait for it instead of exiting successfully and
            # silently leaving Hammer without its resident helper.
            if STOP.exists():
                return {"ok": True, "status": "stopped"}
            time.sleep(1)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("run", "once", "status", "stop"))
    parser.add_argument("--key", type=Path)
    parser.add_argument("--environment", type=Path)
    parser.add_argument("--known-hosts", type=Path)
    args = parser.parse_args()
    try:
        if os.name != "nt":
            raise auth.AuthError("windows_only")
        auth.no_reparse(OUTPUT)
        OUTPUT.mkdir(parents=True, exist_ok=True)
        if args.action == "status":
            auth.no_reparse(STATUS)
            result = json.loads(STATUS.read_text(encoding="utf-8")) if STATUS.exists() else {
                "ok": False, "status": "not_started"}
            if result.get("status") != "stopped" and time.time() - result.get("updated_at", 0) > 90:
                result = {"ok": False, "status": "heartbeat_expired"}
        elif args.action == "stop":
            result = stop()
        else:
            settings = local_config.load(ROOT)
            result = run(Bridge(
                key=args.key if args.key is not None else settings["ssh_key"],
                environment=args.environment if args.environment is not None else settings["environment"],
                known_hosts=args.known_hosts if args.known_hosts is not None else settings["known_hosts"]),
                once=args.action == "once")
    except (auth.AuthError, tunnel.TunnelError, local_config.ConfigError) as exc:
        result = {"ok": False, "error": str(exc)}
    except Exception:
        result = {"ok": False, "error": "local_bridge_operation_failed"}
    print(json.dumps(result))
    return 0 if result.get("ok") else 1


if __name__ == "__main__":
    raise SystemExit(main())
