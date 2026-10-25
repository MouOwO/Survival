"""Account metadata, separate from archive rewards and pure combat projections.

The database INSERT trigger is the first-login authority. No caller may infer a
new account from its wins, profile revision, inventory or elapsed play time.
"""
from __future__ import annotations

import re

VERSION = 1
KINDS = frozenset(("onboarding_state", "onboarding_finish"))
STATUSES = frozenset(("required", "completed", "skipped", "legacy"))
ACCOUNT = re.compile(r"[0-9]{1,20}\Z")
SESSION = re.compile(r"[A-Za-z0-9_.:-]{8,128}\Z")


def command(application, payload):
    """Use the existing authenticated archive route without a reward bundle.

    These commands cannot change gameplay stats, inventory or archive state.
    Their protocol version is independent of the configurable rewards hash.
    Both SQL functions also require the account's durable match session.
    """
    if not isinstance(payload, dict) or set(payload) - {
            "account_id", "match_session_id", "command", "config_hash"}:
        raise ValueError("onboarding_request_fields_invalid")
    account, session, item = (payload.get(key) for key in
                              ("account_id", "match_session_id", "command"))
    if not isinstance(account, str) or not ACCOUNT.fullmatch(account):
        raise ValueError("account_id_invalid")
    if not isinstance(session, str) or not SESSION.fullmatch(session):
        raise ValueError("match_session_id_invalid")
    if (not isinstance(item, dict) or not isinstance(item.get("kind"), str)
            or item["kind"] not in KINDS):
        raise ValueError("onboarding_command_invalid")
    finishing = item["kind"] == "onboarding_finish"
    allowed = {"id", "kind", "version"} | ({"outcome"} if finishing else set())
    if set(item) != allowed or type(item.get("version")) is not int or item["version"] != VERSION:
        raise ValueError("onboarding_command_fields_invalid")
    outcome = item.get("outcome")
    if finishing and outcome not in ("completed", "skipped"):
        raise ValueError("onboarding_outcome_invalid")
    expected_id = session + ":onboarding:" + (outcome if finishing else "state")
    if item.get("id") != expected_id:
        raise ValueError("onboarding_id_invalid")
    database_id = application._database_account_id(account)
    arguments = {"p_account": database_id, "p_session": session}
    if finishing:
        arguments["p_outcome"] = outcome
    value = application.rpc_client.rpc(
        "onboarding_finish" if finishing else "onboarding_state", arguments)
    if not isinstance(value, dict) or value.get("ok") is not True:
        error = value.get("error") if isinstance(value, dict) else None
        allowed_errors = {"match_session_missing", "onboarding_not_required"}
        if error not in allowed_errors:
            raise ValueError("onboarding_response_invalid")
        return {"ok": False, "error": error, "terminal": True}
    status = value.get("status")
    if (not isinstance(status, str) or status not in STATUSES or type(value.get("version")) is not int
            or value["version"] != VERSION or type(value.get("required")) is not bool
            or value["required"] != (status == "required")):
        raise ValueError("onboarding_response_invalid")
    # Deliberately return only metadata, never database IDs or a battle profile.
    return {"ok": True, "account_id": account, "match_session_id": session,
            "version": VERSION, "required": status == "required", "status": status}
