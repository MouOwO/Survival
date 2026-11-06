from __future__ import annotations

import json
import logging
import re
import socket
import sys
import threading
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from typing import Any

from .application import ApiError, FishingApplication
from .config import ConfigError, Settings
from .definitions import DefinitionError, load_definitions, load_rule
from .gameplay_stats import GameplayStatsError, load_gameplay_stats
from .supabase import SupabaseError, SupabaseRpcClient


MAX_BODY_BYTES = 16 * 1024
logger = logging.getLogger("survival_fishing_api")


def _log_checkpoint_summary(payload: dict[str, Any], response: Any,
                            http_status: int = 200) -> None:
    session_id = payload.get("session_id")
    request_id = payload.get("request_id")
    final = payload.get("final", False)
    if not isinstance(response, dict):
        logger.info(
            "checkpoint_response session_id=%s request_id=%s final=%s "
            "http_status=%s response_type=%s",
            session_id, request_id, str(final).lower(), http_status,
            type(response).__name__,
        )
        return
    grants = response.get("grants")
    if not isinstance(grants, list):
        grants = []
    reward_ids = sorted({
        str(grant.get("reward_id"))
        for grant in grants
        if isinstance(grant, dict) and grant.get("reward_id")
    })
    logger.info(
        "checkpoint_response session_id=%s request_id=%s final=%s "
        "http_status=%s elapsed_seconds=%s online_seconds_total=%s "
        "grant_count=%s reward_ids=%s",
        session_id, request_id, str(final).lower(), http_status,
        response.get("elapsed_seconds"), response.get("online_seconds_total"),
        len(grants), ",".join(reward_ids) or "none",
    )
def _database_ready(client: Any) -> bool:
    if hasattr(client, "ready"):
        return client.ready() is True
    # The legacy profile RPC inserts a player; readiness must never call it.
    # A limit-zero table query proves PostgREST can reach the database without
    # fetching player data or performing any writes.
    headers = {"apikey": client.service_key, "Accept": "application/json"}
    if not client.service_key.startswith("sb_secret_"):
        headers["Authorization"] = "Bearer " + client.service_key
    request = urllib.request.Request(
        client.base_url + "/rest/v1/star_blessing_reward_definitions?select=definition_version&limit=0",
        headers=headers, method="GET")
    try:
        with urllib.request.urlopen(request, timeout=min(client.timeout, 5)) as response:
            return response.status == 200 and response.read(1024).strip() == b"[]"
    except Exception:
        raise SupabaseError("database_unavailable", 503) from None


class BoundedThreadingHTTPServer(ThreadingHTTPServer):
    """Bound worker threads and accepted sockets; never build an unbounded queue."""

    daemon_threads = True
    request_queue_size = 16
    allow_reuse_address = True

    def __init__(self, address: tuple[str, int], handler: type[BaseHTTPRequestHandler],
                 *, max_concurrency: int = 8):
        if address[0] not in {"127.0.0.1", "localhost", "::1"}:
            raise ConfigError("HTTP listener must be loopback-only")
        if type(max_concurrency) is not int or not 1 <= max_concurrency <= 32:
            raise ConfigError("HTTP concurrency must be between 1 and 32")
        if address[0] == "::1":
            self.address_family = socket.AF_INET6
        self._workers = threading.BoundedSemaphore(max_concurrency)
        super().__init__(address, handler)

    def process_request(self, request: socket.socket, client_address: Any) -> None:
        if not self._workers.acquire(blocking=False):
            body = b'{"ok":false,"error":"server_busy"}'
            try:
                request.settimeout(0.05)
                request.sendall(b"HTTP/1.0 503 Service Unavailable\r\n"
                                b"Connection: close\r\nContent-Type: application/json\r\n"
                                b"Content-Length: " + str(len(body)).encode() + b"\r\n\r\n" + body)
            except OSError:
                pass
            self.shutdown_request(request)
            return
        try:
            super().process_request(request, client_address)
        except Exception:
            self._workers.release()
            self.shutdown_request(request)

    def process_request_thread(self, request: socket.socket, client_address: Any) -> None:
        try:
            super().process_request_thread(request, client_address)
        finally:
            self._workers.release()

    def handle_error(self, request: Any, client_address: Any) -> None:
        # Socket parsing errors must not print headers, request paths, or a
        # traceback containing driver responses or authentication information.
        logger.error("http_connection_failed")


def make_handler(application: FishingApplication, *, client_timeout: float = 5,
                 request_deadline: float = 20) -> type[BaseHTTPRequestHandler]:
    class Handler(BaseHTTPRequestHandler):
        server_version = "SurvivalFishingAPI/1"

        def setup(self) -> None:
            self.request.settimeout(client_timeout)
            super().setup()
            # A per-read timeout alone permits a client to hold a worker forever
            # by sending one byte before every timeout. Bound total lifetime too.
            def expire() -> None:
                try:
                    self.connection.shutdown(socket.SHUT_RDWR)
                except OSError:
                    pass
            self._deadline = threading.Timer(request_deadline, expire)
            self._deadline.daemon = True
            self._deadline.start()

        def finish(self) -> None:
            self._deadline.cancel()
            try:
                super().finish()
            except OSError:
                pass

        def log_message(self, format_string: str, *args: object) -> None:
            # BaseHTTPRequestHandler normally logs the entire URL, including
            # any accidentally supplied credentials. Only fixed status is kept.
            return

        def _send(self, status: int, payload: dict[str, Any]) -> None:
            body = json.dumps(payload, ensure_ascii=False, allow_nan=False, separators=(",", ":")).encode()
            try:
                self.send_response(status)
                self.send_header("Content-Type", "application/json; charset=utf-8")
                self.send_header("Content-Length", str(len(body)))
                self.send_header("Cache-Control", "no-store")
                self.send_header("Connection", "close")
                if status == 503:
                    self.send_header("Retry-After", "1")
                self.end_headers()
                self.wfile.write(body)
                self.close_connection = True
            except OSError:
                logger.info("client_disconnected_before_response status=%s", status)

        def _authorized(self) -> bool:
            if application.authorized(self.headers.get("Authorization")):
                return True
            self._send(401, {"ok": False, "error": "unauthorized"})
            return False

        def _body(self) -> dict[str, Any]:
            if self.headers.get("Transfer-Encoding") is not None:
                raise ApiError("transfer_encoding_unsupported", 400)
            if len(self.headers.get_all("Content-Length", [])) != 1:
                raise ApiError("content_length_invalid", 400)
            try:
                length = int(self.headers.get("Content-Length", "0"))
            except ValueError as exc:
                raise ApiError("content_length_invalid", 400) from exc
            if length <= 0 or length > MAX_BODY_BYTES:
                raise ApiError("request_body_size_invalid", 413)
            try:
                data = self.rfile.read(length)
            except TimeoutError:
                raise ApiError("request_timeout", 408) from None
            if len(data) != length:
                raise ApiError("request_body_incomplete", 400)
            try:
                def reject_constant(value: str) -> None:
                    raise ValueError
                payload = json.loads(data.decode("utf-8"), parse_constant=reject_constant)
            except (UnicodeDecodeError, ValueError, RecursionError):
                raise ApiError("request_json_invalid", 400) from None
            if not isinstance(payload, dict):
                raise ApiError("request_json_invalid", 400)
            return payload

        def do_GET(self) -> None:
            if self.path == "/health":
                self._send(200, {"ok": True, "service": "survival-fishing-api"})
                return
            if self.path == "/ready":
                if not self._authorized():
                    return
                try:
                    if not _database_ready(application.rpc_client):
                        raise SupabaseError("database_unavailable", 503)
                    self._send(200, {"ok": True, "service": "survival-fishing-api", "database": "ready"})
                except Exception:
                    logger.error("database_readiness_failed")
                    self._send(503, {"ok": False, "error": "database_unavailable"})
                return
            self._send(404, {"ok": False, "error": "route_not_found"})

        def do_POST(self) -> None:
            if not self._authorized():
                return
            try:
                payload = self._body()
                archive = getattr(application, "archive", None)
                from . import match_profiles
                match_context = (match_profiles.context(application, payload)
                                 if self.path not in ("/v1/session/login", "/v1/session/authenticate") else None)
                if self.path == "/v1/session/authenticate":
                    response = match_profiles.authenticate(application, payload)
                elif self.path == "/v1/session/login":
                    response = match_profiles.login(application, payload)
                elif self.path == "/v1/profile":
                    response = archive.profile(payload) if archive else application.profile(payload)
                    if not isinstance(response, dict) or not response:
                        raise SupabaseError("database_response_invalid", 503)
                elif self.path == "/v1/rewards/grant":
                    response = application.grant_out_of_match_reward(payload)
                elif self.path == "/v1/online-time/checkpoint":
                    response = application.online_checkpoint(payload)
                    _log_checkpoint_summary(payload, response)
                    if archive:
                        account = application._database_account_id(payload["account_id"])
                        archive.drain_online(account)
                        response["profile"] = archive.profile({"account_id": payload["account_id"]})
                elif self.path == "/v1/lottery/catalog":
                    if not archive:
                        raise ApiError("archive_disabled", 503)
                    response = archive.lottery_catalog(payload)
                elif self.path == "/v1/lottery/snapshot":
                    if not archive:
                        raise ApiError("archive_disabled", 503)
                    response = archive.lottery_snapshot(payload)
                elif self.path == "/v1/archive/config":
                    if not archive:
                        raise ApiError("archive_disabled", 503)
                    response = {"ok": True, "protocol": 1, "config_hash": archive.bundle.hash, "capabilities": {"endless_batch": 1, "endless_batch_limit": 32}}
                elif self.path == "/v1/archive/endless-batch":
                    if not archive:
                        raise ApiError("archive_disabled", 503)
                    from archive_backend.service import ArchiveError
                    try:
                        response = archive.endless_batch(payload)
                    except ArchiveError as exc:
                        code = str(exc)
                        if re.fullmatch(r"[a-z][a-z0-9_:]{0,79}", code) is None:
                            code = "archive_request_invalid"
                        raise ApiError(code, 400) from None
                elif self.path == "/v1/archive/endless-leaderboard":
                    if not archive:
                        raise ApiError("archive_disabled", 503)
                    from archive_backend.service import ArchiveError
                    try:
                        response = archive.endless_leaderboard(payload)
                    except (ArchiveError, ValueError) as exc:
                        code = str(exc)
                        if re.fullmatch(r"[a-z][a-z0-9_:]{0,79}", code) is None:
                            code = "archive_request_invalid"
                        raise ApiError(code, 400) from None
                elif self.path == "/v1/archive/command":
                    if not archive:
                        raise ApiError("archive_disabled", 503)
                    from archive_backend.service import ArchiveError
                    try:
                        response = archive.command(payload)
                    except ArchiveError as exc:
                        code = str(exc)
                        if re.fullmatch(r"[a-z][a-z0-9_:]{0,79}", code) is None:
                            code = "archive_request_invalid"
                        raise ApiError(code, 400) from None
                else:
                    raise ApiError("route_not_found", 404)
                response = match_profiles.project(application, payload, response, match_context)
                self._send(200, response if isinstance(response, dict) else {
                    "ok": True, "data": response,
                })
            except ApiError as exc:
                self._send(exc.status, {"ok": False, "error": exc.code})
            except SupabaseError as exc:
                logger.error("database_request_failed")
                self._send(503, {"ok": False, "error": "database_unavailable"})
            except TimeoutError:
                logger.error("archive_request_pending")
                self._send(503, {"ok": False, "error": "archive_pending", "retryable": True})
            except Exception:
                logger.error("unhandled_request_error")
                self._send(500, {"ok": False, "error": "internal_error"})

    return Handler


def build_application(settings: Settings) -> FishingApplication:
    settings.validate()
    definitions = load_definitions(settings.reward_csv, allow_decimal_values=True)
    rule = load_rule(settings.rule_csv)
    if definitions.version != rule.definition_version:
        raise DefinitionError("reward and rule definition versions differ")
    gameplay_stats = load_gameplay_stats(settings.gameplay_stats_csv)
    if settings.database_backend == "postgres":
        from .postgres import PostgresRpcClient
        client = PostgresRpcClient(
            settings.postgres_dsn,
            connect_timeout=settings.postgres_connect_timeout_seconds,
            statement_timeout_ms=settings.postgres_statement_timeout_ms,
            lock_timeout_ms=settings.postgres_lock_timeout_ms,
            max_concurrency=settings.postgres_max_concurrency,
        )
        client.ready()
    else:
        client = SupabaseRpcClient(settings.supabase_url, settings.supabase_key,
                                   settings.request_timeout_seconds)
    application = FishingApplication(
        settings.api_token,
        settings.account_id_pepper,
        definitions,
        client,
        gameplay_stats,
        online_time_lease_seconds=rule.online_time_lease_seconds,
        interval_min_seconds=rule.interval_min_seconds,
        interval_max_seconds=rule.interval_max_seconds,
    )
    application.sync_definitions()
    if settings.archive_http:
        try:
            from archive_backend.service import install
            application.archive = install(application, str(settings.addon_root), settings.archive_lua_path)
        except SupabaseError:
            raise
        except Exception:
            raise ConfigError("archive_initialization_failed") from None
    return application


def main() -> int:
    logging.basicConfig(level=logging.INFO, format="[FishingAPI] %(message)s")
    try:
        settings = Settings.from_env()
        application = build_application(settings)
    except (ConfigError, DefinitionError, GameplayStatsError, SupabaseError):
        print("FISHING_API_STARTUP_ERROR configuration_or_database_unavailable", file=sys.stderr)
        return 2
    except Exception:
        print("FISHING_API_STARTUP_ERROR initialization_failed", file=sys.stderr)
        return 2
    server = BoundedThreadingHTTPServer(
        (settings.host, settings.port),
        make_handler(application, client_timeout=settings.http_client_timeout_seconds,
                     request_deadline=settings.http_request_deadline_seconds),
        max_concurrency=settings.http_max_concurrency,
    )
    print(f"FISHING_API_READY http://{settings.host}:{settings.port}", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
