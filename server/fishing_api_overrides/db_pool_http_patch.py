"""Apply the reviewed bounded-database HTTP integration to one frozen source.

The HTTP error body contains only fixed public codes. A busy/timeout response
does not prove an entire command was unwritten: earlier RPCs may have committed.
There are no HTTP or database retries in this overlay.

The connection lifetime already has a socket timer. The same absolute deadline
is exposed to the pool only while GET/POST runs, so header/body time counts and
thread reuse cannot inherit another request's context.
"""
from __future__ import annotations

import argparse
import ast
import hashlib
from pathlib import Path


BASELINE_SHA256 = "0e51a360c2830d3a812537e28bad1475b9f000bea939da7b98cc7025a78af9d5"
TIMING_BASELINE_SHA256 = "2bb49b61eddca2ce82ac969869399d66f16e22940f35194a49a6ecb8506efda6"
MARKER = "# SURVIVAL_BOUNDED_DATABASE_HTTP_V1"

IMPORT_ANCHOR = "from .supabase import SupabaseError, SupabaseRpcClient\n"
IMPORT_ADDITION = """
# SURVIVAL_BOUNDED_DATABASE_HTTP_V1
import time
from functools import wraps
from ._bounded_pool import request_deadline as _database_request_deadline
"""

FUNCTION_ANCHOR = "\ndef _database_ready(client: Any) -> bool:\n"
FUNCTION_ADDITION = '''
def _database_error_code(error: SupabaseError) -> str:
    # Do not stringify exceptions: driver diagnostics and DSNs stay private.
    code = getattr(error, "code", None)
    if type(code) is str and code in {
            "database_busy", "database_timeout", "database_unavailable"}:
        return code
    return "database_unavailable"


def _bounded_database_request(function):
    @wraps(function)
    def bounded(handler, *args, **kwargs):
        with _database_request_deadline(handler._database_deadline_until):
            return function(handler, *args, **kwargs)
    return bounded


def _drain_database_requests(server, timeout: float = 45) -> bool:
    # Only shutdown walks the fixed worker budget (at most 32), never players.
    # server_close does not join daemon request threads, so wait for their
    # existing semaphore leases before stopping a multi-RPC command's pool.
    until = time.monotonic() + timeout
    acquired = 0
    try:
        for _ in range(server._worker_limit):
            if not server._workers.acquire(timeout=max(0, until - time.monotonic())):
                return False
            acquired += 1
        return True
    finally:
        for _ in range(acquired):
            server._workers.release()

'''

REPLACEMENTS = (
    ("        self._workers = threading.BoundedSemaphore(max_concurrency)\n",
     "        self._worker_limit = max_concurrency\n"
     "        self._workers = threading.BoundedSemaphore(max_concurrency)\n"),
    ("            self._deadline = threading.Timer(request_deadline, expire)\n",
     "            self._database_deadline_until = time.monotonic() + request_deadline\n"
     "            self._deadline = threading.Timer(request_deadline, expire)\n"),
    ("        def do_GET(self) -> None:\n",
     "        @_bounded_database_request\n        def do_GET(self) -> None:\n"),
    ("        @request_span\n        def do_POST(self) -> None:\n",
     "        @_bounded_database_request\n        @request_span\n"
     "        def do_POST(self) -> None:\n"),
    ("                except Exception:\n"
     "                    logger.error(\"database_readiness_failed\")\n"
     "                    self._send(503, {\"ok\": False, \"error\": \"database_unavailable\"})\n",
     "                except SupabaseError as exc:\n"
     "                    code = _database_error_code(exc)\n"
     "                    logger.error(\"database_readiness_failed code=%s\", code)\n"
     "                    self._send(503, {\"ok\": False, \"error\": code})\n"
     "                except Exception:\n"
     "                    logger.error(\"database_readiness_failed\")\n"
     "                    self._send(503, {\"ok\": False, \"error\": \"database_unavailable\"})\n"),
    ("            except SupabaseError as exc:\n"
     "                logger.error(\"database_request_failed\")\n"
     "                self._send(503, {\"ok\": False, \"error\": \"database_unavailable\"})\n",
     "            except SupabaseError as exc:\n"
     "                code = _database_error_code(exc)\n"
     "                logger.error(\"database_request_failed code=%s\", code)\n"
     "                self._send(503, {\"ok\": False, \"error\": code})\n"),
    ("    finally:\n        server.server_close()\n    return 0\n",
     "    finally:\n        server.server_close()\n"
     "        drained = _drain_database_requests(server)\n"
     "        if drained:\n"
     "            close = getattr(application.rpc_client, \"close\", None)\n"
     "            if callable(close):\n                close()\n"
     "        else:\n"
     "            logger.error(\"database_shutdown_requests_pending\")\n"
     "    return 0 if drained else 2\n"),
)

_TIMING_OLD = "                    'db_query', 'db_commit', 'db_rollback', 'db_close'))"
_TIMING_NEW = ("                    'db_query', 'db_commit', 'db_rollback', 'db_close',\n"
               "                    'db_pool_wait', 'db_reset'))")


def _digest(source: str) -> str:
    return hashlib.sha256(source.encode("utf-8")).hexdigest()


def _replace_once(source: str, before: str, after: str) -> str:
    if source.count(before) != 1:
        raise ValueError("db_pool_http_patch_anchor_invalid")
    return source.replace(before, after, 1)


def _apply(source: str) -> str:
    result = _replace_once(source, IMPORT_ANCHOR, IMPORT_ANCHOR + IMPORT_ADDITION)
    result = _replace_once(result, FUNCTION_ANCHOR, FUNCTION_ADDITION + FUNCTION_ANCHOR)
    for before, after in REPLACEMENTS:
        result = _replace_once(result, before, after)
    return result


def _restore(source: str) -> str:
    result = source
    for before, after in reversed(REPLACEMENTS):
        result = _replace_once(result, after, before)
    result = _replace_once(result, FUNCTION_ADDITION + FUNCTION_ANCHOR, FUNCTION_ANCHOR)
    return _replace_once(result, IMPORT_ANCHOR + IMPORT_ADDITION, IMPORT_ANCHOR)


def patch_server(source: str) -> str:
    """Reject drift/partial patches; applying the exact patch twice is stable."""
    if type(source) is not str or "\r" in source:
        raise ValueError("db_pool_http_source_invalid")
    if MARKER in source:
        if source.count(MARKER) != 1:
            raise ValueError("db_pool_http_patch_marker_invalid")
        original = _restore(source)
        if _digest(original) != BASELINE_SHA256 or _apply(original) != source:
            raise ValueError("db_pool_http_patched_source_changed")
        return source
    if _digest(source) != BASELINE_SHA256:
        raise ValueError("db_pool_http_source_baseline_mismatch")
    before = ast.parse(source)
    result = _apply(source)
    # Reversing only declared substitutions must recover the entire source and
    # AST. Exact-byte baseline and round-trip checks also protect comments/code
    # outside the intentionally changed handler/deadline/error boundaries.
    restored = _restore(result)
    if restored != source or ast.dump(before) != ast.dump(ast.parse(restored)):
        raise ValueError("db_pool_http_unrelated_change")
    compile(result, "<bounded-database-http-overlay>", "exec")
    return result


def patch_timing(source: str) -> str:
    """Admit only two fixed counters; all logging limits/privacy stay intact."""
    if type(source) is not str or "\r" in source:
        raise ValueError("db_pool_timing_source_invalid")
    if _TIMING_NEW in source:
        original = _replace_once(source, _TIMING_NEW, _TIMING_OLD)
        if _digest(original) != TIMING_BASELINE_SHA256:
            raise ValueError("db_pool_timing_changed_patch")
        return source
    if _digest(source) != TIMING_BASELINE_SHA256:
        raise ValueError("db_pool_timing_baseline_mismatch")
    result = _replace_once(source, _TIMING_OLD, _TIMING_NEW)
    before, after = ast.parse(source), ast.parse(result)
    # Prove the executable delta is precisely the declared STAGES literal.
    stage_nodes = [node for node in after.body
                   if isinstance(node, ast.Assign)
                   and len(node.targets) == 1
                   and isinstance(node.targets[0], ast.Name)
                   and node.targets[0].id == "STAGES"]
    if len(stage_nodes) != 1:
        raise ValueError("db_pool_timing_stages_layout_invalid")
    before_stage = next(node for node in before.body
                        if isinstance(node, ast.Assign)
                        and len(node.targets) == 1
                        and isinstance(node.targets[0], ast.Name)
                        and node.targets[0].id == "STAGES")
    original_value = ast.literal_eval(before_stage.value.args[0])
    actual_value = ast.literal_eval(stage_nodes[0].value.args[0])
    if actual_value != original_value + ("db_pool_wait", "db_reset"):
        raise ValueError("db_pool_timing_stages_delta_invalid")
    stage_nodes[0].value = before_stage.value
    if ast.dump(before, include_attributes=False) != ast.dump(after, include_attributes=False):
        raise ValueError("db_pool_timing_unrelated_change")
    compile(result, "<bounded-database-timing-overlay>", "exec")
    return result


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    result = patch_server(args.source.read_text(encoding="utf-8-sig"))
    # A frozen baseline/candidate is never overwritten by this entry point.
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open("x", encoding="utf-8", newline="\n") as stream:
        stream.write(result)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
