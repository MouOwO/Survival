"""Explicitly pinned Valve-server credentials for the isolated Workshop test API.

Unregistered keys only produce an irreversible pairing fingerprint. They never
authorize a request, query a profile, or replace a pin. An operator must compare
the fingerprint shown in the owner's actual Workshop game before approving it.
"""
from __future__ import annotations

import hashlib
import hmac
import json
import os
from pathlib import Path
import re
import stat
import threading
import time

KEY = re.compile(r"[A-Za-z0-9_\-+/=]{24,256}\Z")
DIGEST = re.compile(r"[a-f0-9]{64}\Z")


def credential(header):
    if not isinstance(header, str) or not header.startswith("Bearer "):
        return None
    key = header[7:]
    if not KEY.fullmatch(key) or key.lower().startswith("invalid"):
        return None
    return key


class Policy:
    def __init__(self, pins: Path, pending: Path, *, clock=time.time):
        self.pins, self.pending, self.clock = pins, pending, clock
        self.lock = threading.Lock()
        self.last_recorded = {}

    def approved(self):
        try:
            metadata = self.pins.lstat()
            if not stat.S_ISREG(metadata.st_mode) or (os.name != "nt" and metadata.st_mode & 0o022):
                return []
            raw = self.pins.read_bytes()
            if len(raw) > 8192:
                return []
            document = json.loads(raw)
            rows = document["sha256"]
            if (document.get("workshop_id") != "3824360109" or not isinstance(rows, list)
                    or len(rows) > 4 or any(not isinstance(s, str) or not DIGEST.fullmatch(s) for s in rows)):
                return []
            return rows
        except (OSError, ValueError, KeyError, TypeError):
            return []

    def check(self, header):
        key = credential(header)
        if key is None:
            return False, None
        digest = hashlib.sha256(key.encode("ascii")).hexdigest()
        if any(hmac.compare_digest(digest, known) for known in self.approved()):
            return True, None
        now = int(self.clock())
        with self.lock:
            # Bound both pending state and writes under unauthenticated traffic.
            if now - self.last_recorded.get(digest, -3600) >= 60:
                rows = {}
                try:
                    if self.pending.is_symlink():
                        return False, None
                    if self.pending.exists() and self.pending.stat().st_size <= 16384:
                        rows = json.loads(self.pending.read_text())
                except (OSError, ValueError):
                    rows = {}
                if not isinstance(rows, dict):
                    rows = {}
                rows = {d: t for d, t in rows.items() if isinstance(d, str) and DIGEST.fullmatch(d)
                        and type(t) is int and now - 1800 <= t <= now}
                if digest in rows or len(rows) < 32:
                    rows[digest] = now
                    temporary = self.pending.with_name(self.pending.name + ".new")
                    if temporary.exists() or temporary.is_symlink():
                        return False, None
                    try:
                        fd = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
                        with os.fdopen(fd, "w") as stream:
                            json.dump(rows, stream, sort_keys=True)
                            stream.flush()
                            os.fsync(stream.fileno())
                        os.replace(temporary, self.pending)
                    except OSError:
                        return False, None
                    finally:
                        try:
                            temporary.unlink(missing_ok=True)
                        except OSError:
                            pass
                    self.last_recorded = dict(sorted(rows.items(), key=lambda item: item[1], reverse=True)[:32])
                    return False, digest[:16]
        # Repeated legitimate pairing requests should continue displaying the
        # same code even when the private pending file does not need rewriting.
        return False, digest[:16] if digest in self.last_recorded else None


def handler(base, policy):
    class WorkshopHandler(base):
        def _authorized(self):
            allowed, fingerprint = policy.check(self.headers.get("Authorization"))
            if allowed:
                return True
            response = {"ok": False, "error": "workshop_server_not_authorized"}
            if fingerprint:
                response.update(error="workshop_server_pairing_required", pairing_fingerprint=fingerprint)
            self._send(403, response)
            return False

    return WorkshopHandler
