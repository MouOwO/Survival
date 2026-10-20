"""Read existing clear receipts after durable account/session mode scoping.

Protocol upgrades may change the request kind or add a trusted mode field. They
must resume the already accepted operation, not re-prepare it with a new hash or
fingerprint. This module never writes or reclassifies historical receipts.
"""
from __future__ import annotations

from dataclasses import dataclass
import re

from .match_modes import CLEAR_MODES, MODE_IDS


@dataclass(frozen=True)
class ClearReceipt:
    operation_id: str
    prepared: dict
    mode_id: str


def _error(code="archive_id_conflict"):
    from .service import ArchiveError
    raise ArchiveError(code)


def bound_command(command, mode_id):
    """Give a worker copy trusted scope while leaving the durable row intact."""
    kind = command.get("kind")
    if mode_id not in MODE_IDS or kind not in ("clear", "mode_clear", *CLEAR_MODES):
        _error()
    expected = CLEAR_MODES.get(kind)
    if expected is not None and expected != mode_id:
        _error()
    if kind == "clear" and mode_id not in ("pure", "standard"):
        _error()
    recorded_mode = command.get("mode_id")
    if recorded_mode is not None and recorded_mode != mode_id:
        _error()
    if kind == "mode_clear" and recorded_mode is None:
        _error()
    return dict(command, mode_id=mode_id)


def resolve_pending_mode(service, database_account, command):
    """Resolve a pre-upgrade pending clear when the profile outbox drains it.

    Production enables this through the installed match-mode service. Only an
    explicitly absent legacy session keeps the pre-mode compatibility path;
    outages or an inconsistent durable identity must never grant a reward.
    """
    kind = command.get("kind")
    if kind not in ("clear", "mode_clear", *CLEAR_MODES):
        return None
    suffix_kind = kind
    if kind == "mode_clear":
        mode = command.get("mode_id")
        if mode not in MODE_IDS:
            _error("match_session_invalid")
        suffix_kind = "clear" if mode == "pure" else mode + "_clear"
    operation_id, suffix = command.get("id"), ":" + suffix_kind
    if not isinstance(operation_id, str) or not operation_id.endswith(suffix):
        _error("match_session_invalid")
    session = operation_id[:-len(suffix)]
    if not re.fullmatch(r"[A-Za-z0-9_.:-]{8,128}", session):
        if kind == "clear" and command.get("mode_id") is None:
            return None  # Pre-mode clear IDs were not required to be sessions.
        _error("match_session_invalid")
    context = service.app.rpc_client.rpc("match_profile_context", {
        "p_account": database_account, "p_session": session})
    if isinstance(context, dict) and context.get("ok") is False and context.get("error") == "match_session_missing":
        if kind == "clear" and command.get("mode_id") is None:
            return None
        _error("match_session_missing")
    if not isinstance(context, dict) or context.get("ok") is not True:
        _error("match_session_unavailable")
    if (context.get("account_id") != database_account or context.get("match_session_id") != session
            or context.get("mode") not in MODE_IDS):
        _error("match_session_invalid")
    mode = context["mode"]
    bound_command(command, mode)
    return mode


def lookup(service, payload, command):
    """Only call after scope_clear validated the authenticated durable session.

    Missing legacy scope keeps the previous compatibility path. A standard
    session alone may reuse its legacy ``session:clear`` receipt: a durable mode
    cannot be rebound from pure to standard. Unknown RPC failures fail closed.
    """
    if command.get("kind") not in ("clear", "mode_clear", *CLEAR_MODES):
        return None
    mode, session = command.get("mode_id"), payload.get("match_session_id")
    if mode is None:
        return None
    if mode not in MODE_IDS or not isinstance(session, str) or not re.fullmatch(r"[A-Za-z0-9_.:-]{8,128}", session):
        _error("match_session_invalid")
    canonical = session + (":clear" if mode == "pure" else ":" + mode + "_clear")
    if command.get("id") != canonical:
        _error("match_session_invalid")
    # Also enforce the caller's already scoped typed command. This is an
    # internal API; accepting an inconsistent scope must not select a receipt.
    bound_command(command, mode)
    account = service.app._database_account_id(payload["account_id"])
    candidates = [canonical]
    if mode == "standard":
        candidates.append(session + ":clear")
    for operation_id in candidates:
        prepared = service.app.rpc_client.rpc("archive_resume", {"p_account": account, "p_id": operation_id})
        if not isinstance(prepared, dict):
            _error("archive_receipt_unavailable")
        if prepared.get("error") == "archive_operation_missing":
            continue
        stored = prepared.get("command")
        if not isinstance(stored, dict):
            _error("archive_receipt_unavailable")
        if stored.get("id") != operation_id:
            _error()
        # Strict business fields keep normal operation-ID conflict protection.
        # Server-injected date/hash/fingerprint and the old wire kind are kept
        # exactly as originally recorded when the existing operation resumes.
        if (stored.get("difficulty_id") != command.get("difficulty_id")
                or type(stored.get("count")) is not int or stored["count"] != command.get("count")
                or stored.get("cooperative_win", 0) != command.get("cooperative_win", 0)):
            _error()
        bound_command(stored, mode)
        if operation_id != canonical and stored.get("kind") != "clear":
            _error()
        return ClearReceipt(operation_id=operation_id, prepared=prepared, mode_id=mode)
    return None
