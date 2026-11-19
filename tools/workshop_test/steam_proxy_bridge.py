"""Loopback-only Steam TLS bridge through the current FeiNiao HTTP CONNECT port.

The bridge never receives Steam credentials in plaintext: it forwards the
cloud verifier's TLS bytes to the official Steam host through a local proxy.
The cloud still checks Steam's certificate and hostname. No arbitrary target
or externally reachable listener is accepted.
"""
from __future__ import annotations

import csv
import http.client
import io
import ipaddress
import json
import re
import selectors
import socket
import ssl
import subprocess
import sys
import threading
import time
import urllib.parse
import urllib.request

LISTEN = ("127.0.0.1", 18770)
DESTINATION = b"steamcommunity.com:443"
STATUS_REQUEST = b"WS4-STEAM-BRIDGE-STATUS-1\n"
STATUS_RESPONSE = b"WS4-STEAM-BRIDGE-READY-1\n"
MAX_WORKERS = 8
MAX_CANDIDATES = 8
MAX_STREAM_BYTES = 256 * 1024
STEAM_HOST = "steamcommunity.com"
DOH_ENDPOINTS = (
    "https://dns.google/resolve?name=steamcommunity.com&type=A",
    "https://cloudflare-dns.com/dns-query?name=steamcommunity.com&type=A",
)
DISCOVERY_SECONDS = 10
_cached_route = None  # (owned proxy port, certificate-checked Steam IPv4, DNS expiry)
_discovery_lock = threading.Lock()


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, request, fp, code, message, headers, newurl):
        return None


def remaining(deadline):
    value = deadline - time.monotonic()
    if value <= 0:
        raise TimeoutError("steam_discovery_budget_exhausted")
    return min(3, value)


def dns_answers(raw):
    """Accept bounded public A records for our single fixed query only."""
    if len(raw) > 8192:
        raise ValueError("steam_dns_response_too_large")
    data = json.loads(raw)
    if not isinstance(data, dict) or data.get("Status") != 0 or data.get("TC") is True:
        raise ValueError("steam_dns_response_invalid")
    answers = data.get("Answer")
    if not isinstance(answers, list) or len(answers) > 32:
        raise ValueError("steam_dns_answers_invalid")
    result = []
    for answer in answers:
        if (not isinstance(answer, dict) or answer.get("type") != 1
                or str(answer.get("name", "")).lower().rstrip(".") != STEAM_HOST):
            continue
        address = ipaddress.IPv4Address(answer.get("data"))
        ttl = answer.get("TTL")
        if not address.is_global or type(ttl) is not int or ttl < 0:
            raise ValueError("steam_dns_address_invalid")
        result.append((str(address), min(ttl, 60)))
    if not result:
        raise ValueError("steam_dns_no_public_address")
    return result[:2]


def resolve_steam(port, endpoint, deadline):
    proxy = "http://127.0.0.1:" + str(port)
    opener = urllib.request.build_opener(
        urllib.request.ProxyHandler({"http": proxy, "https": proxy}), NoRedirect())
    request = urllib.request.Request(endpoint, headers={"Accept": "application/dns-json"})
    with opener.open(request, timeout=remaining(deadline)) as response:
        if response.status != 200:
            raise ValueError("steam_dns_http_failed")
        raw = response.read(8193)
    return dns_answers(raw)


def verify_route(port, address, deadline):
    """An anonymous invalid assertion must be rejected by the real Steam TLS peer."""
    body = urllib.parse.urlencode({"openid.ns": "http://specs.openid.net/auth/2.0",
                                   "openid.mode": "check_authentication"}).encode("ascii")
    with connect_proxy(port, address, timeout=remaining(deadline)) as upstream:
        upstream.settimeout(remaining(deadline))
        with ssl.create_default_context().wrap_socket(upstream, server_hostname=STEAM_HOST) as peer:
            peer.settimeout(remaining(deadline))
            peer.sendall(b"POST /openid/login HTTP/1.1\r\nHost: steamcommunity.com\r\n"
                         b"Content-Type: application/x-www-form-urlencoded\r\nConnection: close\r\n"
                         b"Content-Length: " + str(len(body)).encode("ascii") + b"\r\n\r\n" + body)
            response = http.client.HTTPResponse(peer)
            response.begin()
            raw = response.read(8193)
            if response.status != 200 or len(raw) > 8192:
                raise ValueError("steam_probe_http_failed")
    fields = {}
    for line in raw.decode("utf-8").splitlines():
        key, separator, value = line.partition(":")
        if not separator or key in fields:
            raise ValueError("steam_probe_response_invalid")
        fields[key] = value
    if (fields.get("ns") != "http://specs.openid.net/auth/2.0"
            or fields.get("is_valid") != "false"):
        raise ValueError("steam_probe_not_rejected")


def discover_route(port, deadline):
    for endpoint in DOH_ENDPOINTS:
        try:
            answers = resolve_steam(port, endpoint, deadline)
            resolved_at = time.monotonic()
        except (OSError, ValueError, http.client.HTTPException):
            remaining(deadline)
            continue
        for address, ttl in answers:
            try:
                verify_route(port, address, deadline)
                return port, address, resolved_at + ttl
            except (OSError, ValueError, http.client.HTTPException):
                remaining(deadline)
    raise OSError("steam_proxy_no_verified_route")


def candidate_ports(*, tasklist=None, netstat=None):
    """Find loopback listeners of the current FeiNiao core, not arbitrary ports."""
    if tasklist is None:
        tasklist = subprocess.run(
            ["tasklist", "/FI", "IMAGENAME eq core.exe", "/FO", "CSV", "/NH"],
            capture_output=True, text=True, errors="replace", timeout=5, check=True).stdout
    if netstat is None:
        netstat = subprocess.run(
            ["netstat", "-ano", "-p", "tcp"], capture_output=True, text=True,
            errors="replace", timeout=5, check=True).stdout
    pids = set()
    for row in csv.reader(io.StringIO(tasklist)):
        if len(row) >= 2 and row[0].lower() == "core.exe" and row[1].isdigit():
            pids.add(row[1])
    if not pids:
        return []
    ports = set()
    for line in netstat.splitlines():
        parts = line.split()
        if (len(parts) != 5 or parts[0].upper() != "TCP"
                or parts[3].upper() != "LISTENING" or parts[4] not in pids
                or not parts[1].startswith("127.0.0.1:")):
            continue
        value = parts[1].rsplit(":", 1)[-1]
        if re.fullmatch(r"[0-9]{1,5}", value) and 1 <= int(value) <= 65535:
            ports.add(int(value))
    return sorted(ports)[:MAX_CANDIDATES]


def connect_proxy(port, address=None, *, timeout=3):
    """CONNECT only to Steam; reject proxy auth, redirects and partial replies."""
    destination = DESTINATION
    if address is not None:
        address = ipaddress.IPv4Address(address)
        if not address.is_global:
            raise ValueError("steam_proxy_nonpublic_address")
        destination = (str(address) + ":443").encode("ascii")
    upstream = socket.create_connection(("127.0.0.1", port), timeout=timeout)
    try:
        upstream.settimeout(timeout)
        upstream.sendall(b"CONNECT " + destination + b" HTTP/1.1\r\nHost: "
                         + destination + b"\r\nProxy-Connection: Keep-Alive\r\n\r\n")
        response = b""
        while b"\r\n\r\n" not in response and len(response) < 2048:
            chunk = upstream.recv(2048 - len(response))
            if not chunk:
                break
            response += chunk
        head, marker, extra = response.partition(b"\r\n\r\n")
        if not marker or extra or head.split(b"\r\n", 1)[0] not in (
                b"HTTP/1.0 200 Connection established", b"HTTP/1.1 200 Connection established",
                b"HTTP/1.1 200 OK", b"HTTP/1.0 200 OK"):
            raise OSError("steam_proxy_connect_failed")
        return upstream
    except Exception:
        upstream.close()
        raise


def current_proxy():
    global _cached_route
    deadline = time.monotonic() + DISCOVERY_SECONDS
    if not _discovery_lock.acquire(timeout=DISCOVERY_SECONDS):
        raise TimeoutError("steam_discovery_busy")
    try:
        previous_port = _cached_route[0] if _cached_route else None
        if _cached_route is not None:
            try:
                port, address, expires = _cached_route
                if expires <= time.monotonic():
                    _cached_route = discover_route(port, deadline)
                    port, address, _ = _cached_route
                return port, connect_proxy(port, address, timeout=remaining(deadline))
            except (OSError, ValueError, http.client.HTTPException):
                _cached_route = None
        for port in candidate_ports():
            remaining(deadline)
            if port in (LISTEN[1], previous_port):
                continue
            try:
                route = discover_route(port, deadline)
                upstream = connect_proxy(port, route[1], timeout=remaining(deadline))
            except (OSError, ValueError, http.client.HTTPException):
                continue
            _cached_route = route
            return port, upstream
    finally:
        _discovery_lock.release()
    raise OSError("steam_proxy_unavailable")


def transfer(client, upstream):
    """Bounded bidirectional TCP copy; no TLS parsing or alternate destination."""
    totals = {client: 0, upstream: 0}
    with selectors.DefaultSelector() as selector:
        for peer in (client, upstream):
            peer.setblocking(False)
            selector.register(peer, selectors.EVENT_READ)
        while True:
            ready = selector.select(timeout=20)
            if not ready:
                return
            for key, _ in ready:
                source = key.fileobj
                target = upstream if source is client else client
                try:
                    data = source.recv(16384)
                    if not data:
                        return
                    totals[source] += len(data)
                    if totals[source] > MAX_STREAM_BYTES:
                        return
                    target.setblocking(True)
                    target.settimeout(8)
                    target.sendall(data)
                    target.setblocking(False)
                except (OSError, ValueError):
                    return


def handle(client, slots):
    try:
        with client:
            client.settimeout(1)
            try:
                prefix = client.recv(1, socket.MSG_PEEK)
            except socket.timeout:
                prefix = b""
            if prefix == STATUS_REQUEST[:1]:
                request = b""
                while len(request) < len(STATUS_REQUEST):
                    chunk = client.recv(len(STATUS_REQUEST) - len(request))
                    if not chunk:
                        break
                    request += chunk
                if request == STATUS_REQUEST:
                    client.sendall(STATUS_RESPONSE)
                return
            _, upstream = current_proxy()
            with upstream:
                transfer(client, upstream)
    except (OSError, ValueError, subprocess.SubprocessError):
        pass
    finally:
        slots.release()


def serve():
    slots = threading.BoundedSemaphore(MAX_WORKERS)
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as listener:
        if hasattr(socket, "SO_EXCLUSIVEADDRUSE"):
            listener.setsockopt(socket.SOL_SOCKET, socket.SO_EXCLUSIVEADDRUSE, 1)
        listener.bind(LISTEN)
        listener.listen(MAX_WORKERS)
        while True:
            client, _ = listener.accept()
            if not slots.acquire(blocking=False):
                client.close()
                continue
            threading.Thread(target=handle, args=(client, slots), daemon=True).start()


def probe():
    try:
        with socket.create_connection(LISTEN, timeout=2) as client:
            client.settimeout(2)
            client.sendall(STATUS_REQUEST)
            result = b""
            while len(result) < len(STATUS_RESPONSE):
                chunk = client.recv(len(STATUS_RESPONSE) - len(result))
                if not chunk:
                    break
                result += chunk
            return result == STATUS_RESPONSE
    except OSError:
        return False


if __name__ == "__main__":
    if sys.argv[1:] != ["--serve"]:
        raise SystemExit(2)
    serve()
