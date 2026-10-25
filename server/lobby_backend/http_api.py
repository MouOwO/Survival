"""Small loopback-only development adapter; no access/path/body logging."""
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import ipaddress
import json
import threading

from .service import ACTIONS, LobbyError

BODY_LIMIT = 8192
ROUTES = frozenset("/v1/lobby/"+action for action in ACTIONS)


def post(service, path, authorization, payload):
    if path not in ROUTES:
        raise LobbyError("lobby_route_not_found",404)
    action = path[len("/v1/lobby/"):]
    if not action or "/" in action:
        raise LobbyError("lobby_route_not_found",404)
    bearer = authorization[7:] if isinstance(authorization,str) and authorization.startswith("Bearer ") else ""
    return service.dispatch(action,bearer,payload)


def unique_object(pairs):
    result = {}
    for key,value in pairs:
        if key in result:
            raise ValueError("duplicate field")
        result[key] = value
    return result


def handler(service):
    class Handler(BaseHTTPRequestHandler):
        server_version, sys_version = "WS4Lobby", ""

        def setup(self):
            super().setup(); self.connection.settimeout(10)

        def log_message(self,*_):
            pass

        def reply(self,status,value):
            raw = json.dumps(value,separators=(",",":"),ensure_ascii=True,allow_nan=False).encode("ascii")
            self.send_response(status)
            self.send_header("Content-Type","application/json; charset=utf-8")
            self.send_header("Content-Length",str(len(raw)))
            self.send_header("Cache-Control","no-store")
            self.send_header("X-Content-Type-Options","nosniff")
            self.send_header("Referrer-Policy","no-referrer")
            self.end_headers(); self.wfile.write(raw)

        def do_GET(self):
            if self.path != "/health":
                self.reply(404,dict(ok=False,error="lobby_route_not_found")); return
            self.reply(200,service.health())

        def do_POST(self):
            try:
                if self.headers.get("Transfer-Encoding") or len(self.headers.get_all("Content-Length",[])) != 1:
                    raise LobbyError("lobby_body_invalid")
                length = self.headers.get("Content-Length","")
                if not length.isascii() or not length.isdecimal() or not 0 < int(length) <= BODY_LIMIT:
                    raise LobbyError("lobby_body_too_large",413)
                if self.headers.get("Content-Type","").split(";",1)[0].strip().lower() != "application/json":
                    raise LobbyError("lobby_content_type_required",415)
                raw = self.rfile.read(int(length))
                if len(raw) != int(length):
                    raise LobbyError("lobby_body_invalid")
                payload = json.loads(raw.decode("utf-8"),object_pairs_hook=unique_object,
                                     parse_constant=lambda _: (_ for _ in ()).throw(ValueError()))
                if len(self.headers.get_all("Authorization",[])) != 1:
                    raise LobbyError("lobby_identity_required",401)
                self.reply(200,post(service,self.path,self.headers.get("Authorization"),payload))
            except LobbyError as error:
                self.reply(error.status,dict(ok=False,error=error.code,**(error.context or service.response_context())))
            except (ValueError,UnicodeError,RecursionError):
                self.reply(400,dict(ok=False,error="lobby_body_invalid"))
            except Exception:
                self.reply(503,dict(ok=False,error="lobby_unavailable"))
    return Handler


class Server(ThreadingHTTPServer):
    daemon_threads = True

    def __init__(self,address,service):
        if not ipaddress.ip_address(address[0]).is_loopback:
            raise ValueError("lobby_loopback_bind_required")
        self.slots = threading.BoundedSemaphore(16)
        super().__init__(address,handler(service))

    def process_request(self,request,client_address):
        if not self.slots.acquire(blocking=False):
            self.shutdown_request(request); return
        try:
            super().process_request(request,client_address)
        except BaseException:
            self.slots.release(); raise

    def process_request_thread(self,request,client_address):
        try:
            super().process_request_thread(request,client_address)
        finally:
            self.slots.release()

    def handle_error(self,request,client_address):
        pass
