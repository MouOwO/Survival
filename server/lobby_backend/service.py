"""Bounded in-memory lobby; identities and native worker readiness are injected.

No live worker is assumed. A worker address belongs to trusted configuration,
never a player request. Lobby tickets do not attest battle results or replace
the Dota worker's engine-Steam-ID/immutable-roster admission check.
"""
from __future__ import annotations

from copy import deepcopy
from dataclasses import dataclass
import hashlib
import ipaddress
import json
import re
import secrets
import threading
import time

STEAM_BASE = 76561197960265728
NAME = re.compile(r"[A-Za-z0-9_-]{8,128}\Z")
SHA = re.compile(r"[a-f0-9]{64}\Z")
USER_FIELDS = frozenset(("account_id", "match_session_id", "request_id"))
ACTIONS = frozenset(("rooms","room","create","invite","join","ready","start","leave","close",
                     "ticket","reconnect","redeem","worker-heartbeat","worker-claim"))


class LobbyError(Exception):
    def __init__(self, code, status=400):
        self.code, self.status = code, status
        self.context = None
        super().__init__(code)


def need(value, code, status=400):
    if not value:
        raise LobbyError(code, status)


def digest(value):
    return hashlib.sha256(value.encode("utf-8")).hexdigest()


def steam_account(steam):
    need(isinstance(steam, str) and re.fullmatch(r"7656119\d{10}", steam), "steam_configuration_invalid", 503)
    account = int(steam) - STEAM_BASE
    need(0 < account <= 0xFFFFFFFF, "steam_configuration_invalid", 503)
    return str(account)


@dataclass(frozen=True)
class Principal:
    steam_id: str
    account_id: str
    source_session_id: str


class AuthServicePrincipalAdapter:
    """Use existing verified pwa1 identity only; never call its cloud proxy."""
    def __init__(self, auth_service):
        self.auth = auth_service
        accounts = auth_service.settings.accounts
        need(isinstance(accounts, dict) and len(accounts) == 4 and len(set(accounts.values())) == 4,
             "four_accounts_required", 503)
        for account, steam in accounts.items():
            need(steam_account(steam) == account, "steam_configuration_invalid", 503)
        self.allowed_steam_ids = frozenset(accounts.values())

    def __call__(self, bearer, payload):
        try:
            row = self.auth.principal(bearer, payload)
            account, session = row["account"], row["match_id"]
            steam = self.auth.settings.accounts.get(account)
        except Exception:
            raise LobbyError("lobby_identity_required", 401) from None
        need(steam in self.allowed_steam_ids and isinstance(session, str), "lobby_identity_required", 401)
        return Principal(steam, account, session)


@dataclass(frozen=True)
class WorkerSpec:
    worker_id: str
    connect_address: str
    build_sha256: str

    def validate(self):
        need(isinstance(self.worker_id, str) and NAME.fullmatch(self.worker_id), "worker_configuration_invalid", 503)
        need(isinstance(self.build_sha256, str) and SHA.fullmatch(self.build_sha256), "worker_configuration_invalid", 503)
        try:
            address, port = self.connect_address.rsplit(":", 1)
            parsed = ipaddress.IPv4Address(address)
            valid = str(parsed) == address and str(int(port)) == port and 1024 <= int(port) <= 65535
        except (ValueError, AttributeError):
            valid = False
        need(valid, "worker_configuration_invalid", 503)


class LobbyService:
    WORKER_TTL, LEASE_TTL, TICKET_TTL, INVITE_TTL = 15, 30, 60, 600

    def __init__(self, *, allowed_steam_ids=(), build_sha256=None, principal_verifier=None,
                 worker_verifier=None, readiness_verifier=None, workers=(), clock=time.time):
        allowed = tuple(allowed_steam_ids)
        need(not allowed or len(allowed) == len(set(allowed)) == 4, "four_accounts_required", 503)
        self.accounts = {steam: steam_account(steam) for steam in allowed}
        need(build_sha256 is None or isinstance(build_sha256, str) and SHA.fullmatch(build_sha256),
             "build_configuration_invalid", 503)
        self.build = build_sha256
        self.principal_verifier, self.worker_verifier = principal_verifier, worker_verifier
        self.readiness_verifier, self.clock = readiness_verifier, clock
        self.lock = threading.RLock()
        self.rooms, self.invites, self.tickets, self.cache, self.limits, self.workers = {}, {}, {}, {}, {}, {}
        for spec in workers:
            need(isinstance(spec, WorkerSpec), "worker_configuration_invalid", 503)
            spec.validate()
            need(spec.worker_id not in self.workers and spec.build_sha256 == self.build,
                 "worker_configuration_invalid", 503)
            self.workers[spec.worker_id] = dict(spec=spec, state="OFFLINE", generation=0,
                lease_id=None, room_id=None, match_id=None, last_seen=0, lease_expires=0)

    @classmethod
    def from_auth_service(cls, auth_service, **kwargs):
        adapter = AuthServicePrincipalAdapter(auth_service)
        return cls(allowed_steam_ids=adapter.allowed_steam_ids, principal_verifier=adapter, **kwargs)

    def _now(self):
        return int(self.clock())

    def _expire(self):
        now = self._now()
        self.invites = {key:value for key,value in self.invites.items() if value["expires_at"] > now}
        self.tickets = {key:value for key,value in self.tickets.items() if value["expires_at"] > now}
        self.cache = {key:value for key,value in self.cache.items() if value[0] > now}
        self.limits = {key:value for key,value in self.limits.items() if key[1] >= now // 60 - 1}
        for worker in self.workers.values():
            if worker["state"] != "OFFLINE" and (worker["last_seen"] + self.WORKER_TTL <= now
                    or worker["lease_id"] and worker["lease_expires"] <= now):
                room = self.rooms.get(worker["room_id"])
                if room and room["state"] not in ("CLOSED", "INTERRUPTED"):
                    room["state"], room["version"] = "INTERRUPTED", room["version"] + 1
                worker.update(state="OFFLINE", lease_id=None, room_id=None, match_id=None, lease_expires=0)

    def _rate(self, actor):
        key = actor, self._now() // 60
        count = self.limits.get(key, 0)
        need(count < 120, "lobby_rate_limited", 429)
        self.limits[key] = count + 1

    def health(self):
        with self.lock:
            self._expire()
            return dict(ok=True, kind="WS4-LOBBY-1", mode="session_memory_only",
                identity_adapter_configured=callable(self.principal_verifier),
                worker_verifier_configured=callable(self.worker_verifier),
                readiness_verifier_configured=callable(self.readiness_verifier),
                registered_workers=len(self.workers), available_workers=sum(w["state"] == "IDLE" for w in self.workers.values()),
                cloud_archive_enabled=False, commerce_enabled=False)

    def _principal(self, bearer, payload):
        need(callable(self.principal_verifier), "lobby_identity_unavailable", 401)
        try:
            principal = self.principal_verifier(bearer, payload)
        except Exception:
            raise LobbyError("lobby_identity_required", 401) from None
        need(isinstance(principal, Principal) and principal.steam_id in self.accounts
             and self.accounts[principal.steam_id] == principal.account_id
             and payload.get("account_id") == principal.account_id
             and payload.get("match_session_id") == principal.source_session_id,
             "lobby_identity_required", 401)
        return principal

    def _live_room_worker(self, room):
        worker = self.workers.get(room.get("worker_id"))
        return bool(worker and room["state"] in ("READY","RUNNING")
            and worker["state"] in ("READY","RUNNING") and worker["room_id"] == room["room_id"]
            and worker["match_id"] == room.get("match_id") and worker["lease_id"]
            and worker["lease_id"] == room.get("lease_id") and worker["generation"] == room.get("worker_generation")
            and worker["lease_expires"] > self._now() and worker["last_seen"] + self.WORKER_TTL > self._now()
            and worker["spec"].build_sha256 == self.build)

    def response_context(self, actor=None, room_id=None):
        with self.lock:
            self._expire()
            available = any(w["state"] == "IDLE" for w in self.workers.values())
            room = self.rooms.get(room_id) if isinstance(room_id,str) else None
            if room and actor in room["members"] and room.get("match_id"):
                available = self._live_room_worker(room)
            elif actor is not None:
                owned = [r for r in self.rooms.values() if actor in r["members"] and r["state"] != "CLOSED"]
                current = next((r for r in owned if r["state"] != "INTERRUPTED"), owned[-1] if owned else None)
                if current and current.get("match_id"):
                    available = self._live_room_worker(current)
            return dict(worker_available=available,build_sha256=self.build)

    def _worker(self, bearer):
        need(callable(self.worker_verifier), "worker_identity_unavailable", 401)
        try:
            identifier = self.worker_verifier(bearer)
        except Exception:
            raise LobbyError("worker_identity_required", 401) from None
        need(isinstance(identifier, str) and identifier in self.workers, "worker_identity_required", 401)
        return self.workers[identifier]

    @staticmethod
    def _fields(payload, required, optional=()):
        need(required <= payload.keys() and payload.keys() <= required | set(optional), "lobby_fields_invalid")

    def _room(self, identifier, actor):
        room = self.rooms.get(identifier) if isinstance(identifier, str) else None
        need(room is not None and actor in room["members"], "room_not_found", 404)
        return room

    @staticmethod
    def _version(room, expected):
        need(type(expected) is int and room["version"] == expected, "room_version_conflict", 409)

    @staticmethod
    def _owner(room, actor):
        need(room["owner"] == actor, "room_owner_required", 403)

    def _view(self, room, actor):
        return dict(room_id=room["room_id"], version=room["version"], state=room["state"],
            self_member_id=room["members"][actor]["member_id"], max_players=4, match_id=room.get("match_id"),
            members=[dict(member_id=member["member_id"], ready=member["ready"], owner=key == room["owner"])
                     for key,member in room["members"].items()],
            build_sha256=self.build, mode="session_memory_only", cloud_archive_enabled=False, commerce_enabled=False)

    def dispatch(self, action, bearer, payload):
        try:
            return self._dispatch(action,bearer,payload)
        except LobbyError as error:
            if action not in ("worker-heartbeat","worker-claim") and isinstance(payload,dict):
                try:
                    principal = self._principal(bearer,payload)
                    error.context = self.response_context(principal.steam_id,payload.get("room_id"))
                except LobbyError:
                    pass
            raise

    def _dispatch(self, action, bearer, payload):
        need(isinstance(payload, dict), "lobby_fields_invalid")
        need(action in ACTIONS,
             "lobby_action_not_found",404)
        worker_action = action in ("worker-heartbeat", "worker-claim")
        with self.lock:
            self._expire()
            identity = self._worker(bearer) if worker_action else self._principal(bearer, payload)
            actor = identity["spec"].worker_id if worker_action else identity.steam_id
            self._rate(("worker:" if worker_action else "player:") + actor)
            mutating = action not in ("rooms", "room", "worker-claim")
            request = payload.get("request_id")
            if mutating or request is not None:
                need(isinstance(request, str) and NAME.fullmatch(request), "request_id_required")
            fingerprint = digest(json.dumps({"action":action,"payload":payload}, sort_keys=True, separators=(",",":")))
            key = ("worker" if worker_action else "player", actor, request)
            if mutating and key in self.cache:
                _, saved_hash, response = self.cache[key]
                need(saved_hash == fingerprint, "request_id_conflict", 409)
                response = deepcopy(response)
                if not worker_action: response.update(self.response_context(actor,payload.get("room_id")))
                return response
            if mutating:
                need(len(self.cache) < 1024, "lobby_capacity_reached", 503)
            data = dict(payload) if worker_action else {k:v for k,v in payload.items() if k not in USER_FIELDS}
            result = self._worker_action(action, identity, data) if worker_action else self._action(action, actor, data)
            response = dict(ok=True, **result)
            if not worker_action: response.update(self.response_context(actor,payload.get("room_id")))
            if mutating:
                expires = min(self._now() + 300, result.get("expires_at", self._now() + 300))
                if worker_action:
                    expires = min(expires,self._now()+self.WORKER_TTL-1)
                self.cache[key] = expires, fingerprint, deepcopy(response)
            return response

    def _action(self, action, actor, data):
        if action == "rooms":
            self._fields(data, set())
            return {"rooms":[self._view(r,actor) for r in self.rooms.values() if actor in r["members"] and r["state"] != "CLOSED"]}
        if action == "create":
            self._fields(data, set())
            need(len(self.rooms) < 32, "lobby_capacity_reached", 503)
            need(not any(actor in r["members"] and r["state"] not in ("CLOSED","INTERRUPTED") for r in self.rooms.values()),
                 "already_in_room", 409)
            identifier = secrets.token_urlsafe(18)
            room = dict(room_id=identifier, owner=actor, version=1, state="OPEN",
                members={actor:dict(member_id=secrets.token_urlsafe(12), ready=False)}, match_id=None)
            self.rooms[identifier] = room
            return {"room":self._view(room,actor)}
        if action == "join":
            self._fields(data, {"invite_code"})
            code = data["invite_code"]
            invite = self.invites.get(digest(code)) if isinstance(code,str) else None
            need(invite is not None, "invite_invalid_or_expired", 404)
            room = self.rooms[invite["room_id"]]
            need(room["state"] == "OPEN", "room_not_open", 409)
            need(actor not in room["members"] and len(room["members"]) < 4, "room_full_or_already_joined", 409)
            need(not any(actor in r["members"] and r["state"] not in ("CLOSED","INTERRUPTED") for r in self.rooms.values()),
                 "already_in_room", 409)
            room["members"][actor] = dict(member_id=secrets.token_urlsafe(12),ready=False)
            room["version"] += 1
            del self.invites[digest(code)]
            return {"room":self._view(room,actor)}
        required = {"room_id"}
        if action in ("invite","ready","start","leave","close"):
            required.add("expected_version")
        if action == "ready": required.add("ready")
        if action == "redeem": required.add("ticket")
        self._fields(data,required)
        room = self._room(data["room_id"], actor)
        if action == "room":
            need(set(data) == {"room_id"}, "lobby_fields_invalid")
            return {"room":self._view(room,actor)}
        if action in ("invite","ready","start","leave","close"):
            self._version(room,data["expected_version"])
        if action == "invite":
            self._owner(room,actor)
            need(room["state"] == "OPEN" and len(self.invites) < 64, "room_not_open_or_invites_full", 409)
            code = secrets.token_urlsafe(12)
            expires = self._now() + self.INVITE_TTL
            self.invites[digest(code)] = dict(room_id=room["room_id"],expires_at=expires)
            return dict(invite_code=code,expires_at=expires,room=self._view(room,actor))
        if action == "ready":
            need(room["state"] == "OPEN" and type(data.get("ready")) is bool, "room_not_open_or_ready_invalid", 409)
            room["members"][actor]["ready"] = data["ready"]
            room["version"] += 1
            return {"room":self._view(room,actor)}
        if action == "start":
            self._owner(room,actor)
            need(room["state"] == "OPEN" and all(m["ready"] for m in room["members"].values()), "room_not_ready", 409)
            available = [w for w in self.workers.values() if w["state"] == "IDLE" and w["spec"].build_sha256 == self.build]
            need(available, "no_ready_worker", 503)
            worker = sorted(available,key=lambda w:w["spec"].worker_id)[0]
            worker.update(generation=worker["generation"]+1,lease_id=secrets.token_urlsafe(24),
                          room_id=room["room_id"],match_id=secrets.token_urlsafe(24),state="ALLOCATING",
                          lease_expires=self._now()+self.LEASE_TTL)
            room.update(state="ALLOCATING",version=room["version"]+1,match_id=worker["match_id"],worker_id=worker["spec"].worker_id,
                        lease_id=worker["lease_id"],worker_generation=worker["generation"])
            return {"room":self._view(room,actor)}
        if action == "leave":
            need(room["state"] == "OPEN" and actor != room["owner"], "owner_must_close_or_room_started", 409)
            del room["members"][actor]; room["version"] += 1
            return dict(left=True,room_id=room["room_id"],version=room["version"])
        if action == "close":
            self._owner(room,actor)
            need(room["state"] in ("OPEN","INTERRUPTED"), "running_worker_must_stop_first", 409)
            room["state"],room["version"] = "CLOSED",room["version"]+1
            return {"room":self._view(room,actor)}
        need(action in ("ticket","reconnect","redeem"), "lobby_action_not_found", 404)
        need(room["state"] in ("READY","RUNNING"), "match_not_ready", 409)
        worker = self.workers[room["worker_id"]]
        need(worker["lease_id"] and worker["match_id"] == room["match_id"], "match_lease_expired", 409)
        if action in ("ticket","reconnect"):
            need(set(data) == {"room_id"}, "lobby_fields_invalid")
            need(len(self.tickets) < 128, "lobby_capacity_reached", 503)
            self.tickets = {k:v for k,v in self.tickets.items() if (v["match_id"],v["actor"]) != (room["match_id"],actor)}
            token, expires = secrets.token_urlsafe(32), self._now()+self.TICKET_TTL
            self.tickets[digest(token)] = dict(actor=actor,room_id=room["room_id"],match_id=room["match_id"],
                worker_id=worker["spec"].worker_id,generation=worker["generation"],lease_id=worker["lease_id"],
                build_sha256=self.build,expires_at=expires,used=False,purpose=action)
            return dict(ticket=token,expires_at=expires,match_id=room["match_id"],build_sha256=self.build,purpose=action)
        need(set(data) == {"room_id","ticket"} and isinstance(data["ticket"],str), "lobby_fields_invalid")
        ticket = self.tickets.get(digest(data["ticket"]))
        need(ticket and not ticket["used"] and ticket["actor"] == actor and ticket["room_id"] == room["room_id"]
             and ticket["match_id"] == room["match_id"] and ticket["worker_id"] == worker["spec"].worker_id
             and ticket["generation"] == worker["generation"] and ticket["lease_id"] == worker["lease_id"]
             and ticket["build_sha256"] == self.build, "join_ticket_invalid_or_used", 403)
        ticket["used"] = True
        return dict(connect_address=worker["spec"].connect_address,match_id=room["match_id"],build_sha256=self.build,
                    admission="verified_lobby_member",native_connection_verified=False,expires_at=ticket["expires_at"])

    def _worker_action(self, action, worker, data):
        spec = worker["spec"]
        if action == "worker-claim":
            self._fields(data,set())
            need(worker["lease_id"] is not None, "worker_no_assignment", 404)
            room = self.rooms[worker["room_id"]]
            return dict(assignment=dict(worker_id=spec.worker_id,room_id=room["room_id"],match_id=room["match_id"],
                lease_id=worker["lease_id"],generation=worker["generation"],lease_expires=worker["lease_expires"],
                build_sha256=self.build,map="template_map",sv_cheats=0,mode="session_memory_only",
                accounts=[self.accounts[steam] for steam in room["members"]],
                cloud_archive_enabled=False,commerce_enabled=False))
        self._fields(data,{"request_id","generation","lease_id","state","evidence"})
        need(type(data["generation"]) is int and data["generation"] == worker["generation"]
             and data["lease_id"] == worker["lease_id"], "worker_stale_lease", 409)
        desired = data["state"]
        need(desired in ("idle","starting","ready","running","stopped"), "worker_state_invalid")
        evidence = data["evidence"]
        need(isinstance(evidence,dict) and evidence.get("build_sha256") == self.build
             and evidence.get("mode") == "session_memory_only" and type(evidence.get("sv_cheats")) is int
             and evidence["sv_cheats"] == 0 and evidence.get("cloud_archive_enabled") is False
             and evidence.get("commerce_enabled") is False,"worker_evidence_invalid",403)
        if desired in ("ready","running"):
            need(evidence.get("native_ready") is True and evidence.get("map") == "template_map"
                 and type(evidence.get("game_pid")) is int and evidence["game_pid"] > 0,
                 "worker_native_not_ready",403)
        need(callable(self.readiness_verifier), "worker_readiness_unavailable", 503)
        try:
            verified = self.readiness_verifier(spec.worker_id,deepcopy(data["evidence"]),desired)
        except Exception:
            verified = False
        need(verified is True, "worker_readiness_not_verified", 403)
        if desired == "idle":
            need(worker["lease_id"] is None, "worker_has_active_lease", 409)
            worker.update(state="IDLE",last_seen=self._now())
        else:
            need(worker["lease_id"] is not None, "worker_no_assignment", 409)
            room = self.rooms[worker["room_id"]]
            need(room["state"] not in ("CLOSED","INTERRUPTED"), "match_lease_expired", 409)
            if desired == "stopped":
                room["state"],room["version"] = "CLOSED",room["version"]+1
                worker.update(state="OFFLINE",lease_id=None,room_id=None,match_id=None,lease_expires=0,last_seen=self._now())
            else:
                worker.update(state=desired.upper(),last_seen=self._now(),lease_expires=self._now()+self.LEASE_TTL)
                if desired in ("ready","running"):
                    room["state"],room["version"] = desired.upper(),room["version"]+1
        return dict(worker_id=spec.worker_id,state=worker["state"],generation=worker["generation"],
                    lease_id=worker["lease_id"],lease_expires=worker["lease_expires"])
