"""Explicit, temporary four-account test transport; default is a read-only plan.

Forward encrypted Steam TLS through this PC's existing connection. The cloud
still verifies the official Steam certificate. No local HTTP proxy, account
password, callback replay, or general-purpose remote destination is provided.
"""
from __future__ import annotations

import argparse
import ctypes
from ctypes import wintypes
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import shutil
import stat
import subprocess
import time

ROOT = Path(__file__).resolve().parents[2]
RECEIPT = ROOT / "output/workshop_web_auth_20261024/steam_tls_relay_process.json"
FORWARD = "127.0.0.1:18768:steamcommunity.com:443"


def transport():
    spec = importlib.util.spec_from_file_location("ws4_steam_pinned_ssh", ROOT / "tools/archive_caps_20261020/remote_driver.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def arguments():
    pinned = transport()
    options = list(pinned.OPTIONS)
    known_hosts = "UserKnownHostsFile=tools/deploy/goufayu_test_known_hosts"
    if options.count(known_hosts) != 1:
        raise RuntimeError("relay_pinned_known_hosts_invalid")
    # OpenSSH parses -o values again as config syntax. Keep a path containing
    # spaces quoted inside that single argv value, using Windows-safe slashes.
    options[options.index(known_hosts)] = 'UserKnownHostsFile="' + (
        ROOT / "tools/deploy/goufayu_test_known_hosts").resolve().as_posix() + '"'
    return ["ssh.exe", "-N", "-T", *options, "-o", "ExitOnForwardFailure=yes",
            "-o", "ServerAliveInterval=15", "-o", "ServerAliveCountMax=3", "-R", FORWARD, pinned.HOST]


def command_line(pid):
    """Read exactly one PID through Windows CIM; never enumerate other SSHs."""
    if os.name != "nt" or type(pid) is not int or not 0 < pid < 2**32:
        raise RuntimeError("relay_windows_process_required")
    kernel = ctypes.WinDLL("kernel32", use_last_error=True)
    kernel.GetSystemDirectoryW.argtypes = (wintypes.LPWSTR, wintypes.UINT)
    kernel.GetSystemDirectoryW.restype = wintypes.UINT
    directory = ctypes.create_unicode_buffer(32768)
    length = kernel.GetSystemDirectoryW(directory, len(directory))
    if not 0 < length < len(directory):
        raise RuntimeError("relay_process_command_unavailable")
    shell = Path(directory.value) / "WindowsPowerShell/v1.0/powershell.exe"
    script = ("$ErrorActionPreference='Stop';"
              "[Console]::OutputEncoding=New-Object System.Text.UTF8Encoding($false);"
              "$p=Get-CimInstance -ClassName Win32_Process -Filter 'ProcessId = " + str(pid) + "';"
              "if($null -eq $p -or [string]::IsNullOrEmpty($p.CommandLine)){throw 'command_unavailable'};"
              "ConvertTo-Json -InputObject ([string]$p.CommandLine) -Compress")
    try:
        result = subprocess.run([str(shell), "-NoProfile", "-NonInteractive", "-Command", script],
                                capture_output=True, timeout=10,
                                creationflags=subprocess.CREATE_NO_WINDOW)
        if result.returncode or len(result.stdout) > 131072:
            raise RuntimeError("relay_process_command_unavailable")
        value = json.loads(result.stdout.decode("utf-8-sig"))
        if not isinstance(value, str) or not value or len(value) > 32767 or "\0" in value:
            raise RuntimeError("relay_process_command_unavailable")
        return value
    except (OSError, ValueError, subprocess.SubprocessError):
        raise RuntimeError("relay_process_command_unavailable") from None


def split_command_line(value):
    shell = ctypes.WinDLL("shell32", use_last_error=True)
    kernel = ctypes.WinDLL("kernel32", use_last_error=True)
    shell.CommandLineToArgvW.argtypes = (wintypes.LPCWSTR, ctypes.POINTER(ctypes.c_int))
    shell.CommandLineToArgvW.restype = ctypes.POINTER(wintypes.LPWSTR)
    kernel.LocalFree.argtypes = (ctypes.c_void_p,)
    kernel.LocalFree.restype = ctypes.c_void_p
    count = ctypes.c_int()
    pointer = shell.CommandLineToArgvW(value, ctypes.byref(count))
    if not pointer:
        raise RuntimeError("relay_process_command_unavailable")
    try:
        if not 1 <= count.value <= 128:
            raise RuntimeError("relay_process_command_unavailable")
        return [pointer[index] for index in range(count.value)]
    finally:
        kernel.LocalFree(ctypes.cast(pointer, ctypes.c_void_p))


def process_identity(pid, *, terminate=False, expected=None, kernel=None,
                     last_error=None, command_reader=None, argv_parser=None):
    """Hold a process handle and check creation time before stopping our SSH."""
    if (os.name != "nt" and kernel is None) or type(pid) is not int or not 0 < pid < 2**32:
        raise RuntimeError("relay_windows_process_required")
    kernel = kernel if kernel is not None else ctypes.WinDLL("kernel32", use_last_error=True)
    kernel.OpenProcess.argtypes = (wintypes.DWORD, wintypes.BOOL, wintypes.DWORD)
    kernel.OpenProcess.restype = wintypes.HANDLE
    kernel.CloseHandle.argtypes = (wintypes.HANDLE,)
    kernel.GetExitCodeProcess.argtypes = (wintypes.HANDLE, ctypes.POINTER(wintypes.DWORD))
    kernel.GetExitCodeProcess.restype = wintypes.BOOL
    kernel.GetProcessTimes.argtypes = (wintypes.HANDLE, *([ctypes.POINTER(wintypes.FILETIME)] * 4))
    kernel.QueryFullProcessImageNameW.argtypes = (wintypes.HANDLE, wintypes.DWORD, wintypes.LPWSTR, ctypes.POINTER(wintypes.DWORD))
    kernel.TerminateProcess.argtypes = (wintypes.HANDLE, wintypes.UINT)
    kernel.WaitForSingleObject.argtypes = (wintypes.HANDLE, wintypes.DWORD)
    kernel.WaitForSingleObject.restype = wintypes.DWORD
    handle = kernel.OpenProcess(0x1000 | (0x00100001 if terminate else 0), False, pid)
    if not handle:
        code = (last_error or ctypes.get_last_error)()
        if code == 87:  # Valid access flags + nonzero PID: process no longer exists.
            raise RuntimeError("relay_process_not_found")
        raise RuntimeError("relay_process_access_failed")
    try:
        exit_code = wintypes.DWORD()
        if not kernel.GetExitCodeProcess(handle, ctypes.byref(exit_code)):
            raise RuntimeError("relay_process_identity_unavailable")
        # A completed process may retain an open kernel object after CIM no
        # longer lists it. Its image is then unavailable, but it is safe to
        # retire its receipt without terminating any process or reusing a PID.
        if exit_code.value != 259:  # STILL_ACTIVE
            raise RuntimeError("relay_process_not_found")
        values = [wintypes.FILETIME() for _ in range(4)]
        if not kernel.GetProcessTimes(handle, *[ctypes.byref(value) for value in values]):
            raise RuntimeError("relay_process_identity_unavailable")
        size, path = wintypes.DWORD(32768), ctypes.create_unicode_buffer(32768)
        if not kernel.QueryFullProcessImageNameW(handle, 0, path, ctypes.byref(size)):
            raise RuntimeError("relay_process_identity_unavailable")
        identity = {"pid": pid, "created": values[0].dwHighDateTime * 2**32 + values[0].dwLowDateTime,
                    "executable": str(Path(path.value).resolve())}
        if Path(identity["executable"]).name.lower() != "ssh.exe":
            raise RuntimeError("relay_process_is_not_ssh")
        if terminate and (not isinstance(expected, dict)
                          or any(expected.get(key) != value for key, value in identity.items())):
            raise RuntimeError("relay_process_identity_changed")
        argv = (argv_parser or split_command_line)((command_reader or command_line)(pid))
        fixed = [identity["executable"], *arguments()[1:]]
        if (not argv or str(Path(argv[0]).resolve()).casefold() != identity["executable"].casefold()
                or argv[1:] != fixed[1:]):
            raise RuntimeError("relay_process_is_not_owned_forward")
        identity["command_sha256"] = hashlib.sha256(
            json.dumps(fixed, ensure_ascii=True, separators=(",", ":")).encode("ascii")).hexdigest()
        if terminate:
            if identity != expected:
                raise RuntimeError("relay_process_identity_changed")
            if not kernel.TerminateProcess(handle, 0):
                raise RuntimeError("relay_stop_failed")
            if kernel.WaitForSingleObject(handle, 10000) != 0:
                raise RuntimeError("relay_stop_not_confirmed")
        return identity
    finally:
        kernel.CloseHandle(handle)


def start():
    if os.name != "nt":
        raise RuntimeError("relay_windows_process_required")
    if RECEIPT.exists():
        # Even a stale receipt requires an explicit stop/review, never a second
        # forward racing the first one for the same loopback listener.
        raise RuntimeError("relay_receipt_exists_review_before_start")
    args = arguments()
    executable = shutil.which(args[0])
    if not executable:
        raise RuntimeError("pinned_ssh_client_missing")
    args[0] = executable
    with open(os.devnull, "wb") as silent:
        process = subprocess.Popen(args, cwd=ROOT, stdin=subprocess.DEVNULL, stdout=silent, stderr=silent,
                                   creationflags=subprocess.CREATE_NO_WINDOW | subprocess.CREATE_NEW_PROCESS_GROUP)
    time.sleep(2)
    if process.poll() is not None:
        raise RuntimeError("relay_ssh_start_failed")
    try:
        identity = process_identity(process.pid)
        RECEIPT.parent.mkdir(parents=True, exist_ok=True)
        with RECEIPT.open("x", encoding="utf-8") as stream:
            json.dump(identity, stream)
    except Exception:
        # This Popen retains our exact child handle, avoiding a PID reuse race.
        process.terminate()
        process.wait(timeout=10)
        raise
    return {"ok": True, "status": "SSH_STARTED_REQUIRES_REMOTE_TLS_PROBE", "pid": process.pid,
            "cloud_transport_enabled": False, "pc_must_remain_online": True}


def stop():
    metadata = RECEIPT.lstat()
    if (not stat.S_ISREG(metadata.st_mode) or metadata.st_size > 4096 or RECEIPT.is_symlink()
            or getattr(metadata, "st_file_attributes", 0) & 0x400):
        raise RuntimeError("relay_receipt_invalid")
    identity = json.loads(RECEIPT.read_text(encoding="utf-8"))
    if (not isinstance(identity, dict) or set(identity) != {"pid", "created", "executable", "command_sha256"}
            or type(identity["pid"]) is not int or not 0 < identity["pid"] < 2**32
            or type(identity["created"]) is not int or identity["created"] <= 0
            or not isinstance(identity["executable"], str) or not Path(identity["executable"]).is_absolute()
            or not isinstance(identity["command_sha256"], str)
            or not re.fullmatch(r"[a-f0-9]{64}", identity["command_sha256"])):
        raise RuntimeError("relay_receipt_invalid")
    try:
        process_identity(identity["pid"], terminate=True, expected=identity)
    except RuntimeError as error:
        if str(error) != "relay_process_not_found":
            raise
    RECEIPT.unlink()
    return {"ok": True, "status": "TEST_SSH_STOPPED", "cloud_transport_changed": False}


def parser():
    result = argparse.ArgumentParser(description=__doc__)
    modes = result.add_mutually_exclusive_group()
    modes.add_argument("--start", action="store_true")
    modes.add_argument("--stop", action="store_true")
    return result


def main():
    args = parser().parse_args()
    try:
        result = start() if args.start else stop() if args.stop else {
            "ok": True, "status": "READ_ONLY_PLAN", "fixed_remote_listener": "127.0.0.1:18768",
            "fixed_destination": "steamcommunity.com:443", "ssh_host_key_pinned": True,
            "official_tls_verified_by_cloud": True, "pc_must_remain_online": True,
            "process_started": False, "cloud_transport_enabled": False}
    except (OSError, ValueError, KeyError, RuntimeError):
        result = {"ok": False, "error": "temporary_steam_relay_action_failed"}
    print(json.dumps(result))
    return 0 if result["ok"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
