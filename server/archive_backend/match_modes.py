"""Advanced gameplay sessions reuse standard combat views and independent clears.

Installed alongside the archive service so the deployed fishing API retains its
existing projection and HTTP identity checks. No account save is projected into
settlement; only its response is projected for combat.
"""
from __future__ import annotations

PARENT_MODES = {"rich": "standard", "cold": "rich", "scourge": "cold"}
CLEAR_MODES = {"standard_clear": "standard", **{mode + "_clear": mode for mode in PARENT_MODES}}
MODE_IDS = ("pure", "standard", "rich", "cold", "scourge")


def counts(value):
    if not isinstance(value, dict):
        return {}
    return {"n" + str(n): value["n" + str(n)] for n in range(1, 21)
            if type(value.get("n" + str(n))) is int and value["n" + str(n)] > 0}


def progression(profile):
    archive = profile.get("save", {}).get("archive", {})
    ordinary = counts(archive.get("clear_counts"))
    # Missing means a pre-mode account. An existing empty map is authoritative:
    # later pure/rich clears must not reactivate the historical fallback.
    standard = counts(archive.get("standard_clear_counts") if "standard_clear_counts" in archive
                      else archive.get("clear_counts"))
    return {"loaded": True, "clear_counts": ordinary,
            "standard_clear_counts": standard,
            **{mode + "_clear_counts": counts(archive.get(mode + "_clear_counts")) for mode in PARENT_MODES},
            # This map contains only clears whose durable session supplied a
            # gameplay mode. Mixed pre-mode history is never copied into it.
            "mode_clear_counts": {mode: counts(archive.get("mode_clear_counts", {}).get(mode))
                                  for mode in MODE_IDS}
                                  if isinstance(archive.get("mode_clear_counts"), dict)
                                  else {mode: {} for mode in MODE_IDS},
            "highest_difficulty": max((int(key[1:]) for key in ordinary), default=0)}


def _archive_service(application):
    for name in ("archive_service", "archive"):
        service = getattr(application, name, None)
        if getattr(service, "bundle", None) is not None:
            return service
    return None


def _daily_projection(application, response, result):
    """Quota UI uses the real account save, including for pure combat views."""
    archive_service = _archive_service(application)
    bundle = getattr(archive_service, "bundle", None)
    if bundle is None or not isinstance(result, dict):
        return result
    view = result if "schema_version" in result else result.get("profile")
    if not isinstance(view, dict):
        return result
    account = view.get("account_profile")
    if not isinstance(account, dict) and isinstance(response, dict):
        account = response if "schema_version" in response else response.get("profile")
    if not isinstance(account, dict):
        return result
    from .daily_limits import snapshot
    summary = snapshot(account, bundle)
    view["daily_limits"] = summary
    if isinstance(view.get("progression"), dict):
        view["progression"]["daily_limits"] = summary
    result["daily_limits"] = summary
    return result


def install(module=None):
    if module is None:
        from fishing_api import match_profiles as module
    if getattr(module, "_archive_modes_version", 0) >= 3:
        return
    # Retain the original API even if install is called again after a module
    # hot reload, rather than nesting wrappers around previous mode wrappers.
    originals = getattr(module, "_archive_modes_originals", None)
    if originals is None:
        originals = (module._validate_context, module.login, module.project)
        module._archive_modes_originals = originals
    original_validate, original_login, original_project = originals
    if not hasattr(module, "_archive_modes_original_authenticate"):
        module._archive_modes_original_authenticate = getattr(module, "authenticate", None)
    original_authenticate = module._archive_modes_original_authenticate
    module.progression = progression

    def validate_context(value, account, session):
        if isinstance(value, dict) and isinstance(value.get("mode"), str) and value["mode"] in PARENT_MODES:
            value = dict(value, mode="standard")
        return original_validate(value, account, session)

    def authenticate(application, payload):
        # Keep all original admission and field allowlist checks. The entry
        # gate must not bind a mode or create/read a match-session baseline.
        result = original_authenticate(application, payload)
        archive = _archive_service(application)
        if archive is None or not isinstance(result, dict) or result.get("authenticated") is not True:
            return result
        account = result.get("account_id")
        if account != payload.get("account_id"):
            raise module.ApiError("authentication_profile_invalid", 503)
        profile = archive.profile({"account_id": account})
        if (not isinstance(profile, dict) or profile.get("account_id") != account
                or type(profile.get("revision")) is not int or profile["revision"] < 0
                or not isinstance(profile.get("save"), dict)):
            raise module.ApiError("authentication_profile_invalid", 503)
        from .daily_limits import snapshot
        result = dict(result, progression=progression(profile))
        summary = snapshot(profile, archive.bundle)
        result["daily_limits"] = summary
        result["progression"]["daily_limits"] = summary
        return result

    def login(application, payload):
        mode = payload.get("mode")
        if not isinstance(mode, str) or mode not in PARENT_MODES:
            return original_login(application, payload)
        account = module._string(payload, "account_id", module.ACCOUNT_ID)
        session = module._string(payload, "match_session_id", module.OPAQUE_ID)
        archive = getattr(application, "archive", None)
        raw = archive.profile({"account_id": account}) if archive else application.profile({"account_id": account})
        if not progression(raw)[PARENT_MODES[mode] + "_clear_counts"].get("n10"):
            raise module.ApiError(mode + "_mode_locked", 409)
        database_id = application._database_account_id(account)
        result = application.rpc_client.rpc("match_profile_login", {
            "p_account": database_id, "p_session": session,
            "p_mode": mode, "p_defaults": application.gameplay_stats})
        if isinstance(result, dict) and result.get("error") in (mode + "_mode_locked", "match_mode_locked"):
            raise module.ApiError(result["error"], 409)
        validate_context(result, database_id, session)
        if result.get("mode") != mode:
            raise module.ApiError("match_session_invalid", 503)
        raw = application._public_response(result.get("profile"), database_id, account)
        return project(application, payload, raw, result, login=True)

    def project(application, payload, response, match_context, *, login=False):
        if not match_context or not isinstance(match_context.get("mode"), str) or match_context["mode"] not in PARENT_MODES:
            result = original_project(application, payload, response, match_context, login=login)
            return _daily_projection(application, response, result)
        # Original standard projection preserves all existing account bonuses,
        # entitlements and account_profile. Keep gameplay identity as trusted session data.
        result = original_project(application, payload, response,
                                  dict(match_context, mode="standard"), login=login)
        if isinstance(result, dict):
            view = result if "schema_version" in result else result.get("profile")
            if isinstance(view, dict):
                view["game_mode"] = match_context["mode"]
        return _daily_projection(application, response, result)

    module._validate_context, module.login, module.project = validate_context, login, project
    if original_authenticate is not None:
        module.authenticate = authenticate
    module._rich_modes_installed = True
    module._archive_modes_version = 3


def scope_clear(service, payload, command):
    """Resolve clear scope from a durable authenticated account/session binding."""
    from .service import ArchiveError
    kind = command["kind"]
    if kind not in ("clear", "mode_clear") and kind not in CLEAR_MODES:
        return command
    session = payload.get("match_session_id")
    if session is None and kind == "clear":
        return command  # Pre-mode compatibility, never an explicit standard win.
    import re
    if not isinstance(session, str) or not re.fullmatch(r"[A-Za-z0-9_.:-]{8,128}", session):
        raise ArchiveError("match_session_missing")
    account = service.app._database_account_id(payload["account_id"])
    context = service.app.rpc_client.rpc("match_profile_context", {"p_account": account, "p_session": session})
    if (not isinstance(context, dict) or context.get("ok") is not True
            or context.get("account_id") != account or context.get("match_session_id") != session):
        raise ArchiveError("match_session_invalid")
    mode = context.get("mode")
    expected = CLEAR_MODES.get(kind)
    if mode not in MODE_IDS or (expected and mode != expected) or (kind == "clear" and mode in PARENT_MODES):
        raise ArchiveError("match_clear_mode_mismatch")
    # A caller's kind/mode string cannot choose the reward scope. All new
    # commands derive both scope and receipt from the authenticated session.
    receipt_kind = "clear" if mode == "pure" else mode + "_clear"
    return dict(command, mode_id=mode, id=session + ":" + receipt_kind)
