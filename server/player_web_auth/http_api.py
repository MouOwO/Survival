"""Small bounded HTTP adapter. It never logs paths, tokens, cookies, or exceptions."""
from http.cookies import SimpleCookie, CookieError
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import ipaddress
import sqlite3
import threading
from urllib.parse import parse_qsl, urlsplit

from .service import AuthError, BODY_LIMIT


def strict_pairs(raw, maximum=30):
    try:
        pairs = parse_qsl(raw, keep_blank_values=True, strict_parsing=True, max_num_fields=maximum,
                          encoding="utf-8", errors="strict")
        if len({key for key, _ in pairs}) != len(pairs) or any(len(key) > 100 or len(value) > 4096 for key, value in pairs):
            raise ValueError()
        return dict(pairs)
    except (ValueError, UnicodeError):
        raise AuthError("request_fields_invalid") from None


def handler(service):
    class Handler(BaseHTTPRequestHandler):
        server_version = "WS4PlayerAuth"
        sys_version = ""

        def setup(self):
            super().setup()
            self.connection.settimeout(15)

        def log_message(self, *args):
            pass

        def send_error(self, code, message=None, explain=None):
            self.reply(code, {"ok": False, "error": "request_rejected"})

        def reply(self, status, body=b"", *, content_type="application/json; charset=utf-8", cookie=None, location=None):
            if not isinstance(body, bytes):
                body = json.dumps(body, separators=(",", ":")).encode()
            self.send_response(status)
            self.send_header("Content-Type", content_type)
            self.send_header("Cache-Control", "no-store")
            self.send_header("Referrer-Policy", "no-referrer")
            self.send_header("X-Content-Type-Options", "nosniff")
            self.send_header("X-Frame-Options", "DENY")
            self.send_header("Content-Security-Policy", "default-src 'none'; form-action 'self'; base-uri 'none'; frame-ancestors 'none'")
            self.send_header("Content-Length", str(len(body)))
            if cookie:
                path = urlsplit(service.settings.public_base).path
                self.send_header("Set-Cookie", "ws4_browser=" + cookie + "; Path=" + path + "; Secure; HttpOnly; SameSite=Lax")
            if location:
                self.send_header("Location", location)
            if status == 429:
                self.send_header("Retry-After", "3")
            self.send_header("Connection", "close")
            self.end_headers()
            self.close_connection = True
            self.wfile.write(body)

        def sid(self):
            if len(self.headers.get("Cookie", "")) > 2048:
                raise AuthError("browser_cookie_invalid")
            cookie = SimpleCookie()
            try:
                cookie.load(self.headers.get("Cookie", ""))
            except CookieError:
                raise AuthError("browser_cookie_invalid") from None
            value = cookie.get("ws4_browser")
            return value.value if value else None

        def route(self):
            if len(self.path) > 8192:
                raise AuthError("request_target_too_large", 414)
            parsed = urlsplit(self.path)
            if parsed.scheme or parsed.netloc or parsed.fragment or "%" in parsed.path or "\\" in parsed.path:
                raise AuthError("request_path_invalid")
            return parsed.path, strict_pairs(parsed.query) if parsed.query else {}

        def peer(self):
            peer = self.client_address[0]
            forwarded = self.headers.get_all("X-Forwarded-For", [])
            if peer != "127.0.0.1" or not forwarded:
                return peer
            if len(forwarded) != 1 or "%" in forwarded[0]:
                raise AuthError("forwarded_address_invalid")
            try:
                return str(ipaddress.ip_address(forwarded[0].strip()))
            except ValueError:
                raise AuthError("forwarded_address_invalid") from None

        def body(self, form=False):
            lengths = self.headers.get_all("Content-Length", [])
            if (self.headers.get("Transfer-Encoding") or len(lengths) != 1 or not lengths[0].isdigit()
                    or not 0 < int(lengths[0]) <= BODY_LIMIT):
                raise AuthError("request_body_too_large", 413)
            expected = "application/x-www-form-urlencoded" if form else "application/json"
            if self.headers.get_content_type() != expected:
                raise AuthError("content_type_invalid", 415)
            raw = self.rfile.read(int(lengths[0]))
            if len(raw) != int(lengths[0]):
                raise AuthError("request_body_incomplete")
            try:
                if form:
                    return strict_pairs(raw.decode("utf-8"), 4)
                def unique(pairs):
                    result = {}
                    for key, value in pairs:
                        if key in result:
                            raise ValueError()
                        result[key] = value
                    return result
                value = json.loads(raw, object_pairs_hook=unique,
                                   parse_constant=lambda _: (_ for _ in ()).throw(ValueError()))
                if not isinstance(value, dict):
                    raise ValueError()
                return value
            except (ValueError, UnicodeError, RecursionError):
                raise AuthError("request_json_invalid") from None

        def do_GET(self):
            try:
                service.rate("global-http", "all", 2400)
                peer = self.peer()
                path, query = self.route()
                if path == "/health" and not query:
                    self.reply(200, {"ok": True, "kind": "WS4-PLAYER-WEB-AUTH-1", "steam_login": True,
                                     "isolated_accounts": True, "local_progress_unverified": service.settings.isolated_local_progress})
                elif path == "/authorize" and set(query) == {"code"}:
                    service.rate("authorize-page", peer, 60)
                    sid, fresh, page = service.page(query["code"], self.sid())
                    self.reply(200, page, content_type="text/html; charset=utf-8", cookie=sid if fresh else None)
                elif path == "/steam/login" and set(query) == {"code"}:
                    sid, location = service.login(query["code"], self.sid(), peer)
                    self.reply(303, cookie=sid, location=location)
                elif path == "/steam/callback" and "state" in query:
                    code = service.callback(query, self.sid(), peer)
                    self.reply(303, location=service.settings.public_base + "/authorize?code=" + code)
                else:
                    raise AuthError("route_not_found", 404)
            except AuthError as error:
                self.reply(error.status, {"ok": False, "error": error.code})
            except sqlite3.Error:
                self.reply(503, {"ok": False, "error": "authentication_unavailable"})
            except Exception:
                self.reply(503, {"ok": False, "error": "authentication_unavailable"})

        def do_POST(self):
            try:
                service.rate("global-http", "all", 2400)
                peer = self.peer()
                path, query = self.route()
                if query:
                    raise AuthError("request_query_not_allowed")
                if path == "/authorize":
                    service.approve(self.body(form=True), self.sid(), self.headers.get("Origin"), peer)
                    self.reply(200, "<!doctype html><meta charset=utf-8><title>授权完成</title><p>授权完成，请返回游戏。若游戏仍等待，请让游戏重试校验。</p>".encode("utf-8"), content_type="text/html; charset=utf-8")
                    return
                payload = self.body()
                if path == "/v1/player-auth/start":
                    self.reply(200, service.start(payload, peer))
                elif path == "/v1/player-auth/poll":
                    self.reply(200, service.poll(payload, peer))
                else:
                    header = self.headers.get("Authorization", "")
                    bearer = header[7:] if header.startswith("Bearer ") else ""
                    status, body = service.proxy(path, bearer, payload, peer)
                    self.reply(status, body)
            except AuthError as error:
                self.reply(error.status, {"ok": False, "error": error.code})
            except sqlite3.Error:
                self.reply(503, {"ok": False, "error": "authentication_unavailable"})
            except Exception:
                self.reply(503, {"ok": False, "error": "authentication_unavailable"})
    return Handler


class BoundedServer(ThreadingHTTPServer):
    daemon_threads = True
    request_queue_size = 16

    def __init__(self, address, request_handler):
        self.slots = threading.BoundedSemaphore(24)
        super().__init__(address, request_handler)

    def process_request(self, request, address):
        if not self.slots.acquire(blocking=False):
            self.shutdown_request(request)
            return
        try:
            super().process_request(request, address)
        except BaseException:
            self.slots.release()
            raise

    def process_request_thread(self, request, address):
        try:
            super().process_request_thread(request, address)
        finally:
            self.slots.release()

    def handle_error(self, request, address):
        # BaseServer prints tracebacks including context; keep this service quiet.
        pass
