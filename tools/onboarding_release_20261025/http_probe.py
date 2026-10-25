"""Rollback-only checks through the candidate's real authenticated HTTP handler.

The caller supplies an existing owner transaction and a verified release root.
No TCP listener, remote connection, commit, credential discovery or logging is
performed. Only the handler's response writer is captured; authorization,
request parsing, durable match context, archive dispatch and projection use the
candidate's actual production implementations.
"""
from __future__ import annotations

from contextlib import contextmanager
from copy import deepcopy
from email.message import Message
import importlib
from io import BytesIO
import json
from pathlib import Path
import sys
from types import SimpleNamespace
import uuid


def _require(condition, name):
    if not condition:
        raise AssertionError("onboarding_http_" + name)


@contextmanager
def _candidate_modules(release_root):
    backend = (Path(release_root).resolve() / "backend").resolve()
    _require(backend.is_dir(), "backend_missing")
    before = list(sys.path)
    sys.path.insert(0, str(backend))
    try:
        modules = {
            name: importlib.import_module(name)
            for name in ("fishing_api.application", "fishing_api.postgres", "fishing_api.server",
                         "fishing_api.match_profiles", "archive_backend.service", "archive_backend.match_modes")
        }
        for module in modules.values():
            _require(Path(module.__file__).resolve().is_relative_to(backend),
                     "candidate_import_mismatch")
        yield modules
    finally:
        sys.path[:] = before


def _profiles(conn, accounts):
    return {
        table: conn.execute(
            "SELECT to_jsonb(t) FROM public." + table + " t WHERE " + column
            + "=ANY(%s::text[]) ORDER BY " + column, (list(accounts),)
        ).fetchall()
        for table, column in (("survival_players", "account_id"),
                              ("player_gameplay_stats", "player_id"),
                              ("player_archive_state", "account_id"))
    }


def run(conn, release_root):
    """Run synthetic HTTP requests and return only aggregate boolean checks."""
    session_user, previous_role, superuser = conn.execute(
        "SELECT session_user,current_user,"
        "(SELECT rolsuper FROM pg_roles WHERE rolname=session_user)"
    ).fetchone()
    _require(superuser is True, "owner_session_required")
    nonce = uuid.uuid4().hex
    public_ids = [str(int(uuid.uuid4().hex[:16], 16)) for _ in range(2)]
    _require(len(set(public_ids)) == 2, "synthetic_identity_collision")
    sessions = ["onboarding-http:" + nonce + ":" + str(index) for index in range(2)]
    token, pepper = "synthetic-http-token:" + uuid.uuid4().hex, "synthetic-http-pepper:" + uuid.uuid4().hex
    accounts = []
    checks = {}
    conn.execute("SAVEPOINT onboarding_release_http")
    try:
        with _candidate_modules(release_root) as modules:
            class TransactionLease:
                def cursor(self):
                    return conn.cursor()

                def commit(self):
                    pass

                def rollback(self):
                    pass

                def close(self):
                    pass

            client = modules["fishing_api.postgres"].PostgresRpcClient(
                "service=goufayu_app", connector=lambda *args, **kwargs: TransactionLease())

            class CountedClient:
                def __init__(self):
                    self.calls = []

                def ready(self):
                    return client.ready()

                def rpc(self, name, arguments):
                    self.calls.append(name)
                    return client.rpc(name, arguments)

            counted = CountedClient()
            app = modules["fishing_api.application"].FishingApplication(token, pepper, None, counted)
            # Match the real ArchiveService.install() ordering: this production
            # wrapper supplies the final context validator and projector. The
            # other service installers add unrelated leaderboard/VIP methods;
            # they do not change these HTTP metadata paths.
            modules["archive_backend.match_modes"].install(modules["fishing_api.match_profiles"])
            app._archive_modes_active = True
            app.archive = modules["archive_backend.service"].ArchiveService(app, SimpleNamespace(), "not-executable")
            accounts = [app._database_account_id(public) for public in public_ids]
            for account in accounts:
                conn.execute("INSERT INTO public.survival_players(account_id) VALUES(%s)", (account,))
                conn.execute("INSERT INTO public.player_gameplay_stats(player_id) VALUES(%s)", (account,))
            before_profiles = _profiles(conn, accounts)
            conn.execute("RESET ROLE")
            conn.execute("SET SESSION AUTHORIZATION goufayu_app")
            _require(conn.execute("SELECT session_user,current_user").fetchone()
                     == ("goufayu_app", "goufayu_app"), "actual_app_identity")
            _require(client.ready() is True, "strict_real_transport_ready")
            checks["real_candidate_application_hmac_identity_and_strict_app_transport"] = True

            for index, mode in enumerate(("standard", "pure")):
                login = counted.rpc("match_profile_login", {
                    "p_account": accounts[index], "p_session": sessions[index],
                    "p_mode": mode, "p_defaults": {},
                })
                _require(isinstance(login, dict) and login.get("ok") is True, "match_login_failed")
            handler_class = modules["fishing_api.server"].make_handler(app)

            def payload(index, *, outcome=None, session=None):
                selected = sessions[index] if session is None else session
                command = {"id": selected + ":onboarding:" + (outcome or "state"),
                           "kind": "onboarding_finish" if outcome else "onboarding_state", "version": 1}
                if outcome is not None:
                    command["outcome"] = outcome
                return {"account_id": public_ids[index], "match_session_id": selected,
                        "config_hash": "intentionally-unrelated-reward-hash", "command": command}

            def post(body, *, authorization=None):
                encoded = json.dumps(body, separators=(",", ":"), allow_nan=False).encode()
                handler = handler_class.__new__(handler_class)
                handler.path = "/v1/archive/command"
                handler.headers = Message()
                handler.headers["Content-Length"] = str(len(encoded))
                handler.headers["Content-Type"] = "application/json"
                handler.headers["Authorization"] = "Bearer " + token if authorization is None else authorization
                handler.rfile = BytesIO(encoded)
                captured = []
                handler._send = lambda status, response: captured.append((status, deepcopy(response)))
                handler.do_POST()
                _require(len(captured) == 1, "handler_response_count_invalid")
                return captured[0], handler.rfile.tell()

            def expected(index, status):
                return {"ok": True, "account_id": public_ids[index], "match_session_id": sessions[index],
                        "version": 1, "required": status == "required", "status": status}

            for index in range(2):
                before_calls = len(counted.calls)
                result, consumed = post(payload(index))
                _require(result == (200, expected(index, "required")), "required_metadata_invalid")
                _require(consumed > 0 and counted.calls[before_calls:]
                         == ["match_profile_context", "onboarding_state"], "context_and_dispatch_bypassed")
            checks["http_standard_and_pure_required_responses_use_real_context_and_archive_dispatch"] = True
            checks["pure_metadata_is_preserved_without_profile_projection_or_reward_bundle_access"] = True

            for index, outcome in enumerate(("completed", "skipped")):
                result, _ = post(payload(index, outcome=outcome))
                _require(result == (200, expected(index, outcome)), "terminal_http_response_invalid")
                result, _ = post(payload(index))
                _require(result == (200, expected(index, outcome)), "terminal_state_not_saved")
            checks["http_completed_and_skipped_accounts_no_longer_require_tutorial"] = True

            before_calls = len(counted.calls)
            result, consumed = post(payload(0), authorization="Bearer definitely-not-the-synthetic-token")
            _require(result == (401, {"ok": False, "error": "unauthorized"})
                     and consumed == 0 and len(counted.calls) == before_calls,
                     "bad_token_reached_parser_or_database")
            checks["wrong_bearer_token_returns_401_before_body_parse_or_rpc"] = True

            before_calls = len(counted.calls)
            result, _ = post(payload(0, session=sessions[0] + ":unknown"))
            _require(result == (409, {"ok": False, "error": "match_session_missing"})
                     and counted.calls[before_calls:] == ["match_profile_context"],
                     "unknown_session_not_rejected_by_real_context")
            checks["unknown_session_returns_409_before_archive_onboarding_rpc"] = True

            for field, value in (("required", False), ("status", "completed"),
                                 ("first_login", False), ("step", 4), ("account_id", public_ids[1])):
                forged = payload(0)
                forged["command"][field] = value
                before_calls = len(counted.calls)
                result, _ = post(forged)
                _require(result == (400, {"ok": False, "error": "onboarding_command_fields_invalid"})
                         and counted.calls[before_calls:] == ["match_profile_context"],
                         "forged_command_reached_onboarding_rpc")
            checks["forged_command_fields_return_400_without_onboarding_rpc"] = True

            conn.execute("RESET SESSION AUTHORIZATION")
            if previous_role != session_user:
                conn.execute('SET ROLE "' + previous_role.replace('"', '""') + '"')
            _require(_profiles(conn, accounts) == before_profiles, "profile_stats_or_inventory_changed")
            checks["http_auth_context_metadata_and_projection_preserve_gameplay_and_inventory"] = True
    finally:
        conn.execute("ROLLBACK TO SAVEPOINT onboarding_release_http")
        conn.execute("RESET SESSION AUTHORIZATION")
        if previous_role != session_user:
            conn.execute('SET ROLE "' + previous_role.replace('"', '""') + '"')
        conn.execute("RELEASE SAVEPOINT onboarding_release_http")
    _require(conn.execute("SELECT session_user,current_user").fetchone()
             == (session_user, previous_role), "authorization_not_restored")
    _require(conn.execute(
        "SELECT count(*) FROM public.survival_players WHERE account_id=ANY(%s::text[])",
        (accounts,),
    ).fetchone() == (0,), "synthetic_players_retained")
    _require(conn.execute(
        "SELECT count(*) FROM public.match_profile_sessions WHERE match_session_id=ANY(%s::text[])",
        (sessions,),
    ).fetchone() == (0,), "synthetic_sessions_retained")
    checks["all_http_synthetic_accounts_sessions_and_writes_rolled_back_identity_restored"] = True
    return {"ok": True, "checks": checks, "groups": len(checks), "synthetic_players": 2,
            "durable_player_changes": 0, "real_payments": 0, "tcp_listeners": 0}
