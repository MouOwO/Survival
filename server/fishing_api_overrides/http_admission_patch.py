"""Exact-source bounded HTTP admission experiment, preparation only.

Pool-v2 -> optional checkpoint observation -> admission. No business changes,
new identity paths, SQL/HTTP retry, payload logging, or unbounded user queue.
"""
from __future__ import annotations
import ast
import hashlib
from pathlib import Path

KEYS = ('fishing_api/server.py', 'player_web_auth/http_api.py')
HELPER_PATH = 'survival_http_admission.py'
HELPER_SHA256 = 'f5470dcd73a2ff29379351aab78b9f1000e89c774ec84f85c446021e162652b8'
PARENT_PAIRS = frozenset((
    ('e49e903ff7abe51c333d2715f35911ae5b0ed2afea55867f5304a837b19ceb32',
     '138de5c50bc71f0861ed6f85f4d3d6d0a3d6399e17ff39d93f228383ae687dc2'),
    ('b04f363b3b603895a44c45e1f9b316b2ed204da1b1f11be4e713a517c94710b6',
     '66137f76d4b2eb6cfe00076714718489abdcd5375f9da81b472de6bae34eef5b'),
))
MARKER = '# SURVIVAL_BOUNDED_HTTP_ADMISSION_V1'
IMPORT_ANCHOR = 'from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer\n'
IMPORT_NEW = IMPORT_ANCHOR + MARKER + '\nfrom survival_http_admission import BoundedAdmissionMixin\n'
OLD_BACKEND = 'class BoundedThreadingHTTPServer(ThreadingHTTPServer):\n    """Bound worker threads and accepted sockets; never build an unbounded queue."""\n\n    daemon_threads = True\n    request_queue_size = 16\n    allow_reuse_address = True\n\n    def __init__(self, address: tuple[str, int], handler: type[BaseHTTPRequestHandler],\n                 *, max_concurrency: int = 8):\n        if address[0] not in {"127.0.0.1", "localhost", "::1"}:\n            raise ConfigError("HTTP listener must be loopback-only")\n        if type(max_concurrency) is not int or not 1 <= max_concurrency <= 32:\n            raise ConfigError("HTTP concurrency must be between 1 and 32")\n        if address[0] == "::1":\n            self.address_family = socket.AF_INET6\n        self._worker_limit = max_concurrency\n        self._workers = threading.BoundedSemaphore(max_concurrency)\n        super().__init__(address, handler)\n\n    def process_request(self, request: socket.socket, client_address: Any) -> None:\n        if not self._workers.acquire(blocking=False):\n            body = b\'{"ok":false,"error":"server_busy"}\'\n            try:\n                request.settimeout(0.05)\n                request.sendall(b"HTTP/1.0 503 Service Unavailable\\r\\n"\n                                b"Connection: close\\r\\nContent-Type: application/json\\r\\n"\n                                b"Content-Length: " + str(len(body)).encode() + b"\\r\\n\\r\\n" + body)\n            except OSError:\n                pass\n            self.shutdown_request(request)\n            return\n        try:\n            super().process_request(request, client_address)\n        except Exception:\n            self._workers.release()\n            self.shutdown_request(request)\n\n    def process_request_thread(self, request: socket.socket, client_address: Any) -> None:\n        try:\n            super().process_request_thread(request, client_address)\n        finally:\n            self._workers.release()\n\n    def handle_error(self, request: Any, client_address: Any) -> None:\n        # Socket parsing errors must not print headers, request paths, or a\n        # traceback containing driver responses or authentication information.\n        logger.error("http_connection_failed")\n'
NEW_BACKEND = 'class BoundedThreadingHTTPServer(BoundedAdmissionMixin, ThreadingHTTPServer):\n    """Bound workers, one acceptor wait, and a fixed kernel socket backlog."""\n    daemon_threads = True\n    request_queue_size = 64\n    allow_reuse_address = True\n\n    def __init__(self, address: tuple[str, int], handler: type[BaseHTTPRequestHandler],\n                 *, max_concurrency: int = 8, request_backlog: int = 64,\n                 admission_wait_seconds: float = 2.0):\n        if address[0] not in {"127.0.0.1", "localhost", "::1"}:\n            raise ConfigError("HTTP listener must be loopback-only")\n        if type(max_concurrency) is not int or not 1 <= max_concurrency <= 32:\n            raise ConfigError("HTTP concurrency must be between 1 and 32")\n        if address[0] == "::1":\n            self.address_family = socket.AF_INET6\n        self._configure_admission(layer=\'backend\', max_concurrency=max_concurrency,\n            request_backlog=request_backlog, admission_wait_seconds=admission_wait_seconds)\n        self._worker_limit = max_concurrency\n        self._workers = self._admission_slots\n        super().__init__(address, handler)\n\n    def handle_error(self, request: Any, client_address: Any) -> None:\n        logger.error("http_connection_failed")'
OLD_FRONT = 'class BoundedServer(ThreadingHTTPServer):\n    daemon_threads = True\n    request_queue_size = 16\n\n    def __init__(self, address, request_handler):\n        self.slots = threading.BoundedSemaphore(24)\n        super().__init__(address, request_handler)\n\n    def process_request(self, request, address):\n        if not self.slots.acquire(blocking=False):\n            self.shutdown_request(request)\n            return\n        try:\n            super().process_request(request, address)\n        except BaseException:\n            self.slots.release()\n            raise\n\n    def process_request_thread(self, request, address):\n        try:\n            super().process_request_thread(request, address)\n        finally:\n            self.slots.release()\n\n    def handle_error(self, request, address):\n        # BaseServer prints tracebacks including context; keep this service quiet.\n        pass\n'
NEW_FRONT = "class BoundedServer(BoundedAdmissionMixin, ThreadingHTTPServer):\n    daemon_threads = True\n    request_queue_size = 64\n\n    def __init__(self, address, request_handler, *, max_concurrency=24, request_backlog=64):\n        self._configure_admission(layer='frontend', max_concurrency=max_concurrency,\n                                  request_backlog=request_backlog)\n        self.slots = self._admission_slots\n        super().__init__(address, request_handler)\n\n    def handle_error(self, request, address):\n        # Keep headers, payloads, paths and exception context private.\n        pass"
OLD_DEADLINE = '            self._database_deadline_until = time.monotonic() + request_deadline\n            self._deadline = threading.Timer(request_deadline, expire)\n'
NEW_DEADLINE = "            # The acceptor's bounded wait is part of the original lifetime.\n            # Generic HTTPServer callers have no admission wait to subtract.\n            accepted_at = (self.server.request_started_at(self.request)\n                           if hasattr(self.server, 'request_started_at') else time.monotonic())\n            self._database_deadline_until = accepted_at + request_deadline\n            remaining = max(0, self._database_deadline_until - time.monotonic())\n            self._deadline = threading.Timer(remaining, expire)\n"


def _normalized(source):
    if type(source) is not str:
        raise ValueError('http_admission_source_invalid')
    result = source.replace('\r\n', '\n')
    if '\r' in result:
        raise ValueError('http_admission_source_invalid')
    return result


def _sha(source):
    return hashlib.sha256(source.encode('utf8')).hexdigest()


def _replace(source, before, after):
    if source.count(before) != 1:
        raise ValueError('http_admission_anchor_invalid')
    return source.replace(before, after, 1)


def _apply(key, source):
    result = _replace(source, IMPORT_ANCHOR, IMPORT_NEW)
    if key == KEYS[0]:
        result = _replace(result, OLD_BACKEND, NEW_BACKEND)
        result = _replace(result, OLD_DEADLINE, NEW_DEADLINE)
    else:
        result = _replace(result, OLD_FRONT, NEW_FRONT)
    return result


def _restore(key, source):
    if source.count(MARKER) != 1:
        raise ValueError('http_admission_marker_invalid')
    if key == KEYS[0]:
        result = _replace(source, NEW_DEADLINE, OLD_DEADLINE)
        result = _replace(result, NEW_BACKEND, OLD_BACKEND)
    else:
        result = _replace(source, NEW_FRONT, OLD_FRONT)
    return _replace(result, IMPORT_NEW, IMPORT_ANCHOR)


def patch_sources(sources):
    """Input exactly two reviewed parents; emit those files and one helper.

    Two whole-source pairs are admitted. A mixed observed/unobserved pair,
    changed helper, partial patch, or any unrelated byte drift is rejected.
    Runtime never loads this preparation operator.
    """
    if type(sources) is not dict or set(sources) != set(KEYS):
        raise ValueError('http_admission_source_set_invalid')
    normalized = {key: _normalized(sources[key]) for key in KEYS}
    marked = [MARKER in normalized[key] for key in KEYS]
    if any(marked) and not all(marked):
        raise ValueError('http_admission_partial_patch')
    parents = ({key: _restore(key, normalized[key]) for key in KEYS}
               if all(marked) else normalized)
    if tuple(_sha(parents[key]) for key in KEYS) not in PARENT_PAIRS:
        raise ValueError('http_admission_parent_pair_mismatch')
    try:
        helper = _normalized(Path(__file__).with_name('http_admission.py').read_text(encoding='utf-8-sig'))
    except (OSError, UnicodeError):
        raise ValueError('http_admission_helper_unavailable') from None
    if _sha(helper) != HELPER_SHA256:
        raise ValueError('http_admission_helper_changed')
    result = {key: _apply(key, parents[key]) for key in KEYS}
    for key in KEYS:
        restored = _restore(key, result[key])
        if restored != parents[key] or ast.dump(ast.parse(restored)) != ast.dump(ast.parse(parents[key])):
            raise ValueError('http_admission_unrelated_change')
        if all(marked) and normalized[key] != result[key]:
            raise ValueError('http_admission_patched_source_changed')
        compile(result[key], '<reviewed-http-admission>', 'exec')
    compile(helper, '<reviewed-http-admission-helper>', 'exec')
    return dict(result, **{HELPER_PATH: helper})
