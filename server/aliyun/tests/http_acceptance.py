"""Opt-in HTTP acceptance against a loopback TEST backend, without DB credentials.

Creates two random synthetic accounts and retains them for inspection. Never
restarts services, interrupts a database, clears data, or claims a restore test.
Every profile read uses POST /v1/profile, the actual API contract, over a fresh
connection. A fresh HTTP connection is not a process restart.

After an operator restarts the service, --verify-report reloads the synthetic
accounts from a prior successful report without submitting new business
commands. The existing profile endpoint may ensure/upsert and drain pending
settlements; this mode does not promise a read-only database transaction.
"""
from __future__ import annotations

import argparse
import base64
import hashlib
from datetime import datetime, timezone
import http.client
import ipaddress
import json
import os
from pathlib import Path
import re
import secrets
import stat
import subprocess
import sys
import time
from urllib.parse import urlsplit


NOT_TESTED = ["real_game_client", "process_restart", "database_outage", "offsite_restore"]
MAX_RESPONSE_BYTES = 4 * 1024 * 1024
MAX_REPORT_BYTES = 64 * 1024
REPORT_FORMAT = 2
REPORT_GENERATOR = "goufayu.http_acceptance.v2"
PROFILE_READ_EFFECTS = "profile_may_ensure_upsert_and_drain_pending_settlements"
WRITE_CHECKS = {
    "unauthorized_requests_rejected", "authenticated_database_readiness", "archive_config_loaded",
    "two_synthetic_profiles_initialized", "boss_command_replay_exactly_once",
    "player_isolation_and_operation_scope", "profile_reentry_over_fresh_http_connections",
    "raw_save_routes_and_command_rejected", "positive_online_interval_replay_exactly_once",
}


class AcceptanceFailure(RuntimeError):
    """Only fixed, non-sensitive failure codes may be used here."""


def require(condition, code):
    if not condition:
        raise AcceptanceFailure(code)


def loopback_target(base_url):
    try:
        parsed = urlsplit(base_url)
        address = ipaddress.ip_address(parsed.hostname or "")
        port = 8765 if parsed.port is None else parsed.port
        valid = (parsed.scheme == "http" and address.is_loopback
                 and parsed.username is None and parsed.password is None
                 and parsed.path in {"", "/"} and not parsed.query and not parsed.fragment
                 and 1 <= port <= 65535)
    except (ValueError, TypeError):
        raise AcceptanceFailure("loopback_target_required") from None
    require(valid, "loopback_target_required")
    return str(address), port


def _windows_acl_script(path, script):
    encoded = base64.b64encode(script.encode("utf-16-le")).decode("ascii")
    try:
        result = subprocess.run(
            ["powershell.exe", "-NoProfile", "-NonInteractive", "-EncodedCommand", encoded],
            env={**os.environ, "GOUFAYU_ACCEPTANCE_TOKEN_PATH": str(path.resolve())},
            capture_output=True, timeout=8, check=False,
            creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
        require(result.returncode == 0, "token_file_permissions_invalid")
    except (OSError, subprocess.SubprocessError):
        raise AcceptanceFailure("token_file_permissions_unverified") from None


def _windows_private_file(path):
    # Windows mode bits do not describe NTFS ACLs. Inspect the ACL without
    # printing it and without passing any token bytes to another process.
    script = r"""
$ErrorActionPreference = 'Stop'
try {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    $allowed = @($identity, 'S-1-5-18', 'S-1-5-32-544')
    # Python may inherit PSModulePath from PowerShell 7 while powershell.exe is
    # Windows PowerShell 5.1. Use .NET directly instead of cmdlet auto-loading.
    $acl = [System.IO.File]::GetAccessControl($env:GOUFAYU_ACCEPTANCE_TOKEN_PATH)
    $owner = $acl.GetOwner([Security.Principal.SecurityIdentifier]).Value
    if ($owner -notin $allowed) { exit 3 }
    $descriptor = [Security.AccessControl.RawSecurityDescriptor]::new($acl.GetSecurityDescriptorBinaryForm(), 0)
    if ($null -eq $descriptor.DiscretionaryAcl) { exit 3 }
    foreach ($rule in $acl.GetAccessRules($true, $true, [Security.Principal.SecurityIdentifier])) {
        if ($rule.AccessControlType -eq 'Allow') {
            $sid = $rule.IdentityReference.Value
            if ($sid -notin $allowed) { exit 3 }
        }
    }
    exit 0
} catch { exit 3 }
"""
    _windows_acl_script(path, script)


def _windows_protect_report(path):
    # os.open(mode=0600) does not restrict NTFS ACLs. Protect the newly created
    # empty report before writing its evidence, so it can be trusted on reentry.
    script = r"""
$ErrorActionPreference = 'Stop'
try {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent().User
    $acl = [Security.AccessControl.FileSecurity]::new()
    $acl.SetOwner($identity)
    $acl.SetAccessRuleProtection($true, $false)
    foreach ($sid in @($identity.Value, 'S-1-5-18', 'S-1-5-32-544')) {
        $principal = [Security.Principal.SecurityIdentifier]::new($sid)
        $rule = [Security.AccessControl.FileSystemAccessRule]::new($principal, 'FullControl', 'Allow')
        $acl.AddAccessRule($rule)
    }
    [System.IO.File]::SetAccessControl($env:GOUFAYU_ACCEPTANCE_TOKEN_PATH, $acl)
    exit 0
} catch { exit 3 }
"""
    _windows_acl_script(path, script)


def read_token(path):
    path = Path(path)
    try:
        require(not path.is_symlink(), "token_file_symlink_refused")
        if os.name == "nt":
            _windows_private_file(path)
        flags = os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0)
        descriptor = os.open(path, flags)
        with os.fdopen(descriptor, "rb") as stream:
            info = os.fstat(stream.fileno())
            require(stat.S_ISREG(info.st_mode), "token_file_not_regular")
            if os.name == "posix":
                require(info.st_uid in {0, os.geteuid()} and not info.st_mode & 0o077,
                        "token_file_permissions_invalid")
            raw = stream.read(4097)
        require(len(raw) <= 4096, "token_file_invalid")
        token = raw.decode("utf-8").rstrip("\r\n")
        # HTTP bearer headers must be printable ASCII; never trim significant
        # leading/trailing spaces or silently change the deployment identity.
        require(len(token) >= 24 and all(32 <= ord(c) < 127 for c in token), "token_file_invalid")
        return token
    except AcceptanceFailure:
        raise
    except (OSError, UnicodeError):
        raise AcceptanceFailure("token_file_unreadable") from None


class HttpClient:
    def __init__(self, target, token):
        self.target = target
        self._token = token

    def request(self, method, path, payload=None, *, authenticated=True):
        connection = http.client.HTTPConnection(*self.target, timeout=25)
        try:
            headers = {"Accept": "application/json", "Connection": "close"}
            if authenticated:
                headers["Authorization"] = "Bearer " + self._token
            body = None
            if payload is not None:
                body = json.dumps(payload, ensure_ascii=False, allow_nan=False,
                                  separators=(",", ":")).encode("utf-8")
                headers["Content-Type"] = "application/json"
            # HTTPConnection does not follow redirects or honor HTTP_PROXY.
            connection.request(method, path, body=body, headers=headers)
            response = connection.getresponse()
            data = response.read(MAX_RESPONSE_BYTES + 1)
            require(len(data) <= MAX_RESPONSE_BYTES, "http_response_too_large")
            value = json.loads(data.decode("utf-8"))
            require(isinstance(value, dict), "http_response_shape_invalid")
            return response.status, value
        except AcceptanceFailure:
            raise
        except (OSError, http.client.HTTPException):
            raise AcceptanceFailure("http_transport_failed") from None
        except (ValueError, UnicodeError, RecursionError):
            raise AcceptanceFailure("http_response_invalid") from None
        finally:
            connection.close()

    def success(self, method, path, payload, code):
        status, value = self.request(method, path, payload)
        require(status == 200 and value.get("ok") is not False, code)
        return value

    def profile(self, account):
        value = self.success("POST", "/v1/profile", {"account_id": account}, "profile_load_failed")
        require(value.get("account_id") == account and type(value.get("revision")) is int
                and value["revision"] >= 0 and isinstance(value.get("save"), dict)
                and isinstance(value["save"].get("gameplay_stats"), dict)
                and bool(value["save"]["gameplay_stats"]), "profile_contract_invalid")
        archive = value["save"].get("archive", {})
        require(isinstance(archive, dict), "archive_profile_invalid")
        return value


def boss_count(profile):
    count = profile["save"].get("archive", {}).get("boss_kills", 0)
    require(type(count) is int and count >= 0, "boss_counter_invalid")
    return count


def same_saved_state(first, second):
    return first["revision"] == second["revision"] and first["save"] == second["save"]


def profile_summary(profile):
    """Minimal non-secret persistence evidence; never store full save content."""
    saved = profile["save"]
    online = saved.get("archive", {}).get("online", {})
    require(isinstance(online, dict), "online_profile_invalid")
    seconds = saved["gameplay_stats"].get("online_seconds_total", 0)
    archive_seconds = online.get("actual_seconds", 0)
    require(type(seconds) is int and seconds >= 0 and type(archive_seconds) is int and archive_seconds >= 0,
            "online_counter_invalid")
    encoded = json.dumps(saved, ensure_ascii=False, allow_nan=False, sort_keys=True,
                         separators=(",", ":")).encode("utf-8")
    return {"account_id": profile["account_id"], "revision": profile["revision"],
            "boss_kills": boss_count(profile), "online_seconds_total": seconds,
            "archive_online_actual_seconds": archive_seconds,
            "save_sha256": hashlib.sha256(encoded).hexdigest()}


def run_acceptance(client, report):
    checks = report["checks"]
    status, value = client.request("GET", "/ready", authenticated=False)
    require(status == 401 and value.get("ok") is False, "readiness_authentication_failed")
    status, value = client.request("POST", "/v1/profile", {}, authenticated=False)
    require(status == 401 and value.get("ok") is False, "profile_authentication_failed")
    checks["unauthorized_requests_rejected"] = True

    ready = client.success("GET", "/ready", None, "database_readiness_failed")
    require(ready.get("ok") is True and ready.get("database") == "ready", "database_readiness_failed")
    checks["authenticated_database_readiness"] = True
    config = client.success("POST", "/v1/archive/config", {}, "archive_config_failed")
    config_hash = config.get("config_hash")
    require(config.get("ok") is True and config.get("protocol") == 1
            and isinstance(config_hash, str) and re.fullmatch(r"[0-9a-f]{64}", config_hash),
            "archive_config_contract_invalid")
    checks["archive_config_loaded"] = True

    # Reserved-looking numeric identifiers, deliberately unrelated to live
    # game accounts. No user can specify an existing account through this CLI.
    account = "900" + f"{secrets.randbelow(10**16):016d}"
    other = "900" + f"{secrets.randbelow(10**16):016d}"
    while other == account:
        other = "900" + f"{secrets.randbelow(10**16):016d}"
    report["synthetic_accounts"] = [account, other]
    before = client.profile(account)
    other_before = client.profile(other)
    require(boss_count(before) == boss_count(other_before) == 0, "synthetic_account_not_fresh")
    checks["two_synthetic_profiles_initialized"] = True

    operation = {"id": "http-acceptance:" + secrets.token_hex(16), "kind": "boss_kill"}
    payload = {"account_id": account, "config_hash": config_hash, "command": operation}
    first = client.success("POST", "/v1/archive/command", payload, "boss_command_failed")
    require(first.get("ok") is True and first.get("done") is True, "boss_command_not_committed")
    after_first = client.profile(account)
    require(boss_count(after_first) == 1 and after_first["revision"] > before["revision"],
            "boss_command_not_persisted")
    repeated = client.success("POST", "/v1/archive/command", payload, "boss_repeat_failed")
    require(repeated.get("ok") is True and repeated.get("done") is True, "boss_repeat_not_committed")
    after_repeat = client.profile(account)
    require(boss_count(after_repeat) == 1 and same_saved_state(after_first, after_repeat),
            "boss_repeat_applied_more_than_once")
    checks["boss_command_replay_exactly_once"] = True

    other_untouched = client.profile(other)
    require(same_saved_state(other_before, other_untouched), "player_isolation_failed")
    # The same operation ID must be scoped to each player, not globally shared.
    other_payload = {**payload, "account_id": other}
    result = client.success("POST", "/v1/archive/command", other_payload, "second_player_command_failed")
    require(result.get("ok") is True, "second_player_command_failed")
    other_after = client.profile(other)
    require(boss_count(other_after) == 1 and same_saved_state(after_repeat, client.profile(account)),
            "operation_player_scope_failed")
    checks["player_isolation_and_operation_scope"] = True
    require(same_saved_state(after_repeat, client.profile(account)), "profile_reentry_not_persisted")
    checks["profile_reentry_over_fresh_http_connections"] = True

    raw = {"account_id": account, "save": {"archive": {"boss_kills": 999999999}}}
    for path in ("/v1/archive/save", "/v1/profile/save", "/v1/save"):
        status, value = client.request("POST", path, raw)
        require(status in {404, 405} and value.get("ok") is False, "raw_save_route_accepted")
    malicious = {**payload, "command": {"id": "http-raw-save:" + secrets.token_hex(16),
                                       "kind": "raw_save", "save": raw["save"]}}
    status, value = client.request("POST", "/v1/archive/command", malicious)
    require(status == 400 and value.get("ok") is False, "raw_save_command_accepted")
    require(same_saved_state(after_repeat, client.profile(account)), "raw_save_mutated_profile")
    checks["raw_save_routes_and_command_rejected"] = True

    session = "http-acceptance:" + secrets.token_hex(16)
    checkpoint = {"account_id": account, "session_id": session,
                  "request_id": "http-online-start:" + secrets.token_hex(16), "final": False}
    first_checkpoint = client.success("POST", "/v1/online-time/checkpoint", checkpoint, "online_checkpoint_failed")
    require(first_checkpoint.get("ok") is True, "online_checkpoint_failed")
    # Observe a real elapsed interval instead of passing on a duplicate zero.
    time.sleep(1.2)
    checkpoint.update(request_id="http-online-final:" + secrets.token_hex(16), final=True)
    completed = client.success("POST", "/v1/online-time/checkpoint", checkpoint, "online_final_failed")
    require(completed.get("ok") is True and type(completed.get("elapsed_seconds")) is int
            and completed["elapsed_seconds"] >= 1, "online_interval_not_recorded")
    saved_checkpoint = client.profile(account)
    replayed = client.success("POST", "/v1/online-time/checkpoint", checkpoint, "online_repeat_failed")
    require(replayed.get("ok") is True and completed == replayed, "online_duplicate_response_changed")
    require(same_saved_state(saved_checkpoint, client.profile(account)), "online_repeat_applied_more_than_once")
    require(same_saved_state(other_after, client.profile(other)), "online_player_isolation_failed")
    checks["positive_online_interval_replay_exactly_once"] = True
    report["verification"] = {
        "schema": 1, "test_kind": "boss_replay_online_final_v1", "config_hash": config_hash,
        "boss_operation_id": operation["id"], "online_session_id": session,
        "online_final_request_id": checkpoint["request_id"],
        "players": [profile_summary(saved_checkpoint), profile_summary(other_after)],
    }
    report["status"] = "PASS"
    report["code"] = "http_acceptance_passed"


def validate_verification_report(value):
    required = {"format", "generator", "mode", "status", "code", "started_at", "finished_at",
                "synthetic_accounts", "checks", "not_tested", "test_records_retained",
                "profile_read_side_effects", "verification"}
    require(isinstance(value, dict) and set(value) == required, "verification_report_fields_invalid")
    require(type(value["format"]) is int and value["format"] == REPORT_FORMAT
            and value["generator"] == REPORT_GENERATOR and value["mode"] == "write_test"
            and value["status"] == "PASS" and value["code"] == "http_acceptance_passed"
            and value["test_records_retained"] is True
            and value["profile_read_side_effects"] == PROFILE_READ_EFFECTS
            and value["not_tested"] == NOT_TESTED, "verification_report_not_approved_source")
    for name in ("started_at", "finished_at"):
        require(isinstance(value[name], str) and len(value[name]) <= 64, "verification_report_time_invalid")
        try:
            require(datetime.fromisoformat(value[name]).tzinfo is not None, "verification_report_time_invalid")
        except ValueError:
            raise AcceptanceFailure("verification_report_time_invalid") from None
    accounts = value["synthetic_accounts"]
    require(isinstance(accounts, list) and len(accounts) == 2
            and all(isinstance(account, str) and re.fullmatch(r"900[0-9]{16}", account) for account in accounts)
            and accounts[0] != accounts[1], "verification_report_synthetic_accounts_invalid")
    checks = value["checks"]
    require(isinstance(checks, dict) and set(checks) == WRITE_CHECKS
            and all(result is True for result in checks.values()), "verification_report_checks_invalid")
    recorded = value["verification"]
    fields = {"schema", "test_kind", "config_hash", "boss_operation_id", "online_session_id",
              "online_final_request_id", "players"}
    require(isinstance(recorded, dict) and set(recorded) == fields and type(recorded["schema"]) is int
            and recorded["schema"] == 1 and recorded["test_kind"] == "boss_replay_online_final_v1",
            "verification_report_evidence_invalid")
    require(isinstance(recorded["config_hash"], str) and re.fullmatch(r"[0-9a-f]{64}", recorded["config_hash"]),
            "verification_report_evidence_invalid")
    for name, prefix in (("boss_operation_id", "http-acceptance:"), ("online_session_id", "http-acceptance:"),
                         ("online_final_request_id", "http-online-final:")):
        require(isinstance(recorded[name], str) and re.fullmatch(prefix + r"[0-9a-f]{32}", recorded[name]),
                "verification_report_operation_invalid")
    players = recorded["players"]
    require(isinstance(players, list) and len(players) == 2, "verification_report_players_invalid")
    for index, player in enumerate(players):
        require(isinstance(player, dict) and set(player) == {
            "account_id", "revision", "boss_kills", "online_seconds_total", "archive_online_actual_seconds", "save_sha256"},
            "verification_report_player_fields_invalid")
        require(player["account_id"] == accounts[index], "verification_report_player_account_mismatch")
        require(all(type(player[name]) is int and 0 <= player[name] <= 2**63 - 1 for name in (
            "revision", "boss_kills", "online_seconds_total", "archive_online_actual_seconds"))
            and player["revision"] >= 1 and player["boss_kills"] == 1, "verification_report_counter_invalid")
        require(isinstance(player["save_sha256"], str) and re.fullmatch(r"[0-9a-f]{64}", player["save_sha256"]),
                "verification_report_digest_invalid")
        require((player["online_seconds_total"] >= 1 and player["archive_online_actual_seconds"] >= 1) if index == 0
                else (player["online_seconds_total"] == player["archive_online_actual_seconds"] == 0),
                "verification_report_online_isolation_invalid")
    return value


def load_private_report(path, validator):
    path = Path(path)
    try:
        require(not path.is_symlink(), "verification_report_symlink_refused")
        if os.name == "nt":
            try:
                _windows_private_file(path)
            except AcceptanceFailure:
                raise AcceptanceFailure("verification_report_permissions_invalid") from None
        descriptor = os.open(path, os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0))
        with os.fdopen(descriptor, "rb") as stream:
            info = os.fstat(stream.fileno())
            require(stat.S_ISREG(info.st_mode), "verification_report_not_regular")
            if os.name == "posix":
                require(info.st_uid in {0, os.geteuid()} and not info.st_mode & 0o077,
                        "verification_report_permissions_invalid")
            data = stream.read(MAX_REPORT_BYTES + 1)
        require(len(data) <= MAX_REPORT_BYTES, "verification_report_too_large")

        def unique_pairs(pairs):
            result = {}
            for key, child in pairs:
                require(key not in result, "verification_report_duplicate_field")
                result[key] = child
            return result

        def reject_constant(constant):
            raise AcceptanceFailure("verification_report_json_invalid")

        return validator(json.loads(data.decode("utf-8"),
            object_pairs_hook=unique_pairs, parse_constant=reject_constant))
    except AcceptanceFailure:
        raise
    except (OSError, UnicodeError, ValueError, RecursionError):
        raise AcceptanceFailure("verification_report_unreadable_or_invalid") from None


def load_verification_report(path):
    return load_private_report(path, validate_verification_report)


def verify_previous_run(client, source, report):
    # No archive command, reward grant, or online checkpoint is sent. The
    # existing profile route itself can still ensure/upsert/drain; see module doc.
    validate_verification_report(source)
    report["synthetic_accounts"] = list(source["synthetic_accounts"])
    ready = client.success("GET", "/ready", None, "database_readiness_failed")
    require(ready.get("ok") is True and ready.get("database") == "ready", "database_readiness_failed")
    report["checks"]["authenticated_database_readiness"] = True
    config = client.success("POST", "/v1/archive/config", {}, "archive_config_failed")
    require(config.get("ok") is True and config.get("config_hash") == source["verification"]["config_hash"],
            "verification_config_changed")
    report["checks"]["original_archive_config_retained"] = True
    for index, expected in enumerate(source["verification"]["players"], 1):
        actual = profile_summary(client.profile(expected["account_id"]))
        require(actual == expected, "verification_saved_state_mismatch")
        report["checks"][f"synthetic_player_{index}_saved_state_retained"] = True
    report["checks"]["stored_rewards_counters_and_account_isolation_retained"] = True
    report["checks"]["no_new_business_commands_submitted"] = True
    report["status"] = "PASS"
    report["code"] = "http_prior_report_verified"


def write_report(path, report):
    # Persist only synthetic IDs, operation IDs, counters, hashes, and results.
    # Do not add full server response objects or Authorization material.
    path = Path(path)
    try:
        path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
        descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(descriptor, "w", encoding="utf-8", newline="\n") as stream:
            if os.name == "nt":
                _windows_protect_report(path)
            json.dump(report, stream, ensure_ascii=False, indent=2)
            stream.write("\n")
    except (OSError, AcceptanceFailure):
        raise AcceptanceFailure("report_write_failed") from None


def main(argv=None):
    class SafeArgumentParser(argparse.ArgumentParser):
        def error(self, message):
            # A mistaken command may contain a secret value; never echo argv.
            self.exit(2, '{"status":"FAIL","code":"cli_arguments_invalid"}\n')

    parser = SafeArgumentParser(description=__doc__)
    parser.add_argument("--base-url", default="http://127.0.0.1:8765")
    parser.add_argument("--token-file", type=Path, default=Path("/etc/goufayu/api-token"))
    modes = parser.add_mutually_exclusive_group()
    modes.add_argument("--confirm-test-writes", action="store_true",
                        help="Acknowledge committed synthetic test accounts on this TEST backend")
    modes.add_argument("--verify-report", type=Path,
                       help="Re-read accounts from a private v2 PASS report; submit no new business commands")
    parser.add_argument("--report", type=Path, help="New result JSON file; existing files are never overwritten")
    args = parser.parse_args(argv)
    report = {"format": REPORT_FORMAT, "generator": REPORT_GENERATOR,
              "mode": "verify_prior_report" if args.verify_report else "write_test",
              "status": "FAIL", "code": "not_started",
              "started_at": datetime.now(timezone.utc).isoformat(),
              "synthetic_accounts": [], "checks": {}, "not_tested": NOT_TESTED,
              "test_records_retained": True, "profile_read_side_effects": PROFILE_READ_EFFECTS}
    try:
        require(args.confirm_test_writes or args.verify_report, "explicit_test_write_confirmation_required")
        if args.report:
            require(not args.report.exists() and not args.report.is_symlink(), "report_path_already_exists")
        target = loopback_target(args.base_url)
        source = load_verification_report(args.verify_report) if args.verify_report else None
        token = read_token(args.token_file)
        client = HttpClient(target, token)
        if source is not None:
            verify_previous_run(client, source, report)
        else:
            run_acceptance(client, report)
    except AcceptanceFailure as exc:
        report["code"] = str(exc)
    except Exception:
        report["code"] = "http_acceptance_internal_failure"
    report["finished_at"] = datetime.now(timezone.utc).isoformat()
    if args.report and report["code"] != "report_path_already_exists":
        try:
            write_report(args.report, report)
        except AcceptanceFailure:
            report["status"] = "FAIL"
            report["code"] = "report_write_failed"
    print(json.dumps(report, ensure_ascii=False, separators=(",", ":")))
    return 0 if report["status"] == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
