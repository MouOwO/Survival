"""Server-owned redeem definitions; public requests contain no reward data."""
from __future__ import annotations

import hashlib
import json
import re
import subprocess
from pathlib import Path

ACCOUNT = re.compile(r"[0-9]{1,20}\Z")
TOKEN = re.compile(r"[A-Za-z0-9_.-]{8,96}\Z")
SESSION = re.compile(r"[A-Za-z0-9_.:-]{8,128}\Z")


def normalize(code):
    if not isinstance(code, str) or not 6 <= len(code.strip()) <= 80 or not code.isascii():
        raise ValueError("redeem_code_invalid")
    value = code.strip().upper().replace("-", "")
    if not re.fullmatch(r"[A-Z0-9]{6,64}", value):
        raise ValueError("redeem_code_invalid")
    return value


def command(service, payload):
    if not isinstance(payload, dict) or set(payload) - {
            "account_id", "match_session_id", "config_hash", "command"}:
        raise ValueError("redeem_request_invalid")
    account, session, item = (payload.get(k) for k in
                              ("account_id", "match_session_id", "command"))
    if not isinstance(account, str) or not ACCOUNT.fullmatch(account):
        raise ValueError("account_id_invalid")
    if not isinstance(session, str) or not SESSION.fullmatch(session):
        raise ValueError("match_session_missing")
    if not isinstance(item, dict) or set(item) != {"id", "kind", "code", "request_id"}:
        raise ValueError("redeem_request_invalid")
    token = item.get("request_id")
    if (item.get("kind") != "redemption_redeem" or not isinstance(token, str)
            or not TOKEN.fullmatch(token) or item.get("id") != "redeem:" + token):
        raise ValueError("redeem_request_invalid")
    digest = hashlib.sha256(normalize(item.get("code")).encode("ascii")).hexdigest()
    database = service.app._database_account_id(account)
    service.app._ensure_gameplay_stats(database)
    prepared = service.app.rpc_client.rpc("redemption_prepare", {
        "p_account": database, "p_session": session, "p_code_hash": digest,
        "p_request": token, "p_hash": service.bundle.hash})
    result = service.finish_prepared(database, prepared.get("command", {}).get("id", ""), prepared)
    # A frozen definition and internal operation command must never reach clients.
    public = {k: result[k] for k in ("ok", "terminal", "done", "error", "response", "profile")
              if k in result}
    return service.app._public_response(public, database, account)


def settle(service, profile, command, has_pass):
    directory = Path(__file__).resolve().parent
    payload = {"configs": service.bundle.configs, "profile": profile,
               "command": command, "has_pass": has_pass}
    if not service.slots.acquire(timeout=2):
        raise TimeoutError("archive_workers_busy")
    try:
        result = subprocess.run([service.lua, str(directory / "redemption_worker.lua"),
                                 str(directory / "redemption_settlement.lua")],
                                cwd=service.bundle.directory,
                                input=json.dumps(payload, ensure_ascii=False, allow_nan=False).encode(),
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=15, check=True,
                                creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
    finally:
        service.slots.release()
    from .service import object_maps
    value = object_maps(json.loads(result.stdout))
    if not isinstance(value, dict) or value.get("ok") is not True:
        # Keep the accepted receipt pending on a deployment/configuration error.
        raise TimeoutError("redeem_rewards_pending")
    return value


def finish(service, account, operation, prepared):
    for _ in range(4):
        if not prepared.get("ok") or prepared.get("done"):
            return prepared
        profile, item = prepared["profile"], prepared["command"]
        recorded = service
        version = prepared.get("config_hash", service.bundle.hash)
        if version != service.bundle.hash:
            if not isinstance(version, str) or not re.fullmatch(r"[0-9a-f]{64}", version):
                raise ValueError("archive_config_invalid")
            from .service import ArchiveService
            from .bundle import Bundle
            recorded = ArchiveService(service.app, Bundle(service.bundle.directory.parent / version), service.lua)
        value = settle(recorded, profile, item, prepared.get("has_pass") is True)
        old = profile["save"]["gameplay_stats"]
        deltas = {k: v - old.get(k, 0) for k, v in value["gameplay_stats"].items()
                  if v != old.get(k, 0)}
        archive = value["archive"]
        archive.pop("processed", None)
        result = service.app.rpc_client.rpc("redemption_commit", {
            "p_account": account, "p_id": operation, "p_revision": profile["revision"],
            "p_archive": archive, "p_deltas": deltas,
            "p_inventory": value["content_inventory"], "p_response": value["response"]})
        if result.get("error") != "archive_revision_conflict":
            return result
        prepared = service.app.rpc_client.rpc("archive_resume", {"p_account": account, "p_id": operation})
    return {"ok": False, "terminal": False, "error": "archive_busy_retry"}
