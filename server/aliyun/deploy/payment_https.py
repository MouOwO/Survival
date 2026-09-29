"""Provision the dedicated payment HTTPS gateway on the verified Alibaba Linux ECS.

Run over SSH with Python 3.11, first `prepare`, then externally verify port 80,
then `activate`. This does not expose the game API or accept payment notices.
TLS keys are created on the server by Certbot and never enter the repository.
"""
import hashlib
import json
import os
from pathlib import Path
import shutil
import socket
import subprocess
import sys
import urllib.request

DOMAIN = "pay.xiaofengnet.com"
EXPECTED_IP = "47.110.238.248"
STATE_DIR = Path("/etc/goufayu-payment-https")
STATE = STATE_DIR / "state.json"
CONF = Path("/etc/nginx/nginx.conf")
WEBROOT = Path("/var/lib/goufayu-payment-acme")
CERTROOT = Path("/etc/letsencrypt/live") / DOMAIN
MARKER = "# Managed by survival/server/aliyun/deploy/payment_https.py\n"
COMMON = """user nginx;
worker_processes auto;
pid /run/nginx.pid;
error_log /var/log/nginx/goufayu-pay-error.log warn;
events { worker_connections 1024; }
http {
    include /etc/nginx/mime.types;
    default_type application/octet-stream;
    server_tokens off;
    log_format payment '$remote_addr [$time_local] "$request_method $uri $server_protocol" $status';
    access_log /var/log/nginx/goufayu-pay-access.log payment;
    client_max_body_size 64k;
    client_body_timeout 10s;
    client_header_timeout 10s;
    keepalive_timeout 15s;
    server { listen 80 default_server; server_name _; return 404; }
"""
HTTP_SITE = """    server {
        listen 80;
        server_name pay.xiaofengnet.com;
        location ^~ /.well-known/acme-challenge/ {
            root /var/lib/goufayu-payment-acme;
            default_type text/plain;
            limit_except GET { deny all; }
            try_files $uri =404;
        }
        HTTP_OTHER
    }
"""
TLS_SITE = """    server {
        listen 443 ssl;
        server_name pay.xiaofengnet.com;
        ssl_certificate /etc/letsencrypt/live/pay.xiaofengnet.com/fullchain.pem;
        ssl_certificate_key /etc/letsencrypt/live/pay.xiaofengnet.com/privkey.pem;
        ssl_protocols TLSv1.2 TLSv1.3;
        ssl_session_cache shared:payment_tls:10m;
        ssl_session_timeout 1d;
        ssl_session_tickets off;
        location = /connection-check {
            default_type text/plain;
            add_header Cache-Control "no-store" always;
            return 200 'payment HTTPS connection ready\\n';
        }
        # Fail closed until durable orders, signature checks and delivery exist.
        location = /v1/payments/wechat/notify {
            default_type application/json;
            return 503 '{"status":"payment_not_ready"}';
        }
        location = /v1/payments/alipay/notify {
            default_type application/json;
            return 503 '{"status":"payment_not_ready"}';
        }
        location / { return 404; }
    }
"""
BOOTSTRAP = MARKER + COMMON + HTTP_SITE.replace(
    "HTTP_OTHER", "location = /connection-check { default_type text/plain; return 200 'payment HTTP bootstrap ready\\n'; }\n        location / { return 404; }"
) + "}\n"
TLS_CONFIG = MARKER + COMMON + HTTP_SITE.replace(
    "HTTP_OTHER", "location / { return 301 https://pay.xiaofengnet.com$request_uri; }"
) + TLS_SITE + "}\n"


def emit(**data):
    print(json.dumps(data, ensure_ascii=True), flush=True)


def run(args, timeout=60):
    completed = subprocess.run(args, capture_output=True, text=True, timeout=timeout)
    if completed.returncode:
        raise RuntimeError("Command failed: " + args[0] + " " + " ".join(args[1:3]) + "\n" + (completed.stdout + completed.stderr)[-3500:])
    return completed.stdout.strip()


def atomic_write(path, content, mode=0o644):
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(path.name + ".goufayu-new")
    with open(temporary, "w", encoding="utf-8") as stream:
        os.chmod(temporary, mode)
        stream.write(content)
        stream.flush()
        os.fsync(stream.fileno())
    os.replace(temporary, path)


def save_state(state):
    atomic_write(STATE, json.dumps(state, indent=2) + "\n", 0o600)


def backend_health():
    with urllib.request.urlopen("http://127.0.0.1:8765/health", timeout=5) as response:
        if response.status != 200:
            raise RuntimeError("Game backend is unhealthy")
    return run(["systemctl", "show", "goufayu-api.service", "--property=MainPID", "--value"])


def install_config(content):
    previous = CONF.read_text() if CONF.exists() else None
    atomic_write(CONF, content)
    try:
        run(["nginx", "-t"])
    except Exception:
        if previous is not None:
            atomic_write(CONF, previous)
        raise


def prepare():
    state = json.loads(STATE.read_text()) if STATE.exists() else None
    if state is None:
        if shutil.which("nginx") or CONF.exists():
            raise RuntimeError("Existing unmanaged Nginx detected; inspect before changing it")
        if set(socket.gethostbyname_ex(DOMAIN)[2]) != {EXPECTED_IP}:
            raise RuntimeError("Unexpected DNS destination")
        STATE_DIR.mkdir(mode=0o700, parents=True, exist_ok=True)
        state = {"owner": "goufayu-payment-https", "phase": "installing", "domain": DOMAIN}
        save_state(state)
    else:
        if state.get("owner") != "goufayu-payment-https":
            raise RuntimeError("Unexpected state owner")
        if state.get("phase") == "https_ready":
            emit(phase="https_already_ready")
            return
        if CONF.exists() and state.get("phase") != "installing" and CONF.read_text() != BOOTSTRAP:
            raise RuntimeError("Nginx configuration was changed outside this provisioner")
    before_pid = backend_health()
    emit(phase="installing_distribution_packages", packages=["nginx", "certbot"])
    run(["dnf", "install", "-y", "nginx", "certbot"], timeout=240)
    backup = STATE_DIR / "nginx.original.conf"
    if not backup.exists() and CONF.exists():
        atomic_write(backup, CONF.read_text(), 0o600)
    WEBROOT.mkdir(parents=True, exist_ok=True, mode=0o755)
    challenge = WEBROOT / ".well-known/acme-challenge"
    challenge.mkdir(parents=True, exist_ok=True, mode=0o755)
    atomic_write(challenge / "goufayu-connection-check", "goufayu-payment-acme-ready\n")
    install_config(BOOTSTRAP)
    run(["systemctl", "enable", "--now", "nginx"])
    run(["systemctl", "reload", "nginx"])
    state.update(phase="http_ready", config_sha256=hashlib.sha256(BOOTSTRAP.encode()).hexdigest())
    save_state(state)
    emit(phase="http_ready", backend_health=200, backend_pid_unchanged=before_pid == backend_health())


def activate():
    if not STATE.exists():
        raise RuntimeError("Run prepare first")
    state = json.loads(STATE.read_text())
    if state.get("phase") == "payments_ready":
        if hashlib.sha256(CONF.read_bytes()).hexdigest() != state.get("config_sha256"):
            raise RuntimeError("Payment gateway configuration differs from its recorded deployment")
        emit(phase="payments_already_ready", backend_health=200)
        return
    if state.get("owner") != "goufayu-payment-https" or CONF.read_text() not in (BOOTSTRAP, TLS_CONFIG):
        raise RuntimeError("Unexpected gateway state/configuration")
    before_pid = backend_health()
    emit(phase="requesting_domain_certificate", domain=DOMAIN)
    run(["certbot", "certonly", "--webroot", "-w", str(WEBROOT), "-d", DOMAIN,
         "--cert-name", DOMAIN, "--non-interactive", "--agree-tos",
         "--register-unsafely-without-email", "--key-type", "rsa", "--rsa-key-size", "2048",
         "--preferred-challenges", "http", "--keep-until-expiring",
         "--server", "https://acme-v02.api.letsencrypt.org/directory"], timeout=180)
    install_config(TLS_CONFIG)
    run(["systemctl", "reload", "nginx"])
    hook = Path("/etc/letsencrypt/renewal-hooks/deploy/goufayu-pay-nginx")
    atomic_write(hook, '#!/bin/sh\nset -eu\n[ "${RENEWED_LINEAGE:-}" = "/etc/letsencrypt/live/pay.xiaofengnet.com" ] || exit 0\n/usr/sbin/nginx -t\n/usr/bin/systemctl reload nginx\n', 0o755)
    atomic_write(Path("/etc/systemd/system/goufayu-payment-cert-renew.service"),
                 "[Unit]\nDescription=Renew payment domain TLS certificate\nAfter=network-online.target nginx.service\nWants=network-online.target\n\n[Service]\nType=oneshot\nExecStart=/usr/bin/certbot renew --quiet --cert-name pay.xiaofengnet.com\n")
    atomic_write(Path("/etc/systemd/system/goufayu-payment-cert-renew.timer"),
                 "[Unit]\nDescription=Check payment TLS renewal twice daily\n\n[Timer]\nOnCalendar=*-*-* 03,15:20:00\nRandomizedDelaySec=3600\nPersistent=true\n\n[Install]\nWantedBy=timers.target\n")
    run(["systemctl", "daemon-reload"])
    run(["systemctl", "enable", "--now", "goufayu-payment-cert-renew.timer"])
    state.update(phase="https_ready", config_sha256=hashlib.sha256(TLS_CONFIG.encode()).hexdigest())
    save_state(state)
    emit(phase="https_ready", backend_health=200, backend_pid_unchanged=before_pid == backend_health(),
         certificate=run(["openssl", "x509", "-in", str(CERTROOT / "fullchain.pem"), "-noout", "-subject", "-issuer", "-dates"]),
         renewal_timer=run(["systemctl", "is-active", "goufayu-payment-cert-renew.timer"]),
         payment_routes_ready=False, orders_created=0)


if __name__ == "__main__":
    if os.geteuid() != 0 or sys.version_info < (3, 11):
        raise SystemExit("Requires root and Python 3.11+")
    try:
        action = sys.argv[1] if len(sys.argv) == 2 else ""
        if action == "prepare":
            prepare()
        elif action == "activate":
            activate()
        else:
            raise RuntimeError("Usage: payment_https.py prepare|activate")
    except Exception as error:
        emit(status="failed", error=str(error))
        raise SystemExit(1)
