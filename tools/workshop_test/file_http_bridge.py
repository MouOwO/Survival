"""Closed-test HTTPS transport. Does not grant login or replace backend checks.

No listener, arbitrary URL/console command, request replay, or token persistence.
The helper must run as the Dota host's Windows user. Importing is side effect free.
"""
from __future__ import annotations

import argparse
import base64
from collections import deque
from concurrent.futures import Future, ThreadPoolExecutor
import ctypes
from ctypes import wintypes
from dataclasses import dataclass, field
import hashlib
import heapq
import json
import math
import os
from pathlib import Path
import queue
import re
import secrets
import subprocess
import threading
import time
import urllib.error
import urllib.request

BASE = "https://pay.xiaofengnet.com/ws4-web"
POST = frozenset("/v1/" + name for name in (
    "player-auth/start", "player-auth/poll", "session/authenticate", "session/login",
    "profile", "lottery/catalog", "lottery/snapshot", "archive/config", "archive/command",
    "archive/endless-batch", "archive/endless-leaderboard", "online-time/checkpoint", "payments/catalog", "payments/create",
    "payments/status", "payments/cancel"))
ACCOUNTS = frozenset(str(int(s) - 76561197960265728) for s in (
    "76561198424163156", "76561198845461206", "76561198104787442",
    "76561198974301984", "76561198296534615"))
MAX_PENDING, MAX_REQUEST, MAX_RESPONSE = 16, 262144, 8388608
OUT_CHUNK, IN_CHUNK, BLOCK_CHUNKS = 1024, 192, 16
PREFIX = "[SFB1] "
EPOCH = re.compile(r"[A-Za-z0-9_]{1,24}\Z")
SESSION = re.compile(r"[A-Za-z0-9_.:-]{8,200}\Z")


def compact(value):
    return json.dumps(value, separators=(",", ":"), ensure_ascii=True).encode("ascii")


def integer(value, low, high):
    if type(value) is not int or not low <= value <= high:
        raise ValueError("invalid_integer")
    return value


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *args, **kwargs):
        raise ValueError("redirect_rejected")


def https(method, path, headers, body, timeout):
    """Exactly one request. HTTP errors are responses, transport errors are not retried."""
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}), NoRedirect())
    request = urllib.request.Request(BASE + path, data=body if method == "POST" else None,
                                     headers=headers, method=method)
    try:
        response = opener.open(request, timeout=timeout)
    except urllib.error.HTTPError as error:
        response = error
    with response:
        raw = response.read(MAX_RESPONSE + 1)
        if len(raw) > MAX_RESPONSE:
            raise ValueError("response_too_large")
        return response.code, raw


class Vault:
    """Opaque aliases preserve the game's token format; real credentials stay in RAM."""
    def __init__(self, clock=time.monotonic):
        self.clock, self.entries, self.expiries = clock, {}, []
        self.lock = threading.Lock()

    def _expire(self):
        now = self.clock()
        while self.expiries and self.expiries[0][0] <= now:
            _, alias = heapq.heappop(self.expiries)
            self.entries.pop(alias, None)

    def store(self, kind, real, identity, ttl):
        if not isinstance(real, str) or not 24 <= len(real) <= 512:
            raise ValueError("credential_invalid")
        if type(ttl) not in (int, float) or not 0 < ttl <= 86400:
            raise ValueError("credential_expiry_invalid")
        with self.lock:
            self._expire()
            if len(self.entries) >= 64:
                raise ValueError("credential_capacity")
            alias = ("pwa1_" + secrets.token_hex(32) if kind == "token"
                     else "sfb1d_" + secrets.token_hex(24))
            expiry = self.clock() + ttl
            self.entries[alias] = (kind, real, identity, expiry)
            heapq.heappush(self.expiries, (expiry, alias))
            return alias

    def resolve(self, alias, kind, identity):
        with self.lock:
            self._expire()
            entry = self.entries.get(alias)
            if not entry or entry[0] != kind or entry[2] != identity:
                raise ValueError("credential_scope_invalid")
            return entry[1]


@dataclass
class Job:
    epoch: str
    id: int
    method: str
    path: str
    headers: dict
    size: int
    chunks: int
    deadline: float
    parts: dict = field(default_factory=dict)
    received: int = 0
    submitted: bool = False


class Deadlines:
    """Indexed heap: successful completion removes its deadline immediately."""
    def __init__(self):
        self.heap, self.positions = [], {}

    def swap(self, a, b):
        self.heap[a], self.heap[b] = self.heap[b], self.heap[a]
        self.positions[self.heap[a][1]], self.positions[self.heap[b][1]] = a, b

    def up(self, index):
        while index and self.heap[index] < self.heap[(index - 1) // 2]:
            parent = (index - 1) // 2
            self.swap(index, parent); index = parent

    def down(self, index):
        while 2 * index + 1 < len(self.heap):
            child = 2 * index + 1
            if child + 1 < len(self.heap) and self.heap[child + 1] < self.heap[child]:
                child += 1
            if self.heap[index] <= self.heap[child]:
                break
            self.swap(index, child); index = child

    def put(self, deadline, key):
        self.remove(key)
        self.positions[key] = len(self.heap)
        self.heap.append((deadline, key)); self.up(len(self.heap) - 1)

    def remove(self, key):
        index = self.positions.pop(key, None)
        if index is None:
            return
        last = self.heap.pop()
        if index < len(self.heap):
            self.heap[index] = last; self.positions[last[1]] = index
            if index and self.heap[index] < self.heap[(index - 1) // 2]:
                self.up(index)
            else:
                self.down(index)

    def expired(self, now):
        while self.heap and self.heap[0][0] <= now:
            key = self.heap[0][1]
            self.remove(key)
            yield key


class Transport:
    def __init__(self, network=https, clock=time.monotonic):
        self.network, self.clock = network, clock
        self.vault = Vault(clock)

    def send(self, job):
        if not ((job.method == "GET" and job.path == "/health") or (job.method == "POST" and job.path in POST)):
            raise ValueError("route_invalid")
        timeout = min(30, job.deadline - self.clock())
        if timeout <= 0:
            raise ValueError("request_expired")
        body = b"".join(job.parts[i] for i in range(1, job.chunks + 1))
        headers = {"Content-Type": "application/json; charset=utf-8"}
        if job.method == "GET":
            if job.path != "/health" or body or job.headers:
                raise ValueError("health_invalid")
            return self.network("GET", job.path, {}, b"", timeout)
        value = json.loads(body)
        if not isinstance(value, dict):
            raise ValueError("body_invalid")
        account, match = value.get("account_id"), value.get("match_session_id")
        if account not in ACCOUNTS or not isinstance(match, str) or not SESSION.fullmatch(match):
            raise ValueError("identity_invalid")
        identity = (account, match)
        if job.path == "/v1/player-auth/start":
            if job.headers or set(value) != {"account_id", "match_session_id"}:
                raise ValueError("start_invalid")
        elif job.path == "/v1/player-auth/poll":
            if job.headers or set(value) != {"account_id", "match_session_id", "device_code"}:
                raise ValueError("poll_invalid")
            value["device_code"] = self.vault.resolve(value["device_code"], "device", identity)
            body = compact(value)
        else:
            bearer = job.headers.get("Authorization", "")
            if not bearer.startswith("Bearer "):
                raise ValueError("authorization_missing")
            real = self.vault.resolve(bearer[7:], "token", identity)
            headers["Authorization"] = "Bearer " + real
            wire = job.headers.get("X-Survival-Wire")
            if wire is not None:
                if not re.fullmatch(r"[a-f0-9]{64}", wire):
                    raise ValueError("wire_invalid")
                headers["X-Survival-Wire"] = wire
        status, raw = self.network(job.method, job.path, headers, body, timeout)
        if len(raw) > MAX_RESPONSE or not 100 <= status <= 599:
            raise ValueError("response_invalid")
        if job.path.startswith("/v1/player-auth/") and status == 200:
            value = json.loads(raw)
            if not isinstance(value, dict):
                raise ValueError("auth_response_invalid")
            if "device_code" in value:
                if job.path != "/v1/player-auth/start":
                    raise ValueError("unexpected_credential")
                value["device_code"] = self.vault.store("device", value["device_code"], identity, value.get("expires_in"))
            if "access_token" in value:
                if job.path != "/v1/player-auth/poll" or value.get("account_id") != account or value.get("match_session_id") != match:
                    raise ValueError("auth_scope_invalid")
                value["access_token"] = self.vault.store("token", value["access_token"], identity, value.get("expires_in"))
            raw = compact(value)
        return status, raw


_SECURITY = None


def security():
    global _SECURITY
    if _SECURITY is None:
        import csv
        output = subprocess.check_output(["whoami", "/user", "/fo", "csv", "/nh"],
                                         creationflags=0x08000000, text=True)
        sid = next(csv.reader([output.strip()]))[1]
        if not re.fullmatch(r"S-1-[0-9-]+", sid):
            raise ValueError("sid_invalid")
        api = ctypes.WinDLL("advapi32", use_last_error=True)
        api.ConvertStringSecurityDescriptorToSecurityDescriptorW.argtypes = [wintypes.LPCWSTR, wintypes.DWORD, ctypes.POINTER(ctypes.c_void_p), ctypes.POINTER(wintypes.DWORD)]
        api.SetFileSecurityW.argtypes = [wintypes.LPCWSTR, wintypes.DWORD, ctypes.c_void_p]
        api.GetFileSecurityW.argtypes = [wintypes.LPCWSTR, wintypes.DWORD, ctypes.c_void_p, wintypes.DWORD, ctypes.POINTER(wintypes.DWORD)]
        api.GetSecurityDescriptorControl.argtypes = [ctypes.c_void_p, ctypes.POINTER(wintypes.WORD), ctypes.POINTER(wintypes.DWORD)]
        descriptor = ctypes.c_void_p()
        if not api.ConvertStringSecurityDescriptorToSecurityDescriptorW(f"D:P(A;;FA;;;SY)(A;;FA;;;{sid})", 1, ctypes.byref(descriptor), None):
            raise ValueError("private_acl_unavailable")
        _SECURITY = api, descriptor
    return _SECURITY


def private_acl(path):
    """Exact protected DACL, no inherited or explicit access for other users."""
    api, descriptor = security()
    if not api.SetFileSecurityW(str(path), 4 | 0x80000000, descriptor):
        raise ValueError("private_acl_failed")


def saved_acl(path):
    api, _ = security()
    size = wintypes.DWORD()
    api.GetFileSecurityW(str(path), 4, None, 0, ctypes.byref(size))
    data = ctypes.create_string_buffer(size.value)
    if not api.GetFileSecurityW(str(path), 4, data, size, ctypes.byref(size)):
        raise ValueError("acl_backup_failed")
    control, revision = wintypes.WORD(), wintypes.DWORD()
    if not api.GetSecurityDescriptorControl(data, ctypes.byref(control), ctypes.byref(revision)):
        raise ValueError("acl_control_failed")
    return data, 0x80000000 if control.value & 0x1000 else 0x20000000


class Files:
    def __init__(self, cfg, nonce):
        self.cfg, self.nonce, self.owned = Path(cfg).resolve(strict=True), nonce, {}
        self.directory = self.cfg / "survival_ws4_http_bridge"
        self.bootstrap = self.cfg / "survival_ws4_http_bridge_bootstrap.cfg"
        self.cursor = self.cfg / "survival_ws4_http_bridge_cursor.cfg"
        if self.directory.exists() or self.bootstrap.exists() or self.cursor.exists():
            raise ValueError("bridge_files_already_exist")
        self.directory.mkdir()
        private_acl(self.directory)
        self.write(self.cursor, b"// No completed reply.\n")
        self.write(self.bootstrap, f"survival_sfb_begin {nonce} 1\n".encode("ascii"))

    def write(self, path, body):
        if path.exists() and (path not in self.owned or hashlib.sha256(path.read_bytes()).hexdigest() != self.owned[path]):
            raise ValueError("bridge_file_changed")
        temporary = path.with_suffix(".sfbtmp")
        with temporary.open("xb") as stream:
            stream.write(body)
        private_acl(temporary)
        os.replace(temporary, path)
        self.owned[path] = hashlib.sha256(body).hexdigest()

    def publish(self, job, serial, status, raw):
        chunks = math.ceil(len(raw) / IN_CHUNK)
        blocks = max(1, math.ceil(chunks / BLOCK_CHUNKS))
        paths = []
        for block in range(1, blocks + 1):
            lines = []
            for index in range((block - 1) * BLOCK_CHUNKS + 1, min(chunks, block * BLOCK_CHUNKS) + 1):
                data = base64.b64encode(raw[(index - 1) * IN_CHUNK:index * IN_CHUNK]).decode("ascii")
                lines.append(f"survival_sfb_chunk {self.nonce} {job.epoch} {serial} {index} {data}\n")
            lines.append(f"survival_sfb_block {self.nonce} {job.epoch} {serial} {block}\n")
            path = self.directory / f"b_{self.nonce}_{job.epoch}_{serial}_{block}.cfg"
            self.write(path, "".join(lines).encode("ascii"))
            paths.append(path)
        self.write(self.cursor, f"survival_sfb_reply {self.nonce} {job.epoch} {serial} {job.id} {status} {len(raw)} {chunks} {blocks}\n".encode("ascii"))
        return paths

    def retire(self, paths):
        self.write(self.cursor, b"// No completed reply.\n")
        for path in paths:
            self.remove(path)

    def remove(self, path):
        digest = self.owned.get(path)
        if path.exists() and digest and hashlib.sha256(path.read_bytes()).hexdigest() == digest:
            path.unlink()
            self.owned.pop(path)

    def close(self):
        for path in list(self.owned):
            self.remove(path)
        try:
            self.directory.rmdir()
        except OSError:
            pass


class Engine:
    """Incremental log consumer: O(new bytes), <=16 jobs, four HTTPS workers.

    Completed futures enqueue once. Expiry is an indexed-id check after heap pop;
    stale bounded entries disappear by deadline. Never scans pending per poll.
    """
    def __init__(self, nonce, files, transport=None, clock=time.monotonic):
        self.nonce, self.files, self.clock = nonce, files, clock
        self.transport = transport or Transport(clock=clock)
        self.pool = ThreadPoolExecutor(max_workers=4, thread_name_prefix="sfb_https")
        self.done, self.waiting = queue.SimpleQueue(), deque()
        self.jobs, self.expiries = {}, Deadlines()
        self.epoch, self.highest, self.serial, self.active = None, 0, 0, None
        self.http_count = 0
        self.running = 0

    def event(self, event):
        if not isinstance(event, dict) or event.get("nonce") != self.nonce:
            return
        epoch = event.get("epoch")
        if not isinstance(epoch, str) or not EPOCH.fullmatch(epoch):
            return
        kind = event.get("event")
        if kind == "ready":
            if event.get("protocol") != 1 or event.get("tools") is not False:
                return
            if self.epoch != epoch:
                if self.active:
                    self.files.retire(self.active[3])
                self.epoch, self.highest, self.active = epoch, 0, None
                self.jobs.clear(); self.expiries = Deadlines(); self.waiting.clear()
            return
        if epoch != self.epoch:
            return
        if kind == "ack":
            if self.active and event.get("serial") == self.active[0] and event.get("id") == self.active[1].id:
                self.files.retire(self.active[3])
                self.jobs.pop(self.active[1].id, None)
                self.expiries.remove(self.active[1].id)
                self.active = None
            return
        request_id = integer(event.get("id"), 1, 9999999)
        if kind == "request":
            if request_id <= self.highest or len(self.jobs) >= MAX_PENDING:
                return
            self.highest = request_id
            method, path, headers = event.get("method"), event.get("path"), event.get("headers")
            if headers == []:  # Shared Lua encoder represents an empty table as [].
                headers = {}
            if not ((method == "GET" and path == "/health") or (method == "POST" and path in POST)):
                return
            if not isinstance(headers, dict) or set(headers) - {"Authorization", "X-Survival-Wire"}:
                return
            if any(not isinstance(v, str) or len(v) > 512 or "\r" in v or "\n" in v for v in headers.values()):
                return
            size = integer(event.get("bytes"), 0, MAX_REQUEST)
            chunks = integer(event.get("chunks"), 0, 256)
            timeout = integer(event.get("timeout_ms"), 100, 30000) / 1000
            if chunks != math.ceil(size / OUT_CHUNK):
                return
            job = Job(epoch, request_id, method, path, headers, size, chunks, self.clock() + timeout)
            self.jobs[request_id] = job
            self.expiries.put(job.deadline, request_id)
            if not chunks:
                self.submit(job)
        elif kind == "body":
            job = self.jobs.get(request_id)
            if not job or job.submitted:
                return
            index = integer(event.get("index"), 1, job.chunks)
            data = event.get("data")
            if index in job.parts or not isinstance(data, str) or len(data) > 1368:
                return
            raw = base64.b64decode(data, validate=True)
            expected = min(OUT_CHUNK, job.size - (index - 1) * OUT_CHUNK)
            if len(raw) != expected:
                return
            job.parts[index] = raw
            job.received += len(raw)
            if len(job.parts) == job.chunks and job.received == job.size:
                self.submit(job)

    def submit(self, job):
        job.submitted = True  # Never replay an ambiguous request.
        if self.running >= MAX_PENDING:
            failed = Future()
            failed.set_exception(ValueError("transport_capacity"))
            self.done.put((job, failed, False))
            return
        self.http_count += 1
        self.running += 1
        future = self.pool.submit(self.transport.send, job)
        future.add_done_callback(lambda completed: self.done.put((job, completed, True)))

    def tick(self):
        now = self.clock()
        for request_id in self.expiries.expired(now):
            self.jobs.pop(request_id, None)
        if self.active and self.active[1].id not in self.jobs:
            self.files.retire(self.active[3]); self.active = None
        while not self.done.empty():
            job, future, submitted = self.done.get()
            if submitted:
                self.running -= 1
            if self.jobs.get(job.id) is not job or job.epoch != self.epoch:
                continue
            try:
                status, raw = future.result()
            except Exception:
                status, raw = 0, b""  # Never print exceptions containing credentials.
            self.waiting.append((job, status, raw))
        while not self.active and self.waiting:
            job, status, raw = self.waiting.popleft()
            if self.jobs.get(job.id) is not job or job.deadline <= now:
                continue
            self.serial += 1
            paths = self.files.publish(job, self.serial, status, raw)
            self.active = (self.serial, job, status, paths)
            print(f"[SFB_HELPER] response id={job.id} status={status} bytes={len(raw)}", flush=True)

    def close(self):
        self.pool.shutdown(wait=True, cancel_futures=True)
        self.files.close()


class Process:
    def __init__(self, pid, expected_filetime, expected_exe):
        kernel = ctypes.WinDLL("kernel32", use_last_error=True)
        kernel.OpenProcess.argtypes = [wintypes.DWORD, wintypes.BOOL, wintypes.DWORD]
        kernel.OpenProcess.restype = wintypes.HANDLE
        kernel.GetProcessTimes.argtypes = [wintypes.HANDLE] + [ctypes.POINTER(wintypes.FILETIME)] * 4
        kernel.QueryFullProcessImageNameW.argtypes = [wintypes.HANDLE, wintypes.DWORD, wintypes.LPWSTR, ctypes.POINTER(wintypes.DWORD)]
        kernel.WaitForSingleObject.argtypes = [wintypes.HANDLE, wintypes.DWORD]
        kernel.CloseHandle.argtypes = [wintypes.HANDLE]
        self.kernel = kernel
        self.handle = kernel.OpenProcess(0x100000 | 0x1000, False, pid)
        if not self.handle:
            raise ValueError("process_unavailable")
        created, exited, user, system = (wintypes.FILETIME() for _ in range(4))
        if not kernel.GetProcessTimes(self.handle, ctypes.byref(created), ctypes.byref(exited), ctypes.byref(user), ctypes.byref(system)):
            raise ValueError("process_identity_unavailable")
        actual = (created.dwHighDateTime << 32) | created.dwLowDateTime
        name, size = ctypes.create_unicode_buffer(32768), wintypes.DWORD(32768)
        if (actual != expected_filetime or not kernel.QueryFullProcessImageNameW(self.handle, 0, name, ctypes.byref(size))
                or Path(name.value).resolve() != Path(expected_exe).resolve()):
            raise ValueError("process_identity_mismatch")

    def alive(self):
        return self.kernel.WaitForSingleObject(self.handle, 0) == 258

    def close(self):
        self.kernel.CloseHandle(self.handle)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--game-root", type=Path, required=True, help="Dota installation's game directory")
    parser.add_argument("--pid", type=int, required=True)
    parser.add_argument("--filetime", type=int, required=True)
    parser.add_argument("--state-dir", type=Path, required=True, help="New private run directory outside the game installation")
    parser.add_argument("--apply", action="store_true")
    args = parser.parse_args()
    root = args.game_root.resolve(strict=True)
    state_dir = args.state_dir.resolve()
    if state_dir == root or root in state_dir.parents:
        raise ValueError("state_directory_must_be_external")
    exe, cfg, log = root / "bin/win64/dota2.exe", root / "dota/cfg", root / "dota/console.log"
    if not args.apply:
        print("CHECK_ONLY: fixed HTTPS endpoint; no files, HTTP or game changes")
        return
    if os.name != "nt":
        raise ValueError("windows_required")
    process = Process(args.pid, args.filetime, exe)
    engine = None
    files = None
    log_acl = None
    log_identity = None
    try:
        if not process.alive():
            raise ValueError("process_exited")
        # Start in the main menu before entering the game. Read only appended
        # data, never reconsume old account/session requests from an existing log.
        with log.open("rb") as stream:
            state_dir.mkdir(exist_ok=False)
            private_acl(state_dir)
            log_acl = saved_acl(log)
            log_identity = (log.stat().st_dev, log.stat().st_ino)
            (state_dir / "console_acl.before.bin").write_bytes(log_acl[0].raw)
            (state_dir / "console_acl.before.json").write_bytes(compact({"path": str(log), "device": log_identity[0],
                "inode": log_identity[1], "protection": log_acl[1], "note": "Log remains private after helper exit; may contain private game payloads."}))
            private_acl(state_dir / "console_acl.before.bin")
            private_acl(state_dir / "console_acl.before.json")
            private_acl(log)
            stream.seek(0, 2)
            files = Files(cfg, secrets.token_hex(16))
            engine = Engine(files.nonce, files)
            partial = b""
            print("[SFB_HELPER] ready; enter the original Workshop game", flush=True)
            while process.alive():
                if log.stat().st_size < stream.tell():
                    # Dota can truncate condebug on map startup. This helper's
                    # fresh nonce plus monotonic per-world IDs reject replays.
                    stream.seek(0)
                    partial = b""
                data = stream.read(65536)
                partial += data
                lines = partial.split(b"\n")
                partial = lines.pop()
                if len(partial) > 16384:
                    partial = b""  # Unrelated huge console line, never parse it.
                for line in lines:
                    marker = line.find(PREFIX.encode("ascii"))
                    if marker < 0 or len(line) - marker > 4096:
                        continue
                    try:
                        engine.event(json.loads(line[marker + len(PREFIX):]))
                    except (ValueError, TypeError, KeyError, OverflowError):
                        pass
                engine.tick()
                if not data:
                    time.sleep(0.05)
    finally:
        if engine:
            engine.close()
        elif files:
            files.close()
        # Retain the protected DACL on this log. Restoring public inherited read
        # access would expose private game payloads that may have been recorded.
        # The previous descriptor is saved in the explicitly selected private run.
        process.close()
    print("[SFB_HELPER] stopped; owned files cleaned", flush=True)


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("[SFB_HELPER] interrupted", flush=True)
    except Exception as error:
        # Avoid echoing raw bodies, URL query strings, headers or Windows paths.
        code = str(error) if isinstance(error, ValueError) and re.fullmatch(r"[a-z_]{3,64}", str(error)) else "unclassified"
        print(f"[SFB_HELPER] stopped safely type={type(error).__name__} code={code}", flush=True)
        raise SystemExit(1)
