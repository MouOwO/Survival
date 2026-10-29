"""Bind the free public-beta login tier to a real account/match session.

Inventory, day selection, revision conflicts and durable receipts deliberately
reuse benefit_claim and archive_commit_lottery. No new reward RPC is opened.
"""
from __future__ import annotations

import hashlib
import re
import time
import math

TIER = "public_beta_login"
TRACK = "public_beta_login"
MARKER = ":public_beta_gift:"
SESSION = re.compile(r"[A-Za-z0-9_.:-]{8,128}\Z")
TOKEN = re.compile(r"[0-9a-f]{24}\Z")
MODES = {"pure", "standard", "rich", "cold", "scourge", "ruins", "celestial"}


def applies(command):
    return command.get("kind") == "benefit_claim" and command.get("tier_id") == TIER


def current_activity_error(service, command):
    """Today's authority stops unfinished/new work from compatible old hashes.

    Call only after the durable done-receipt fast path. This is deliberately
    independent of which historical bundle supplies the reward reducer.
    """
    if not applies(command):
        return None
    row = service.bundle.tables.get("archive_benefit_rewards", {}).get(TIER)
    if not row or row.get("enabled") is not True or row.get("track") != TRACK:
        return "public_beta_activity_inactive"
    now = time.time()
    starts, finishes = row.get("starts_at", 0), row.get("ends_at", 0)
    for value in (starts, finishes):
        if type(value) not in (int, float) or not math.isfinite(value) or value < 0:
            return "public_beta_activity_inactive"
    if starts and now < starts or finishes and now >= finishes:
        return "public_beta_activity_inactive"
    return None


def _validate_context(service, account, session):
    from .service import ArchiveError
    if not isinstance(session, str) or not SESSION.fullmatch(session):
        raise ArchiveError("match_session_missing")
    context = service.app.rpc_client.rpc("match_profile_context", {
        "p_account": account, "p_session": session})
    if (not isinstance(context, dict) or context.get("ok") is not True
            or context.get("account_id") != account
            or context.get("match_session_id") != session
            or context.get("mode") not in MODES):
        raise ArchiveError("match_session_invalid")


def scope(service, payload, command):
    if not applies(command):
        return command
    from .service import ArchiveError
    if command.get("track") != TRACK:
        raise ArchiveError("archive_benefit_invalid")
    session = payload.get("match_session_id")
    account = service.app._database_account_id(payload["account_id"])
    _validate_context(service, account, session)
    # The suffix correlates a game-server intent; it never chooses a date or
    # reward. The reducer uses the immutable DB event_at and account day bucket.
    nonce = hashlib.sha256(command["id"].encode("utf-8")).hexdigest()[:24]
    return dict(command, id=session + MARKER + nonce)


def validate_pending(service, account, command):
    if not applies(command):
        return
    from .service import ArchiveError
    identifier = command.get("id", "")
    session, separator, nonce = identifier.rpartition(MARKER)
    if not separator or not TOKEN.fullmatch(nonce):
        raise ArchiveError("match_session_invalid")
    _validate_context(service, account, session)
