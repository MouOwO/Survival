import hashlib
import importlib.util
import json
import archive_backend
from pathlib import Path
import sqlite3
import sys
import types
import unittest
from player_web_auth import test_service as service_fixtures
from player_web_auth.service import SESSION_TTL

ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/"tools"))
spec=importlib.util.spec_from_file_location("reserved_patch",ROOT/"server/player_web_auth_overrides/sqlite_reserved_rate_patch.py")
op=importlib.util.module_from_spec(spec);spec.loader.exec_module(op)
# The immutable parent is produced by the normal observed + hot + WAL chain;
# use a local fixture supplied by the test runner, never an online service.
_fixture=__import__("os").environ.get("SURVIVAL_RESERVATION_PARENT")
PARENT=None
if _fixture:
    PARENT=Path(_fixture)
    parent=PARENT.read_text(encoding="utf8")
    lab=PARENT.parents[2];cfg=json.loads((lab/"lab.json").read_bytes());obs=lab/"runtime/archive_backend/_checkpoint_observation.py"
    assert hashlib.sha256(obs.read_bytes()).hexdigest()==cfg["sources"]["runtime/archive_backend/_checkpoint_observation.py"]
    archive_backend.__path__.append(str(obs.parent))
    child=op.patch_sources({op.TARGET:parent})[op.TARGET]
    mod=types.ModuleType("player_web_auth._reserved_probe");mod.__file__=str(PARENT);mod.__package__="player_web_auth";sys.modules[mod.__name__]=mod
    exec(compile(child,"<exact-reserved-service>","exec"),mod.__dict__)

@unittest.skipUnless(_fixture,"requires independently prepared immutable observed/WAL service fixture")
class ReservedServiceTests(unittest.TestCase):
    def setUp(self):
        self.f=service_fixtures.ServiceTest();self.f.setUp();self.f.service.close()
        def forward(path,raw):
            self.f.forward_calls.append(path);return 200,b'{"ok":true}'
        self.f.service=mod.Service(self.f.settings,clock=lambda:self.f.now,verify_steam=lambda fields:True,forward=forward)
    def tearDown(self):self.f.tearDown()
    def token(self):return self.f.approved()[1]["access_token"]
    def test_full_source_roundtrip(self):
        self.assertEqual(op.restore_sources({op.TARGET:child})[op.TARGET],parent)
        self.assertEqual(op.MODULE_SOURCE,(ROOT/"server/player_web_auth/rate_reservations.py").read_text(encoding="utf8"))
    def test_parent_child_drift_rejected(self):
        for fn,source in [(op.patch_sources,parent+"\n"),(op.restore_sources,child+"\n")]:
            with self.assertRaises(ValueError):fn({op.TARGET:source})
    def test_previous_wal_binding_unchanged(self):
        from loadtest_lab.frontend_experiments import validate_frontend_experiment
        self.assertTrue(validate_frontend_experiment(cfg,lambda name:(lab/name).read_bytes()))
    def test_reserved_binding_exact_and_orphans_rejected(self):
        from copy import deepcopy
        from loadtest_lab import frontend_experiments as fe
        c=deepcopy(cfg);c["frontend_experiment"]["id"]=fe.RESERVED_MODE
        raw=(ROOT/fe.RESERVED_SOURCE).read_text(encoding="utf8").encode();c["sources"][fe.RESERVED_TARGET]=fe.RESERVED_OPERATOR_SHA256
        c["sources"][fe.TARGETS[0]]=fe.RESERVED_OUTPUTS[fe.TARGETS[0]]
        c["frontend_experiment"]["operator_sources"][fe.RESERVED_TARGET]=fe.RESERVED_OPERATOR_SHA256
        c["frontend_experiment"]["runtime_sha256"]=dict(fe.RESERVED_OUTPUTS)
        def read(name):
            if name==fe.RESERVED_TARGET:return raw
            if name==fe.TARGETS[0]:return child.encode()
            return(lab/name).read_bytes()
        self.assertEqual(fe.validate_frontend_experiment(c,read),fe.INDEXED_PARENTS)
        c["sources"][fe.TARGETS[0]]="0"*64
        with self.assertRaises(ValueError):fe.validate_frontend_experiment(c,read)
        c=deepcopy(cfg);c["sources"][fe.RESERVED_TARGET]=fe.RESERVED_OPERATOR_SHA256
        with self.assertRaises(ValueError):fe.metadata_parent_sources(c)
    def test_wal_full_required(self):
        self.assertEqual(self.f.service.db.execute("PRAGMA journal_mode").fetchone()[0],"wal")
        self.assertEqual(self.f.service.db.execute("PRAGMA synchronous").fetchone()[0],2)
    def test_identity_checked_every_proxy_request(self):
        token=self.token();sql=[];self.f.service.db.set_trace_callback(sql.append)
        for _ in range(3):self.f.service.proxy("/v1/profile",token,self.f.identity,"peer")
        self.assertEqual(len(self.f.forward_calls),3)
        self.assertEqual(sum("SELECT * FROM challenges WHERE token_hash="in s for s in sql),3)
    def test_revocation_invalidates_even_with_reserved_credit(self):
        token=self.token();self.f.service.proxy("/v1/profile",token,self.f.identity,"peer")
        with self.f.service.lock,self.f.service.db:self.f.service.db.execute("UPDATE challenges SET revoked=1")
        with self.assertRaises(mod.AuthError)as caught:self.f.service.proxy("/v1/profile",token,self.f.identity,"peer")
        self.assertEqual(caught.exception.code,"player_session_expired");self.assertEqual(len(self.f.forward_calls),1)
    def test_identity_mismatch_does_not_forward(self):
        token=self.token()
        with self.assertRaises(mod.AuthError):self.f.service.proxy("/v1/profile",token,{**self.f.identity,"account_id":"123"},"peer")
        self.assertEqual(len(self.f.forward_calls),0)
    def test_expired_token_does_not_forward(self):
        token=self.token();self.f.now+=SESSION_TTL+1
        with self.assertRaises(mod.AuthError):self.f.service.proxy("/v1/profile",token,self.f.identity,"peer")
        self.assertEqual(len(self.f.forward_calls),0)
    def test_global_limit_durable_across_restart(self):
        service=self.f.service;service.rate("global-http","all",10);service.close()
        self.f.service=mod.Service(self.f.settings,clock=lambda:self.f.now,verify_steam=lambda fields:True,forward=lambda *args:None)
        with self.assertRaises(mod.AuthError):self.f.service.rate("global-http","all",10)
    def test_reserved_tail_never_exceeds_limit(self):
        self.f.service.rate("proxy","synthetic-one",1)
        with self.assertRaises(mod.AuthError)as caught:self.f.service.rate("proxy","synthetic-one",1)
        self.assertEqual(caught.exception.code,"rate_limited")
    def test_other_scopes_keep_attempt_counter(self):
        service=self.f.service;service.rate("start-ip","peer",1)
        with self.assertRaises(mod.AuthError):service.rate("start-ip","peer",1)
        k=service._derived("rate:start-ip:peer");self.assertEqual(service.db.execute("SELECT count FROM limits WHERE key=?",(k,)).fetchone()[0],2)
    def test_failed_reservation_never_forwards(self):
        token=self.token()
        with self.f.service.db:self.f.service.db.execute("CREATE TRIGGER reject_limit BEFORE INSERT ON limits BEGIN SELECT RAISE(ABORT,'synthetic_limit_failure'); END")
        with self.assertRaises(sqlite3.Error):self.f.service.proxy("/v1/profile",token,self.f.identity,"peer")
        self.assertEqual(len(self.f.forward_calls),0)

if __name__=="__main__":unittest.main()
