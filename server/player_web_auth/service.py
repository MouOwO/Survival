"""Steam OpenID consent and narrowly scoped player sessions (standard library only).

These sessions identify consenting players. They do not attest local battle results.
The existing privileged WS4 bearer remains exclusively in this server's environment.
"""
from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timezone
import hashlib
import hmac
import html
import json
import os
from pathlib import Path
import re
import secrets
import sqlite3
import stat
import threading
import time
from urllib.parse import urlencode, urlsplit
import urllib.error
import urllib.request


STEAM_BASE = 76561197960265728
STEAM_ENDPOINT = "https://steamcommunity.com/openid/login"
OPENID_NS = "http://specs.openid.net/auth/2.0"
IDENTIFIER_SELECT = OPENID_NS + "/identifier_select"
SESSION = re.compile(r"[A-Za-z0-9_:.-]{8,200}\Z")
OPAQUE = re.compile(r"[A-Za-z0-9_-]{40,100}\Z")
USER_CODE = re.compile(r"[A-HJ-NP-Z2-9]{8}\Z")
READ_PATHS = frozenset("/v1/" + name for name in (
    "session/authenticate", "session/login", "profile", "lottery/catalog",
    "lottery/snapshot", "archive/config"))
LOCAL_PROGRESS_PATHS = frozenset("/v1/" + name for name in (
    "archive/command", "archive/endless-batch", "online-time/checkpoint"))
BODY_LIMIT = 16384
PENDING_TTL = 600
SESSION_TTL = 4 * 3600
POLL_INTERVAL = 3


class AuthError(Exception):
    def __init__(self, code, status=400):
        super().__init__(code)
        self.code, self.status = code, status


def digest(value):
    return hashlib.sha256(value.encode("utf-8")).hexdigest()


def equal(left, right):
    return isinstance(left, str) and isinstance(right, str) and hmac.compare_digest(left, right)


@dataclass(frozen=True)
class Settings:
    database: Path
    secret: str
    upstream_bearer: str
    steam_ids: tuple[str, ...]
    public_base: str = "https://pay.xiaofengnet.com/ws4-web"
    upstream: str = "http://127.0.0.1:18765"
    bind: str = "127.0.0.1"
    port: int = 18767
    isolated_local_progress: bool = False

    def validate(self):
        public = urlsplit(self.public_base)
        if (public.scheme != "https" or not public.hostname or public.username or public.password
                or public.query or public.fragment or public.path != "/ws4-web"
                or self.public_base.endswith("/")):
            raise ValueError("public_base_invalid")
        if self.upstream != "http://127.0.0.1:18765" or self.bind != "127.0.0.1" or self.port != 18767:
            raise ValueError("isolated_loopback_required")
        if (not re.fullmatch(r"[a-fA-F0-9]{64,128}", self.secret)
                or not re.fullmatch(r"[A-Za-z0-9_+/=-]{32,256}", self.upstream_bearer)
                or self.secret == self.upstream_bearer):
            raise ValueError("server_secret_invalid")
        if len(self.steam_ids) != 4 or len(set(self.steam_ids)) != 4:
            raise ValueError("four_test_accounts_required")
        for steam in self.steam_ids:
            if (not re.fullmatch(r"7656119\d{10}", steam)
                    or not 0 < int(steam) - STEAM_BASE <= 0xFFFFFFFF):
                raise ValueError("steam_id_invalid")

    @property
    def accounts(self):
        return {str(int(steam) - STEAM_BASE): steam for steam in self.steam_ids}

    @property
    def origin(self):
        value = urlsplit(self.public_base)
        return value.scheme + "://" + value.netloc


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *args, **kwargs):
        return None


def fixed_request(url, body, headers, limit, timeout=15):
    """No caller-controlled destination, redirects, ambient proxies, or verbose errors."""
    request = urllib.request.Request(url, data=body, headers=headers, method="POST")
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}), NoRedirect())
    try:
        with opener.open(request, timeout=timeout) as response:
            status, result = response.status, response.read(limit + 1)
    except urllib.error.HTTPError as response:
        with response:
            status, result = response.code, response.read(limit + 1)
    except (OSError, ValueError, urllib.error.URLError):
        raise AuthError("upstream_unavailable", 502) from None
    if len(result) > limit:
        raise AuthError("upstream_response_too_large", 502)
    return status, result


def steam_check(fields):
    outgoing = {key: value for key, value in fields.items() if key.startswith("openid.")}
    outgoing["openid.mode"] = "check_authentication"
    status, raw = fixed_request(STEAM_ENDPOINT, urlencode(outgoing).encode("ascii"),
                                {"Content-Type": "application/x-www-form-urlencoded"}, 8192)
    try:
        pairs = [line.split(":", 1) for line in raw.decode("utf-8").splitlines() if line]
        if any(len(pair) != 2 for pair in pairs) or len({pair[0] for pair in pairs}) != len(pairs):
            return False
        response = dict(pairs)
        return status == 200 and response.get("is_valid") == "true" and response.get("ns") == OPENID_NS
    except (ValueError, UnicodeError):
        return False


class Service:
    def __init__(self, settings, *, clock=time.time, verify_steam=steam_check, forward=None):
        settings.validate()
        self.settings, self.clock, self.verify_steam = settings, clock, verify_steam
        self.forward = forward or self._forward
        self.lock = threading.RLock()
        target = settings.database
        target.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
        if target.is_symlink() or target.parent.is_symlink():
            raise ValueError("auth_database_path_invalid")
        if os.name != "nt" and stat.S_IMODE(target.parent.stat().st_mode) & 0o077:
            raise ValueError("auth_database_directory_not_private")
        if not target.exists():
            descriptor = os.open(target, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
            os.close(descriptor)
        if not stat.S_ISREG(target.stat().st_mode):
            raise ValueError("auth_database_path_invalid")
        if os.name != "nt":
            os.chmod(target, 0o600)
        self.db = sqlite3.connect(target, check_same_thread=False, timeout=10)
        self.db.row_factory = sqlite3.Row
        self.db.executescript("""
            PRAGMA journal_mode=DELETE;
            PRAGMA foreign_keys=ON;
            CREATE TABLE IF NOT EXISTS challenges(
                device_hash TEXT PRIMARY KEY, user_code TEXT UNIQUE NOT NULL,
                account TEXT NOT NULL, match_id TEXT NOT NULL,
                created INTEGER NOT NULL, expires INTEGER NOT NULL,
                approved_steam TEXT, approved_at INTEGER, token_hash TEXT UNIQUE,
                token_expires INTEGER, revoked INTEGER NOT NULL DEFAULT 0,
                last_poll INTEGER NOT NULL DEFAULT 0);
            CREATE TABLE IF NOT EXISTS browsers(
                sid_hash TEXT PRIMARY KEY, csrf_hash TEXT NOT NULL,
                steam TEXT, expires INTEGER NOT NULL);
            CREATE TABLE IF NOT EXISTS flows(
                state_hash TEXT PRIMARY KEY, sid_hash TEXT NOT NULL,
                user_code TEXT NOT NULL, return_to_hash TEXT NOT NULL,
                expires INTEGER NOT NULL, used INTEGER NOT NULL DEFAULT 0);
            CREATE TABLE IF NOT EXISTS nonces(nonce_hash TEXT PRIMARY KEY, expires INTEGER NOT NULL);
            CREATE TABLE IF NOT EXISTS limits(
                key TEXT NOT NULL, bucket INTEGER NOT NULL, count INTEGER NOT NULL,
                PRIMARY KEY(key,bucket));
        """)
        self.db.commit()

    def close(self):
        with self.lock:
            self.db.close()

    def _derived(self, label):
        return hmac.new(bytes.fromhex(self.settings.secret), label.encode(), hashlib.sha256).hexdigest()

    def rate(self, scope, actor, maximum):
        now = int(self.clock())
        key, bucket = self._derived("rate:" + scope + ":" + actor), now // 60
        with self.lock, self.db:
            self.db.execute("DELETE FROM limits WHERE bucket < ?", (bucket - 1,))
            self.db.execute("INSERT INTO limits VALUES(?,?,1) ON CONFLICT(key,bucket) DO UPDATE SET count=count+1", (key, bucket))
            count = self.db.execute("SELECT count FROM limits WHERE key=? AND bucket=?", (key, bucket)).fetchone()[0]
        if count > maximum:
            raise AuthError("rate_limited", 429)

    def _identity(self, payload, extra=()):
        if (not isinstance(payload, dict)
                or set(payload) != {"account_id", "match_session_id", *extra}
                or not isinstance(payload.get("account_id"), str)
                or payload["account_id"] not in self.settings.accounts):
            raise AuthError("test_account_not_allowed", 403)
        if not isinstance(payload.get("match_session_id"), str) or not SESSION.fullmatch(payload["match_session_id"]):
            raise AuthError("match_session_invalid")
        return payload["account_id"], payload["match_session_id"]

    def start(self, payload, peer):
        account, match = self._identity(payload)
        self.rate("start-ip", peer, 24)
        self.rate("start-account", account, 8)
        now = int(self.clock())
        device = secrets.token_urlsafe(32)
        code = "".join(secrets.choice("ABCDEFGHJKLMNPQRSTUVWXYZ23456789") for _ in range(8))
        with self.lock, self.db:
            self.db.execute("DELETE FROM challenges WHERE expires < ? AND COALESCE(token_expires,0) < ?", (now - 86400, now - 86400))
            self.db.execute("DELETE FROM browsers WHERE expires < ?", (now,))
            self.db.execute("DELETE FROM flows WHERE expires < ?", (now,))
            self.db.execute("DELETE FROM nonces WHERE expires < ?", (now,))
            self.db.execute("INSERT INTO challenges(device_hash,user_code,account,match_id,created,expires) VALUES(?,?,?,?,?,?)",
                            (digest(device), code, account, match, now, now + PENDING_TTL))
        return {"ok": True, "status": "pending", "device_code": device, "user_code": code,
                "verification_uri": self.settings.public_base + "/authorize?" + urlencode({"code": code}),
                "expires_in": PENDING_TTL, "poll_interval": POLL_INTERVAL}

    def _token(self, device_hash):
        return "pwa1_" + self._derived("access:" + device_hash)

    def poll(self, payload, peer):
        account, match = self._identity(payload, ("device_code",))
        device = payload.get("device_code")
        if not isinstance(device, str) or not OPAQUE.fullmatch(device):
            raise AuthError("device_code_invalid", 403)
        self.rate("poll-ip", peer, 240)
        now = int(self.clock())
        with self.lock, self.db:
            row = self.db.execute("SELECT * FROM challenges WHERE device_hash=?", (digest(device),)).fetchone()
            if row is None or row["account"] != account or row["match_id"] != match or row["revoked"]:
                raise AuthError("device_code_invalid", 403)
            if row["approved_at"] is not None:
                if row["token_expires"] <= now:
                    raise AuthError("player_session_expired", 403)
                return {"ok": True, "status": "approved", "access_token": self._token(row["device_hash"]),
                        "expires_in": row["token_expires"] - now, "account_id": account,
                        "match_session_id": match, "local_progress_unverified": self.settings.isolated_local_progress}
            if row["expires"] <= now:
                raise AuthError("device_code_expired", 403)
            if row["last_poll"] and now - row["last_poll"] < POLL_INTERVAL:
                raise AuthError("slow_down", 429)
            self.db.execute("UPDATE challenges SET last_poll=? WHERE device_hash=?", (now, row["device_hash"]))
        return {"ok": True, "status": "pending", "poll_interval": POLL_INTERVAL}

    def browser(self, sid=None):
        now = int(self.clock())
        with self.lock, self.db:
            if isinstance(sid, str) and OPAQUE.fullmatch(sid):
                row = self.db.execute("SELECT * FROM browsers WHERE sid_hash=? AND expires>?", (digest(sid), now)).fetchone()
                if row:
                    return sid, row, False
            sid = secrets.token_urlsafe(32)
            csrf = self._derived("csrf:" + sid)
            self.db.execute("INSERT INTO browsers VALUES(?,?,NULL,?)", (digest(sid), digest(csrf), now + SESSION_TTL))
            row = self.db.execute("SELECT * FROM browsers WHERE sid_hash=?", (digest(sid),)).fetchone()
            return sid, row, True

    def challenge(self, code):
        if not isinstance(code, str) or not USER_CODE.fullmatch(code):
            raise AuthError("authorization_code_invalid", 404)
        with self.lock:
            row = self.db.execute("SELECT * FROM challenges WHERE user_code=?", (code,)).fetchone()
            if row is None or row["revoked"] or row["expires"] <= int(self.clock()):
                raise AuthError("authorization_code_expired", 404)
            return row

    def login(self, code, sid, peer):
        self.rate("steam-login", peer, 24)
        self.challenge(code)
        sid, _, _ = self.browser(sid)
        state = secrets.token_urlsafe(32)
        return_to = self.settings.public_base + "/steam/callback?" + urlencode({"state": state})
        with self.lock, self.db:
            self.db.execute("INSERT INTO flows VALUES(?,?,?,?,?,0)",
                            (digest(state), digest(sid), code, digest(return_to), int(self.clock()) + PENDING_TTL))
        values = {"openid.ns": OPENID_NS, "openid.mode": "checkid_setup",
                  "openid.claimed_id": IDENTIFIER_SELECT, "openid.identity": IDENTIFIER_SELECT,
                  "openid.return_to": return_to, "openid.realm": self.settings.public_base + "/"}
        return sid, STEAM_ENDPOINT + "?" + urlencode(values)

    def callback(self, fields, sid, peer):
        self.rate("steam-callback", peer, 30)
        state = fields.get("state")
        if (not isinstance(sid, str) or not OPAQUE.fullmatch(sid)
                or not isinstance(state, str) or not OPAQUE.fullmatch(state)):
            raise AuthError("steam_state_invalid", 403)
        now = int(self.clock())
        with self.lock, self.db:
            flow = self.db.execute("SELECT * FROM flows WHERE state_hash=?", (digest(state),)).fetchone()
            browser = self.db.execute("SELECT * FROM browsers WHERE sid_hash=? AND expires>?", (digest(sid), now)).fetchone()
            if (flow is None or browser is None or flow["used"] or flow["expires"] <= now
                    or not equal(flow["sid_hash"], digest(sid))):
                raise AuthError("steam_state_invalid", 403)
            self.db.execute("UPDATE flows SET used=1 WHERE state_hash=?", (digest(state),))
        required = {"op_endpoint", "claimed_id", "identity", "return_to", "response_nonce", "assoc_handle"}
        signed = fields.get("openid.signed", "").split(",")
        if (fields.get("openid.ns") != OPENID_NS or fields.get("openid.mode") != "id_res"
                or fields.get("openid.op_endpoint") != STEAM_ENDPOINT
                or not equal(digest(fields.get("openid.return_to", "")), flow["return_to_hash"])
                or len(signed) != len(set(signed)) or not required.issubset(signed)
                or any(not re.fullmatch(r"[a-z_]+", name) for name in signed)
                or any(not fields.get("openid." + name) for name in signed)
                or not fields.get("openid.sig")):
            raise AuthError("steam_assertion_invalid", 403)
        claimed = fields.get("openid.claimed_id", "")
        match = re.fullmatch(r"https://steamcommunity\.com/openid/id/(7656119\d{10})", claimed)
        if match is None or claimed != fields.get("openid.identity"):
            raise AuthError("steam_identity_invalid", 403)
        steam = match[1]
        if steam not in self.settings.steam_ids:
            raise AuthError("test_account_not_allowed", 403)
        nonce = fields.get("openid.response_nonce", "")
        try:
            if not 21 <= len(nonce) <= 255:
                raise ValueError()
            stamp = int(datetime.strptime(nonce[:20], "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc).timestamp())
        except ValueError:
            raise AuthError("steam_nonce_invalid", 403) from None
        if stamp < now - 300 or stamp > now + 30:
            raise AuthError("steam_nonce_expired", 403)
        with self.lock:
            if self.db.execute("SELECT 1 FROM nonces WHERE nonce_hash=?", (digest(nonce),)).fetchone():
                raise AuthError("steam_nonce_replayed", 403)
        if not self.verify_steam(fields):
            raise AuthError("steam_assertion_rejected", 403)
        try:
            with self.lock, self.db:
                self.db.execute("INSERT INTO nonces VALUES(?,?)", (digest(nonce), now + 600))
                self.db.execute("UPDATE browsers SET steam=? WHERE sid_hash=?", (steam, digest(sid)))
        except sqlite3.IntegrityError:
            raise AuthError("steam_nonce_replayed", 403) from None
        return flow["user_code"]

    def approve(self, payload, sid, origin, peer):
        self.rate("approve", peer, 30)
        if origin != self.settings.origin:
            raise AuthError("origin_rejected", 403)
        if not isinstance(payload, dict) or set(payload) != {"code", "csrf"}:
            raise AuthError("authorization_fields_invalid")
        if not isinstance(sid, str) or not OPAQUE.fullmatch(sid):
            raise AuthError("browser_session_invalid", 403)
        now = int(self.clock())
        with self.lock, self.db:
            browser = self.db.execute("SELECT * FROM browsers WHERE sid_hash=? AND expires>?", (digest(sid), now)).fetchone()
            if browser is None or not browser["steam"]:
                raise AuthError("steam_login_required", 403)
            csrf = payload.get("csrf")
            if not isinstance(csrf, str) or not equal(digest(csrf), browser["csrf_hash"]):
                raise AuthError("csrf_rejected", 403)
            row = self.challenge(payload.get("code"))
            if browser["steam"] != self.settings.accounts[row["account"]]:
                raise AuthError("steam_account_mismatch", 403)
            if row["approved_at"] is None:
                token = self._token(row["device_hash"])
                # A new approval for this account revokes older local game grants.
                self.db.execute("UPDATE challenges SET revoked=1 WHERE account=? AND device_hash!=? AND approved_at IS NOT NULL",
                                (row["account"], row["device_hash"]))
                self.db.execute("UPDATE challenges SET approved_steam=?,approved_at=?,token_hash=?,token_expires=? WHERE device_hash=?",
                                (browser["steam"], now, digest(token), now + SESSION_TTL, row["device_hash"]))
        return {"ok": True, "status": "approved"}

    def principal(self, bearer, payload):
        if not isinstance(bearer, str) or not re.fullmatch(r"pwa1_[a-f0-9]{64}", bearer):
            raise AuthError("player_session_required", 403)
        with self.lock:
            row = self.db.execute("SELECT * FROM challenges WHERE token_hash=?", (digest(bearer),)).fetchone()
        if row is None or row["revoked"] or row["token_expires"] <= int(self.clock()):
            raise AuthError("player_session_expired", 403)
        if (not isinstance(payload, dict) or payload.get("account_id") != row["account"]
                or payload.get("match_session_id") != row["match_id"]):
            raise AuthError("player_session_identity_mismatch", 403)
        return row

    def proxy(self, path, bearer, payload, peer):
        allowed = READ_PATHS | (LOCAL_PROGRESS_PATHS if self.settings.isolated_local_progress else frozenset())
        if path not in allowed:
            raise AuthError("player_route_not_allowed", 403)
        row = self.principal(bearer, payload)
        self.rate("proxy", row["account"], 300)
        raw = json.dumps(payload, separators=(",", ":"), ensure_ascii=False).encode("utf-8")
        if len(raw) > BODY_LIMIT:
            raise AuthError("request_body_too_large", 413)
        status, body = self.forward(path, raw)
        if not isinstance(body, bytes) or len(body) > 8 * 1024 * 1024:
            raise AuthError("upstream_response_too_large", 502)
        try:
            result = json.loads(body)
            if not isinstance(result, dict):
                raise ValueError()
        except (ValueError, UnicodeError):
            raise AuthError("upstream_response_invalid", 502) from None
        return status, body

    def _forward(self, path, raw):
        return fixed_request(self.settings.upstream + path, raw,
                             {"Authorization": "Bearer " + self.settings.upstream_bearer,
                              "Content-Type": "application/json; charset=utf-8"}, 8 * 1024 * 1024, 30)

    def page(self, code, sid):
        row = self.challenge(code)
        sid, browser, fresh = self.browser(sid)
        base = self.settings.public_base
        escape = html.escape
        text = "<h1>生存守城 · 测试授权</h1><p>登录将前往 Steam 官方页面；本站不收集 Steam 密码。</p>"
        text += "<p>游戏账号尾号：" + escape(row["account"][-4:]) + "</p>"
        text += "<p>授权码：" + escape(code) + "。只有当此码与你正在玩的游戏内显示一致时才继续。</p>"
        if self.settings.isolated_local_progress:
            text += "<p>确认后，本次游戏可以读取并保存你的独立测试进度。本地主机进度可能被房主修改，不作为可信战果。</p>"
        else:
            text += "<p>确认后，本次游戏可以读取你的测试存档和已有权益，不能上传战斗进度。</p>"
        text += "<p>本测试不开放正式排行和真实支付。</p>"
        if browser["steam"]:
            text += "<p>已登录 Steam 尾号：" + escape(browser["steam"][-4:]) + "</p>"
            if browser["steam"] != self.settings.accounts[row["account"]]:
                text += "<p>当前 Steam 与游戏账号不一致，不能授权。请切换 Steam 账号后重新登录。</p>"
            else:
                text += ('<form method="post" action="' + escape(base + "/authorize", quote=True) + '">'
                         '<input type="hidden" name="code" value="' + code + '">'
                         '<input type="hidden" name="csrf" value="' + self._derived("csrf:" + sid) + '">'
                         '<button type="submit">确认授权本次对局</button></form>')
        text += '<p><a href="' + escape(base + "/steam/login?" + urlencode({"code": code}), quote=True) + '">前往 Steam 官方登录</a></p>'
        document = '<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>WS4 测试授权</title><body>' + text + "</body></html>"
        return sid, fresh, document.encode("utf-8")
