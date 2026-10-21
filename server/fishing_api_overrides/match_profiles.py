"""Durable per-match views. Never submit a projected save to a write RPC.

Business settlement always sees the complete account. Pure matches see configured
defaults plus changes since their immutable login baseline, including after an
HTTP retry or Python restart. Account inventory/eligibility is a separate view.
"""
from __future__ import annotations

from copy import deepcopy
import math
import time
from typing import Any

from .application import ACCOUNT_ID, OPAQUE_ID, ApiError, _string


def _number(value: Any) -> bool:
    return type(value) in (int, float) and math.isfinite(value)


def _changes(current: Any, baseline: Any) -> Any:
    """Only newly accumulated counters/ownership, never a copy of old inventory."""
    if isinstance(current, dict):
        previous = baseline if isinstance(baseline, dict) else {}
        result = {}
        for key, value in current.items():
            changed = _changes(value, previous.get(key))
            if changed not in (None, {}, False, 0):
                result[key] = changed
        return result
    if _number(current):
        return max(0, current - (baseline if _number(baseline) else 0))
    if type(current) is bool:
        return current and baseline is not True
    # Strings/arrays are descriptive history, not accrued bonuses. Do not let
    # timestamps, saved operation IDs or a reordered list restore old content.
    return None


def progression(profile: dict[str, Any]) -> dict[str, Any]:
    raw = profile.get("save", {}).get("archive", {}).get("clear_counts", {})
    counts = {}
    if isinstance(raw, dict):
        for difficulty in range(1, 21):
            value = raw.get("n" + str(difficulty))
            if type(value) is int and value > 0:
                counts["n" + str(difficulty)] = value
    return {"loaded": True, "clear_counts": counts,
            "highest_difficulty": max((int(key[1:]) for key in counts), default=0)}


def _entitlement_active(state, at):
    expiry = state.get("expires_at")
    return (state.get("active") is True and
            (expiry is None or _number(expiry) and expiry > at))


def _new_boss_effects(application, current, baseline, captured_at, current_time):
    """Threshold rewards are derived, not stored in gameplay_stats columns."""
    archive = getattr(application, "archive", None)
    definitions = archive.bundle.tables.get("archive_boss_achievements", {}) if archive else {}
    old_kills = baseline.get("save", {}).get("archive", {}).get("boss_kills", 0)
    new_kills = current.get("save", {}).get("archive", {}).get("boss_kills", 0)
    old_pass = _entitlement_active(baseline.get("entitlements", {}).get("archive_pass", {}), captured_at)
    new_pass = _entitlement_active(current.get("entitlements", {}).get("archive_pass", {}), current_time)
    effects = {}
    for row in definitions.values():
        if row.get("enabled") is not True:
            continue
        was_active = old_kills >= row["pass_required_kills" if old_pass else "required_kills"]
        now_active = new_kills >= row["pass_required_kills" if new_pass else "required_kills"]
        if now_active and not was_active:
            for field, value in zip(row["effect_ids"], row["effect_values"]):
                effects[field] = effects.get(field, 0) + float(value)
    return effects


def context(application, payload):
    if "match_session_id" not in payload:
        return None  # Compatibility for the existing game until it is switched.
    account = _string(payload, "account_id", ACCOUNT_ID)
    session = _string(payload, "match_session_id", OPAQUE_ID)
    database_id = application._database_account_id(account)
    result = application.rpc_client.rpc("match_profile_context", {
        "p_account": database_id, "p_session": session})
    _validate_context(result, database_id, session)
    return result


def _validate_context(value, account, session):
    if not isinstance(value, dict) or value.get("ok") is not True:
        code = value.get("error") if isinstance(value, dict) else None
        raise ApiError(code if code in ("match_session_missing", "match_mode_locked")
                       else "match_session_unavailable", 409)
    if (value.get("account_id") != account or value.get("match_session_id") != session
            or value.get("mode") not in ("pure", "standard")
            or not isinstance(value.get("baseline"), dict)
            or not isinstance(value.get("defaults"), dict)
            or not _number(value.get("created_at"))):
        raise ApiError("match_session_invalid", 503)


def authenticate(application, payload):
    """Entry gate only: prove account/DB readiness without choosing a game mode.

    Read/drain the authoritative account internally, but return a strict metadata
    allowlist. In particular this must never call match_profile_login/context or
    take a baseline before the player chooses a mode inside the running game.
    """
    account = _string(payload, "account_id", ACCOUNT_ID)
    session = _string(payload, "match_session_id", OPAQUE_ID)
    if set(payload) - {"account_id", "match_session_id"}:
        raise ApiError("authenticate_fields_invalid", 400)
    archive = getattr(application, "archive", None)
    profile = archive.profile({"account_id": account}) if archive else application.profile({"account_id": account})
    if (not isinstance(profile, dict) or profile.get("account_id") != account
            or type(profile.get("revision")) is not int or profile["revision"] < 0
            or not isinstance(profile.get("save"), dict)):
        raise ApiError("authentication_profile_invalid", 503)
    return {"authenticated": True, "account_id": account,
            "match_session_id": session, "progression": progression(profile)}


def login(application, payload):
    account = _string(payload, "account_id", ACCOUNT_ID)
    session = _string(payload, "match_session_id", OPAQUE_ID)
    mode = payload.get("mode")
    if mode not in ("pure", "standard"):
        raise ApiError("match_mode_invalid", 400)
    # Drain previously accepted rewards before capturing the baseline. This is
    # internal only: the pure login response never contains the old save.
    archive = getattr(application, "archive", None)
    if archive:
        archive.profile({"account_id": account})
    else:
        application.profile({"account_id": account})
    database_id = application._database_account_id(account)
    result = application.rpc_client.rpc("match_profile_login", {
        "p_account": database_id, "p_session": session,
        "p_mode": mode, "p_defaults": application.gameplay_stats})
    _validate_context(result, database_id, session)
    raw = application._public_response(result.get("profile"), database_id, account)
    return project(application, payload, raw, result, login=True)


def project(application, payload, response, match_context, *, login=False):
    if match_context is None:
        return response
    result = deepcopy(response)
    if not isinstance(result, dict):
        raise ApiError("match_profile_invalid", 503)
    # Lottery UI snapshots contain no profile and intentionally show the real
    # account's prices/ownership. They are never a source of combat stats.
    if "schema_version" in result:
        source = result
        top_level = True
    elif isinstance(result.get("profile"), dict):
        source = result["profile"]
        top_level = False
    else:
        return result
    if (source.get("account_id") != payload.get("account_id")
            or type(source.get("revision")) is not int
            or not isinstance(source.get("save"), dict)):
        raise ApiError("match_profile_invalid", 503)
    real_profile = deepcopy(source)
    view = deepcopy(source)
    baseline = match_context["baseline"]
    if source["revision"] < baseline.get("revision", 0):
        raise ApiError("match_profile_stale", 409)
    if match_context["mode"] == "pure":
        current_time = time.time()
        defaults = match_context["defaults"]
        current_save, old_save = source["save"], baseline.get("save", {})
        view["save"] = _changes(current_save, old_save)
        stats = {}
        archive = getattr(application, "archive", None)
        specs = archive.bundle.tables.get("player_gameplay_stats", {}) if archive else {}
        from archive_backend.stackable_effects import difference
        stackable_delta = difference(current_save, old_save, archive.bundle) if archive else {}
        for field, default in defaults.items():
            before = old_save.get("gameplay_stats", {}).get(field, default)
            after = current_save.get("gameplay_stats", {}).get(field, default)
            if not all(_number(x) for x in (before, after, default)):
                raise ApiError("match_profile_stats_invalid", 503)
            value = default + after - before + stackable_delta.get(field, 0)
            spec = specs.get(field, {})
            if _number(spec.get("min_value")):
                value = max(spec["min_value"], value)
            if _number(spec.get("max_value")):
                value = min(spec["max_value"], value)
            stats[field] = value
        view["save"]["gameplay_stats"] = stats
        # This trusted response field is never written to the account save.
        # Lua must not derive these effects again from the inventory delta.
        view["save"]["stackable_projection_applied"] = True
        view["save"].setdefault("archive", {})
        view["save"].setdefault("content_inventory", {})
        # Some effects improve a stat by reducing it (e.g. cooldown). Unlike
        # owned item counts, signed committed effect deltas are meaningful.
        old_effects = old_save.get("permanent_effects", {})
        effects = {}
        for key, after in current_save.get("permanent_effects", {}).items():
            before = old_effects.get(key, 0)
            if not _number(after) or not _number(before):
                raise ApiError("match_profile_effects_invalid", 503)
            if after != before:
                effects[key] = after - before
        view["save"]["permanent_effects"] = effects
        view["save"]["match_boss_effects"] = _new_boss_effects(
            application, source, baseline, match_context["created_at"], current_time)
        # Post-clear gameplay freezes the ordinary stat snapshot, but allows a
        # newly settled social draw through by its durable unique ID/effects.
        draw = current_save.get("archive", {}).get("social_last_draw", {})
        old_draw = old_save.get("archive", {}).get("social_last_draw", {})
        if isinstance(draw, dict) and draw.get("id") and draw.get("id") != old_draw.get("id"):
            view["save"]["archive"]["social_last_draw"] = deepcopy(draw)
        view["entitlements"] = {}
        for key, state in source.get("entitlements", {}).items():
            old = baseline.get("entitlements", {}).get(key, {})
            if (_entitlement_active(state, current_time)
                    and not _entitlement_active(old, match_context["created_at"])):
                view["entitlements"][key] = deepcopy(state)
        view["achievements"] = {}
        for key, state in source.get("achievements", {}).items():
            old = baseline.get("achievements", {}).get(key, {})
            progress = max(0, state.get("progress", 0) - old.get("progress", 0))
            unlocked = state.get("unlocked") is True and old.get("unlocked") is not True
            if progress or unlocked:
                view["achievements"][key] = {"progress": progress, "unlocked": unlocked}
        view["public"] = {}
    view["match_session_id"] = match_context["match_session_id"]
    view["mode"] = match_context["mode"]
    view["progression"] = progression(real_profile)
    if not login or match_context["mode"] == "standard":
        view["account_profile"] = real_profile
    if top_level:
        return view
    result["profile"] = view
    return result
