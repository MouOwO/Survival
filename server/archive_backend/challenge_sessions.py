"""Check challenge tiers against immutable config and durable session identity.

Old mode-less N1..N20 requests keep their existing receipt contract. New high
tiers require an authenticated session; callers cannot select a gameplay mode.
New high-tier/solo-tower receipts use the authenticated match session, which is
different from the game's archive queue runtime ID. Existing receipts keep
their original ID, fingerprint and recorded admission contract.
"""
from __future__ import annotations

import re


def _difficulty(command):
    value = command.get("difficulty") if command.get("kind") == "endless" else command.get("difficulty_id")
    if isinstance(value, str):
        value = value.lower().removeprefix("n")
    return int(value)


def bound_receipt(command):
    return command.get("kind") in {"challenge", "endless"} and (
        _difficulty(command) > 20 or command.get("variant") == "tower")


def _suffix(command):
    if command["kind"] == "endless":
        return ":" + command.get("variant", "endless") + ":" + str(command["wave"])
    return ":challenge_kind:" + command["challenge_id"]


def scope(service, payload, command):
    """Scope only new high-tier/tower prepares; never rewrite accepted rows."""
    validate(service, payload, command)
    if bound_receipt(command):
        return dict(command, id=payload["match_session_id"] + _suffix(command))
    return command


def legacy_receipt(service, account, original, scoped):
    """Resume an accepted pre-contract ID before creating its new scoped ID."""
    if not bound_receipt(original) or original["id"] == scoped["id"]:
        return
    from .bundle import Bundle
    from .service import ArchiveError
    prepared = service.app.rpc_client.rpc("archive_resume", {
        "p_account": account, "p_id": original["id"]})
    if not isinstance(prepared, dict):
        raise ArchiveError("archive_receipt_unavailable")
    if prepared.get("error") == "archive_operation_missing":
        return
    stored, version = prepared.get("command"), prepared.get("config_hash")
    if not isinstance(stored, dict) or not isinstance(version, str) or not re.fullmatch(r"[0-9a-f]{64}", version):
        raise ArchiveError("archive_receipt_unavailable")
    business = {key: value for key, value in stored.items() if key not in {"today", "day_key", "event_at"}}
    if business != original:
        raise ArchiveError("archive_id_conflict")
    recorded = service.bundle if version == service.bundle.hash else Bundle(service.bundle.directory.parent / version)
    if "archive_challenge_modes" in recorded.tables:
        raise ArchiveError("match_session_invalid")
    return prepared


def validate(service, payload, command, *, database_account=None, pending=False, _context=None):
    if command.get("kind") not in {"challenge", "endless"}:
        return
    from .service import ArchiveError
    number = _difficulty(command)
    tower = command.get("kind") == "endless" and command.get("variant") == "tower"
    session = payload.get("match_session_id")
    if pending:
        # Already accepted low-tier receipts preserve their original protocol.
        if number <= 20 and not tower:
            return
        suffix = _suffix(command)
        identifier = command.get("id", "")
        session = identifier[:-len(suffix)] if identifier.endswith(suffix) else None
    if session is None and number <= 20 and not tower:
        return
    if not isinstance(session, str) or not re.fullmatch(r"[A-Za-z0-9_.:-]{8,128}", session):
        raise ArchiveError("match_session_missing")
    modes = service.bundle.tables.get("archive_challenge_modes")
    if not modes:
        if number <= 20 and not tower:
            return  # Previously frozen bundles do not invent a new tier policy.
        raise ArchiveError("archive_challenge_mode_config_missing")
    account = database_account or service.app._database_account_id(payload["account_id"])
    context = _context if _context is not None else service.app.rpc_client.rpc(
        "match_profile_context", {"p_account": account, "p_session": session})
    if not isinstance(context, dict) or context.get("ok") is not True:
        raise ArchiveError("match_session_invalid")
    if context.get("account_id") != account or context.get("match_session_id") != session:
        raise ArchiveError("match_session_invalid")
    rule = modes.get(context.get("mode"), {})
    if number not in rule.get("difficulties", []):
        raise ArchiveError("archive_mode_difficulty_unavailable")
    if tower and (context.get("mode") not in {"cold", "scourge"} or number < 10):
        raise ArchiveError("endless_variant_unavailable")
    return context


def validate_batch(service, payload, commands):
    """Reject an incompatible later wave before an earlier wave can commit."""
    context = None
    for command in sorted(commands, key=lambda item: (
            item.get("variant") == "tower", _difficulty(item)), reverse=True):
        checked = validate(service, payload, command, _context=context)
        if checked is not None:
            context = checked
