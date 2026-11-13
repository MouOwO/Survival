"""Exact-source overlay for the reviewed PostgreSQL transport snapshot.

This does not deploy or connect anywhere. The operator must copy bounded_pool.py
as fishing_api/_bounded_pool.py alongside the returned transport. No database
RPC signature, SQL permission guard, result check or transaction boundary is
removed. Frozen historical source snapshots must remain unchanged.
"""
from __future__ import annotations

import ast
import hashlib


BASELINE_SHA256 = "12b2890f0b6bfa01a8b4372cd819f7556de133867f551428086eafe2759fcf3b"
MARKER = "# SURVIVAL_BOUNDED_DB_POOL_V1"

_TRANSACTION = '''    def _transaction(self, query: Any, parameters: tuple[Any, ...], *, probe: bool = False) -> Any:
        if not self._slots.acquire(blocking=False):
            raise DatabaseError("database_busy")
        connection = None
        try:
            with measure("db_connect"):
                connection = self._connect(self._dsn, **self._connect_options)
            with connection.cursor() as cursor:
                with measure("db_guard"):
                    self._check_runtime(cursor)
                with measure("db_query"):
                    cursor.execute(query, parameters)
                    row = cursor.fetchone()
                result = row[0] if row and len(row) == 1 else None
                if probe:
                    if result != 1:
                        raise DatabaseError("database_response_invalid")
                elif not isinstance(result, (dict, list)):
                    raise DatabaseError("database_response_invalid")
            with measure("db_commit"):
                connection.commit()
            return result
        except Exception as exc:
            if connection is not None:
                try:
                    with measure("db_rollback"):
                        connection.rollback()
                except Exception:
                    pass
            if isinstance(exc, DatabaseError):
                raise exc from None
            raise DatabaseError() from None
        finally:
            if connection is not None:
                try:
                    with measure("db_close"):
                        connection.close()
                except Exception:
                    pass
            self._slots.release()
'''

_POOLED_TRANSACTION = '''    @staticmethod
    def _connection_reusable(connection: Any) -> bool:
        return (connection.closed is False and connection.broken is False
                and connection.info.transaction_status == 0
                and connection.autocommit is False)

    @staticmethod
    def _ensure_deadline() -> None:
        if remaining_budget() == 0.0:
            raise DatabaseError("database_timeout")

    def _open_connection(self) -> Any:
        with measure("db_connect"):
            return self._connect(self._dsn, **self._connect_options)

    def _reset_connection(self, connection: Any) -> None:
        # Commit has succeeded. Reset outside a transaction, clearing session
        # GUCs, advisory locks, LISTEN, temp objects and server prepared plans.
        # Automatic psycopg preparation is disabled when opening connections.
        if not self._connection_reusable(connection):
            raise DatabaseError("database_unavailable")
        connection.autocommit = True
        try:
            with connection.cursor() as cursor:
                self._ensure_deadline()
                cursor.execute("DISCARD ALL")
                self._ensure_deadline()
                cursor.execute(
                    "SELECT pg_catalog.set_config('statement_timeout', %s, false), "
                    "pg_catalog.set_config('lock_timeout', %s, false), "
                    "pg_catalog.set_config('idle_in_transaction_session_timeout', %s, false), "
                    "pg_catalog.set_config('search_path', %s, false), "
                    "pg_catalog.set_config('application_name', %s, false)",
                    self._reset_options)
        finally:
            connection.autocommit = False
        if not self._connection_reusable(connection):
            raise DatabaseError("database_unavailable")

    def pool_stats(self) -> dict[str, int | float | bool]:
        return self._pool.stats()

    def close(self) -> None:
        self._pool.close()

    def _transaction(self, query: Any, parameters: tuple[Any, ...], *, probe: bool = False) -> Any:
        connection = None
        committed = False
        try:
            with measure("db_pool_wait"):
                connection = self._pool.acquire()
            self._ensure_deadline()
            with connection.cursor() as cursor:
                with measure("db_guard"):
                    self._check_runtime(cursor)
                self._ensure_deadline()
                with measure("db_query"):
                    cursor.execute(query, parameters)
                    row = cursor.fetchone()
                result = row[0] if row and len(row) == 1 else None
                if probe:
                    if result != 1:
                        raise DatabaseError("database_response_invalid")
                elif not isinstance(result, (dict, list)):
                    raise DatabaseError("database_response_invalid")
            self._ensure_deadline()
            with measure("db_commit"):
                connection.commit()
            committed = True
            return result
        except Exception as exc:
            if connection is not None:
                try:
                    with measure("db_rollback"):
                        connection.rollback()
                except Exception:
                    pass
            if isinstance(exc, DatabaseError):
                raise exc from None
            if isinstance(exc, PoolError):
                raise DatabaseError(exc.code) from None
            if getattr(exc, "sqlstate", None) in {"57014", "55P03"}:
                raise DatabaseError("database_timeout") from None
            raise DatabaseError() from None
        finally:
            if connection is not None:
                reusable = False
                try:
                    if committed and remaining_budget() != 0.0:
                        try:
                            with measure("db_reset"):
                                self._reset_connection(connection)
                            reusable = True
                        except Exception:
                            # Cleanup after a known commit must never turn a
                            # successful write into an ambiguous client error.
                            self._pool.note_reset_failed()
                finally:
                    self._pool.release(connection, reusable=reusable)
'''

_POOL_INIT = '''        # SURVIVAL_BOUNDED_DB_POOL_V1
        self._reset_options = (
            str(statement_timeout_ms), str(lock_timeout_ms),
            str(statement_timeout_ms + 1000), "pg_catalog", "goufayu-fishing-api")
        self._pool = BoundedConnectionPool(
            self._open_connection, max_size=max_concurrency,
            max_waiters=4, wait_timeout=2.0, reusable=self._connection_reusable)
'''

_REPLACEMENTS = (
    ('from .supabase import SupabaseError\n',
     'from .supabase import SupabaseError\nfrom ._bounded_pool import BoundedConnectionPool, PoolError, remaining_budget\n'),
    ('        self._slots = threading.BoundedSemaphore(max_concurrency)\n', ''),
    ('            "connect_timeout": connect_timeout, "autocommit": False,\n',
     '            "connect_timeout": connect_timeout, "autocommit": False,\n            "prepare_threshold": None,\n'),
    ('        }\n\n    def __repr__(self) -> str:\n',
     '        }\n' + _POOL_INIT + '\n    def __repr__(self) -> str:\n'),
    ('        with measure("db_function_guard"):\n',
     '        self._ensure_deadline()\n        with measure("db_function_guard"):\n'),
    (_TRANSACTION, _POOLED_TRANSACTION),
)


def _digest(source: str) -> str:
    return hashlib.sha256(source.encode("utf-8")).hexdigest()


def patch_postgres(source: str) -> str:
    """Apply only to the reviewed full source; exact repeat application is safe."""
    if not isinstance(source, str):
        raise ValueError("db_pool_source_invalid")
    source = source.replace("\r\n", "\n")
    if MARKER in source:
        original = source
        for old, new in reversed(_REPLACEMENTS):
            if not new:
                # The deleted semaphore is restored at its original constructor
                # boundary, which remains unambiguous after reversing later edits.
                anchor = '        self._connect_options = {\n'
                if original.count(anchor) != 1:
                    raise ValueError("db_pool_partial_patch")
                original = original.replace(anchor, old + anchor, 1)
            else:
                if original.count(new) != 1:
                    raise ValueError("db_pool_partial_patch")
                original = original.replace(new, old, 1)
        if _digest(original) != BASELINE_SHA256 or patch_postgres(original) != source:
            raise ValueError("db_pool_changed_patch")
        return source
    if _digest(source) != BASELINE_SHA256:
        raise ValueError("db_pool_unreviewed_source")
    output = source
    for old, new in _REPLACEMENTS:
        if output.count(old) != 1:
            raise ValueError("db_pool_anchor_invalid")
        output = output.replace(old, new, 1)
    ast.parse(output)
    compile(output, "<bounded-db-pool-overlay>", "exec")
    return output
