"""Synthetic identities/workers and real loopback HTTP; no Dota/cloud access."""
import http.client
import json
import threading
import unittest
from concurrent.futures import ThreadPoolExecutor

from .http_api import Server
from .service import AuthServicePrincipalAdapter, LobbyError, LobbyService, Principal, STEAM_BASE, WorkerSpec

STEAMS = tuple(str(STEAM_BASE+n) for n in (101,102,103,104))
BUILD = "d"*64


class Fixture:
    def __init__(self, *, workers=True, verify_ready=True):
        self.now, self.serial = 10000, 0
        self.people = {"person-"+str(i):Principal(steam,str(int(steam)-STEAM_BASE),"source-session-"+str(i))
                       for i,steam in enumerate(STEAMS)}
        def principal(token,payload):
            return self.people.get(token)
        self.service = LobbyService(allowed_steam_ids=STEAMS,build_sha256=BUILD,principal_verifier=principal,
            worker_verifier=lambda token:"local-worker-1" if token == "fixture-worker-secret" else None,
            readiness_verifier=(lambda worker,evidence,state:evidence.get("fixture_verified") is True) if verify_ready else None,
            workers=(WorkerSpec("local-worker-1","127.0.0.1:27015",BUILD),) if workers else (),clock=lambda:self.now)

    def payload(self, actor=0, **data):
        self.serial += 1
        who = self.people["person-"+str(actor)]
        return dict(account_id=who.account_id,match_session_id=who.source_session_id,
                    request_id="request-"+str(self.serial).zfill(8),**data)

    def call(self,action,actor=0,**data):
        return self.service.dispatch(action,"person-"+str(actor),self.payload(actor,**data))

    def heartbeat(self,state="idle",generation=0,lease_id=None,**changes):
        self.serial += 1
        evidence = dict(build_sha256=BUILD,mode="session_memory_only",sv_cheats=0,
            cloud_archive_enabled=False,commerce_enabled=False,fixture_verified=True,
            native_ready=True,map="template_map",game_pid=1234)
        evidence.update(changes)
        return self.service.dispatch("worker-heartbeat","fixture-worker-secret",dict(
            request_id="heartbeat-"+str(self.serial).zfill(8),generation=generation,lease_id=lease_id,state=state,evidence=evidence))

    def room(self):
        return self.call("create")["room"]

    def started(self):
        room = self.room()
        room = self.call("ready",room_id=room["room_id"],expected_version=room["version"],ready=True)["room"]
        self.heartbeat()
        room = self.call("start",room_id=room["room_id"],expected_version=room["version"])["room"]
        assignment = self.service.dispatch("worker-claim","fixture-worker-secret",{})["assignment"]
        self.heartbeat("ready",assignment["generation"],assignment["lease_id"])
        return room,assignment


class ServiceTest(unittest.TestCase):
    def fail(self,code,call):
        with self.assertRaises(LobbyError) as caught: call()
        self.assertEqual(caught.exception.code,code)

    def test_closed_defaults_no_worker_no_auth_no_cloud(self):
        service = LobbyService()
        self.assertEqual(service.health()["available_workers"],0)
        self.assertFalse(service.health()["cloud_archive_enabled"])
        self.fail("lobby_identity_unavailable",lambda:service.dispatch("create","anything",{}))
        self.fail("worker_identity_unavailable",lambda:service.dispatch("worker-claim","anything",{}))

    def test_payload_identity_and_extra_connect_are_never_trusted(self):
        f = Fixture()
        payload = f.payload(0); payload["account_id"] = "102"
        self.fail("lobby_identity_required",lambda:f.service.dispatch("create","person-0",payload))
        self.fail("lobby_identity_required",lambda:f.service.dispatch("create","person-5",f.payload()))
        self.fail("lobby_fields_invalid",lambda:f.call("create",connect_address="evil.example:1"))
        self.assertEqual(f.service.rooms,{})

    def test_real_existing_auth_principal_adapter_and_no_cloud_forward(self):
        from player_web_auth import test_service as web_tests
        auth_fixture = web_tests.ServiceTest("runTest"); auth_fixture.setUp()
        try:
            _,grant,_ = auth_fixture.approved()
            service = LobbyService.from_auth_service(auth_fixture.service,build_sha256=BUILD,clock=lambda:auth_fixture.now)
            payload = dict(auth_fixture.identity,request_id="real-auth-0001")
            response = service.dispatch("create",grant["access_token"],payload)
            self.assertTrue(response["ok"])
            self.assertEqual(auth_fixture.forward_calls,[])
            wrong = dict(payload,account_id="999")
            self.fail("lobby_identity_required",lambda:service.dispatch("rooms",grant["access_token"],wrong))
            auth_fixture.now += 4*3600+1
            self.fail("lobby_identity_required",lambda:service.dispatch("rooms",grant["access_token"],payload))
        finally:
            auth_fixture.tearDown()

    def test_versions_owner_ready_and_invites(self):
        f = Fixture(); room = f.room(); identifier=room["room_id"]
        invitation=f.call("invite",room_id=identifier,expected_version=room["version"])
        joined=f.call("join",1,invite_code=invitation["invite_code"])["room"]
        self.assertEqual(len(joined["members"]),2)
        self.fail("invite_invalid_or_expired",lambda:f.call("join",2,invite_code=invitation["invite_code"]))
        self.fail("room_version_conflict",lambda:f.call("ready",room_id=identifier,expected_version=1,ready=True))
        self.fail("room_owner_required",lambda:f.call("start",1,room_id=identifier,expected_version=joined["version"]))
        self.fail("room_not_ready",lambda:f.call("start",room_id=identifier,expected_version=joined["version"]))

    def test_single_user_native_smoke_allocation_refuses_without_real_worker(self):
        f=Fixture(workers=False); room=f.room()
        room=f.call("ready",room_id=room["room_id"],expected_version=1,ready=True)["room"]
        self.fail("no_ready_worker",lambda:f.call("start",room_id=room["room_id"],expected_version=room["version"]))
        self.assertEqual(f.service.rooms[room["room_id"]]["state"],"OPEN")

    def test_ready_requires_separate_worker_identity_and_real_readiness_validator(self):
        f=Fixture(verify_ready=False)
        self.fail("worker_readiness_unavailable",lambda:f.heartbeat())
        self.assertEqual(f.service.health()["available_workers"],0)
        f=Fixture()
        self.fail("worker_identity_required",lambda:f.service.dispatch("worker-claim","person-0",{}))
        self.fail("worker_evidence_invalid",lambda:f.heartbeat(sv_cheats=1))
        self.fail("worker_readiness_not_verified",lambda:f.heartbeat(fixture_verified=False))
        self.assertEqual(f.service.health()["available_workers"],0)

    def test_claim_freezes_roster_build_and_memory_scope(self):
        f=Fixture(); room,assignment=f.started()
        self.assertNotEqual(assignment["match_id"],f.people["person-0"].source_session_id)
        self.assertEqual(assignment["accounts"],["101"])
        self.assertEqual(assignment["sv_cheats"],0)
        self.assertFalse(assignment["cloud_archive_enabled"])
        self.assertFalse(assignment["commerce_enabled"])
        self.assertEqual(assignment["build_sha256"],BUILD)
        self.fail("worker_stale_lease",lambda:f.heartbeat("ready",0,None))
        self.fail("room_not_open_or_invites_full",lambda:f.call("invite",room_id=room["room_id"],expected_version=4))

    def test_tickets_bound_single_use_and_reconnect_fresh_same_match(self):
        f=Fixture(); room,assignment=f.started(); identifier=room["room_id"]
        issued=f.call("ticket",room_id=identifier)
        result=f.call("redeem",room_id=identifier,ticket=issued["ticket"])
        self.assertEqual(result["connect_address"],"127.0.0.1:27015")
        self.assertFalse(result["native_connection_verified"])
        self.fail("join_ticket_invalid_or_used",lambda:f.call("redeem",room_id=identifier,ticket=issued["ticket"]))
        new=f.call("reconnect",room_id=identifier)
        self.assertNotEqual(new["ticket"],issued["ticket"])
        self.assertEqual(new["match_id"],assignment["match_id"])
        self.assertTrue(f.call("redeem",room_id=identifier,ticket=new["ticket"])["ok"])

    def test_tickets_other_account_room_build_generation_and_expiry_fail_closed(self):
        f=Fixture(); room,assignment=f.started(); issued=f.call("ticket",room_id=room["room_id"])
        self.fail("room_not_found",lambda:f.call("redeem",1,room_id=room["room_id"],ticket=issued["ticket"]))
        ticket=next(iter(f.service.tickets.values())); ticket["build_sha256"]="0"*64
        self.fail("join_ticket_invalid_or_used",lambda:f.call("redeem",room_id=room["room_id"],ticket=issued["ticket"]))
        ticket["build_sha256"]=BUILD; ticket["generation"]+=1
        self.fail("join_ticket_invalid_or_used",lambda:f.call("redeem",room_id=room["room_id"],ticket=issued["ticket"]))
        f.now+=61
        self.fail("match_not_ready",lambda:f.call("redeem",room_id=room["room_id"],ticket=issued["ticket"]))
        self.assertEqual(f.service.rooms[room["room_id"]]["state"],"INTERRUPTED")

    def test_heartbeat_loss_revokes_lease_and_never_fabricates_reconnect(self):
        f=Fixture(); room,assignment=f.started(); f.now+=16
        self.assertEqual(f.service.health()["available_workers"],0)
        self.fail("worker_stale_lease",lambda:f.heartbeat("ready",assignment["generation"],assignment["lease_id"]))
        self.fail("match_not_ready",lambda:f.call("reconnect",room_id=room["room_id"]))

    def test_idempotent_start_and_concurrent_same_ticket_redeem(self):
        f=Fixture(); room=f.room()
        payload=f.payload(room_id=room["room_id"],expected_version=1,ready=True)
        a=f.service.dispatch("ready","person-0",payload); b=f.service.dispatch("ready","person-0",payload)
        self.assertEqual(a,b)
        self.fail("request_id_conflict",lambda:f.service.dispatch("ready","person-0",dict(payload,ready=False)))
        f.heartbeat(); room=a["room"]
        payload=f.payload(room_id=room["room_id"],expected_version=room["version"])
        a=f.service.dispatch("start","person-0",payload); b=f.service.dispatch("start","person-0",payload)
        self.assertEqual(a,b)
        assignment=f.service.dispatch("worker-claim","fixture-worker-secret",{})["assignment"]
        f.heartbeat("ready",assignment["generation"],assignment["lease_id"])
        issued=f.call("ticket",room_id=room["room_id"])
        payloads=[f.payload(room_id=room["room_id"],ticket=issued["ticket"]) for _ in range(2)]
        def redeem(payload):
            try: return f.service.dispatch("redeem","person-0",payload)["ok"]
            except LobbyError: return False
        with ThreadPoolExecutor(max_workers=2) as pool: results=list(pool.map(redeem,payloads))
        self.assertEqual(sorted(results),[False,True])

    def test_no_address_registration_or_client_worker_selection(self):
        f=Fixture(); room=f.room()
        self.fail("lobby_fields_invalid",lambda:f.call("start",room_id=room["room_id"],expected_version=1,worker_id="evil"))
        with self.assertRaises(LobbyError): WorkerSpec("local-worker-1","127.0.0.1:27015;quit",BUILD).validate()
        self.assertEqual(f.service.health()["registered_workers"],1)

    def test_four_members_and_ticket_cannot_be_used_by_another_member(self):
        f=Fixture(); room=f.room(); identifier=room["room_id"]
        for actor in (1,2,3):
            invite=f.call("invite",room_id=identifier,expected_version=room["version"])
            room=f.call("join",actor,invite_code=invite["invite_code"])["room"]
        self.assertEqual(len(room["members"]),4)
        for actor in range(4):
            room=f.call("ready",actor,room_id=identifier,expected_version=room["version"],ready=True)["room"]
        f.heartbeat(); f.call("start",room_id=identifier,expected_version=room["version"])
        assignment=f.service.dispatch("worker-claim","fixture-worker-secret",{})["assignment"]
        self.assertEqual(set(assignment["accounts"]),{"101","102","103","104"})
        f.heartbeat("ready",assignment["generation"],assignment["lease_id"])
        issued=f.call("ticket",room_id=identifier)
        self.fail("join_ticket_invalid_or_used",lambda:f.call("redeem",1,room_id=identifier,ticket=issued["ticket"]))
        self.assertTrue(f.call("redeem",room_id=identifier,ticket=issued["ticket"])["ok"])

    def test_expired_ticket_rejected_even_while_native_worker_stays_ready(self):
        f=Fixture(); room,assignment=f.started(); issued=f.call("ticket",room_id=room["room_id"])
        for _ in range(6):
            f.now+=10; f.heartbeat("ready",assignment["generation"],assignment["lease_id"])
        f.now+=1
        self.fail("join_ticket_invalid_or_used",lambda:f.call("redeem",room_id=room["room_id"],ticket=issued["ticket"]))
        self.assertEqual(f.service.rooms[room["room_id"]]["state"],"READY")

    def test_capacity_refuses_before_any_room_side_effect_and_heartbeat_cache_expires(self):
        f=Fixture()
        f.service.cache={str(i):(f.now+100,"hash",{}) for i in range(1024)}
        self.fail("lobby_capacity_reached",lambda:f.call("create"))
        self.assertEqual(f.service.rooms,{})
        f=Fixture(); f.heartbeat(); f.now+=16
        self.assertEqual(f.service.health()["available_workers"],0)
        self.assertEqual(f.service.cache,{})

    def test_top_level_availability_is_fresh_on_cached_player_response(self):
        f=Fixture(); payload=f.payload()
        first=f.service.dispatch("create","person-0",payload)
        self.assertFalse(first["worker_available"])
        self.assertEqual(first["build_sha256"],BUILD)
        f.heartbeat()
        second=f.service.dispatch("create","person-0",payload)
        self.assertTrue(second["worker_available"])
        self.assertEqual(first["room"],second["room"])

    def test_own_ready_running_worker_remains_available_for_reconnect(self):
        f=Fixture(); room,assignment=f.started(); identifier=room["room_id"]
        self.assertEqual(f.service.health()["available_workers"],0,"busy worker is not free capacity")
        self.assertTrue(f.call("room",room_id=identifier)["worker_available"])
        self.assertTrue(f.call("rooms")["worker_available"])
        issued=f.call("reconnect",room_id=identifier)
        self.assertTrue(issued["worker_available"])
        f.heartbeat("running",assignment["generation"],assignment["lease_id"])
        self.assertTrue(f.call("redeem",room_id=identifier,ticket=issued["ticket"])["worker_available"])
        f.now+=16
        f.service.workers["idle-spare"]=dict(spec=WorkerSpec("idle-spare","127.0.0.1:27016",BUILD),
            state="IDLE",generation=0,lease_id=None,room_id=None,match_id=None,last_seen=f.now,lease_expires=0)
        self.assertEqual(f.service.health()["available_workers"],1)
        self.assertFalse(f.call("room",room_id=identifier)["worker_available"])
        self.assertFalse(f.call("rooms")["worker_available"])
        with self.assertRaises(LobbyError) as caught: f.call("reconnect",room_id=identifier)
        self.assertFalse(caught.exception.context["worker_available"])

    def test_own_worker_availability_requires_exact_current_lease_generation_build(self):
        for field,value in (("generation",99),("lease_id","wrong-lease"),("lease_expires",0)):
            with self.subTest(field=field):
                f=Fixture(); room,_=f.started()
                f.service.workers["local-worker-1"][field]=value
                self.assertFalse(f.call("room",room_id=room["room_id"])["worker_available"])
        f=Fixture(); room,_=f.started()
        f.service.workers["local-worker-1"]["spec"]=WorkerSpec("local-worker-1","127.0.0.1:27015","a"*64)
        self.assertFalse(f.call("room",room_id=room["room_id"])["worker_available"])


class HttpTest(unittest.TestCase):
    def setUp(self):
        self.fixture=Fixture(workers=False)
        self.server=Server(("127.0.0.1",0),self.fixture.service)
        self.thread=threading.Thread(target=self.server.serve_forever,daemon=True); self.thread.start()

    def tearDown(self):
        self.server.shutdown(); self.server.server_close(); self.thread.join(timeout=2)

    def request(self,path="/v1/lobby/create",payload=None,token="person-0",raw=None,method="POST",headers=None):
        connection=http.client.HTTPConnection(*self.server.server_address,timeout=3)
        body=raw if raw is not None else json.dumps(payload if payload is not None else self.fixture.payload())
        actual={"Content-Type":"application/json","Authorization":"Bearer "+token}; actual.update(headers or {})
        try:
            connection.request(method,path,body if method=="POST" else None,actual)
            response=connection.getresponse(); return response.status,json.loads(response.read()),dict(response.headers)
        finally: connection.close()

    def test_health_and_authenticated_post_no_cookie_or_cloud(self):
        status,body,headers=self.request("/health",method="GET")
        self.assertEqual(status,200); self.assertEqual(body["available_workers"],0)
        self.assertEqual(headers["Cache-Control"],"no-store")
        status,body,_=self.request()
        self.assertEqual(status,200); self.assertTrue(body["ok"])

    def test_missing_wrong_identity_and_payload_steam_are_rejected(self):
        self.assertEqual(self.request(token="untrusted")[0],401)
        self.assertEqual(self.request(payload=self.fixture.payload(steam_id=STEAMS[0]))[0],400)
        self.assertEqual(self.request("/v1/profile")[0],404)

    def test_duplicate_fields_nonjson_query_oversize_and_unknown_route_rejected(self):
        for raw in ('{"account_id":"101","account_id":"102"}', '{"a":NaN}', '[1,2]'):
            self.assertEqual(self.request(raw=raw)[0],400)
        self.assertEqual(self.request(path="/v1/lobby/create?token=private")[0],404)
        self.assertEqual(self.request(raw="x"*8193)[0],413)
        self.assertEqual(self.request(headers={"Content-Type":"text/plain"})[0],415)
        self.assertEqual(self.request(path="/v1/lobby/register-any-host")[0],404)

    def test_nonloopback_bind_is_rejected(self):
        with self.assertRaisesRegex(ValueError,"loopback_bind_required"):
            Server(("0.0.0.0",0),self.fixture.service)


class IntegratedHttpTest(unittest.TestCase):
    def setUp(self):
        from player_web_auth import test_service as web_tests
        from player_web_auth.http_api import BoundedServer, handler
        from player_web_auth.run import lobby_from_environment
        self.auth_fixture=web_tests.ServiceTest("runTest"); self.auth_fixture.setUp()
        _,grant,_=self.auth_fixture.approved()
        self.token=grant["access_token"]
        self.lobby=lobby_from_environment(self.auth_fixture.service,{"PLAYER_WEB_AUTH_LOBBY_ENABLED":"1"})
        self.http=BoundedServer(("127.0.0.1",0),handler(self.auth_fixture.service,lobby=self.lobby))
        self.thread=threading.Thread(target=self.http.serve_forever,daemon=True); self.thread.start()

    def tearDown(self):
        self.http.shutdown(); self.http.server_close(); self.thread.join(timeout=2)
        self.auth_fixture.tearDown()

    def request(self,action="create",**data):
        payload=dict(self.auth_fixture.identity,request_id="integrated-"+action.replace("/","_"),**data)
        connection=http.client.HTTPConnection(*self.http.server_address,timeout=3)
        try:
            connection.request("POST","/v1/lobby/"+action,json.dumps(payload),
                               {"Content-Type":"application/json","Authorization":"Bearer "+self.token})
            response=connection.getresponse()
            return response.status,json.loads(response.read())
        finally: connection.close()

    def test_enabled_identity_room_ready_but_no_worker_start_and_no_cloud_proxy(self):
        status,response=self.request()
        self.assertEqual(status,200)
        self.assertFalse(response["worker_available"])
        self.assertIsNone(response["build_sha256"])
        room=response["room"]
        status,response=self.request("ready",room_id=room["room_id"],expected_version=room["version"],ready=True)
        self.assertEqual(status,200)
        status,response=self.request("start",room_id=room["room_id"],expected_version=response["room"]["version"])
        self.assertEqual((status,response["error"]),(503,"no_ready_worker"))
        self.assertFalse(response["worker_available"])
        self.assertIn("build_sha256",response)
        self.assertEqual(self.auth_fixture.forward_calls,[])

    def test_unknown_lobby_routes_expired_grants_and_cloud_mutations_stay_denied(self):
        status,response=self.request("arbitrary/proxy")
        self.assertEqual(status,404)
        self.assertFalse(response["worker_available"])
        self.auth_fixture.now+=4*3600+1
        status,response=self.request()
        self.assertEqual((status,response["error"]),(401,"lobby_identity_required"))
        connection=http.client.HTTPConnection(*self.http.server_address,timeout=3)
        try:
            connection.request("POST","/v1/archive/command",json.dumps(self.auth_fixture.identity),
                {"Content-Type":"application/json","Authorization":"Bearer "+self.token})
            response=connection.getresponse(); self.assertEqual(response.status,403); response.read()
        finally: connection.close()
        self.assertEqual(self.auth_fixture.forward_calls,[])

    def test_flag_defaults_closed_and_malformed_values_rejected(self):
        from player_web_auth.run import lobby_from_environment
        self.assertIsNone(lobby_from_environment(self.auth_fixture.service,{}))
        self.assertIsNone(lobby_from_environment(self.auth_fixture.service,{"PLAYER_WEB_AUTH_LOBBY_ENABLED":"0"}))
        for value in ("true","yes",1,None):
            with self.assertRaisesRegex(ValueError,"lobby_enabled_invalid"):
                lobby_from_environment(self.auth_fixture.service,{"PLAYER_WEB_AUTH_LOBBY_ENABLED":value})

    def test_handler_without_optional_lobby_never_forwards_new_routes(self):
        from player_web_auth.http_api import BoundedServer,handler
        from unittest.mock import patch
        server=BoundedServer(("127.0.0.1",0),handler(self.auth_fixture.service))
        thread=threading.Thread(target=server.serve_forever,daemon=True); thread.start()
        try:
            with patch.object(self.auth_fixture.service,"proxy",side_effect=AssertionError("cloud proxy reached")):
                connection=http.client.HTTPConnection(*server.server_address,timeout=3)
                try:
                    connection.request("POST","/v1/lobby/create",json.dumps(self.auth_fixture.identity),
                        {"Content-Type":"application/json","Authorization":"Bearer "+self.token})
                    response=connection.getresponse(); body=json.loads(response.read())
                    self.assertEqual((response.status,body["error"]),(503,"lobby_disabled"))
                    self.assertFalse(body["worker_available"])
                finally: connection.close()
        finally: server.shutdown(); server.server_close(); thread.join(timeout=2)


if __name__=="__main__":
    unittest.main()
