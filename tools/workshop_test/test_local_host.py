"""Local-only checks for routing, account gates, frozen bytes and named host pins."""
import ast
import hashlib
import http.client
from http.server import ThreadingHTTPServer
import json
import os
from pathlib import Path
import tempfile
import threading
from types import SimpleNamespace
import unittest
from unittest.mock import patch

import local_host as local


class ProxyChecks(unittest.TestCase):
    def setUp(self):
        self.calls=[]
        def forward(path,raw):
            self.calls.append((path,json.loads(raw)))
            return 200,b'{"ok":true}'
        self.server=ThreadingHTTPServer(('127.0.0.1',0),local.proxy_handler('a'*64,forward))
        self.thread=threading.Thread(target=self.server.serve_forever,daemon=True);self.thread.start()
    def tearDown(self):
        self.server.shutdown();self.server.server_close();self.thread.join()
    def request(self,path='/v1/session/authenticate',payload=None,authorization=True):
        conn=http.client.HTTPConnection('127.0.0.1',self.server.server_port,timeout=3)
        try:
            body=json.dumps(payload or {'account_id':local.OWNER_ACCOUNT}).encode()
            headers={'Authorization':'Bearer '+'a'*64} if authorization else {}
            conn.request('POST',path,body,headers)
            response=conn.getresponse();return response.status,json.loads(response.read())
        finally:conn.close()
    def test_only_authenticated_loopback_requests_reach_fixed_game_routes(self):
        self.assertEqual(self.request()[0],200)
        self.assertEqual(self.calls,[('/v1/session/authenticate',{'account_id':local.OWNER_ACCOUNT})])
        self.calls.clear()
        for path in ('/v1/payment/create','/health','/v1/profile?url=https://other.invalid'):
            self.assertEqual(self.request(path)[0],404)
        self.assertEqual(self.request(authorization=False)[0],403)
        self.assertFalse(self.calls)
    def test_fifth_account_and_unbounded_bodies_never_reach_cloud(self):
        for account in ('42',42,True,None):
            status,body=self.request(payload={'account_id':account})
            self.assertEqual((status,body['error']),(403,'test_account_not_allowed'))
        self.assertEqual(self.request(payload={'account_id':local.OWNER_ACCOUNT,'extra':'x'*17000})[0],413)
        self.assertFalse(self.calls)
    def test_four_confirmed_accounts_remain_distinct(self):
        for account in local.ACCOUNTS:self.assertEqual(self.request(payload={'account_id':account})[0],200)
        self.assertEqual({body['account_id'] for _,body in self.calls},local.ACCOUNTS)
    def test_cloud_failures_expose_only_fixed_code(self):
        def failed(*args):raise RuntimeError('must-never-show-private-key')
        other=ThreadingHTTPServer(('127.0.0.1',0),local.proxy_handler('a'*64,failed))
        worker=threading.Thread(target=other.serve_forever,daemon=True);worker.start()
        original=self.server;self.server=other
        try:
            status,body=self.request()
            self.assertEqual(status,502);self.assertEqual(body['error'],'isolated_backend_unreachable')
        finally:self.server=original;other.shutdown();other.server_close();worker.join()
    def test_cloud_redirects_are_not_followed_with_bearer_credentials(self):
        self.assertIsNone(local.NoRedirect().redirect_request(None,None,None,None,None,None,None))


class FrozenChecks(unittest.TestCase):
    def test_running_game_is_preserved_before_any_install_or_provision(self):
        with patch.object(local,'existing_game',return_value=True), patch.object(local,'install') as install, \
                patch.object(local,'provision') as provision:
            with self.assertRaisesRegex(local.LocalError,'close_dota_first'):local.run(1)
        install.assert_not_called();provision.assert_not_called()

    def test_frozen_stage_rejects_changed_or_extra_runtime(self):
        with tempfile.TemporaryDirectory() as temp:
            stage=Path(temp)
            raw=b'unchanged frozen fixture'
            row={'path':'one.txt','bytes':len(raw),'sha256':hashlib.sha256(raw).hexdigest(),
                 'md5':hashlib.md5(raw).hexdigest()}
            expected=local.expected_manifest({'files':[row]}, {'local.lua':b'return true'})
            (stage/'one.txt').write_bytes(raw);(stage/'local.lua').write_bytes(b'return true')
            with patch.object(local,'STAGE',stage):
                local.verify_stage(expected)
                (stage/'one.txt').write_bytes(b'changed')
                with self.assertRaisesRegex(local.LocalError,'bytes_changed'):local.verify_stage(expected)
                (stage/'one.txt').write_bytes(raw);(stage/'unreviewed.lua').write_bytes(b'bad')
                with self.assertRaisesRegex(local.LocalError,'file_set_changed'):local.verify_stage(expected)
    def test_local_overlay_changes_only_tools_route_and_contains_no_host_key(self):
        with tempfile.TemporaryDirectory() as temp:
            base=Path(temp);name='scripts/vscripts/systems/workshop_connection.lua'
            path=base/name;path.parent.mkdir(parents=True)
            raw=b'if IsInToolsMode and IsInToolsMode() then return local_url, local_token end\nreturn cloud_url, valve_key'
            path.write_bytes(raw)
            with patch.object(local,'BASE',base):
                result=local.overlay({'files':[{'path':name,'sha256':hashlib.sha256(raw).hexdigest()}]})
            self.assertIn(b'http://127.0.0.1:18766',result[name])
            self.assertIn(b'return cloud_url, valve_key',result[name])
            self.assertNotIn(b'cloud_key',b'\n'.join(result.values()))
            self.assertEqual(len(result),5)


class HostRegistrationChecks(unittest.TestCase):
    def test_named_local_host_pin_never_uses_pending_valve_requests(self):
        source=Path(local.HERE/'remote_operator.py').read_text()
        function=next(n for n in ast.parse(source).body if isinstance(n,ast.FunctionDef) and n.name=='register_local_host')
        module=ast.Module(body=[function],type_ignores=[])
        with tempfile.TemporaryDirectory() as temp:
            config=Path(temp);path=config/'pins.json'
            valve='b'*64;digest='a'*64
            path.write_text(json.dumps({'workshop_id':'3824360109','sha256':[valve]}))
            def private(dest,raw,**kwargs):
                with dest.open('xb') as stream:stream.write(raw)
            context={'unchanged':lambda:None,'need':local.need,'LOCAL_HOST_SHA256':digest,
                'CONFIG':config,'json':json,'re':__import__('re'),'pwd':SimpleNamespace(getpwnam=lambda _:SimpleNamespace(pw_gid=1)),
                'USER':'goufayu-ws4','private':private,'os':os}
            exec(compile(module,'reviewed_local_registration','exec'),context)
            self.assertTrue(context['register_local_host']()['local_host_registered'])
            self.assertEqual(json.loads(path.read_text())['sha256'],[valve,digest])
            context['register_local_host']()
            self.assertEqual(len(json.loads(path.read_text())['sha256']),2)
            context['LOCAL_HOST_SHA256']='c'*64
            with self.assertRaisesRegex(local.LocalError,'different_local_host'):context['register_local_host']()
            self.assertEqual(json.loads(path.read_text())['sha256'],[valve,digest])


if __name__=='__main__':unittest.main()
