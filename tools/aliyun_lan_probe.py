"""Count connected humans before a local LAN host applies backend credentials."""
from __future__ import annotations

import json
from pathlib import Path
import re
import secrets
import shutil
import subprocess

import aliyun_game_test_auth as auth

ROOT = Path(__file__).resolve().parents[1]


def inspection_lua(nonce: str) -> str:
    if not re.fullmatch(r"GOUFAYU_LAN_[0-9a-f]{32}", nonce):
        raise auth.AuthError("lan_probe_nonce_invalid")
    return auth.capabilities() + """
local loading = package.loaded['systems/startup_loading_service']
local status, count = 'gate_not_ready', 0
if loading and type(loading.snapshot) == 'function' and type(loading.is_ready) == 'function'
  and PlayerResource and type(PlayerResource.GetConnectionState) == 'function' then
  local snapshot = loading.snapshot()
  if Convars:GetStr('survival_fishing_api_token') ~= '' or loading.is_ready() then
    status = 'already_released'
  elseif type(snapshot) == 'table' and snapshot.started then
    status = 'waiting_players'
    local accounts = {}
    for id=0,(DOTA_MAX_TEAM_PLAYERS or 24)-1 do
      if PlayerResource:IsValidPlayerID(id) and not PlayerResource:IsFakeClient(id)
        and PlayerResource:GetTeam(id) ~= (DOTA_TEAM_SPECTATOR or 1)
        and PlayerResource:GetPlayer(id) ~= nil
        and PlayerResource:GetConnectionState(id) == (DOTA_CONNECTION_STATE_CONNECTED or 2) then
        local account = tonumber(PlayerResource:GetSteamAccountID(id) or 0)
        if account and account > 0 and not accounts[account] then
          accounts[account] = true
          count = count + 1
        end
      end
    end
  end
end
""" + f"\nprint('{nonce}:' .. status .. ':' .. tostring(count))\nprint('{nonce}')\n"


def parse_result(output: bytes, nonce: str) -> dict:
    lines = output.decode("utf-8", errors="replace").splitlines()
    if nonce not in [line.strip() for line in lines]:
        raise auth.AuthError("tools_server_confirmation_missing")
    for line in reversed(lines):
        match = re.fullmatch(re.escape(nonce) + r":(waiting_players|gate_not_ready|already_released):([0-9]{1,2})", line.strip())
        if not match:
            continue
        status, count = match[1], int(match[2])
        if not 0 <= count <= 24:
            break
        if status == "already_released":
            raise auth.AuthError("lan_session_already_authenticated_restart_without_bridge")
        return {"ok": True, "status": status, "players": count}
    raise auth.AuthError("lan_probe_invalid_response")


def probe() -> dict:
    node = shutil.which("node.exe") or shutil.which("node")
    if not node:
        raise auth.AuthError("node_unavailable")
    nonce = "GOUFAYU_LAN_" + secrets.token_hex(16)
    request = ROOT / "output/ecs_backend_work" / (nonce + ".json")
    auth.no_reparse(request)
    auth.ignored(request)
    request.parent.mkdir(parents=True, exist_ok=True)
    created = False
    try:
        with request.open("x", encoding="utf-8") as target:
            created = True
            json.dump([{"name": "dota_run_lua", "arguments": {"code": inspection_lua(nonce)}}], target)
        result = subprocess.run([node, str(ROOT / "tools/map_c6/console.cjs"), "--file", str(request),
                                 "--timeout-ms", "5000", "--expect", nonce], capture_output=True,
                                timeout=15, creationflags=auth.HIDDEN)
        if result.returncode != 0:
            raise auth.AuthError("tools_server_confirmation_missing")
        return parse_result(result.stdout, nonce)
    finally:
        if created:
            request.unlink(missing_ok=True)


def main() -> int:
    try:
        result = probe()
    except auth.AuthError as exc:
        result = {"ok": False, "error": str(exc)}
    except (OSError, ValueError, subprocess.SubprocessError):
        result = {"ok": False, "error": "lan_local_probe_failed"}
    print(json.dumps(result))
    return 0 if result.get("ok") else 1


if __name__ == "__main__":
    raise SystemExit(main())
