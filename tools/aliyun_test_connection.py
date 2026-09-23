"""Windows-only, loopback SSH tunnel for the ECS test backend.

Does not read API credentials, modify the game or stop another port owner.
The SSH agent must already hold the dedicated login key. The server host key
must match the fingerprint independently checked in the Alibaba console.
"""
from __future__ import annotations

import argparse
import base64
from contextlib import contextmanager
import ctypes
from ctypes import wintypes
import hashlib
import http.client
import json
import os
from pathlib import Path
import shutil
import socket
import subprocess
import sys
import time


ECS_HOST = "47.110.238.248"
PORT = 8765
HOST_FINGERPRINT = "SHA256:3cUNJuxLSLLSw7CIDmtOis7yGlxaSt+D7DQJmc6Uno8"
ROOT = Path(__file__).resolve().parents[1]
HIDDEN = getattr(subprocess, "CREATE_NO_WINDOW", 0)


class TunnelError(RuntimeError):
    """Only fixed public error codes may be exposed to the command line."""


def verify_known_hosts(path: Path) -> None:
    try:
        lines = path.read_text(encoding="utf-8").splitlines()
        entries = [line.split() for line in lines if line.strip() and not line.lstrip().startswith("#")]
        if len(entries) != 1:
            raise ValueError
        hosts, algorithm, encoded, *_ = entries[0]
        if hosts not in {ECS_HOST, f"[{ECS_HOST}]:22"} or algorithm != "ssh-ed25519":
            raise ValueError
        digest = hashlib.sha256(base64.b64decode(encoded, validate=True)).digest()
        fingerprint = "SHA256:" + base64.b64encode(digest).decode().rstrip("=")
        if fingerprint != HOST_FINGERPRINT:
            raise ValueError
    except (OSError, UnicodeError, ValueError):
        raise TunnelError("host_key_pin_invalid") from None


def ssh_command(ssh: str, key: Path, known_hosts: Path) -> list[str]:
    return [ssh, "-F", "none", "-N", "-T", "-n", "-i", str(key),
            "-o", "BatchMode=yes", "-o", "IdentitiesOnly=yes",
            "-o", "PreferredAuthentications=publickey",
            "-o", "PasswordAuthentication=no", "-o", "KbdInteractiveAuthentication=no",
            "-o", "StrictHostKeyChecking=yes", "-o", f'UserKnownHostsFile="{known_hosts.as_posix()}"',
            "-o", "GlobalKnownHostsFile=none", "-o", "HostKeyAlgorithms=ssh-ed25519",
            "-o", "ExitOnForwardFailure=yes", "-o", "ConnectTimeout=10",
            "-o", "ServerAliveInterval=15", "-o", "ServerAliveCountMax=3",
            "-o", "ControlMaster=no", "-o", "ControlPath=none",
            "-o", "LogLevel=ERROR", "-L", f"127.0.0.1:{PORT}:127.0.0.1:{PORT}",
            f"root@{ECS_HOST}"]


def port_free() -> bool:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as listener:
        if hasattr(socket, "SO_EXCLUSIVEADDRUSE"):
            listener.setsockopt(socket.SOL_SOCKET, socket.SO_EXCLUSIVEADDRUSE, 1)
        try:
            listener.bind(("127.0.0.1", PORT))
            return True
        except OSError:
            return False


def health() -> bool:
    connection = http.client.HTTPConnection("127.0.0.1", PORT, timeout=1)
    try:
        connection.request("GET", "/health")
        response = connection.getresponse()
        payload = json.loads(response.read(4097))
        return response.status == 200 and isinstance(payload, dict) and payload.get("ok") is True
    except (OSError, ValueError, http.client.HTTPException):
        return False
    finally:
        connection.close()


def command_digest(command_line: str) -> str:
    return hashlib.sha256(command_line.encode("utf-8")).hexdigest()


def process_command(pid: int) -> str:
    # The filter is an internally validated integer, never interpolated shell text.
    if type(pid) is not int or pid <= 0:
        raise TunnelError("tunnel_state_invalid")
    script = (f"$p=Get-CimInstance Win32_Process -Filter 'ProcessId = {pid}'; "
              "if ($null -eq $p) { exit 3 }; "
              "@{command=$p.CommandLine} | ConvertTo-Json -Compress")
    try:
        result = subprocess.run(["powershell.exe", "-NoLogo", "-NoProfile", "-NonInteractive",
                                 "-Command", script], capture_output=True, check=True,
                                timeout=10, creationflags=HIDDEN)
        value = json.loads(result.stdout.decode("utf-8-sig"))["command"]
        if not isinstance(value, str) or not value:
            raise ValueError
        return value
    except (OSError, ValueError, KeyError, subprocess.SubprocessError):
        raise TunnelError("process_identity_unavailable") from None


def listener_owned(pid: int) -> bool:
    script = (f"@(Get-NetTCPConnection -State Listen -LocalPort {PORT} -ErrorAction SilentlyContinue "
              "| Select-Object LocalAddress,OwningProcess) | ConvertTo-Json -Compress")
    try:
        result = subprocess.run(["powershell.exe", "-NoLogo", "-NoProfile", "-NonInteractive",
                                 "-Command", script], capture_output=True, check=True,
                                timeout=10, creationflags=HIDDEN)
        values = json.loads(result.stdout.decode("utf-8-sig") or "[]")
        if isinstance(values, dict):
            values = [values]
        return any(value.get("LocalAddress") == "127.0.0.1" and value.get("OwningProcess") == pid
                   for value in values)
    except (OSError, ValueError, AttributeError, TypeError, subprocess.SubprocessError):
        raise TunnelError("listener_identity_unavailable") from None


class ProcessHandle:
    """Keep a Windows process handle open across validation and termination."""

    def __init__(self, pid: int, *, stopping: bool = False):
        self.kernel = ctypes.WinDLL("kernel32", use_last_error=True)
        self.kernel.OpenProcess.argtypes = [wintypes.DWORD, wintypes.BOOL, wintypes.DWORD]
        self.kernel.OpenProcess.restype = wintypes.HANDLE
        self.kernel.CloseHandle.argtypes = [wintypes.HANDLE]
        self.kernel.GetProcessTimes.argtypes = [wintypes.HANDLE] + [ctypes.POINTER(wintypes.FILETIME)] * 4
        self.kernel.QueryFullProcessImageNameW.argtypes = [wintypes.HANDLE, wintypes.DWORD,
                                                        wintypes.LPWSTR, ctypes.POINTER(wintypes.DWORD)]
        self.kernel.WaitForSingleObject.argtypes = [wintypes.HANDLE, wintypes.DWORD]
        self.kernel.WaitForSingleObject.restype = wintypes.DWORD
        self.kernel.TerminateProcess.argtypes = [wintypes.HANDLE, wintypes.UINT]
        self.handle = self.kernel.OpenProcess(0x1000 | 0x100000 | (1 if stopping else 0), False, pid)
        if not self.handle:
            raise TunnelError("tunnel_process_unavailable")

    def __enter__(self):
        return self

    def __exit__(self, *args):
        self.kernel.CloseHandle(self.handle)

    def identity(self) -> dict:
        if self.kernel.WaitForSingleObject(self.handle, 0) != 258:
            raise TunnelError("tunnel_process_exited")
        created, exited, kernel_time, user_time = (wintypes.FILETIME() for _ in range(4))
        if not self.kernel.GetProcessTimes(self.handle, ctypes.byref(created), ctypes.byref(exited),
                                          ctypes.byref(kernel_time), ctypes.byref(user_time)):
            raise TunnelError("process_identity_unavailable")
        size = wintypes.DWORD(32768)
        name = ctypes.create_unicode_buffer(size.value)
        if not self.kernel.QueryFullProcessImageNameW(self.handle, 0, name, ctypes.byref(size)):
            raise TunnelError("process_identity_unavailable")
        return {"created": (created.dwHighDateTime << 32) | created.dwLowDateTime,
                "executable": str(Path(name.value).resolve()).casefold()}

    def terminate(self) -> None:
        if not self.kernel.TerminateProcess(self.handle, 0):
            raise TunnelError("owned_tunnel_stop_failed")
        if self.kernel.WaitForSingleObject(self.handle, 5000) != 0:
            raise TunnelError("owned_tunnel_stop_timeout")


def validate_owned(state: dict, identity: dict, command_line: str) -> None:
    if (state.get("version") != 1 or type(state.get("pid")) is not int or state["pid"] <= 0
            or identity.get("created") != state.get("created")
            or identity.get("executable") != state.get("executable")
            or command_digest(command_line) != state.get("command_digest")):
        raise TunnelError("tunnel_owner_mismatch")


def read_state(path: Path) -> dict | None:
    if not path.exists():
        return None
    try:
        if path.is_symlink() or path.stat().st_size > 8192:
            raise ValueError
        state = json.loads(path.read_text(encoding="utf-8"))
        if not isinstance(state, dict) or type(state.get("pid")) is not int or state["pid"] <= 0:
            raise ValueError
        return state
    except (OSError, ValueError):
        raise TunnelError("tunnel_state_invalid") from None


@contextmanager
def state_lock(path: Path):
    import msvcrt
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.with_suffix(".lock").open("a+b") as handle:
        handle.seek(0)
        if not handle.read(1):
            handle.write(b"0")
            handle.flush()
        handle.seek(0)
        try:
            msvcrt.locking(handle.fileno(), msvcrt.LK_NBLCK, 1)
        except OSError:
            raise TunnelError("tunnel_operation_in_progress") from None
        try:
            yield
        finally:
            handle.seek(0)
            msvcrt.locking(handle.fileno(), msvcrt.LK_UNLCK, 1)


def check(path: Path) -> dict:
    state = read_state(path)
    if state is None:
        return {"ok": False, "status": "not_started"}
    with ProcessHandle(state["pid"]) as handle:
        validate_owned(state, handle.identity(), process_command(state["pid"]))
        if not listener_owned(state["pid"]):
            raise TunnelError("owned_tunnel_listener_missing")
    ready = health()
    return {"ok": ready, "status": "connected" if ready else "backend_unavailable",
            "local_address": f"127.0.0.1:{PORT}", "ssh_pid": state["pid"]}


def stop(path: Path) -> dict:
    state = read_state(path)
    if state is None:
        return {"ok": True, "status": "not_started"}
    with ProcessHandle(state["pid"], stopping=True) as handle:
        validate_owned(state, handle.identity(), process_command(state["pid"]))
        handle.terminate()
    path.unlink()
    path.with_suffix(".stderr").unlink(missing_ok=True)
    return {"ok": True, "status": "stopped"}


def connect(path: Path, key: Path, known_hosts: Path) -> dict:
    verify_known_hosts(known_hosts)
    if not key.is_file() or key.is_symlink():
        raise TunnelError("ssh_private_key_file_missing")
    ssh = shutil.which("ssh.exe")
    if not ssh:
        raise TunnelError("windows_openssh_missing")
    if not port_free():
        # Do not terminate or replace the current listener, even if unhealthy.
        state = read_state(path)
        if state is not None:
            return check(path)
        raise TunnelError("local_port_8765_in_use")
    old = read_state(path)
    if old is not None:
        try:
            with ProcessHandle(old["pid"]) as handle:
                validate_owned(old, handle.identity(), process_command(old["pid"]))
            raise TunnelError("existing_tunnel_has_no_listener")
        except TunnelError as exc:
            if str(exc) not in {"tunnel_process_unavailable", "tunnel_process_exited"}:
                raise
        path.unlink()
    command = ssh_command(str(Path(ssh).resolve()), key.resolve(), known_hosts.resolve())
    # stderr remains a private temporary log; only classified codes are printed.
    error_path = path.with_suffix(".stderr")
    process = None
    try:
        with error_path.open("w+b") as errors:
            process = subprocess.Popen(command, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                                       stderr=errors, creationflags=HIDDEN)
            deadline = time.monotonic() + 15
            while process.poll() is None and time.monotonic() < deadline:
                if health():
                    break
                time.sleep(0.2)
            if process.poll() is not None or not health():
                errors.seek(0)
                detail = errors.read(8192).decode("utf-8", errors="replace")
                if "Permission denied" in detail:
                    raise TunnelError("ssh_public_key_authentication_failed")
                if "Host key verification failed" in detail:
                    raise TunnelError("ssh_host_key_verification_failed")
                if "Address already in use" in detail or "cannot listen to port" in detail:
                    raise TunnelError("local_port_8765_in_use")
                raise TunnelError("ssh_tunnel_or_backend_unavailable")
            with ProcessHandle(process.pid) as handle:
                state = {"version": 1, "pid": process.pid, **handle.identity(),
                         "command_digest": command_digest(subprocess.list2cmdline(command))}
                validate_owned(state, handle.identity(), process_command(process.pid))
                if not listener_owned(process.pid):
                    raise TunnelError("owned_tunnel_listener_missing")
            temporary = path.with_suffix(".new")
            temporary.write_text(json.dumps(state, indent=2) + "\n", encoding="utf-8")
            temporary.replace(path)
            process = None  # The recorded process deliberately survives this command.
        return check(path)
    finally:
        if process is not None and process.poll() is None:
            process.terminate()  # The Popen handle belongs to this launch, never a port lookup.
            process.wait(timeout=5)
        # A successful background SSH process still owns its stderr handle on
        # Windows. Remove that log after stop, never unlink an open child handle.
        if process is not None:
            error_path.unlink(missing_ok=True)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("connect", "check", "stop"))
    parser.add_argument("--key", type=Path, default=Path.home() / ".ssh/goufayu_ecs_ed25519_v2")
    parser.add_argument("--known-hosts", type=Path,
                        default=ROOT / "output/ecs_backend_work/ecs_hostkey_candidate.pub")
    parser.add_argument("--state", type=Path,
                        default=ROOT / "output/ecs_backend_work/test_tunnel.json")
    args = parser.parse_args()
    try:
        if os.name != "nt":
            raise TunnelError("windows_only")
        with state_lock(args.state):
            result = (connect(args.state, args.key, args.known_hosts) if args.action == "connect"
                      else check(args.state) if args.action == "check" else stop(args.state))
    except TunnelError as exc:
        result = {"ok": False, "error": str(exc)}
    except (OSError, ValueError, subprocess.SubprocessError):
        result = {"ok": False, "error": "local_tunnel_operation_failed"}
    print(json.dumps(result, ensure_ascii=False))
    return 0 if result.get("ok") else 1


if __name__ == "__main__":
    raise SystemExit(main())
