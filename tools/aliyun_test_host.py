"""New-PC setup checks for trusted local Workshop hosts, using public status only."""
from __future__ import annotations

import argparse
import getpass
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys

import aliyun_game_test_auth as auth
import aliyun_local_config as config
import aliyun_test_connection as tunnel

ROOT = Path(__file__).resolve().parents[1]
HIDDEN = getattr(subprocess, "CREATE_NO_WINDOW", 0)


class HostError(RuntimeError):
    pass


def run_public(command: list[str]) -> subprocess.CompletedProcess:
    return subprocess.run(command, capture_output=True, timeout=15, creationflags=HIDDEN)


def fingerprint(output: bytes) -> str | None:
    match = re.search(rb"(?:^|\s)(SHA256:[A-Za-z0-9+/]{43})(?:\s|$)", output)
    return match[1].decode("ascii") if match else None


def ssh_identity(key: Path) -> str:
    """Only retain the fingerprint; never echo tool output or public/private key data."""
    keygen, agent = shutil.which("ssh-keygen.exe"), shutil.which("ssh-add.exe")
    if not keygen or not agent:
        raise HostError("openssh_client_missing")
    if not key.is_file():
        raise HostError("ssh_private_key_missing")
    # -l reads the public fingerprint only and does not prompt for a passphrase.
    result = run_public([keygen, "-l", "-f", str(key)])
    wanted = fingerprint(result.stdout)
    if result.returncode != 0 or wanted is None:
        raise HostError("ssh_key_fingerprint_unavailable")
    result = run_public([agent, "-l"])
    if result.returncode == 2:
        raise HostError("ssh_agent_unavailable")
    loaded = {fingerprint(line) for line in result.stdout.splitlines()}
    if result.returncode != 0 or wanted not in loaded:
        raise HostError("ssh_key_not_loaded_in_current_user_agent")
    return wanted


def asset_identity(root: Path) -> dict:
    """Public identifiers for comparing the same build across LAN computers."""
    result = {}
    game_map = root / "maps/template_map.vpk"
    if game_map.is_file():
        digest = hashlib.sha256()
        with game_map.open("rb") as handle:
            for chunk in iter(lambda: handle.read(1024 * 1024), b""):
                digest.update(chunk)
        result["map_sha256"] = digest.hexdigest()
        result["map_bytes"] = game_map.stat().st_size
    git = shutil.which("git.exe") or shutil.which("git")
    if git:
        base = [git, "-C", str(root)]
        revision = run_public(base + ["rev-parse", "HEAD"])
        value = revision.stdout.strip()
        if revision.returncode == 0 and re.fullmatch(rb"[0-9a-f]{40,64}", value):
            result["git_commit"] = value.decode("ascii")
        changes = run_public(base + ["status", "--porcelain", "--untracked-files=no"])
        if changes.returncode == 0:
            result["tracked_files_modified"] = bool(changes.stdout.strip())
    return result


def check() -> dict:
    settings = config.load(ROOT)
    checks = []

    def record(name, operation):
        try:
            operation()
            checks.append({"check": name, "ok": True})
        except (HostError, auth.AuthError, tunnel.TunnelError) as exc:
            checks.append({"check": name, "ok": False, "error": str(exc)})
        except PermissionError:
            checks.append({"check": name, "ok": False, "error": "local_file_access_denied"})
        except subprocess.TimeoutExpired:
            checks.append({"check": name, "ok": False, "error": "local_command_timeout"})
        except (OSError, ValueError, subprocess.SubprocessError):
            checks.append({"check": name, "ok": False, "error": "local_check_failed"})

    def require(condition, error):
        if not condition:
            raise HostError(error)

    record("python", lambda: require(sys.version_info >= (3, 10), "python_310_or_newer_required"))
    for command in ("git.exe", "node.exe", "ssh.exe", "ssh-keygen.exe", "ssh-add.exe"):
        record(command, lambda c=command: require(shutil.which(c), c.removesuffix(".exe") + "_missing"))
    record("dota", lambda: require((ROOT.parents[1] / "bin/win64/dota2.exe").is_file(), "dota_executable_missing"))
    record("compiled_map", lambda: require((ROOT / "maps/template_map.vpk").is_file(), "compiled_template_map_missing"))
    record("pinned_ecs_host", lambda: tunnel.verify_known_hosts(settings["known_hosts"]))
    record("ssh_agent_identity", lambda: ssh_identity(settings["ssh_key"]))
    # Validate just the expected token field in memory, without printing it.
    def environment_check():
        require(settings["environment"].is_file(), "api_environment_missing")
        auth.read_api_token(settings["environment"])
    record("api_environment", environment_check)
    record("private_temporary_file", auth.check_acl)
    return {"ok": all(item["ok"] for item in checks), "status": "local_checks_complete",
            "checks": checks, "build": asset_identity(ROOT)}


def online_check() -> dict:
    local = check()
    if not local["ok"]:
        return local
    settings = config.load(ROOT)
    state = ROOT / "output/ecs_backend_work/test_tunnel.json"
    with tunnel.state_lock(state):
        connected = tunnel.connect(state, settings["ssh_key"], settings["known_hosts"])
    if not connected.get("ok"):
        raise HostError("ecs_tunnel_not_ready")
    token = auth.read_api_token(settings["environment"])
    try:
        auth.ready(token)
    finally:
        token = None
    return {"ok": True, "status": "backend_ready_game_not_yet_authenticated",
            "local_address": "127.0.0.1:8765", "build": local["build"]}


def create_credential() -> dict:
    """Create one private token-only file; never overwrite a backend .env."""
    if not sys.stdin.isatty():
        raise HostError("interactive_console_required")
    target = ROOT / "output/ecs_backend_work/game-test.env"
    auth.no_reparse(target)
    auth.ignored(target)
    auth.require_ntfs(target)
    if target.exists():
        raise HostError("managed_credential_already_exists")
    config.load(ROOT)  # Validate existing config before asking for a credential.
    token = getpass.getpass("Paste TEST FISHING_API_TOKEN (hidden; stays on this PC): ")
    if (not 24 <= len(token) <= 8192 or token != token.strip()
            or any(ord(char) < 32 or ord(char) == 127 for char in token)):
        raise HostError("api_token_missing_or_invalid")
    target.parent.mkdir(parents=True, exist_ok=True)
    created, saved = False, False
    try:
        with target.open("x", encoding="utf-8"):
            created = True
        auth.private_acl(target)
        auth.no_reparse(target)
        target.write_text("FISHING_API_TOKEN=" + token + "\n", encoding="utf-8")
        config.save({"environment": target}, ROOT)
        saved = True
    finally:
        token = None
        if created and not saved:
            target.unlink(missing_ok=True)
    return {"ok": True, "status": "private_test_credential_saved"}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("configure", "check", "online-check", "credential", "build-info"))
    parser.add_argument("--key", type=Path)
    parser.add_argument("--environment", type=Path)
    parser.add_argument("--known-hosts", type=Path)
    args = parser.parse_args()
    try:
        if os.name != "nt":
            raise HostError("windows_only")
        if args.action == "configure":
            values = {name: value for name, value in (
                ("ssh_key", args.key), ("environment", args.environment),
                ("known_hosts", args.known_hosts)) if value is not None}
            config.save(values, ROOT)
            result = {"ok": True, "status": "local_paths_configured_no_credentials_in_config"}
        elif args.action == "credential":
            result = create_credential()
        elif args.action == "build-info":
            result = {"ok": True, "build": asset_identity(ROOT)}
        else:
            result = check() if args.action == "check" else online_check()
    except (HostError, auth.AuthError, tunnel.TunnelError, config.ConfigError) as exc:
        result = {"ok": False, "error": str(exc)}
    except (OSError, ValueError, subprocess.SubprocessError, EOFError):
        result = {"ok": False, "error": "local_host_setup_failed"}
    print(json.dumps(result, ensure_ascii=False, indent=2))
    return 0 if result.get("ok") else 1


if __name__ == "__main__":
    raise SystemExit(main())
