"""Exercise a candidate's real application transport without retaining test data.

The owner-controlled release operator supplies its existing PostgreSQL
transaction and one existing legacy account. This module never discovers
credentials, opens another database connection, commits, logs diagnostics or
returns account/profile data. All synthetic writes and the legacy account's
temporary match session are rolled back to this module's savepoint.
"""
from __future__ import annotations

from contextlib import contextmanager
from copy import deepcopy
import hashlib
import importlib
from pathlib import Path
import sys
from types import SimpleNamespace
import uuid


def _require(condition, name):
    if not condition:
        raise AssertionError("onboarding_runtime_" + name)


@contextmanager
def _candidate_modules(release_root):
    backend = (Path(release_root).resolve() / "backend").resolve()
    _require(backend.is_dir(), "backend_missing")
    before = list(sys.path)
    sys.path.insert(0, str(backend))
    try:
        service = importlib.import_module("archive_backend.service")
        postgres = importlib.import_module("fishing_api.postgres")
        for module in (service, postgres):
            origin = Path(module.__file__).resolve()
            _require(origin.is_relative_to(backend), "candidate_import_mismatch")
        yield service, postgres
    finally:
        sys.path[:] = before


def _profile_rows(conn, accounts):
    """Internal exact comparison only; no returned/public profile material."""
    return {
        table: conn.execute(
            "SELECT to_jsonb(t) FROM public." + table + " t WHERE "
            + column + "=ANY(%s::text[]) ORDER BY " + column,
            (list(accounts),),
        ).fetchall()
        for table, column in (
            ("survival_players", "account_id"),
            ("player_gameplay_stats", "player_id"),
            ("player_archive_state", "account_id"),
        )
    }


def run(conn, release_root, legacy_account):
    """Return aggregate checks, restoring authorization and all probe writes.

    Call after the candidate SQL/permissions are applied in the owner's open
    transaction. The same function also supports post-deployment verification.
    ``legacy_account`` must be an existing account with no onboarding row.
    """
    _require(isinstance(legacy_account, str) and len(legacy_account) == 64,
             "legacy_fixture_invalid")
    session_user, previous_role, superuser = conn.execute(
        "SELECT session_user,current_user,"
        "(SELECT rolsuper FROM pg_roles WHERE rolname=session_user)"
    ).fetchone()
    _require(superuser is True, "owner_session_required")
    _require(conn.execute(
        "SELECT EXISTS(SELECT 1 FROM public.survival_players WHERE account_id=%s),"
        "EXISTS(SELECT 1 FROM public.player_onboarding_state WHERE account_id=%s)",
        (legacy_account, legacy_account),
    ).fetchone() == (True, False), "legacy_fixture_required")

    nonce = uuid.uuid4().hex
    public_ids = [str(int(uuid.uuid4().hex[:16], 16)) for _ in range(3)]
    _require(len(set(public_ids)) == 3, "synthetic_identity_collision")
    synthetic = [hashlib.sha256(("onboarding-runtime:" + nonce + ":" + str(index)).encode()).hexdigest()
                 for index in range(2)]
    identities = dict(zip(public_ids, [*synthetic, legacy_account]))
    sessions = ["onboarding-runtime:" + nonce + ":" + str(index) for index in range(4)]
    accounts = [*synthetic, legacy_account]
    checks = {}
    conn.execute("SAVEPOINT onboarding_release_runtime")
    try:
        original_profiles = _profile_rows(conn, [legacy_account])
        for account in synthetic:
            conn.execute("INSERT INTO public.survival_players(account_id) VALUES(%s)", (account,))
            conn.execute("INSERT INTO public.player_gameplay_stats(player_id) VALUES(%s)", (account,))
        _require(conn.execute(
            "SELECT count(*) FROM public.player_onboarding_state "
            "WHERE account_id=ANY(%s::text[]) AND status='required' AND finished_at IS NULL",
            (synthetic,),
        ).fetchone() == (2,), "new_account_trigger_required")
        checks["new_accounts_atomically_start_required"] = True
        # This legacy fixture gets a disposable session only. Its profile and
        # metadata are never backfilled, reset or otherwise updated.
        conn.execute(
            "INSERT INTO public.match_profile_sessions(account_id,match_session_id,mode,baseline,defaults) "
            "VALUES(%s,%s,'standard','{}'::jsonb,'{}'::jsonb)",
            (legacy_account, sessions[2]),
        )
        before_profiles = _profile_rows(conn, accounts)
        with _candidate_modules(release_root) as (service_module, postgres_module):
            conn.execute("RESET ROLE")
            conn.execute("SET SESSION AUTHORIZATION goufayu_app")
            _require(conn.execute("SELECT session_user,current_user").fetchone()
                     == ("goufayu_app", "goufayu_app"), "actual_app_identity")

            class TransactionLease:
                # The production client owns its usual cursor/validation
                # lifecycle. Its transaction close operations cannot escape
                # this operator's owner-controlled fixture savepoint.
                def cursor(self):
                    return conn.cursor()

                def commit(self):
                    pass

                def rollback(self):
                    pass

                def close(self):
                    pass

            client = postgres_module.PostgresRpcClient(
                "service=goufayu_app", connector=lambda *args, **kwargs: TransactionLease())
            _require(client.ready() is True, "strict_real_transport_ready")
            checks["actual_app_session_passes_strict_transport_permission_checks"] = True

            class CountedClient:
                def __init__(self):
                    self.calls = 0

                def rpc(self, name, arguments):
                    self.calls += 1
                    return client.rpc(name, arguments)

            counted = CountedClient()
            app = SimpleNamespace(rpc_client=counted,
                                  _database_account_id=lambda public: identities[public])
            # No hash/configs/tables member: the real archive command route
            # must dispatch onboarding before touching reward configuration.
            service = service_module.ArchiveService(app, SimpleNamespace(), "not-executable")

            def request(index, *, session=None, outcome=None):
                selected_session = sessions[index] if session is None else session
                command = {"id": selected_session + ":onboarding:" + (outcome or "state"),
                           "kind": "onboarding_finish" if outcome else "onboarding_state", "version": 1}
                if outcome is not None:
                    command["outcome"] = outcome
                return {"account_id": public_ids[index], "match_session_id": selected_session,
                        "config_hash": "intentionally-unrelated-reward-hash", "command": command}

            def response(index, *, session=None, outcome=None, expected="required"):
                selected_session = sessions[index] if session is None else session
                result = service.command(request(index, session=session, outcome=outcome))
                _require(result == {"ok": True, "account_id": public_ids[index],
                                    "match_session_id": selected_session, "version": 1,
                                    "required": expected == "required", "status": expected},
                         "metadata_response_invalid")
                return result

            for index, mode in enumerate(("standard", "pure")):
                logged_in = client.rpc("match_profile_login", {
                    "p_account": synthetic[index], "p_session": sessions[index],
                    "p_mode": mode, "p_defaults": {},
                })
                _require(isinstance(logged_in, dict) and logged_in.get("ok") is True,
                         "real_match_login_failed")
                response(index)
            checks["real_standard_and_pure_logins_both_require_tutorial_without_reward_hash"] = True

            response(0, outcome="completed", expected="completed")
            response(0, outcome="completed", expected="completed")
            response(0, outcome="skipped", expected="completed")
            response(0, expected="completed")
            checks["completion_retries_and_opposite_outcome_keep_first_terminal_result"] = True

            response(1, outcome="skipped", expected="skipped")
            response(1, outcome="completed", expected="skipped")
            next_login = client.rpc("match_profile_login", {
                "p_account": synthetic[1], "p_session": sessions[3],
                "p_mode": "standard", "p_defaults": {},
            })
            _require(isinstance(next_login, dict) and next_login.get("ok") is True,
                     "next_match_login_failed")
            response(1, session=sessions[3], expected="skipped")
            checks["skip_survives_new_match_and_never_requires_tutorial_again"] = True

            response(2, expected="legacy")
            _require(service.command(request(2, outcome="completed")) == {
                "ok": False, "terminal": True, "error": "onboarding_not_required"},
                "legacy_finish_must_reject")
            checks["existing_account_stays_legacy_and_cannot_finish_unrequired_tutorial"] = True

            for outcome in (None, "skipped"):
                _require(service.command(request(0, session=sessions[0] + ":unknown", outcome=outcome))
                         == {"ok": False, "terminal": True, "error": "match_session_missing"},
                         "unknown_session_must_reject")
            checks["unknown_match_session_cannot_read_or_finish_metadata"] = True

            before_calls = counted.calls
            for field, value in (("status", "completed"), ("required", False),
                                 ("first_login", False), ("step", 4), ("account_id", public_ids[1])):
                forged = deepcopy(request(0))
                forged["command"][field] = value
                try:
                    service.command(forged)
                except service_module.ArchiveError as error:
                    _require(str(error) == "onboarding_command_fields_invalid", "forged_fields_error")
                else:
                    _require(False, "forged_fields_accepted")
            _require(counted.calls == before_calls, "forged_fields_reached_rpc")
            checks["forged_first_login_progress_and_account_fields_reject_before_rpc"] = True

            conn.execute("SAVEPOINT onboarding_release_direct_denied")
            try:
                try:
                    conn.execute("SELECT 1 FROM public.player_onboarding_state LIMIT 1")
                except Exception as error:
                    _require(getattr(error, "sqlstate", None) == "42501", "direct_read_wrong_error")
                else:
                    _require(False, "app_direct_table_read_allowed")
            finally:
                conn.execute("ROLLBACK TO SAVEPOINT onboarding_release_direct_denied")
                conn.execute("RELEASE SAVEPOINT onboarding_release_direct_denied")
            checks["app_role_cannot_directly_read_onboarding_table"] = True

            conn.execute("RESET SESSION AUTHORIZATION")
            if previous_role != session_user:
                conn.execute('SET ROLE "' + previous_role.replace('"', '""') + '"')
            _require(_profile_rows(conn, accounts) == before_profiles,
                     "tutorial_changed_profile_stats_or_inventory")
            _require(_profile_rows(conn, [legacy_account]) == original_profiles,
                     "legacy_profile_changed")
            _require(conn.execute(
                "SELECT 1 FROM public.player_onboarding_state WHERE account_id=%s", (legacy_account,)
            ).fetchone() is None, "legacy_metadata_backfilled")
            checks["tutorial_rpcs_preserve_profiles_gameplay_stats_inventory_and_legacy_metadata"] = True
    finally:
        conn.execute("ROLLBACK TO SAVEPOINT onboarding_release_runtime")
        conn.execute("RESET SESSION AUTHORIZATION")
        if previous_role != session_user:
            conn.execute('SET ROLE "' + previous_role.replace('"', '""') + '"')
        conn.execute("RELEASE SAVEPOINT onboarding_release_runtime")
    _require(conn.execute("SELECT session_user,current_user").fetchone()
             == (session_user, previous_role), "authorization_not_restored")
    _require(conn.execute(
        "SELECT count(*) FROM public.survival_players WHERE account_id=ANY(%s::text[])",
        (synthetic,),
    ).fetchone() == (0,), "synthetic_players_retained")
    _require(conn.execute(
        "SELECT count(*) FROM public.match_profile_sessions WHERE match_session_id=ANY(%s::text[])",
        (sessions,),
    ).fetchone() == (0,), "temporary_match_sessions_retained")
    checks["all_synthetic_accounts_and_temporary_sessions_rolled_back_authorization_restored"] = True
    return {"ok": True, "checks": checks, "groups": len(checks),
            "synthetic_players": 2, "durable_player_changes": 0, "real_payments": 0}
