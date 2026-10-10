"""Bounded, credential-free JSON-lines transport to our private Node worker."""
from __future__ import annotations

import json
from pathlib import Path
import queue
import shutil
import subprocess
import threading

ROOT = Path(__file__).resolve().parents[1]
HIDDEN = getattr(subprocess, "CREATE_NO_WINDOW", 0)


class TransportError(Exception):
    """Fixed public error code; never include child output or console history."""


class ResidentInspector:
    def __init__(self):
        self.process = None
        self.responses = None
        self.reader = None
        self.writer = None
        self.serial = 0
        self.generation = 0
        self.stats = {"console_transport": "persistent_v1", "console_connected": False,
                      "console_connections_total": 0, "console_worker_generation": 0,
                      "console_last_connect_at": 0}

    @staticmethod
    def _read(stream, responses):
        try:
            while True:
                line = stream.readline(8193)
                if not line or len(line) > 8192 or not line.endswith(b"\n"):
                    break
                value = json.loads(line)
                responses.put_nowait(value)
        except (OSError, ValueError, queue.Full):
            pass
        finally:
            try:
                responses.put_nowait(None)
            except queue.Full:
                pass

    def _start(self):
        if self.process is not None and self.process.poll() is None:
            return
        self._dispose()
        node = shutil.which("node.exe") or shutil.which("node")
        if not node:
            raise TransportError("node_unavailable")
        self.process = subprocess.Popen([node, str(ROOT / "tools/map_c6/hammer-console-worker.cjs")],
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
            creationflags=HIDDEN)
        self.responses = queue.Queue(maxsize=4)
        self.reader = threading.Thread(target=self._read,
            args=(self.process.stdout, self.responses), daemon=True)
        self.reader.start()
        self.generation += 1
        self.stats.update(console_worker_generation=self.generation, console_connected=False)

    @staticmethod
    def _write(stream, data, responses):
        try:
            stream.write(data)
            stream.flush()
        except (OSError, ValueError):
            try:
                responses.put_nowait(None)
            except queue.Full:
                pass

    def _rpc(self, operation, *, code=None, timeout=15):
        self._start()
        self.serial += 1
        value = {"id": self.serial, "op": operation}
        if code is not None:
            value["code"] = code
        data = (json.dumps(value, ensure_ascii=True) + "\n").encode("utf-8")
        if len(data) > 65536:
            raise TransportError("inspection_request_too_large")
        try:
            # A hung child may stop reading its pipe. Include writing in the
            # same deadline instead of blocking the bridge/official stop lock.
            self.writer = threading.Thread(target=self._write,
                args=(self.process.stdin, data, self.responses), daemon=True)
            self.writer.start()
            response = self.responses.get(timeout=timeout)
            if not isinstance(response, dict) or type(response.get("id")) is not int \
                    or response.get("id") != self.serial \
                    or response.get("ok") is not True:
                raise TransportError("inspection_worker_protocol_failed")
            stats = response.get("stats", {})
            if not isinstance(stats, dict):
                raise TransportError("inspection_worker_protocol_failed")
            # Do not publish arbitrary fields even if the child malfunctions.
            for key in ("console_connections_total", "console_last_connect_at"):
                number = stats.get(key)
                if type(number) not in (int, float) or not 0 <= number <= 1e15:
                    raise TransportError("inspection_worker_protocol_failed")
                self.stats[key] = number
            if type(stats.get("console_connected")) is not bool:
                raise TransportError("inspection_worker_protocol_failed")
            self.stats["console_connected"] = stats["console_connected"]
            return response
        except (OSError, ValueError, queue.Empty, TransportError):
            self._dispose()
            raise TransportError("inspection_worker_unavailable") from None

    def inspect(self, code):
        response = self._rpc("inspect", code=code)
        state = response.get("state")
        if not isinstance(state, dict):
            raise TransportError("inspection_worker_protocol_failed")
        status = state.get("status")
        if status in {"waiting_for_map", "waiting_for_workshop"}:
            return {"status": status}
        session = state.get("session")
        if status not in {"configured", "authentication_required", "waiting_for_party"} \
                or not isinstance(session, str) or len(session) != 64 \
                or any(c not in "0123456789abcdef" for c in session):
            raise TransportError("inspection_worker_protocol_failed")
        counts = {key: state.get(key) for key in ("players", "authenticated", "loaded")}
        if any(type(n) is not int or not 0 <= n <= 64 for n in counts.values()):
            raise TransportError("inspection_worker_protocol_failed")
        return {"status": status, "session": session, **counts}

    def disconnect(self):
        if self.process is not None and self.process.poll() is None:
            self._rpc("disconnect", timeout=3)

    def _dispose(self):
        process, self.process = self.process, None
        self.stats["console_connected"] = False
        if process is None:
            return
        # This is only our credential-free Node child, never Dota or the auth
        # process. Stop's instance lock remains held until this cleanup ends.
        if process.poll() is None:
            process.terminate()
            try:
                process.wait(timeout=2)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait(timeout=2)
        for stream in (process.stdin, process.stdout):
            if stream:
                try:
                    stream.close()
                except OSError:
                    pass
        if self.reader:
            self.reader.join(timeout=1)
        if self.writer:
            self.writer.join(timeout=1)
        self.reader = self.writer = self.responses = None

    def close(self):
        try:
            if self.process is not None and self.process.poll() is None:
                self._rpc("shutdown", timeout=3)
                self.process.wait(timeout=2)
        except (TransportError, OSError, subprocess.SubprocessError):
            pass
        finally:
            self._dispose()
