"""Capture the one 10:19 manifest timeout, read-only network/official facts.

Default writes nothing and does not initialize Steam. --capture writes a new
ignored evidence directory; --query additionally makes one fresh official UGC
details query. No download, publication, journal change or proxy reconfiguration.
Proxy credentials, signed URL paths/queries, bodies and headers are not exported.
"""
from __future__ import annotations
import argparse
import hashlib
import http.client
import json
import os
from pathlib import Path
import re
import socket
import subprocess
import sys
import urllib.parse

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools/workshop_test"))
import verify_native_shop_download as previous
api, callbacks, need = previous.api, previous.callbacks, previous.need
STATE = ROOT / "output/four_accounts_20261022/steam_upload_state.json"
UPLOAD = ROOT / "output/arcade_cleanup_20261027/upload_log.jsonl"
DEPOT = Path("C:/Program Files (x86)/Steam/workshopbuilds/depot_build_570.log")
WORKSHOP = Path("C:/Program Files (x86)/Steam/logs/workshop_log.txt")
OUTPUT = ROOT / "output/arcade_cleanup_20261027/upload_recovery_attempt_20261027_101903"
PENDING_SHA = "e013c3c897d07c34aa5532e4a45d7dfa92e625daa8b2580d11557af60e76bc22"
UPLOAD_SHA = "c10caa47d06596896b888d383cee32f2413be4b91ac4181b71b67ddbbd71d31e"
DEPOT_SHA = "37b28f87723ed952753e349c0159813e150b27de11a5c48aa2cd7367a7ceefba"
HOST = "depot-ingest.discovery.steamserver.net"
REMOTE_TIME, TOTAL = 1792994420, 3767101843


def endpoint(raw):
    if not raw:
        return None
    try:
        value = urllib.parse.urlsplit(str(raw) if "://" in str(raw) else "//" + str(raw))
        return dict(scheme=value.scheme or None, host=value.hostname, port=value.port,
                    userinfo_present=bool(value.username or value.password))
    except (ValueError, TypeError):
        return dict(present=True, parseable=False)


def redact(line):
    def url(match):
        parsed = endpoint(match.group()) or {}
        return ((parsed.get("scheme") or "https") + "://" + str(parsed.get("host"))
                + (":" + str(parsed["port"]) if parsed.get("port") else "") + "/<path-and-query-redacted>")
    line = re.sub(r"https?://[^\s\]\)\"']+", url, line)
    # Credentials can contain spaces (e.g. Authorization: Bearer <value>).
    # Redact the remaining line rather than leaving a second token behind.
    line = re.sub(r"(?i)\b(authorization|password|token|cookie)\b\s*[:=].*$", r"\1=<redacted>", line)
    return re.sub(r"\bhandle [0-9]+", "handle <redacted>", line)


def network():
    proxy = {name: endpoint(os.environ.get(name)) for name in ("HTTP_PROXY", "HTTPS_PROXY", "ALL_PROXY")}
    result = dict(observed_utc=callbacks.now(), process_proxy_environment=proxy,
        no_proxy_present=bool(os.environ.get("NO_PROXY") or os.environ.get("no_proxy")),
        steam_route_observed=False, network_configuration_changed=False)
    try:
        import winreg
        with winreg.OpenKey(winreg.HKEY_CURRENT_USER,
                r"Software\Microsoft\Windows\CurrentVersion\Internet Settings") as key:
            def value(name):
                try:
                    return winreg.QueryValueEx(key, name)[0]
                except FileNotFoundError:
                    return None
            server = value("ProxyServer") or ""
            result["wininet"] = dict(proxy_enabled=value("ProxyEnable"),
                proxy_servers=[endpoint(part.split("=", 1)[-1]) for part in str(server).split(";") if part],
                pac_endpoint=endpoint(value("AutoConfigURL")))
    except OSError as error:
        result["wininet_error"] = type(error).__name__
    command = subprocess.run(["netsh", "winhttp", "show", "proxy"], capture_output=True)
    raw = command.stdout.decode("utf8", errors="replace")
    result["winhttp"] = dict(query_exit_code=command.returncode,
        direct_access_reported=("Direct access" in raw or "直接访问" in raw),
        raw_not_exported=True)
    try:
        result["ingest_dns"] = dict(host=HOST, addresses=sorted({row[4][0]
            for row in socket.getaddrinfo(HOST, 443, type=socket.SOCK_STREAM)}))
    except OSError as error:
        result["ingest_dns"] = dict(host=HOST, error=type(error).__name__)
    probes = []
    for label, host, port, tunnel in (("direct", HOST, 443, False),
                                       ("manual_loopback_proxy_7890", "127.0.0.1", 7890, True)):
        connection = None
        row = dict(route=label, target_host=HOST, target_port=443,
                   request="unauthenticated_HEAD_root", upload_performed=False)
        try:
            connection = http.client.HTTPSConnection(host, port, timeout=5)
            if tunnel:
                connection.set_tunnel(HOST, 443)
            connection.request("HEAD", "/")
            response = connection.getresponse()
            row.update(tls_verified=True, http_status=response.status, response_body_read=False)
        except (OSError, http.client.HTTPException) as error:
            row.update(error=type(error).__name__)
        finally:
            if connection is not None:
                connection.close()
        probes.append(row)
    result["transport_probes"] = probes
    return result


def validate_old_remote(item):
    previous.validate_remote(item, TOTAL)
    need(item.get("time_updated") == REMOTE_TIME, "failure_capture_remote_no_longer_exact_shop02")


def capture(*, query=False):
    pending = callbacks.read_pinned(STATE, PENDING_SHA, 16 * 1024 * 1024)
    upload = callbacks.read_pinned(UPLOAD, UPLOAD_SHA, 1024 * 1024)
    depot = callbacks.read_pinned(DEPOT, DEPOT_SHA, 1024 * 1024)
    workshop = api.pack.read_metadata(api.pack.handoff.regular_path(WORKSHOP), 16 * 1024 * 1024)
    need(b"Steam API callback 3404 returned EResult=2" in upload
         and b"Upload workshop item 3824360109 failed (Timeout uploading manifest (size 104792))" in workshop
         and b"Timeout uploading manifest (size 104792)" in depot
         and HOST.encode() in depot, "failure_capture_exact_timeout_evidence_missing")
    state = api.pack.handoff.decode_json(pending)
    need(state.get("status") == "SUBMIT_REQUEST_PENDING" and state.get("uploaded") is False
         and state.get("release_sequence") == 2026102703, "failure_capture_pending_identity_changed")
    diagnostics = network()
    fresh = None
    if query:
        with previous.SHOP02Steam(TOTAL) as steam:
            fresh = steam.fresh_item()
        validate_old_remote(fresh)
    need(api.pack.read_metadata(STATE, len(pending)) == pending, "failure_capture_pending_changed")
    directory = api.pack.handoff.regular_path(OUTPUT, must_exist=False)
    need(not directory.exists(), "failure_capture_evidence_already_exists")
    directory.mkdir(parents=True, exist_ok=False)
    for name, raw in (("pending.original.json", pending), ("upload_failure.jsonl", upload)):
        callbacks.write_exclusive(directory / name, raw)
    depot_excerpt = "\n".join(redact(line) for line in depot.decode("utf8", errors="replace").splitlines()) + "\n"
    workshop_excerpt = "\n".join(redact(line) for line in workshop.decode("utf8", errors="replace").splitlines()
        if "2026-10-27 10:18" in line or "2026-10-27 10:19" in line) + "\n"
    callbacks.write_exclusive(directory / "depot_failure.redacted.log", depot_excerpt.encode("utf8"))
    callbacks.write_exclusive(directory / "workshop_failure.redacted.log", workshop_excerpt.encode("utf8"))
    callbacks.write_exclusive(directory / "network.json", callbacks.encoded(diagnostics))
    if fresh:
        callbacks.write_exclusive(directory / "fresh_old_remote_query.json", callbacks.encoded(fresh))
    evidence = dict(schema=1, status="FAILED_REFRESH_UPLOAD_EVIDENCE_CAPTURED",
        observed_utc=callbacks.now(), pending_sha256=PENDING_SHA, upload_report_sha256=UPLOAD_SHA,
        original_depot_log_sha256=DEPOT_SHA, original_workshop_log_sha256=hashlib.sha256(workshop).hexdigest(),
        files={path.name: hashlib.sha256(path.read_bytes()).hexdigest() for path in directory.iterdir()},
        callback_id=3404, result=2, diagnosis="manifest_upload_timeout", manifest_bytes=104792,
        upload_endpoint_host=HOST, failed_release_sequence=2026102703,
        remote_shop02_metadata_freshly_confirmed=bool(fresh), official_download_verified=False,
        journal_changed=False, upload_performed=False, proxy_changed=False, secrets_exported=False)
    callbacks.write_exclusive(directory / "evidence.json", callbacks.encoded(evidence))
    return dict(status=evidence["status"], evidence_directory=str(directory),
                evidence_sha256=api.pack.runtime.digest(directory / "evidence.json"),
                remote_old_metadata_confirmed=bool(fresh), journal_changed=False,
                network=diagnostics, fresh_query=fresh)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--capture", action="store_true")
    parser.add_argument("--query", action="store_true")
    args = parser.parse_args(argv)
    try:
        need(not args.query or args.capture, "failure_query_requires_capture")
        if args.capture:
            api.emit(capture(query=args.query))
        else:
            api.emit(dict(status="READ_ONLY_FAILED_UPLOAD_CAPTURE_PLAN", steam_initialized=False,
                          journal_changed=False, files_written=0, upload_performed=False))
        return 0
    except Exception as error:
        api.emit(dict(status="FAILED_UPLOAD_CAPTURE_REFUSED", reason=str(error)
            if isinstance(error, callbacks.Refused) else type(error).__name__, journal_changed=False))
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
