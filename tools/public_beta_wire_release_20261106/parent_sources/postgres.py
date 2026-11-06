"""Minimal-privilege, bounded PostgreSQL RPC transport (no transport retries).

Each call uses one connection and one transaction. A result leaves this module
only after COMMIT succeeds. The database owns business rules and idempotency.
"""
from __future__ import annotations

import json
import re
import threading
import uuid
from dataclasses import dataclass
from decimal import Decimal
from typing import Any, Callable

from .supabase import SupabaseError


class DatabaseError(SupabaseError):
    """Safe public code only: never attach driver diagnostics or DSN values."""

    def __init__(self, code: str = "database_unavailable", status: int = 503):
        super().__init__(code, status, "")


@dataclass(frozen=True)
class Parameter:
    name: str
    sql_type: str
    kind: str


def _params(*definitions: tuple[str, str, str]) -> tuple[Parameter, ...]:
    return tuple(Parameter(*item) for item in definitions)


# SQL identifiers and casts come exclusively from this constant, never HTTP.
RPC_SIGNATURES = {
    "sync_star_blessing_reward_definitions": _params(
        ("p_definition_version", "integer", "positive_int"),
        ("p_definition_hash", "text", "hash"), ("p_definitions", "jsonb", "array")),
    "ensure_player_gameplay_stats": _params(
        ("p_account_id", "text", "hash"), ("p_gameplay_stats", "jsonb", "object")),
    "get_fishing_profile": _params(("p_account_id", "text", "hash")),
    "grant_out_of_match_reward": _params(
        ("p_account_id", "text", "hash"), ("p_grant_id", "uuid", "uuid"),
        ("p_reward_id", "text", "reward_id"), ("p_definition_version", "integer", "positive_int"),
        ("p_amount", "numeric", "amount")),
    "checkpoint_online_time": _params(
        ("p_account_id", "text", "hash"), ("p_session_id", "text", "request_id"),
        ("p_request_id", "text", "request_id"), ("p_lease_seconds", "integer", "positive_int"),
        ("p_definition_version", "integer", "positive_int"),
        ("p_interval_min_seconds", "integer", "positive_int"),
        ("p_interval_max_seconds", "integer", "positive_int"), ("p_final", "boolean", "bool")),
    "archive_sync_config": _params(("p_hash", "text", "hash"), ("p_config", "jsonb", "object")),
    "archive_resume": _params(("p_account", "text", "hash"), ("p_id", "text", "archive_id")),
    "archive_prepare": _params(
        ("p_account", "text", "hash"), ("p_id", "text", "archive_id"),
        ("p_hash", "text", "hash"), ("p_fingerprint", "text", "hash"),
        ("p_command", "jsonb", "object")),
    "archive_commit": _params(
        ("p_account", "text", "hash"), ("p_id", "text", "archive_id"),
        ("p_revision", "bigint", "revision"), ("p_archive", "jsonb", "object"),
        ("p_deltas", "jsonb", "object"), ("p_error", "text", "nullable_error")),
    "archive_commit_lottery": _params(
        ("p_account", "text", "hash"), ("p_id", "text", "archive_id"),
        ("p_revision", "bigint", "revision"), ("p_archive", "jsonb", "object"),
        ("p_deltas", "jsonb", "object"), ("p_error", "text", "nullable_error"),
        ("p_inventory", "jsonb", "object"), ("p_response", "jsonb", "object")),
    "archive_online_pending": _params(("p_account", "text", "hash"), ("p_hash", "text", "hash")),
    "archive_pending": _params(("p_account", "text", "hash")),
    "match_profile_login": _params(("p_account", "text", "hash"),
        ("p_session", "text", "request_id"), ("p_mode", "text", "match_mode"),
        ("p_defaults", "jsonb", "object")),
    "match_profile_context": _params(("p_account", "text", "hash"),
        ("p_session", "text", "request_id")),
    # BEGIN SURVIVAL_ENDLESS_LEADERBOARD_RPC_V1
    "archive_bind_leaderboard_identity": _params(
        ("p_account", "text", "hash"),
        ("p_public_account_id", "text", "nullable_error")),
    "archive_endless_leaderboard": _params(),
    # END SURVIVAL_ENDLESS_LEADERBOARD_RPC_V1
    # BEGIN SURVIVAL_ONBOARDING_RPC_V1
    "onboarding_state": _params(("p_account", "text", "hash"),
        ("p_session", "text", "request_id")),
    "onboarding_finish": _params(("p_account", "text", "hash"),
        ("p_session", "text", "request_id"), ("p_outcome", "text", "reward_id")),
    # END SURVIVAL_ONBOARDING_RPC_V1
    # BEGIN SURVIVAL_CHALLENGE_RECEIPT_RPC_V1
    "archive_commit_challenge": _params(
        ("p_account", "text", "hash"), ("p_id", "text", "archive_id"),
        ("p_revision", "bigint", "revision"), ("p_archive", "jsonb", "object"),
        ("p_deltas", "jsonb", "object"), ("p_error", "text", "nullable_error"),
        ("p_response", "jsonb", "object")),
    # END SURVIVAL_CHALLENGE_RECEIPT_RPC_V1
    # BEGIN SURVIVAL_REDEMPTION_RPC_V1
    "redemption_prepare": _params(
        ("p_account", "text", "hash"), ("p_session", "text", "request_id"),
        ("p_code_hash", "text", "hash"), ("p_request", "text", "request_id"),
        ("p_hash", "text", "hash")),
    "redemption_commit": _params(
        ("p_account", "text", "hash"), ("p_id", "text", "archive_id"),
        ("p_revision", "bigint", "revision"), ("p_archive", "jsonb", "object"),
        ("p_deltas", "jsonb", "object"), ("p_inventory", "jsonb", "object"),
        ("p_response", "jsonb", "object")),
    # END SURVIVAL_REDEMPTION_RPC_V1
}
RUNTIME_ROLE = "goufayu_app"
_HASH = re.compile(r"[0-9a-f]{64}\Z")
_OPAQUE = re.compile(r"[A-Za-z0-9_.:-]+\Z")


def _signature(name: str, parameters: tuple[Parameter, ...]) -> str:
    return "public." + name + "(" + ",".join(p.sql_type for p in parameters) + ")"


ALLOWED_FUNCTIONS = tuple(_signature(name, parameters) for name, parameters in RPC_SIGNATURES.items())

# Check effective privileges, including PUBLIC and inherited/column privileges.
# Keep permission checks in the same transaction as the business call. This
# includes migration ledgers such as survival_data_migrations: the application
# must never gain direct access to a table merely because a migration adds it.
_RUNTIME_CHECK = """
SELECT current_user::text, session_user::text, current_database()::text,
       r.rolsuper OR r.rolcreatedb OR r.rolcreaterole OR r.rolreplication OR r.rolbypassrls,
       has_database_privilege(current_database(), 'CREATE') OR
       has_database_privilege(current_database(), 'TEMP'),
       EXISTS (SELECT 1 FROM pg_roles other WHERE other.oid <> r.oid
               AND pg_has_role(r.oid, other.oid, 'MEMBER')),
       EXISTS (SELECT 1 FROM pg_namespace n
               WHERE n.nspname !~ '^pg_' AND n.nspname <> 'information_schema'
               AND has_schema_privilege(n.oid, 'CREATE')),
       EXISTS (SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
               WHERE n.nspname !~ '^pg_' AND n.nspname <> 'information_schema'
               AND c.relkind IN ('r','p','v','m','f')
               AND (c.relowner = r.oid OR has_table_privilege(c.oid,
                    'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER')
                    OR has_any_column_privilege(c.oid, 'SELECT,INSERT,UPDATE,REFERENCES'))),
       EXISTS (SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
               WHERE n.nspname !~ '^pg_' AND n.nspname <> 'information_schema'
               AND c.relkind = 'S' AND (c.relowner = r.oid
                    OR has_sequence_privilege(c.oid, 'USAGE,SELECT,UPDATE'))),
       EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
               WHERE n.nspname !~ '^pg_' AND n.nspname <> 'information_schema'
               AND (p.proowner = r.oid OR (has_schema_privilege(n.oid, 'USAGE')
                    AND has_function_privilege(p.oid, 'EXECUTE')
                    AND NOT (p.oid = ANY(ARRAY(SELECT to_regprocedure(s)::oid
                                              FROM unnest(%s::text[]) s))))))
FROM pg_roles r WHERE r.rolname = current_user
"""
_FUNCTION_CHECK = """
SELECT s, p.oid IS NOT NULL AND p.prosecdef AND p.prorettype = 'jsonb'::regtype
       AND p.proowner <> (SELECT oid FROM pg_roles WHERE rolname = current_user)
       AND has_function_privilege(p.oid, 'EXECUTE')
       AND EXISTS (SELECT 1 FROM unnest(p.proconfig) item
                   WHERE replace(item, ' ', '') = 'search_path=pg_catalog,public,extensions,pg_temp')
FROM unnest(%s::text[]) s LEFT JOIN pg_proc p ON p.oid = to_regprocedure(s)
"""


def _json_dumps(value: Any) -> str:
    return json.dumps(value, ensure_ascii=False, allow_nan=False, separators=(",", ":"))


class PostgresRpcClient:
    def __init__(self, dsn: str, *, connect_timeout: int = 3,
                 statement_timeout_ms: int = 5000, lock_timeout_ms: int = 1000,
                 max_concurrency: int = 4, connector: Callable[..., Any] | None = None):
        try:
            import psycopg
            from psycopg import sql
            from psycopg.conninfo import conninfo_to_dict
            from psycopg.types.json import Jsonb
        except ImportError:
            raise DatabaseError("postgres_driver_unavailable") from None
        try:
            info = conninfo_to_dict(dsn)
        except Exception:
            raise DatabaseError("postgres_configuration_invalid") from None
        database = info.get("dbname", "")
        # A service file is supported; resolved identity/database is always checked.
        if (not dsn or (not database and not info.get("service"))
                or database.lower() == "postgres" or database.lower().startswith("template")
                or info.get("user", RUNTIME_ROLE) != RUNTIME_ROLE
                or "," in info.get("host", "") or "," in info.get("hostaddr", "")
                or "service" in info and info["service"] != RUNTIME_ROLE):
            raise DatabaseError("postgres_configuration_invalid")
        if not (type(connect_timeout) is int and 2 <= connect_timeout <= 10
                and type(statement_timeout_ms) is int and 100 <= statement_timeout_ms <= 30000
                and type(lock_timeout_ms) is int and 1 <= lock_timeout_ms <= statement_timeout_ms
                and type(max_concurrency) is int and 1 <= max_concurrency <= 16):
            raise DatabaseError("postgres_configuration_invalid")
        self._dsn = dsn
        self._connect = connector or psycopg.connect
        self._sql = sql
        self._Jsonb = Jsonb
        self._slots = threading.BoundedSemaphore(max_concurrency)
        self._connect_options = {
            "connect_timeout": connect_timeout, "autocommit": False,
            "application_name": "goufayu-fishing-api",
            "options": (f"-c statement_timeout={statement_timeout_ms} "
                        f"-c lock_timeout={lock_timeout_ms} "
                        f"-c idle_in_transaction_session_timeout={statement_timeout_ms + 1000} "
                        "-c search_path=pg_catalog"),
        }

    def __repr__(self) -> str:
        return "PostgresRpcClient(runtime_role='goufayu_app')"

    def _convert(self, parameter: Parameter, value: Any) -> Any:
        kind = parameter.kind
        valid = False
        if kind == "hash":
            valid = isinstance(value, str) and _HASH.fullmatch(value) is not None
        elif kind == "match_mode":
            valid = value in ("pure", "standard", "rich", "cold", "scourge", "ruins", "celestial")
        elif kind in {"reward_id", "request_id", "archive_id"}:
            minimum, maximum = {"reward_id": (1, 128), "request_id": (8, 128),
                                "archive_id": (8, 200)}[kind]
            valid = (isinstance(value, str) and minimum <= len(value) <= maximum
                     and _OPAQUE.fullmatch(value) is not None)
        elif kind in {"positive_int", "revision"}:
            minimum, maximum = (1, 2**31 - 1) if kind == "positive_int" else (0, 2**63 - 1)
            valid = type(value) is int and minimum <= value <= maximum
        elif kind == "bool":
            valid = type(value) is bool
        elif kind == "uuid":
            try:
                if not isinstance(value, str):
                    raise ValueError
                return uuid.UUID(value)
            except (ValueError, AttributeError):
                pass
        elif kind == "amount":
            if type(value) in {int, float, Decimal}:
                amount = Decimal(str(value))
                if amount.is_finite() and amount >= 0:
                    return amount
        elif kind == "nullable_error":
            valid = value is None or (isinstance(value, str) and len(value) <= 512 and "\x00" not in value)
        elif kind in {"array", "object"}:
            if isinstance(value, list if kind == "array" else dict):
                try:
                    encoded = _json_dumps(value)
                    if len(encoded.encode("utf-8")) <= 4_000_000:
                        return self._Jsonb(value, dumps=_json_dumps)
                except (ValueError, TypeError, OverflowError, RecursionError):
                    pass
        if not valid:
            raise DatabaseError("database_rpc_parameters_invalid", 400)
        return value

    def _check_runtime(self, cursor: Any) -> None:
        cursor.execute(_RUNTIME_CHECK, (list(ALLOWED_FUNCTIONS),))
        row = cursor.fetchone()
        if (not row or len(row) != 10 or row[0] != RUNTIME_ROLE or row[1] != RUNTIME_ROLE
                or not isinstance(row[2], str) or row[2].lower() == "postgres"
                or row[2].lower().startswith("template") or any(row[3:])):
            raise DatabaseError("database_runtime_role_invalid")
        cursor.execute(_FUNCTION_CHECK, (list(ALLOWED_FUNCTIONS),))
        functions = cursor.fetchall()
        if (len(functions) != len(ALLOWED_FUNCTIONS)
                or {row[0] for row in functions} != set(ALLOWED_FUNCTIONS)
                or any(row[1] is not True for row in functions)):
            raise DatabaseError("database_rpc_permissions_invalid")

    def _transaction(self, query: Any, parameters: tuple[Any, ...], *, probe: bool = False) -> Any:
        if not self._slots.acquire(blocking=False):
            raise DatabaseError("database_busy")
        connection = None
        try:
            connection = self._connect(self._dsn, **self._connect_options)
            with connection.cursor() as cursor:
                self._check_runtime(cursor)
                cursor.execute(query, parameters)
                row = cursor.fetchone()
                result = row[0] if row and len(row) == 1 else None
                if probe:
                    if result != 1:
                        raise DatabaseError("database_response_invalid")
                elif not isinstance(result, (dict, list)):
                    raise DatabaseError("database_response_invalid")
            connection.commit()
            return result
        except Exception as exc:
            if connection is not None:
                try:
                    connection.rollback()
                except Exception:
                    pass
            if isinstance(exc, DatabaseError):
                raise exc from None
            raise DatabaseError() from None
        finally:
            if connection is not None:
                try:
                    connection.close()
                except Exception:
                    pass
            self._slots.release()

    def ready(self) -> bool:
        self._transaction("SELECT 1", (), probe=True)
        return True

    def rpc(self, function_name: str, payload: dict[str, Any]) -> Any:
        if not isinstance(function_name, str) or function_name not in RPC_SIGNATURES:
            raise DatabaseError("database_rpc_not_allowed", 400)
        signature = RPC_SIGNATURES[function_name]
        if not isinstance(payload, dict) or set(payload) != {p.name for p in signature}:
            raise DatabaseError("database_rpc_parameters_invalid", 400)
        values = tuple(self._convert(parameter, payload[parameter.name]) for parameter in signature)
        arguments = self._sql.SQL(", ").join(
            self._sql.SQL("{} => %s::{}").format(
                self._sql.Identifier(p.name), self._sql.SQL(p.sql_type)) for p in signature)
        query = self._sql.SQL("SELECT {}.{}({})").format(
            self._sql.Identifier("public"), self._sql.Identifier(function_name), arguments)
        return self._transaction(query, values)
