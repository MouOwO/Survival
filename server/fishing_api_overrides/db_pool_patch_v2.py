"""Add bounded pool configuration to the exact reviewed v1 transport.

The historical v1 overlay and helper remain unchanged. This preparation-only
operator loads its sibling v1 operator by pinned digest, then applies only
declared signature/validation/wiring substitutions. It performs no network or
database calls. Runtime defaults remain four waiters and two seconds.
"""
from __future__ import annotations

import ast
import hashlib
from functools import lru_cache
from pathlib import Path


BASELINE_SHA256 = "12b2890f0b6bfa01a8b4372cd819f7556de133867f551428086eafe2759fcf3b"
V1_OPERATOR_SHA256 = "e3761d13fd5ba005d0ea29dda9ff1cdc85706d9ded34aa4495a6e1831b4d03d4"
V1_POSTGRES_SHA256 = "6e9e758142794716ed58801c9e9a76528cb49463cc7df0416f04adfb6c106402"
V1_SERVER_SHA256 = "40ea346963343522775f988bb80c5dc947a076865393fdc586d3588d61ea643f"
POSTGRES_MARKER = "# SURVIVAL_BOUNDED_DB_POOL_CONFIG_V2"
SERVER_MARKER = "# SURVIVAL_BOUNDED_DB_POOL_BUILD_CONFIG_V2"


POSTGRES_REPLACEMENTS = (
    ('                 max_concurrency: int = 4, connector: Callable[..., Any] | None = None):\n',
     '                 max_concurrency: int = 4, connector: Callable[..., Any] | None = None,\n'
     '                 pool_max_waiters: int = 4, pool_wait_timeout: float = 2.0):\n'),
    ('                and type(max_concurrency) is int and 1 <= max_concurrency <= 16):\n',
     '                and type(max_concurrency) is int and 1 <= max_concurrency <= 16\n'
     '                and type(pool_max_waiters) is int and 0 <= pool_max_waiters <= 32\n'
     '                and type(pool_wait_timeout) in (int, float)\n'
     '                and 0 < pool_wait_timeout <= 5):\n'),
    ('            max_waiters=4, wait_timeout=2.0, reusable=self._connection_reusable)\n',
     '            # SURVIVAL_BOUNDED_DB_POOL_CONFIG_V2\n'
     '            max_waiters=pool_max_waiters, wait_timeout=pool_wait_timeout,\n'
     '            reusable=self._connection_reusable)\n'),
)

SERVER_REPLACEMENTS = (
    ('def build_application(settings: Settings) -> FishingApplication:\n',
     '# SURVIVAL_BOUNDED_DB_POOL_BUILD_CONFIG_V2\n'
     'def build_application(settings: Settings, *, pool_max_waiters: int = 4,\n'
     '                      pool_wait_timeout: float = 2.0) -> FishingApplication:\n'),
    ('            max_concurrency=settings.postgres_max_concurrency,\n',
     '            max_concurrency=settings.postgres_max_concurrency,\n'
     '            pool_max_waiters=pool_max_waiters, pool_wait_timeout=pool_wait_timeout,\n'),
)


def _digest(source: str) -> str:
    return hashlib.sha256(source.encode("utf8")).hexdigest()


def _normalized(source: str) -> str:
    if type(source) is not str:
        raise ValueError("db_pool_v2_source_invalid")
    source = source.replace("\r\n", "\n")
    if "\r" in source:
        raise ValueError("db_pool_v2_source_invalid")
    return source


@lru_cache(maxsize=1)
def _v1_patcher():
    parent_path = Path(__file__).with_name("db_pool_patch.py")
    try:
        source = _normalized(parent_path.read_text(encoding="utf-8-sig"))
    except (OSError, UnicodeError):
        raise ValueError("db_pool_v2_parent_operator_unavailable") from None
    if _digest(source) != V1_OPERATOR_SHA256:
        raise ValueError("db_pool_v2_parent_operator_changed")
    namespace = {"__name__": "survival_reviewed_v1_db_pool_parent",
                 "__file__": str(parent_path)}
    exec(compile(source, str(parent_path), "exec"), namespace)
    return namespace["patch_postgres"]


def _replace_all(source: str, replacements, *, reverse: bool = False) -> str:
    pairs = ((new, old) for old, new in reversed(replacements)) if reverse else replacements
    result = source
    for old, new in pairs:
        if result.count(old) != 1:
            raise ValueError("db_pool_v2_patch_anchor_invalid")
        result = result.replace(old, new, 1)
    return result


def patch_postgres(source: str) -> str:
    """Accept the exact original snapshot or this exact v2 output, nothing else."""
    source = _normalized(source)
    if POSTGRES_MARKER in source:
        restored = _replace_all(source, POSTGRES_REPLACEMENTS, reverse=True)
        if _digest(restored) != V1_POSTGRES_SHA256 or _v1_patcher()(restored) != restored:
            raise ValueError("db_pool_v2_postgres_patched_source_changed")
        if _replace_all(restored, POSTGRES_REPLACEMENTS) != source:
            raise ValueError("db_pool_v2_postgres_patched_source_changed")
        return source
    if _digest(source) != BASELINE_SHA256:
        raise ValueError("db_pool_v2_postgres_source_baseline_mismatch")
    parent = _v1_patcher()(source)
    if _digest(parent) != V1_POSTGRES_SHA256:
        raise ValueError("db_pool_v2_postgres_parent_output_changed")
    result = _replace_all(parent, POSTGRES_REPLACEMENTS)
    if _replace_all(result, POSTGRES_REPLACEMENTS, reverse=True) != parent:
        raise ValueError("db_pool_v2_postgres_unrelated_change")
    ast.parse(result)
    compile(result, "<bounded-db-pool-v2-overlay>", "exec")
    return result


def patch_server(source: str) -> str:
    """Wire explicit build keywords after the exact v1 HTTP integration."""
    source = _normalized(source)
    if SERVER_MARKER in source:
        restored = _replace_all(source, SERVER_REPLACEMENTS, reverse=True)
        if (_digest(restored) != V1_SERVER_SHA256
                or _replace_all(restored, SERVER_REPLACEMENTS) != source):
            raise ValueError("db_pool_v2_server_patched_source_changed")
        return source
    if _digest(source) != V1_SERVER_SHA256:
        raise ValueError("db_pool_v2_server_parent_mismatch")
    result = _replace_all(source, SERVER_REPLACEMENTS)
    if _replace_all(result, SERVER_REPLACEMENTS, reverse=True) != source:
        raise ValueError("db_pool_v2_server_unrelated_change")
    ast.parse(result)
    compile(result, "<bounded-db-pool-v2-server-overlay>", "exec")
    return result
