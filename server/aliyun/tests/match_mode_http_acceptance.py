"""Opt-in real HTTP acceptance for mode login and durable pure-match views.

Writes only two newly generated synthetic TEST accounts, retained for inspection.
No service restart, database deletion, player edits, or payment is performed.
Run --verify-report after an independently recorded backend restart to verify
that the same pure session baseline and permanent rewards remain intact.
"""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import secrets
import sys
import time

from http_acceptance import (AcceptanceFailure, HttpClient, load_private_report,
    loopback_target, read_token, require, write_report)

GENERATOR = "goufayu.match_mode_acceptance.v1"


def digest(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, ensure_ascii=False,
        separators=(",", ":"), allow_nan=False).encode()).hexdigest()


def view_signature(profile):
    return digest({key: profile.get(key) for key in
        ("revision", "save", "entitlements", "achievements", "progression", "mode", "match_session_id")})


def login(client, account, session, mode):
    result = client.success("POST", "/v1/session/login", {
        "account_id": account, "match_session_id": session, "mode": mode}, "mode_login_failed")
    require(result.get("account_id") == account and result.get("mode") == mode
            and result.get("match_session_id") == session, "mode_login_contract_invalid")
    return result


def profile(client, account, session):
    return client.success("POST", "/v1/profile", {
        "account_id": account, "match_session_id": session}, "mode_profile_failed")


def command(client, account, session, config, difficulty, identifier):
    return client.success("POST", "/v1/archive/command", {
        "account_id": account, "match_session_id": session, "config_hash": config,
        "command": {"id": identifier, "kind": "clear", "difficulty_id": difficulty,
                    "count": 1, "day_key": str(int((time.time() + 8 * 3600) // 86400))}},
        "mode_clear_command_failed")


def run(client, report):
    checks = report["checks"]
    status, _ = client.request("POST", "/v1/session/login", {}, authenticated=False)
    require(status == 401, "mode_login_authentication_missing")
    status, _ = client.request("POST", "/v1/session/authenticate", {}, authenticated=False)
    require(status == 401, "admission_authentication_missing")
    client.success("GET", "/ready", None, "database_readiness_failed")
    checks["login_requires_server_authentication"] = True
    config = client.success("POST", "/v1/archive/config", {}, "archive_config_failed")["config_hash"]
    accounts = ["901" + f"{secrets.randbelow(10**16):016d}" for _ in range(2)]
    require(accounts[0] != accounts[1], "synthetic_account_collision")
    account, other = accounts
    sessions = {key: "mode-accept:" + secrets.token_hex(16)
                for key in ("seed", "pure", "standard", "other")}
    report["synthetic_accounts"] = accounts
    initial = login(client, account, sessions["seed"], "standard")
    defaults = initial["save"]["gameplay_stats"]
    require(initial.get("progression", {}).get("clear_counts", {}) == {}, "synthetic_account_not_fresh")
    other_initial = login(client, other, sessions["other"], "standard")
    other_signature = view_signature(other_initial)

    # Seed an old permanent achievement through the ordinary transaction route.
    command(client, account, sessions["seed"], config, "n5", "mode-seed:" + secrets.token_hex(16))
    baseline = client.profile(account)
    require(baseline["save"].get("archive", {}).get("clear_counts", {}).get("n5") == 1,
            "old_clear_not_persisted")
    require(baseline["save"]["gameplay_stats"] != defaults, "seed_reward_has_no_stat_delta")
    admission = client.success("POST", "/v1/session/authenticate", {
        "account_id": account, "match_session_id": sessions["pure"]}, "admission_failed")
    require(set(admission) == {"authenticated", "account_id", "match_session_id", "progression"}
            and admission["authenticated"] is True and admission["account_id"] == account
            and admission["match_session_id"] == sessions["pure"]
            and admission["progression"]["clear_counts"].get("n5") == 1,
            "admission_leaked_save_or_wrong_identity")
    status, _ = client.request("POST", "/v1/profile", {
        "account_id": account, "match_session_id": sessions["pure"]})
    require(status == 409, "admission_created_premature_mode_baseline")
    checks["admission_only_metadata_no_mode_lock_or_save"] = True
    pure = login(client, account, sessions["pure"], "pure")
    require(pure["save"]["gameplay_stats"] == defaults and pure["save"].get("archive", {}) == {}
            and pure.get("entitlements", {}) == {} and "account_profile" not in pure,
            "pure_login_leaked_old_save")
    require(pure["progression"]["clear_counts"].get("n5") == 1, "pure_lost_unlock_permission")
    checks["pure_login_defaults_without_old_save"] = True
    checks["pure_retains_difficulty_permissions"] = True
    require(view_signature(login(client, account, sessions["pure"], "pure")) == view_signature(pure),
            "duplicate_login_reset_baseline")
    status, response = client.request("POST", "/v1/session/login", {
        "account_id": account, "match_session_id": sessions["pure"], "mode": "standard"})
    require(status == 409 and response.get("error") == "match_mode_locked", "mode_mutation_accepted")
    status, _ = client.request("POST", "/v1/profile", {
        "account_id": other, "match_session_id": sessions["pure"]})
    require(status == 409, "session_account_isolation_failed")
    checks["login_idempotency_mode_lock_and_account_isolation"] = True

    identifier = "mode-clear:" + secrets.token_hex(16)
    result = command(client, account, sessions["pure"], config, "n6", identifier)
    require(result.get("ok") is True and result.get("done") is True, "new_clear_not_committed")
    actual = client.profile(account)
    after = profile(client, account, sessions["pure"])
    for field, default in defaults.items():
        expected = default + actual["save"]["gameplay_stats"][field] - baseline["save"]["gameplay_stats"][field]
        require(abs(after["save"]["gameplay_stats"][field] - expected) < 1e-7,
                "pure_new_reward_delta_invalid")
    counts = actual["save"].get("archive", {}).get("clear_counts", {})
    require(counts.get("n5") == counts.get("n6") == 1, "permanent_progression_overwritten")
    require(after["progression"]["clear_counts"].get("n6") == 1, "new_unlock_metadata_missing")
    signature = view_signature(after)
    command(client, account, sessions["pure"], config, "n6", identifier)
    require(view_signature(profile(client, account, sessions["pure"])) == signature,
            "duplicate_clear_granted_twice")
    require(view_signature(login(client, account, sessions["pure"], "pure")) == signature,
            "relogin_discarded_match_rewards")
    checks["pure_new_rewards_apply_and_persist_without_old_bonuses"] = True
    checks["clear_replay_exactly_once_and_unlock_persisted"] = True

    online_session = "mode-online:" + secrets.token_hex(16)
    client.success("POST", "/v1/online-time/checkpoint", {
        "account_id": account, "match_session_id": sessions["pure"], "session_id": online_session,
        "request_id": online_session + ":1", "final": False}, "mode_checkpoint_failed")
    after = profile(client, account, sessions["pure"])
    require(after["save"]["gameplay_stats"] == profile(client, account, sessions["pure"])["save"]["gameplay_stats"],
            "checkpoint_restored_old_bonuses")
    # Compare to the already verified projected stats, not merely two reads.
    require(after["save"]["gameplay_stats"] == result["profile"]["save"]["gameplay_stats"],
            "initial_checkpoint_changed_combat_stats")
    checks["automatic_checkpoint_does_not_restore_old_bonuses"] = True
    require(view_signature(profile(client, other, sessions["other"])) == other_signature,
            "other_account_mutated")
    normal = login(client, account, sessions["standard"], "standard")
    require(normal["save"] == client.profile(account)["save"], "standard_did_not_restore_full_save")
    checks["standard_mode_uses_complete_persistent_save"] = True
    checks["other_account_unchanged"] = True
    report["verification"] = {"account": account, "other": other, "sessions": sessions,
        "pure_signature": view_signature(after), "standard_signature": view_signature(normal),
        "other_signature": other_signature, "config_hash": config}


def validate_prior(value):
    require(value.get("generator") == GENERATOR and value.get("status") == "PASS"
            and isinstance(value.get("verification"), dict), "mode_prior_report_invalid")
    return value


def verify(client, report, previous):
    v = previous["verification"]
    for key, mode in (("pure", "pure"), ("standard", "standard"), ("other", "standard")):
        account = v["other"] if key == "other" else v["account"]
        current = login(client, account, v["sessions"][key], mode)
        require(view_signature(current) == v[key + "_signature"], "mode_restart_retention_failed")
    report["checks"]["saved_session_baselines_rewards_and_unlocks_retained"] = True
    report["process_restart"] = "requires_independent_operator_evidence"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base-url", default="http://127.0.0.1:8765")
    parser.add_argument("--token-file", required=True)
    parser.add_argument("--report", required=True)
    parser.add_argument("--verify-report")
    parser.add_argument("--allow-test-writes", action="store_true")
    args = parser.parse_args()
    report = {"generator": GENERATOR, "status": "FAIL", "checks": {},
        "verified_at": datetime.now(timezone.utc).isoformat(),
        "not_tested": ["real_game_client", "payment", "database_outage"]}
    try:
        require(bool(args.verify_report) != bool(args.allow_test_writes), "choose_verify_or_test_writes")
        require(not Path(args.report).exists(), "report_already_exists")
        client = HttpClient(loopback_target(args.base_url), read_token(args.token_file))
        if args.verify_report:
            previous = load_private_report(args.verify_report, validate_prior)
            verify(client, report, previous)
        else:
            run(client, report)
        report["status"] = "PASS"
    except AcceptanceFailure as exc:
        report["error"] = str(exc)
    except Exception as exc:
        report["error"] = type(exc).__name__
    write_report(args.report, report)
    print(json.dumps({"status": report["status"], "checks": report["checks"],
                      "error": report.get("error"), "account_data_printed": False}))
    return 0 if report["status"] == "PASS" else 1


if __name__ == "__main__":
    sys.exit(main())
