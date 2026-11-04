"""Fresh settlement VMs with immutable, lazy native configuration chunks.

Cold cost is O(all configuration bytes), once per immutable bundle/Lua identity.
Warm requests encode O(profile + command) and load only tables actually required
by the unchanged worker. They never serialize/decode all configuration tables.
Four retained caches and the service's existing four-worker semaphore bound IO
and memory. Every command still has its own VM, seed, clock and original sandbox.
"""
from __future__ import annotations

import atexit
from collections import OrderedDict
from contextlib import contextmanager
import hashlib
import json
import logging
import math
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import threading
import time

RUNNER = Path(__file__).with_name("worker_fast.lua")
MAX_TABLES = 512
MAX_CONFIG_BYTES = 16 * 1024 * 1024
MAX_CACHES = 4
_TEMP_ROOT = Path(tempfile.gettempdir()).resolve()
_LOCK = threading.RLock()
_CACHES = OrderedDict()
_BUILDING = {}
_STATS = dict(builds=0, hits=0, job_failures=0)
_ESCAPE = re.compile(rb'[\x00-\x1f\\"]')


def _string(value):
    raw = value.encode("utf-8")
    def escaped(match):
        char = match[0]
        if char == b"\\": return b"\\\\"
        if char == b'"': return b'\\"'
        return ("\\%03d" % char[0]).encode("ascii")
    return b'"' + _ESCAPE.sub(escaped, raw) + b'"'


def _literal(value, depth=0):
    if depth > 64: raise ValueError("settlement_config_depth_invalid")
    if value is None: return b"json_null"
    if value is True: return b"true"
    if value is False: return b"false"
    if isinstance(value, str): return _string(value)
    if isinstance(value, (int, float)):
        if isinstance(value, float) and not math.isfinite(value):
            raise ValueError("settlement_config_nonfinite")
        return json.dumps(value, allow_nan=False).encode("ascii")
    if isinstance(value, list):
        return b"{" + b",".join(_literal(item, depth + 1) for item in value) + b"}"
    if isinstance(value, dict) and all(isinstance(key, str) for key in value):
        return b"{" + b",".join(b"[" + _string(key) + b"]=" + _literal(value[key], depth + 1)
                                 for key in sorted(value)) + b"}"
    raise ValueError("settlement_config_value_invalid")


def _dispose(entry):
    """Delete only this module's explicitly owned, resolved private temp tree."""
    path = entry.directory
    if entry.closed: return
    entry.closed = True
    try:
        info = path.lstat()
        safe = (path.is_absolute() and path.parent == _TEMP_ROOT
            and path.name.startswith("goufayu_config_v1_") and not path.is_symlink()
            and not (getattr(info, "st_file_attributes", 0) & 0x400)
            and path.resolve(strict=True) == path
            and path.parent.resolve(strict=True) == _TEMP_ROOT)
    except FileNotFoundError:
        return
    if not safe:
        logging.getLogger(__name__).warning("settlement_cache_cleanup_path_rejected")
        return
    try: shutil.rmtree(path)
    except OSError: logging.getLogger(__name__).warning("settlement_cache_cleanup_deferred")


class _Entry:
    def __init__(self, bundle, lua):
        self.executable = lua
        self.directory = Path(tempfile.mkdtemp(prefix="goufayu_config_v1_", dir=_TEMP_ROOT)).resolve()
        self.closed, self.retired, self.users = False, False, 0
        try:
            configs = bundle.configs
            if not isinstance(configs, dict) or not 1 <= len(configs) <= MAX_TABLES:
                raise ValueError("settlement_config_table_count_invalid")
            index, total = {}, 0
            for name, config in configs.items():
                if not isinstance(name, str) or re.fullmatch(r"[a-z][a-z0-9_]{0,95}", name) is None:
                    raise ValueError("settlement_config_table_name_invalid")
                token = hashlib.sha256(name.encode("ascii")).hexdigest()
                raw = b'local json_null=require("core/json_decoder").null\nreturn ' + _literal(config) + b"\n"
                total += len(raw)
                if total > MAX_CONFIG_BYTES: raise ValueError("settlement_config_byte_budget")
                (self.directory / (token + ".source.lua")).write_bytes(raw)
                index[name] = token
            (self.directory / "index.lua").write_bytes(b"return " + _literal(index) + b"\n")
            script = (b"local base=" + _string(self.directory.as_posix()) + b"\n" + b'''
local load,open=loadfile,io.open
local index=assert(load(base.."/index.lua"))()
local count=0
for _,token in pairs(index) do
 local chunk=assert(load(base.."/"..token..".source.lua"))
 local output=assert(open(base.."/"..token..".luac","wb"))
 assert(output:write(string.dump(chunk)));assert(output:close());count=count+1
end
local output=assert(open(base.."/index.luac","wb"))
assert(output:write(string.dump(assert(load(base.."/index.lua")))));assert(output:close())
io.write(count)
''')
            result = subprocess.run([lua, "-"], cwd=bundle.directory, input=script,
                stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10, check=True,
                creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
            if result.stdout != str(len(index)).encode("ascii"):
                raise ValueError("settlement_config_compile_count_invalid")
            self.index = self.directory / "index.luac"
            self.source_bytes, self.tables = total, len(index)
            # Sources contain public static config only; retaining them would
            # double disk usage without being required by any future request.
            for token in index.values(): (self.directory / (token + ".source.lua")).unlink()
            (self.directory / "index.lua").unlink()
        except BaseException:
            _dispose(self)
            raise


def _key(bundle, lua):
    if re.fullmatch(r"[a-f0-9]{64}", str(bundle.hash)) is None:
        raise ValueError("settlement_immutable_bundle_hash_required")
    executable = Path(shutil.which(lua) or lua).resolve(strict=True)
    info = executable.stat()
    return (bundle.hash, str(executable), info.st_size, info.st_mtime_ns)


class _Flight:
    def __init__(self):
        self.done, self.failed = threading.Event(), False


def _acquire(bundle, lua):
    """Only same-key cold callers wait; other warm keys never wait for builds."""
    key = _key(bundle, lua)
    deadline = time.monotonic() + 2
    while True:
        with _LOCK:
            entry = _CACHES.get(key)
            if entry is not None:
                _CACHES.move_to_end(key); _STATS["hits"] += 1
                entry.users += 1
                return key, entry
            flight = _BUILDING.get(key)
            owner = flight is None
            if owner:
                if len(_BUILDING) >= 4: raise TimeoutError("archive_workers_busy")
                flight = _Flight(); _BUILDING[key] = flight
        if owner:
            try:
                # Encoding, compiler startup and IO must not hold the manager
                # mutex: a cold historical bundle cannot block a warm account.
                entry = _Entry(bundle, str(key[1]))
            except BaseException:
                with _LOCK:
                    flight.failed = True
                    _BUILDING.pop(key, None); flight.done.set()
                raise
            retired = []
            with _LOCK:
                _CACHES[key] = entry; entry.users += 1
                _STATS["builds"] += 1
                while len(_CACHES) > MAX_CACHES:
                    _, previous = _CACHES.popitem(last=False)
                    previous.retired = True
                    if previous.users == 0: retired.append(previous)
                _BUILDING.pop(key, None); flight.done.set()
            for previous in retired: _dispose(previous)
            return key, entry
        remaining = deadline - time.monotonic()
        if remaining <= 0 or not flight.done.wait(remaining): raise TimeoutError("archive_workers_busy")
        if flight.failed: raise RuntimeError("settlement_config_compile_failed")


@contextmanager
def _cache(bundle, lua):
    key, entry = _acquire(bundle, lua)
    try:
        yield entry
    except (subprocess.CalledProcessError, subprocess.TimeoutExpired):
        # A later explicitly retried receipt may rebuild a broken cache. Never
        # run this command twice or hide an ambiguous worker/timeout outcome.
        with _LOCK:
            _STATS["job_failures"] += 1
            if _CACHES.get(key) is entry: _CACHES.pop(key)
            entry.retired = True
        raise
    finally:
        with _LOCK:
            entry.users -= 1
            dispose = entry.retired and entry.users == 0
        if dispose: _dispose(entry)


def run(bundle, lua, payload):
    if "configs" in payload: raise ValueError("settlement_request_cannot_override_configs")
    raw = json.dumps(payload, ensure_ascii=False, allow_nan=False, separators=(",", ":")).encode("utf-8")
    with _cache(bundle, lua) as cache:
        return subprocess.run([cache.executable, str(RUNNER), str(cache.index)], cwd=bundle.directory,
            input=raw, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10, check=True,
            creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))


def cache_info():
    with _LOCK:
        return {**_STATS, "retained": len(_CACHES),
                "retained_source_bytes": sum(entry.source_bytes for entry in _CACHES.values())}


def clear_cache():
    retired = []
    with _LOCK:
        values = list(_CACHES.values()); _CACHES.clear()
        for entry in values:
            entry.retired = True
            if entry.users == 0: retired.append(entry)
    for entry in retired: _dispose(entry)


atexit.register(clear_cache)
