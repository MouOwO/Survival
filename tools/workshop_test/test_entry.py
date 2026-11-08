"""The two developer test entries. Offline never starts cloud infrastructure."""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import importlib.util
import json
import os
from pathlib import Path
import stat
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[2]
GAME = ROOT.parents[1]
RUNTIME = ROOT / "output/test_entry_runtime"
ADDON_VPK_LAB_ROOTS = (
    "output/portrait_resolution_release_20261102/peer_full_roundtrip_20261102",
    "output/shared_boss_portrait_release_20261101/peer_full_roundtrip_20261102",
    "output/shared_boss_portrait_release_20261101/ql01",
)
LAB_ERROR_MESSAGES = {
    "addon_lab_vpk_detected": "插件目录内存在 VPK 测试包或裸分卷，已阻止离线启动。请将整个实验目录迁移到插件目录之外并保留备份；本工具不会自动移动或删除文件。",
    "addon_lab_path_unsafe": "VPK 实验目录包含目录连接或异常路径，已停止检查；请保留现场并手动核实，避免扫描真实安装或备份。",
    "addon_lab_scan_failed": "无法安全检查 VPK 实验目录，已阻止离线启动；请检查目录权限并保留全部备份。",
    "addon_lab_scan_limit": "VPK 实验目录超过检查预算，已阻止离线启动；请将整个实验目录迁移到插件目录之外并保留备份。",
}
ENTRY_ERROR_MESSAGES = {
    **LAB_ERROR_MESSAGES,
    "dirty_or_unclassified_runtime_source": "本地有未完成的运行文件改动，已停止启动以保护签名验收包。这不是网络错误；请先处理运行改动或生成与改动一致的新验收包。",
    "test_entry_access_denied": "无法访问验收所需文件，已停止启动。请检查文件权限或占用情况。",
    "test_entry_required_file_missing": "验收所需文件缺失，已停止启动。请核对验收包和入口文件是否完整。",
}
# Only declared, fixed diagnostics may cross the CLI boundary. In particular,
# an identifier-shaped exception value can still be a token, not an error code.
PUBLIC_RUNTIME_ERRORS = frozenset(LAB_ERROR_MESSAGES) | frozenset({
    "dota_already_running", "dota_executable_missing", "game_process_check_failed",
    "offline_requires_development", "offline_test_code_missing",
    "online_requires_canonical_launcher", "steam_not_running",
    "steam_test_relay_identity_invalid", "steam_test_relay_start_failed",
    "test_map_missing", "test_mode_invalid", "windows_required",
    "online_authority_changed_before_launch", "online_authority_not_expected_newest",
    "online_binding_changed_before_launch", "online_binding_contract_invalid",
    "online_candidate_hash_invalid", "online_canonical_report_directory_mismatch",
    "online_expected_newest_invalid", "online_expected_newest_mismatch",
    "online_fixed_report_directory_required", "online_immutable_sources_required",
    "online_keeper_exit_failed_preserve_transaction", "online_keeper_failed_preserve_transaction",
    "online_normal_exit_receipt_required", "online_package_binding_invalid",
    "online_production_auth_policy_unverified", "online_release_sequence_invalid",
    "online_restore_not_complete", "online_signed_candidate_required",
    "online_signed_package_not_current_binding", "online_stage_not_complete",
    "online_workshop_mismatch", "pinned_ssh_client_missing", "relay_pinned_known_hosts_invalid",
    "relay_process_access_failed", "relay_process_command_unavailable",
    "relay_process_identity_changed", "relay_process_identity_unavailable",
    "relay_process_is_not_owned_forward", "relay_process_is_not_ssh", "relay_process_not_found",
    "relay_receipt_exists_review_before_start", "relay_receipt_invalid", "relay_ssh_start_failed",
    "relay_stop_failed", "relay_stop_not_confirmed", "relay_windows_process_required",
})


def public_error_code(error):
    """Classify once on CLI failure without returning exception text or paths."""
    if isinstance(error, PermissionError):
        return "test_entry_access_denied"
    if isinstance(error, FileNotFoundError):
        return "test_entry_required_file_missing"
    if error.args == ("dirty_or_unclassified_runtime_source",) and isinstance(error, ValueError):
        return "dirty_or_unclassified_runtime_source"
    if (isinstance(error, RuntimeError) and len(error.args) == 1
            and type(error.args[0]) is str and error.args[0] in PUBLIC_RUNTIME_ERRORS):
        return error.args[0]
    return "test_entry_failed"


def need(value, code):
    if not value:
        raise RuntimeError(code)


def guard_addon_vpk_labs():
    """Once per offline check/launch, never a frame task or workspace scan.

    K=3 fixed roots, D=3 fixed components: <=K*D cached metadata reads when
    absent. Existing LABs alone get one no-reparse traversal, <=4096 entries
    and2 seconds total. No VPK contents, actual packages, or backups are read.
    """
    checked = {}
    reparse = getattr(stat, "FILE_ATTRIBUTE_REPARSE_POINT", 0x400)
    deadline, visited = time.monotonic() + 2, 0
    try:
        for relative in ADDON_VPK_LAB_ROOTS:
            lab = ROOT
            for part in Path(relative).parts:
                lab = lab / part
                if lab not in checked:
                    try:
                        info = lab.lstat()
                    except FileNotFoundError:
                        checked[lab] = False
                    else:
                        need(stat.S_ISDIR(info.st_mode) and not getattr(info, "st_file_attributes", 0) & reparse,
                             "addon_lab_path_unsafe")
                        checked[lab] = True
                if not checked[lab]:
                    break
            else:
                pending = [lab]
                while pending:
                    need(time.monotonic() <= deadline, "addon_lab_scan_limit")
                    directory = pending.pop()
                    with os.scandir(directory) as entries:
                        for item in entries:
                            visited += 1
                            need(visited <= 4096 and time.monotonic() <= deadline, "addon_lab_scan_limit")
                            need(not item.name.lower().endswith(".vpk"), "addon_lab_vpk_detected")
                            info = item.stat(follow_symlinks=False)
                            need(not stat.S_ISLNK(info.st_mode)
                                 and not getattr(info, "st_file_attributes", 0) & reparse,
                                 "addon_lab_path_unsafe")
                            if stat.S_ISDIR(info.st_mode):
                                pending.append(Path(item.path))
    except OSError:
        raise RuntimeError("addon_lab_scan_failed") from None


def load_relay():
    spec = importlib.util.spec_from_file_location("test_entry_steam_relay", Path(__file__).with_name("steam_tls_relay.py"))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def load_online():
    spec = importlib.util.spec_from_file_location("test_entry_signed_online", Path(__file__).with_name("online_signed_entry.py"))
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
    need(mode == "offline", "online_requires_canonical_launcher")
    return ["-steam", "-tools", "-noassetbrowser", "-addon", ROOT.name, "-dev", "-novid",
            "-vconport", "29006", "-condebug", "-con_logfile", str(log), "+sv_cheats", "1",
            "+host_timescale", "1", "+survival_offline_logic_test", "1",
            "+survival_archive_http_enabled", "0", "+dota_launch_custom_game", ROOT.name, "template_map"]


def check(mode):
    need(mode in ("offline", "online"), "test_mode_invalid")
    if mode == "online":
        return load_online().check()
    guard_addon_vpk_labs()
    need((GAME / "bin/win64/dota2.exe").is_file(), "dota_executable_missing")
    need((ROOT / "maps/template_map.vpk").is_file(), "test_map_missing")
    need((ROOT / "scripts/vscripts/debug/offline_logic_test.lua").is_file(), "offline_test_code_missing")
    need(b'channel = "development"' in (ROOT / "scripts/vscripts/config/release_profile.lua").read_bytes(),
         "offline_requires_development")
    return {"ok": True, "mode": mode, "addon": ROOT.name,
            "status": "ENTRY_CHECKED", "cloud_login_required": False, "cheats_allowed": True,
            "offline_storage": "session_memory", "game_started": False}


def run(mode, *, check_only=False):
    need(mode in ("offline", "online"), "test_mode_invalid")
    online = load_online() if mode == "online" else None
    prepared = online.prepare() if online else None
    result = prepared["summary"] if online else check(mode)
    if check_only:
        return result
    inventory = process_inventory()
    need(not inventory.get("dota_pids"), "dota_already_running")
    need(inventory.get("steam_running") is True, "steam_not_running")
    # The owner PC provides temporary Steam egress until a cloud egress node
    # replaces it. This never runs for the offline logic arena.
    if online:
        result["steam_transport"] = ensure_relay()
        # This call keeps the CMD alive until the canonical keeper observes the
        # exact owned game's exit and the original installation is restored.
        return online.run_prepared(prepared)
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
        code = public_error_code(error)
        result = {"ok": False, "error": code, "mode": args.mode}
        if code in ENTRY_ERROR_MESSAGES:
            result["message"] = ENTRY_ERROR_MESSAGES[code]
            print(result["message"], file=sys.stderr)
    print(json.dumps(result, ensure_ascii=True))
    return 0 if result["ok"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
