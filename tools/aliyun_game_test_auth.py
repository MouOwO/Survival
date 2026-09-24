"""Inject the existing test API token into a local Workshop server only.

Temporary KV files are access-restricted and removed after every attempt. No
token enters console commands, generated Lua, JSON requests or this tool's
output. The resulting server Convar is still inspectable by the local developer;
this is a local test helper, not a production credential distribution system.
"""
from __future__ import annotations

import argparse
import base64
import codecs
import ctypes
import http.client
import json
import os
from pathlib import Path
import secrets
import shutil
import socket
import stat
import subprocess

import aliyun_test_connection as tunnel


ROOT = Path(__file__).resolve().parents[1]
GENERATED = ROOT / "scripts/vscripts/tests/c6_console_generated"
OUTPUT = ROOT / "output/ecs_backend_work"
HIDDEN = getattr(subprocess, "CREATE_NO_WINDOW", 0)


class AuthError(RuntimeError):
    pass


def no_reparse(path: Path) -> None:
    absolute = path.absolute()
    for part in (absolute, *absolute.parents):
        if part.exists() or part.is_symlink():
            info = part.lstat()
            if stat.S_ISLNK(info.st_mode) or getattr(info, "st_file_attributes", 0) & 0x400:
                raise AuthError("reparse_path_refused")


def ignored(path: Path) -> None:
    try:
        relative = path.absolute().relative_to(ROOT.absolute()).as_posix()
    except ValueError:
        raise AuthError("temporary_path_outside_addon") from None
    result = subprocess.run(["git", "-c", f"safe.directory={ROOT.as_posix()}", "-C", str(ROOT),
                             "check-ignore", "--quiet", "--", relative], capture_output=True,
                            timeout=10, creationflags=HIDDEN)
    if result.returncode != 0:
        raise AuthError("temporary_auth_file_not_git_ignored")


def private_acl(path: Path) -> None:
    # Only a path reaches PowerShell stdin. The API token is never passed to it.
    script = r"""
$ErrorActionPreference='Stop'
[Console]::InputEncoding=New-Object Text.UTF8Encoding($false)
$p=[Console]::In.ReadToEnd()
$sid=[Security.Principal.WindowsIdentity]::GetCurrent().User
$acl=New-Object Security.AccessControl.FileSecurity
$acl.SetOwner($sid)
$acl.SetAccessRuleProtection($true,$false)
$allowed=@($sid.Value,'S-1-5-18','S-1-5-32-544') | Select-Object -Unique
foreach ($value in $allowed) {
  $identity=New-Object Security.Principal.SecurityIdentifier($value)
  $rule=New-Object Security.AccessControl.FileSystemAccessRule($identity,'FullControl','Allow')
  $acl.AddAccessRule($rule)
}
[IO.File]::SetAccessControl($p,$acl)
$actual=[IO.File]::GetAccessControl($p)
if (-not $actual.AreAccessRulesProtected) { throw 'acl_not_protected' }
$rules=@($actual.GetAccessRules($true,$true,[Security.Principal.SecurityIdentifier]))
if ($rules.Count -ne $allowed.Count) { throw 'acl_count_invalid' }
foreach ($rule in $rules) {
  if ($rule.IsInherited -or $rule.IdentityReference.Value -notin $allowed -or
      $rule.AccessControlType -ne 'Allow' -or $rule.FileSystemRights -ne 'FullControl') {
    throw 'acl_rights_invalid'
  }
}
[Console]::Out.Write('PRIVATE_ACL_READY')
"""
    encoded = base64.b64encode(script.encode("utf-16-le")).decode("ascii")
    result = subprocess.run(["powershell.exe", "-NoLogo", "-NoProfile", "-NonInteractive",
                             "-EncodedCommand", encoded], input=str(path).encode("utf-8"),
                            capture_output=True, timeout=15, creationflags=HIDDEN)
    if result.returncode != 0 or result.stdout.strip() != b"PRIVATE_ACL_READY":
        raise AuthError("temporary_auth_acl_failed")


def require_ntfs(path: Path) -> None:
    filesystem = ctypes.create_unicode_buffer(64)
    kernel = ctypes.WinDLL("kernel32", use_last_error=True)
    kernel.GetVolumeInformationW.argtypes = [ctypes.c_wchar_p, ctypes.c_wchar_p, ctypes.c_uint,
                                            ctypes.c_void_p, ctypes.c_void_p, ctypes.c_void_p,
                                            ctypes.c_wchar_p, ctypes.c_uint]
    if not kernel.GetVolumeInformationW(path.absolute().anchor, None, 0, None, None, None,
                                        filesystem, len(filesystem)) or filesystem.value != "NTFS":
        raise AuthError("temporary_auth_requires_ntfs")


def read_api_token(path: Path) -> str:
    no_reparse(path)
    if path.stat().st_size > 1024 * 1024:
        raise AuthError("api_token_source_too_large")
    with path.open("rb") as source:
        prefix = source.read(4)
    if prefix.startswith((codecs.BOM_UTF32_LE, codecs.BOM_UTF32_BE)):
        encoding = "utf-32"
    elif prefix.startswith((codecs.BOM_UTF16_LE, codecs.BOM_UTF16_BE)):
        encoding = "utf-16"
    else:
        encoding = "utf-8-sig"
    found = None
    # Select this one field; never parse, retain or use the account pepper or
    # other credentials. Match the existing Windows load-env.ps1 semantics:
    # BOM detection, whole-line Trim, case-insensitive keys, last value wins.
    # Quotes, '$', backslashes and inline '#' remain literal characters.
    with path.open("r", encoding=encoding) as source:
        for line in source:
            trimmed = line.strip()
            if not trimmed or trimmed.startswith("#"):
                continue
            key, separator, value = trimmed.partition("=")
            if separator and key.upper() == "FISHING_API_TOKEN":
                found = value
    if (not isinstance(found, str) or not 24 <= len(found) <= 8192
            or any(ord(char) < 32 or ord(char) == 127 for char in found)):
        raise AuthError("api_token_missing_or_invalid")
    return found


def ready(token: str) -> None:
    connection = http.client.HTTPConnection("127.0.0.1", 8765, timeout=10)
    try:
        connection.request("GET", "/ready", headers={"Authorization": "Bearer " + token})
        response = connection.getresponse()
        value = json.loads(response.read(4097))
        if (response.status != 200 or not isinstance(value, dict) or value.get("ok") is not True
                or value.get("database") != "ready"):
            raise AuthError("authenticated_backend_not_ready")
    except (OSError, ValueError, http.client.HTTPException):
        raise AuthError("authenticated_backend_not_ready") from None
    finally:
        connection.close()


def capabilities() -> str:
    return """
if not IsServer or not IsServer() or not IsInToolsMode or not IsInToolsMode()
  or not GetMapName or GetMapName() ~= 'template_map'
  or type(LoadKeyValues) ~= 'function' or not Convars
  or type(Convars.SetStr) ~= 'function' or type(Convars.GetStr) ~= 'function'
  or type(Convars.GetFloat) ~= 'function'
  or tonumber(Convars:GetFloat('host_timescale') or 0) < 0.9
  or Convars:GetStr('survival_fishing_api_token') == nil then return end
"""


def recovery_lua() -> str:
    """Resume the existing admission/profile flow without resetting game state."""
    return """
    local profiles = require('systems/player_profile_service')
    local setup = require('systems/match_setup_service')
    for id=0,(DOTA_MAX_TEAM_PLAYERS or 24)-1 do
      if PlayerResource:IsValidPlayerID(id)
        and not PlayerResource:IsFakeClient(id)
        and PlayerResource:GetTeam(id) ~= (DOTA_TEAM_SPECTATOR or 1)
        and PlayerResource:GetPlayer(id) ~= nil then
        local steam = tonumber(PlayerResource:GetSteamAccountID(id) or 0)
        if steam and steam > 0 then
          local account = string.format('%.0f', steam)
          -- Entry authentication is independent of mode selection. Do not
          -- supersede an in-flight request on every watcher/launcher attempt.
          if not profiles.is_authenticated_for_account(id, account)
            and not profiles.is_authenticating(id) then
            profiles.authenticate_player(id, 'ecs_test_auth_ready')
          end
          -- Pure mode must keep its existing baseline, and neither mode may
          -- reload a loaded profile or replace an already pending load.
          if setup.is_mode_selected()
            and profiles.is_authenticated_for_account(id, account)
            and not profiles.get_profile(id) and not profiles.is_loading(id) then
            profiles.load_player(id, 'ecs_test_auth_ready')
          end
        end
      end
    end
    local loading = package.loaded['systems/startup_loading_service']
    if loading and type(loading.tick) == 'function' then loading.tick() end
"""


def send_lua(code: str, nonce: str, request_path: Path) -> None:
    node = shutil.which("node.exe") or shutil.which("node")
    if not node:
        raise AuthError("node_unavailable")
    no_reparse(request_path)
    ignored(request_path)
    request_path.parent.mkdir(parents=True, exist_ok=True)
    request = [{"name": "dota_run_lua", "arguments": {"code": code}}]
    with request_path.open("x", encoding="utf-8") as destination:
        json.dump(request, destination, ensure_ascii=False)
    try:
        # Never forward console output, including unrelated messages/history.
        result = subprocess.run([node, str(ROOT / "tools/map_c6/console.cjs"), "--file", str(request_path),
                                 "--timeout-ms", "5000", "--expect", nonce], capture_output=True,
                                timeout=25, creationflags=HIDDEN)
        lines = result.stdout.decode("utf-8", errors="replace").splitlines()
        if result.returncode != 0 or nonce not in [line.strip() for line in lines]:
            raise AuthError("tools_server_confirmation_missing")
    finally:
        request_path.unlink(missing_ok=True)


def probe(state: Path) -> dict:
    status = tunnel.check(state)
    if not status.get("ok"):
        raise AuthError("owned_ecs_tunnel_not_ready")
    try:
        with socket.create_connection(("127.0.0.1", 29000), timeout=1):
            pass
    except OSError:
        raise AuthError("tools_console_unavailable") from None
    nonce = "GOUFAYU_AUTH_PROBE_" + secrets.token_hex(16)
    send_lua(capabilities() + f"\nprint('{nonce}')\n", nonce, OUTPUT / (nonce + ".json"))
    return {"ok": True, "status": "tools_server_and_tunnel_ready"}


def inject(state: Path, environment: Path) -> dict:
    probe(state)
    token = read_api_token(environment)
    ready(token)
    nonce = "GOUFAYU_AUTH_APPLIED_" + secrets.token_hex(16)
    temporary = GENERATED / (nonce + ".kv")
    relative = temporary.relative_to(ROOT).as_posix()
    no_reparse(temporary)
    ignored(temporary)
    require_ntfs(temporary)
    temporary.parent.mkdir(parents=True, exist_ok=True)
    created = False
    try:
        # First create an empty file, then restrict/verify its ACL. No token is
        # written until every path, Git-ignore, filesystem and ACL check passes.
        with temporary.open("x", encoding="utf-8"):
            created = True
        private_acl(temporary)
        no_reparse(temporary)
        with temporary.open("w", encoding="utf-8", newline="\n") as target:
            target.write('"goufayu_test_auth"\n{\n "token" ' + json.dumps(token, ensure_ascii=False) + "\n}\n")
        token = None
        code = capabilities() + f"""
local ok = pcall(function()
  local value = LoadKeyValues('{relative}')
  if type(value) ~= 'table' or type(value.token) ~= 'string' or #value.token < 24 then return end
  Convars:SetStr('survival_fishing_api_token', value.token)
  local applied = Convars:GetStr('survival_fishing_api_token') == value.token
  value.token = nil
  if applied then
{recovery_lua()}
    print('{nonce}')
  end
end)
"""
        send_lua(code, nonce, OUTPUT / (nonce + ".json"))
        return {"ok": True, "status": "tools_test_auth_applied", "temporary_credential_removed": True}
    finally:
        token = None
        if created:
            temporary.unlink(missing_ok=True)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("probe", "inject"))
    parser.add_argument("--environment", type=Path, default=Path("D:/survival_database/.env"))
    parser.add_argument("--state", type=Path, default=OUTPUT / "test_tunnel.json")
    args = parser.parse_args()
    try:
        if os.name != "nt":
            raise AuthError("windows_only")
        result = probe(args.state) if args.action == "probe" else inject(args.state, args.environment)
    except AuthError as exc:
        result = {"ok": False, "error": str(exc)}
    except tunnel.TunnelError:
        result = {"ok": False, "error": "owned_ecs_tunnel_not_ready"}
    except (OSError, ValueError, subprocess.SubprocessError):
        result = {"ok": False, "error": "local_auth_setup_failed"}
    print(json.dumps(result, ensure_ascii=False))
    return 0 if result.get("ok") else 1


if __name__ == "__main__":
    raise SystemExit(main())
