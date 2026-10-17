"""Authenticated, read-only endless ranking over the permanent account archive.

Steam identities are bound by the trusted game server after loading a profile;
the ranking never accepts a client-provided score, name, avatar URL or rank.
"""
from __future__ import annotations

import hashlib
import json
import re
import threading
import uuid

STEAM_ID_BASE = 76561197960265728
MAX_ACCOUNT_ID = 4294967295
MAX_SAFE_INTEGER = 9007199254740991


def public_identity(account_id):
    if (not isinstance(account_id, str)
            or not re.fullmatch(r"[1-9][0-9]{0,9}", account_id)
            or int(account_id) > MAX_ACCOUNT_ID):
        raise ValueError("account_id_invalid")
    return account_id, str(STEAM_ID_BASE + int(account_id))


class EndlessLeaderboard:
    def __init__(self, application):
        self.app = application
        self._bound = set()
        self._lock = threading.RLock()

    def bind(self, account_id):
        public, _ = public_identity(account_id)
        # Avoid any repeated identity UPDATE or profile revision change. The
        # database binding is also immutable and an idempotent insert.
        with self._lock:
            if public in self._bound:
                return
            result = self.app.rpc_client.rpc("archive_bind_leaderboard_identity", {
                "p_account": self.app._database_account_id(public),
                "p_public_account_id": public,
            })
            if not isinstance(result, dict) or result.get("ok") is not True:
                raise ValueError("leaderboard_identity_unavailable")
            if len(self._bound) >= 4096:
                self._bound.clear()
            self._bound.add(public)

    def read(self, payload):
        if not isinstance(payload, dict):
            raise ValueError("leaderboard_request_invalid")
        if set(payload) - {"account_id", "revision", "match_session_id"}:
            raise ValueError("leaderboard_request_fields_invalid")
        account, steam_id = public_identity(payload.get("account_id"))
        known_revision = payload.get("revision", "")
        if (not isinstance(known_revision, str)
                or (known_revision and not re.fullmatch(r"[0-9a-f]{64}", known_revision))):
            raise ValueError("leaderboard_revision_invalid")
        self.bind(account)
        value = self.app.rpc_client.rpc("archive_endless_leaderboard", {})
        if not isinstance(value, dict) or value.get("ok") is not True:
            raise ValueError("leaderboard_unavailable")
        rows = value.get("entries")
        if not isinstance(rows, list) or len(rows) > 100:
            raise ValueError("leaderboard_response_invalid")
        entries, seen, steam_seen, previous = [], set(), set(), None
        for rank, row in enumerate(rows, 1):
            if not isinstance(row, dict):
                raise ValueError("leaderboard_response_invalid")
            identity = row.get("steam_id")
            entry_id = row.get("entry_id")
            floor, score = row.get("best_floor"), row.get("endless_score")
            vip_level, medal_level = row.get("vip_level", 0), row.get("vip_medal_level", 0)
            try:
                public_entry = str(uuid.UUID(entry_id))
            except (ValueError, TypeError, AttributeError):
                raise ValueError("leaderboard_response_invalid") from None
            valid_steam = (identity == "" or (isinstance(identity, str)
                and re.fullmatch(r"[0-9]{17}", identity)
                and STEAM_ID_BASE < int(identity) <= STEAM_ID_BASE + MAX_ACCOUNT_ID))
            if (not valid_steam or public_entry != entry_id or entry_id in seen
                    or (identity and identity in steam_seen)
                    or type(floor) is not int or type(score) is not int
                    or not 1 <= floor <= MAX_SAFE_INTEGER
                    or not 0 <= score <= MAX_SAFE_INTEGER
                    or type(vip_level) is not int or not 0 <= vip_level <= 12
                    or type(medal_level) is not int or not 0 <= medal_level <= 10):
                raise ValueError("leaderboard_response_invalid")
            order = (-floor, -score, entry_id)
            if previous is not None and order < previous:
                raise ValueError("leaderboard_order_invalid")
            previous = order
            seen.add(entry_id)
            if identity:
                steam_seen.add(identity)
            entries.append({"rank": rank, "entry_id": entry_id, "steam_id": identity,
                            "display_name": "" if identity else "资料待同步",
                            "best_floor": floor, "endless_score": score,
                            "vip_level": vip_level, "vip_medal_level": medal_level})
        own = next((row for row in entries if row["steam_id"] == steam_id), None)
        position = {"listed": own is not None}
        if own:
            position["rank"] = own["rank"]
        # No request time, save revision or unrelated account data participates:
        # reopening an unchanged list produces the same version and no row data.
        visible = {"entries": entries, "self": position, "self_steam_id": steam_id}
        revision = hashlib.sha256(json.dumps(visible, ensure_ascii=False,
            sort_keys=True, separators=(",", ":")).encode("utf-8")).hexdigest()
        response = {"ok": True, "revision": revision,
                    "unchanged": revision == known_revision, "limit": 100, "total": len(entries),
                    "self_steam_id": steam_id, "self": position}
        if not response["unchanged"]:
            response["entries"] = entries
        return response


def install(service):
    """One install hook; preserve the existing loader and settlement methods."""
    if getattr(service, "_endless_leaderboard", None) is not None:
        return service
    ranking = EndlessLeaderboard(service.app)
    original_profile = service.profile

    def profile(payload):
        value = original_profile(payload)
        account = payload.get("account_id")
        try:
            public_identity(account)
        except ValueError:
            # Older API integrations accept a wider numeric account format.
            # Preserve their loader response; an unverified conversion must
            # never invent a Steam mapping or break an unrelated old profile.
            return value
        ranking.bind(account)
        return value

    service._endless_leaderboard = ranking
    service.profile = profile
    service.endless_leaderboard = ranking.read
    return service
