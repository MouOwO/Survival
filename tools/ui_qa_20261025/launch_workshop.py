"""Prepare/check the ordinary original-Workshop entry; launch only explicitly.

This is a direct command to the real Workshop entry map, not a click on the
Arcade lobby button. It does not start Tools, an author addon or insecure mode.
Receipt validation queries only process/listener identity, never console text,
browser tokens, credentials or player data. Existing relay handling is reused.
"""
from __future__ import annotations

import argparse
from contextlib import contextmanager
import datetime
import hashlib
import json
import os
from pathlib import Path
import re
import stat
import subprocess
import sys
import uuid

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools/workshop_test"))
import test_entry as entry
sys.path.insert(0, str(Path(__file__).resolve().parent))
import native_package_reads_v08 as native

APP_ID, WORKSHOP_ID, PORT = 570, "3824360109", 29007
ENTRY_MAP, GAMEPLAY_MAP = "ws4_entry", "template_map"
EXE = entry.GAME / "bin/win64/dota2.exe"
OUTPUT = ROOT / "output/ui_qa_20261025/online_workshop"
KIND = "ws4_ordinary_original_workshop_launch"


def need(value, code):
    if not value:
        raise RuntimeError(code)


def regular(path, *, exists=True):
    path = Path(path)
    need(path.is_absolute(), "workshop_absolute_path_required")
    for part in (path, *path.parents):
        try:
            info = part.lstat()
        except FileNotFoundError:
            continue
        need(not part.is_symlink() and not (getattr(info, "st_file_attributes", 0)
                 & getattr(stat, "FILE_ATTRIBUTE_REPARSE_POINT", 0x400)), "workshop_reparse_path_forbidden")
    return path.resolve(strict=exists)


def powershell_json(script):
    need(os.name == "nt", "workshop_windows_required")
    reply = subprocess.run(["powershell.exe", "-NoProfile", "-NonInteractive", "-Command",
        "$ErrorActionPreference='Stop';[Console]::OutputEncoding=New-Object System.Text.UTF8Encoding($false);" + script],
        capture_output=True, timeout=15, creationflags=subprocess.CREATE_NO_WINDOW)
    need(reply.returncode == 0 and len(reply.stdout) <= 32768, "workshop_process_query_failed")
    return json.loads(reply.stdout.decode("utf-8-sig"))


def process_details(pid):
    need(type(pid) is int and 0 < pid < 2**31, "workshop_pid_invalid")
    return powershell_json(
        "$p=Get-CimInstance Win32_Process -Filter 'ProcessId=" + str(pid) + "';"
        "if(-not $p){throw 'process_missing'};"
        "[ordered]@{pid=[int]$p.ProcessId;name=$p.Name;executable=$p.ExecutablePath;"
        "created_utc=$p.CreationDate.ToUniversalTime().ToString('o');command_line=$p.CommandLine}|ConvertTo-Json -Compress")


def port_owners():
    value = powershell_json(
        "$p=@(Get-NetTCPConnection -LocalPort 29007 -State Listen -ErrorAction SilentlyContinue);"
        "[ordered]@{owners=@($p|Select-Object -ExpandProperty OwningProcess -Unique)}|ConvertTo-Json -Compress")
    owners = value.get("owners")
    need(isinstance(owners, list) and all(type(pid) is int and pid > 0 for pid in owners),
         "workshop_listener_query_invalid")
    return sorted(set(owners))


def launch_arguments(log):
    return ["-steam", "-novid", "-console", "-vconport", "29007", "-condebug", "-con_logfile", str(log),
            "+sv_cheats", "0", "+dota_launch_custom_game", WORKSHOP_ID, ENTRY_MAP]


def validate_process(observed, pid, log, *, created=None, command_sha=None, argv_parser=None):
    need(observed.get("pid") == pid and observed.get("name", "").casefold() == "dota2.exe"
         and Path(observed.get("executable", "")).resolve() == EXE.resolve(), "ordinary_workshop_process_required")
    line = observed.get("command_line")
    need(isinstance(line, str) and 0 < len(line) <= 32767, "ordinary_workshop_command_missing")
    argv = (argv_parser or entry.load_relay().split_command_line)(line)
    need(argv and Path(argv[0]).resolve() == EXE.resolve() and argv[1:] == launch_arguments(log),
         "ordinary_workshop_arguments_mismatch")
    born = observed.get("created_utc")
    need(isinstance(born, str) and bool(born), "ordinary_workshop_creation_missing")
    if created is not None:
        need(born == created, "ordinary_workshop_pid_reused")
    digest = hashlib.sha256(line.encode("utf-8")).hexdigest()
    if command_sha is not None:
        need(digest == command_sha, "ordinary_workshop_command_changed")
    return dict(pid=pid, executable=str(EXE.resolve()), created_utc=born, command_line_sha256=digest)


def check_download():
    native.require_package_pins()
    target = regular(native.TARGETS["download"])
    members = native.pack.package_paths(target)
    need(set(target.parent.iterdir()) == set(members), "ordinary_workshop_download_members_mismatch")
    need(native.pack.runtime.digest(target) == native.MEMBERS[0]["sha256"], "ordinary_workshop_download_index_mismatch")
    for path, row in zip(members, native.MEMBERS):
        need(regular(path).name == row["name"] and path.stat().st_size == row["bytes"],
             "ordinary_workshop_download_size_mismatch")
    return dict(content_sha256=native.CONTENT_SHA, release_sequence=native.SEQUENCE,
                index_sha256=native.MEMBERS[0]["sha256"], archive_count=4,
                scope="pinned_index_and_member_sizes_not_a_replacement_for_full_download_hash_verification")


def existing_relay():
    relay = entry.load_relay()
    path = regular(relay.RECEIPT)
    need(path.stat().st_size <= 8192, "ordinary_workshop_relay_receipt_invalid")
    record = json.loads(path.read_text(encoding="utf-8-sig"))
    need(isinstance(record, dict) and set(record) == {"pid", "created", "executable", "command_sha256"},
         "ordinary_workshop_relay_receipt_invalid")
    need(relay.process_identity(record["pid"]) == record, "ordinary_workshop_relay_identity_invalid")
    return dict(running=True, started=False)


def preflight():
    inventory = entry.process_inventory()
    need(inventory.get("steam_running") is True, "ordinary_workshop_steam_required")
    need(not inventory.get("dota_pids"), "ordinary_workshop_close_existing_dota_first")
    need(not port_owners(), "ordinary_workshop_vcon_port_in_use")
    regular(EXE)
    return check_download()


@contextmanager
def launch_lock():
    regular(OUTPUT, exists=False).mkdir(parents=True, exist_ok=True)
    path, token = OUTPUT / "launch.lock", uuid.uuid4().hex.encode("ascii")
    with path.open("xb") as stream:
        stream.write(token)
    try:
        yield
    finally:
        if path.read_bytes() == token:
            path.unlink()


def write_new_json(path, value):
    with path.open("x", encoding="utf-8") as stream:
        json.dump(value, stream, ensure_ascii=False, indent=2)
        stream.write("\n")


def run(*, launch=False):
    download = preflight()
    if not launch:
        return dict(ok=True, status="READ_ONLY_ENTRY_CHECKED", app_id=APP_ID, workshop_id=WORKSHOP_ID,
                    entry_map=ENTRY_MAP, expected_auto_reopen_map=GAMEPLAY_MAP, port=PORT,
                    entry_method="ordinary_direct_workshop_entry_map_not_arcade_button",
                    relay=existing_relay(), downloaded_package=download, game_started=False)
    with launch_lock():
        relay = entry.ensure_relay()
        need(relay.get("running") is True, "ordinary_workshop_relay_required")
        preflight()  # Recheck after relay work, while holding the shared launcher lock.
        stamp = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
        folder = OUTPUT / ("workshop_" + stamp + "_" + uuid.uuid4().hex[:8])
        folder.mkdir(exist_ok=False)
        log, receipt = folder / "game.log", folder / "launch_receipt.json"
        args = launch_arguments(log)
        record = dict(schema=1, kind=KIND, app_id=APP_ID, workshop_id=WORKSHOP_ID, entry_map=ENTRY_MAP,
                      expected_auto_reopen_map=GAMEPLAY_MAP, entry_method="ordinary_direct_workshop_entry_map_not_arcade_button",
                      content_sha256=native.CONTENT_SHA, release_sequence=native.SEQUENCE,
                      tools=False, insecure=False, author_addon=False, cheats_allowed=False, vcon_port=PORT,
                      log_file=str(log), arguments=args, relay=relay, downloaded_package=download,
                      started_utc=datetime.datetime.now(datetime.timezone.utc).isoformat())
        write_new_json(folder / "launch_request.json", dict(record, status="REQUEST_PREPARED_NO_GAME_YET"))
        child = None
        try:
            environment = dict(os.environ, SteamAppId="570", SteamGameId="570")
            child = subprocess.Popen([str(EXE), *args], cwd=entry.GAME / "dota", env=environment)
            record.update(pid=child.pid, game_started=True)
            # One read-only CIM query is enough once Windows has returned Popen.
            identity = validate_process(process_details(child.pid), child.pid, log)
            record.update(identity, ok=True, status="GAME_STARTED_WAITING_NATIVE_ACCEPTANCE")
        except Exception:
            record.update(ok=False, status="LAUNCH_OR_IDENTITY_CHECK_FAILED", game_started=child is not None)
        write_new_json(receipt, record)
        return dict(record, receipt=str(receipt))


def validate_live_receipt(path, pid):
    path = regular(path)
    need(path.name == "launch_receipt.json" and path.parent.parent == regular(OUTPUT)
         and re.fullmatch(r"workshop_[0-9]{8}T[0-9]{12}Z_[0-9a-f]{8}", path.parent.name),
         "ordinary_workshop_receipt_path_invalid")
    need(path.stat().st_size <= 32768, "ordinary_workshop_receipt_oversized")
    record = json.loads(path.read_text(encoding="utf-8-sig"))
    need(record.get("ok") is True and record.get("kind") == KIND and record.get("app_id") == APP_ID
         and record.get("workshop_id") == WORKSHOP_ID and record.get("entry_map") == ENTRY_MAP
         and record.get("expected_auto_reopen_map") == GAMEPLAY_MAP
         and record.get("content_sha256") == native.CONTENT_SHA and record.get("release_sequence") == native.SEQUENCE
         and record.get("tools") is False and record.get("insecure") is False
         and record.get("author_addon") is False and record.get("cheats_allowed") is False
         and record.get("vcon_port") == PORT and record.get("pid") == pid,
         "ordinary_workshop_receipt_identity_invalid")
    need(isinstance(record.get("created_utc"), str) and bool(record["created_utc"])
         and isinstance(record.get("command_line_sha256"), str)
         and re.fullmatch(r"[0-9a-f]{64}", record["command_line_sha256"]),
         "ordinary_workshop_receipt_process_binding_missing")
    log = path.parent / "game.log"
    need(record.get("log_file") == str(log) and record.get("arguments") == launch_arguments(log),
         "ordinary_workshop_receipt_arguments_invalid")
    identity = validate_process(process_details(pid), pid, log, created=record.get("created_utc"),
                                command_sha=record.get("command_line_sha256"))
    need(port_owners() == [pid], "ordinary_workshop_vcon_owner_mismatch")
    return dict(ok=True, status="ORDINARY_WORKSHOP_PROCESS_CHECKED", receipt=str(path),
                pid=pid, created_utc=identity["created_utc"], port=PORT,
                capture_directory=str(path.parent / "captures"), app_id=APP_ID,
                workshop_id=WORKSHOP_ID, game_control_performed=False)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--launch", action="store_true")
    mode.add_argument("--check-only", action="store_true")
    mode.add_argument("--check-receipt", type=Path)
    parser.add_argument("--pid", type=int)
    args = parser.parse_args()
    if (args.check_receipt is None) != (args.pid is None):
        parser.error("--check-receipt and --pid must be supplied together")
    try:
        value = validate_live_receipt(args.check_receipt, args.pid) if args.check_receipt else run(launch=args.launch)
    except Exception as error:
        code = str(error)
        if not re.fullmatch(r"[a-z][a-z0-9_]{0,95}", code):
            code = "ordinary_workshop_check_failed"
        value = dict(ok=False, error=code, game_started=False, game_control_performed=False)
    print(json.dumps(value, ensure_ascii=True))
    return 0 if value["ok"] else 2


if __name__ == "__main__":
    raise SystemExit(main())
