"""The two developer test entries. Offline never starts cloud infrastructure."""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
GAME = ROOT.parents[1]
RUNTIME = ROOT / "output/test_entry_runtime"
ONLINE_ADDON = "svt_w24"
ONLINE_POLICY_RECORD = ROOT / "publishing/workshop/online_cheat_policy_20261025.json"


def need(value, code):
    if not value:
        raise RuntimeError(code)


def load_relay():
    spec = importlib.util.spec_from_file_location("test_entry_steam_relay", Path(__file__).with_name("steam_tls_relay.py"))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def ensure_relay():
    relay = load_relay()
    if relay.RECEIPT.exists():
        record = json.loads(relay.RECEIPT.read_text(encoding="utf-8"))
        try:
            observed = relay.process_identity(record["pid"])
        except RuntimeError as error:
            if str(error) != "relay_process_not_found":
                raise RuntimeError("steam_test_relay_identity_invalid") from None
            relay.stop()  # Clears only a confirmed nonexistent owned process.
        else:
            need(observed == record, "steam_test_relay_identity_invalid")
            return {"running": True, "started": False}
    result = relay.start()
    need(result.get("ok") is True, "steam_test_relay_start_failed")
    return {"running": True, "started": True}


def process_inventory():
    need(os.name == "nt", "windows_required")
    script = ("$ErrorActionPreference='Stop';"
              "[Console]::OutputEncoding=New-Object System.Text.UTF8Encoding($false);"
              "$d=@(Get-CimInstance Win32_Process -Filter \"name='dota2.exe'\"|Where-Object{"
              "$live=Get-Process -Id $_.ProcessId -ErrorAction SilentlyContinue;$live -and -not $live.HasExited});"
              "$s=@(Get-CimInstance Win32_Process -Filter \"name='steam.exe'\");"
              "[ordered]@{steam_running=($s.Count -gt 0);dota_pids=@($d|ForEach-Object{$_.ProcessId})}|ConvertTo-Json -Compress")
    result = subprocess.run(["powershell.exe", "-NoProfile", "-NonInteractive", "-Command", script],
                            capture_output=True, timeout=15, creationflags=subprocess.CREATE_NO_WINDOW)
    need(result.returncode == 0 and len(result.stdout) < 8192, "game_process_check_failed")
    return json.loads(result.stdout.decode("utf-8-sig"))


def launch_arguments(mode, log):
    need(mode in ("offline", "online"), "test_mode_invalid")
    addon = ROOT.name if mode == "offline" else ONLINE_ADDON
    result = ["-steam", "-tools", "-noassetbrowser", "-addon", addon, "-dev", "-novid",
              "-vconport", "29006" if mode == "offline" else "29005",
              "-condebug", "-con_logfile", str(log), "+sv_cheats", "1" if mode == "offline" else "0",
              "+host_timescale", "1"]
    if mode == "offline":
        result.extend(("+survival_offline_logic_test", "1"))
    result.extend(("+dota_launch_custom_game", addon, "template_map"))
    return result


def check_online_policy(addon):
    """Refuse a stale online copy that predates the reviewed server cheat gate."""
    record = json.loads(ONLINE_POLICY_RECORD.read_text(encoding="utf-8"))
    need(record.get("online_cheats_allowed") is False, "online_cheat_policy_not_verified")
    candidate = record["candidate"]
    installation = json.loads((addon / "_online_policy_install.json").read_text(encoding="utf-8"))
    need(installation.get("content_sha256") == candidate["content_sha256"], "online_release_policy_outdated")
    policy = addon / "scripts/vscripts/core/release_policy.lua"
    need(hashlib.sha256(policy.read_bytes()).hexdigest() == candidate["runtime_policy_sha256"],
         "online_cheat_policy_bytes_changed")
    profile = (addon / "scripts/vscripts/config/release_profile.lua").read_bytes()
    need(hashlib.sha256(profile).hexdigest() == candidate["release_profile_sha256"],
         "online_release_profile_changed")


def check(mode):
    need(mode in ("offline", "online"), "test_mode_invalid")
    need((GAME / "bin/win64/dota2.exe").is_file(), "dota_executable_missing")
    addon = ROOT if mode == "offline" else ROOT.parent / ONLINE_ADDON
    need((addon / "maps/template_map.vpk").is_file(), "test_map_missing")
    if mode == "offline":
        need((addon / "scripts/vscripts/debug/offline_logic_test.lua").is_file(), "offline_test_code_missing")
        need(b'channel = "development"' in (addon / "scripts/vscripts/config/release_profile.lua").read_bytes(),
             "offline_requires_development")
    else:
        config = (addon / "scripts/vscripts/config/player_web_auth.lua").read_bytes()
        need(b"enabled = true" in config, "online_web_auth_not_enabled")
        need((ROOT / "publishing/workshop/player_web_auth_20261024.json").is_file(), "online_release_record_missing")
        check_online_policy(addon)
    return {"ok": True, "mode": mode, "addon": addon.name,
            "status": "ENTRY_CHECKED", "cloud_login_required": mode == "online",
            "cheats_allowed": mode == "offline",
            "offline_storage": "session_memory" if mode == "offline" else None,
            "game_started": False}


def run(mode, *, check_only=False):
    result = check(mode)
    if check_only:
        return result
    inventory = process_inventory()
    need(not inventory.get("dota_pids"), "dota_already_running")
    need(inventory.get("steam_running") is True, "steam_not_running")
    # The owner PC provides temporary Steam egress until a cloud egress node
    # replaces it. This never runs for the offline logic arena.
    if mode == "online":
        result["steam_transport"] = ensure_relay()
    RUNTIME.mkdir(parents=True, exist_ok=True)
    stamp = datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%S_%f")
    log = RUNTIME / (mode + "_" + stamp + ".log")
    arguments = launch_arguments(mode, log)
    process = subprocess.Popen([str(GAME / "bin/win64/dota2.exe"), *arguments], cwd=GAME / "dota")
    result.update(status="GAME_STARTED", pid=process.pid, log_file=str(log), game_started=True,
                  started_utc=datetime.now(timezone.utc).isoformat())
    (RUNTIME / (mode + "_latest.json")).write_text(json.dumps(result, indent=2), encoding="utf-8")
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=("offline", "online"))
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    try:
        result = run(args.mode, check_only=args.check)
    except (RuntimeError, OSError, ValueError, KeyError) as error:
        code = str(error) if isinstance(error, RuntimeError) else "test_entry_failed"
        if not code.replace("_", "").isalnum() or len(code) > 80:
            code = "test_entry_failed"
        result = {"ok": False, "error": code, "mode": args.mode}
    print(json.dumps(result, ensure_ascii=True))
    return 0 if result["ok"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
