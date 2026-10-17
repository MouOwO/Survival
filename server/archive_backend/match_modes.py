"""Rich gameplay sessions reuse standard combat views, never standard clears.

Installed alongside the archive service so the deployed fishing API retains its
existing projection and HTTP identity checks. No account save is projected into
settlement; only its response is projected for combat.
"""
from __future__ import annotations

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
    rich = counts(archive.get("rich_clear_counts"))
    return {"loaded": True, "clear_counts": ordinary,
            "standard_clear_counts": standard, "rich_clear_counts": rich,
            "highest_difficulty": max((int(key[1:]) for key in ordinary), default=0)}


def install(module=None):
    if module is None:
        from fishing_api import match_profiles as module
    if getattr(module, "_rich_modes_installed", False):
        return
    original_validate, original_login, original_project = module._validate_context, module.login, module.project
    module.progression = progression

    def validate_context(value, account, session):
        if isinstance(value, dict) and value.get("mode") == "rich":
            value = dict(value, mode="standard")
        return original_validate(value, account, session)

    def login(application, payload):
        if payload.get("mode") != "rich":
            return original_login(application, payload)
        account = module._string(payload, "account_id", module.ACCOUNT_ID)
        session = module._string(payload, "match_session_id", module.OPAQUE_ID)
        archive = getattr(application, "archive", None)
        raw = archive.profile({"account_id": account}) if archive else application.profile({"account_id": account})
        if not progression(raw)["standard_clear_counts"].get("n10"):
            raise module.ApiError("rich_mode_locked", 409)
        database_id = application._database_account_id(account)
        result = application.rpc_client.rpc("match_profile_login", {
            "p_account": database_id, "p_session": session,
            "p_mode": "rich", "p_defaults": application.gameplay_stats})
        if isinstance(result, dict) and result.get("error") == "rich_mode_locked":
            raise module.ApiError("rich_mode_locked", 409)
        validate_context(result, database_id, session)
        raw = application._public_response(result.get("profile"), database_id, account)
        return project(application, payload, raw, result, login=True)

    def project(application, payload, response, match_context, *, login=False):
        if not match_context or match_context.get("mode") != "rich":
            return original_project(application, payload, response, match_context, login=login)
        # Original standard projection preserves all existing account bonuses,
        # entitlements and account_profile. Keep rich as trusted session data.
        result = original_project(application, payload, response,
                                  dict(match_context, mode="standard"), login=login)
        if isinstance(result, dict):
            view = result if "schema_version" in result else result.get("profile")
            if isinstance(view, dict):
                view["game_mode"] = "rich"
        return result

    module._validate_context, module.login, module.project = validate_context, login, project
    module._rich_modes_installed = True


def scope_clear(service, payload, command):
    """Resolve clear scope from a durable authenticated account/session binding."""
    from .service import ArchiveError
    kind = command["kind"]
    if kind not in ("clear", "standard_clear", "rich_clear"):
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
    expected = {"standard_clear": "standard", "rich_clear": "rich"}.get(kind)
    if mode not in ("pure", "standard", "rich") or (expected and mode != expected) or (kind == "clear" and mode == "rich"):
        raise ArchiveError("match_clear_mode_mismatch")
    if expected:
        command = dict(command, id=session + ":" + kind)
    return command
