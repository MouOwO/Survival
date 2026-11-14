"""Exact-parent, lab-only checkpoint/backend/proxy observation overlay.

No network/DB/Lua calls run while preparing. Call patch_sources after pool v2,
before admission. The private helper is generated from this committed recipe.
No business payload, SQL parameter, privilege check, transaction or replay changes.
"""
from __future__ import annotations
import ast
import hashlib
from copy import deepcopy

MARKER='# SURVIVAL_CHECKPOINT_OBSERVATION_V1'
PARENT_SHA256={'archive_backend/command_timing.py': 'cde11e5fcc995bed05a331842f547b3e7bfa718198a219d9a7854431f202274d',
 'archive_backend/http_request_timing.py': '7ae0c700e80b2ec1548680de67599597f486671e14109f821739ce2126f9ca4f',
 'archive_backend/settlement_runner.py': '5bbe7508064573bdd25f6474e8c237a27bda01a53bb980a63d16912616503e38',
 'fishing_api/application.py': '056a3a95d6a1a20c4ad57c26aa75cf426caac3580d74cf0f001d840634ea7ba1',
 'fishing_api/server.py': 'e49e903ff7abe51c333d2715f35911ae5b0ed2afea55867f5304a837b19ceb32',
 'player_web_auth/http_api.py': '138de5c50bc71f0861ed6f85f4d3d6d0a3d6399e17ff39d93f228383ae687dc2',
 'player_web_auth/service.py': 'd6d602e76adaaa8340114506b4438094d7d81487d8cbb4a19c9c2856e734c382'}

_SERVICE_PARENT_SHA256 = frozenset(('d6d602e76adaaa8340114506b4438094d7d81487d8cbb4a19c9c2856e734c382',
 'fc76cbf5d54c8e2ff2382fa5ebd9500fbac81399db90b6e6e70ce085d8902c8b'))
HELPER_PATH="archive_backend/_checkpoint_observation.py"
HELPER_SOURCE='"""Bounded checkpoint/backend/proxy observations; no payloads or authority cache.\n\nEvery boundary touches fixed maps. The three mutually exclusive budgets sum to\n60 records/minute and 300/process over 24h, including backend and proxy in the\nsame lab process. Backend final gets 40/min120, proxy final10/min30, others10/min150.\nSamples do not define whole-population latency quantiles. Nested stages overlap.\n"""\nfrom contextlib import contextmanager\nfrom contextvars import ContextVar\nfrom functools import wraps\nimport json\nimport math\nimport sys\nimport threading\nimport time\n\nPREFIX=\'SURVIVAL_HTTP_TIMING \'\nMAX_RECORD_BYTES=4096\nKINDS=frozenset((\'lottery_draw\',\'daily_claim\',\'benefit_claim\',\'vip_claim\',\'commerce_purchase\',\n \'redemption_redeem\',\'building_upgrade\',\'work_upgrade\',\'checkpoint_regular\',\'checkpoint_final\',\n \'checkpoint_unclassified\',\'checkpoint_proxy_regular\',\'checkpoint_proxy_final\',\'checkpoint_proxy_unclassified\'))\nSTAGES=frozenset((\'authorize\',\'body\',\'context\',\'command\',\'project\',\'serialize\',\'write\',\'rpc\',\n \'db_connect\',\'db_guard\',\'db_role_guard\',\'db_function_guard\',\'db_query\',\'db_commit\',\'db_rollback\',\'db_close\',\n \'db_pool_wait\',\'db_reset\',\'checkpoint_app\',\'checkpoint_ensure\',\'checkpoint_sql\',\'checkpoint_drain\',\'checkpoint_profile\',\n \'archive_ensure\',\'archive_prepare\',\'archive_finish\',\'archive_public\',\'archive_snapshot\',\n \'settlement_wait\',\'settlement_worker\',\'settlement_decode\',\'settlement_commit\',\'settlement_resume\',\n \'lua_encode\',\'lua_cache\',\'lua_exec\',\'pwa_global_rate\',\'pwa_account_rate\',\'pwa_body\',\'pwa_principal\',\n \'pwa_request_json\',\'pwa_upstream\',\'pwa_upstream_json\',\'pwa_pack\',\'pwa_serialize\',\'pwa_write\'))\nRPCS=frozenset((\'match_profile_context\',\'ensure_player_gameplay_stats\',\'archive_prepare\',\'archive_commit\',\n \'archive_commit_lottery\',\'archive_commit_challenge\',\'archive_resume\',\'redemption_prepare\',\'redemption_commit\',\n \'archive_pending\',\'archive_online_pending\',\'get_fishing_profile\',\'checkpoint_online_time\',\'archive_bind_leaderboard_identity\'))\nRECORD_KEYS=frozenset((\'v\',\'at_ms\',\'kind\',\'count\',\'status\',\'body_bytes\',\'outcome\',\'total_ms\',\'stages\',\'rpcs\'))\n_ACTIVE=ContextVar(\'checkpoint_observation\',default=None)\n\n\ndef _finite(value):\n    if type(value) not in (int,float):return False\n    try:return math.isfinite(value)\n    except (OverflowError,ValueError):return False\n\n\ndef _clock():\n    try:return time.perf_counter_ns()\n    except Exception:return None\n\n\ndef _elapsed(start):\n    try:\n        end=_clock()\n        return max(0,min(86400000,(end-start)/1000000)) if start is not None and end is not None else 0\n    except Exception:return 0\n\n\nclass Budget:\n    def __init__(self,*,records,per_minute,clock=time.monotonic,lifetime=86400):\n        self.maximum,self.per_minute,self.clock=records,per_minute,clock\n        self.start=clock();self.until=self.start+lifetime;self.last=self.start\n        self.window=None;self.window_count=0;self.disabled=False\n        self.seen=self.admitted=self.emitted=self.dropped=self.inflight=0\n        self.lock=threading.Lock()\n    def take(self):\n        with self.lock:\n            self.seen+=1\n            try:now=self.clock()\n            except Exception:now=None\n            if not _finite(now) or now<self.last:self.disabled=True\n            if self.disabled or now>=self.until or self.admitted>=self.maximum:\n                self.dropped+=1;return False\n            self.last=now;window=int(now//60)\n            if window!=self.window:self.window,self.window_count=window,0\n            if self.window_count>=self.per_minute:\n                self.dropped+=1;return False\n            self.window_count+=1;self.admitted+=1;self.inflight+=1\n            return True\n    def finish(self,emitted):\n        with self.lock:\n            self.inflight-=1\n            if emitted:self.emitted+=1\n            else:self.dropped+=1\n    def stats(self):\n        with self.lock:\n            return dict(maximum=self.maximum,per_minute=self.per_minute,seen=self.seen,\n                admitted=self.admitted,emitted=self.emitted,dropped=self.dropped,\n                inflight=self.inflight,clock_disabled=self.disabled)\n\n\n_BUDGETS={\'backend_final\':Budget(records=120,per_minute=40),\n          \'proxy_final\':Budget(records=30,per_minute=10),\n          \'other\':Budget(records=150,per_minute=10)}\n\n\ndef _budget(kind):\n    return _BUDGETS[\'backend_final\' if kind==\'checkpoint_final\' else\n                    \'proxy_final\' if kind==\'checkpoint_proxy_final\' else \'other\']\n\n\ndef observation_stats():\n    """Fixed aggregate snapshot; no source/account/lease/SQL enumeration."""\n    return {\'kind\':\'CHECKPOINT_OBSERVATION_BUDGET_V1\',\'record_bytes_max\':4096,\n            \'process_records_max\':300,\'process_per_minute_max\':60,\'lifetime_seconds\':86400,\n            \'groups\':{name:budget.stats() for name,budget in _BUDGETS.items()}}\n\n\ndef _emit(record):\n    budget=_budget(record[\'kind\']);taken=False;emitted=False\n    try:\n        taken=budget.take()\n        if not taken:return\n        line=PREFIX+json.dumps(record,allow_nan=False,separators=(\',\',\':\'))+\'\\n\'\n        if len(line.encode(\'utf8\'))<=MAX_RECORD_BYTES:\n            sys.stdout.write(line);sys.stdout.flush();emitted=True\n    except Exception:\n        pass\n    finally:\n        if taken:\n            try:budget.finish(emitted)\n            except Exception:pass\n\n\nclass Trace:\n    def __init__(self,route,proxy=False):\n        self.started=_clock();self.route=route;self.proxy=proxy\n        self.kind=(\'checkpoint_proxy_unclassified\' if proxy else \'checkpoint_unclassified\') if route==\'/v1/online-time/checkpoint\' else None\n        self.count=self.status=self.body_bytes=0\n        self.stages={};self.rpcs={};self.outcome=\'ok\'\n    def finish(self):\n        if self.kind not in KINDS:return\n        try:\n            _emit(dict(v=1,at_ms=int(time.time()*1000),kind=self.kind,count=self.count,\n                status=self.status,body_bytes=self.body_bytes,\n                outcome=self.outcome if self.outcome==\'exception\' else \'http_error\' if self.status>=400 else \'ok\',\n                total_ms=round(_elapsed(self.started),3),stages=self.stages,rpcs=self.rpcs))\n        except Exception:pass\n\n\ndef _span(function,proxy):\n    @wraps(function)\n    def observed(handler,*args,**kwargs):\n        selected=(handler.path==\'/v1/online-time/checkpoint\' if proxy else\n                  handler.path in (\'/v1/archive/command\',\'/v1/online-time/checkpoint\'))\n        if not selected:return function(handler,*args,**kwargs)\n        trace=Trace(handler.path,proxy);token=_ACTIVE.set(trace)\n        try:return function(handler,*args,**kwargs)\n        except BaseException:\n            trace.outcome=\'exception\';raise\n        finally:\n            _ACTIVE.reset(token);trace.finish()\n    return observed\n\n\ndef request_span(function):return _span(function,False)\ndef proxy_span(function):return _span(function,True)\n\n\ndef identify(payload):\n    trace=_ACTIVE.get()\n    if trace is None:return\n    if trace.route==\'/v1/online-time/checkpoint\':\n        final=payload.get(\'final\',False) if isinstance(payload,dict) else None\n        if type(final)is bool:\n            trace.kind=(\'checkpoint_proxy_\' if trace.proxy else \'checkpoint_\')+(\'final\' if final else \'regular\')\n        return\n    command=payload.get(\'command\') if isinstance(payload,dict) else None\n    kind=command.get(\'kind\') if isinstance(command,dict) else None\n    if type(kind)is str and kind in KINDS and not kind.startswith(\'checkpoint_\'):\n        trace.kind=kind;count=command.get(\'count\')\n        trace.count=count if kind==\'lottery_draw\' and type(count)is int and count in (1,10) else 0\n\n\ndef sent(status,body_bytes):\n    trace=_ACTIVE.get()\n    if trace is not None:\n        trace.status=status if type(status)is int and 100<=status<=599 else 0\n        trace.body_bytes=max(0,min(33554432,body_bytes)) if type(body_bytes)is int else 0\n\n\n@contextmanager\ndef measure(stage):\n    trace=_ACTIVE.get()\n    if trace is None or stage not in STAGES:\n        yield;return\n    start=_clock()\n    try:yield\n    finally:\n        try:\n            old=trace.stages.get(stage,[0,0])\n            trace.stages[stage]=[min(65535,old[0]+1),round(min(86400000,old[1]+_elapsed(start)),3)]\n        except Exception:pass\n\n\n@contextmanager\ndef rpc_span(name):\n    trace=_ACTIVE.get()\n    if trace is not None:\n        key=name if type(name)is str and name in RPCS else \'other\'\n        trace.rpcs[key]=min(65535,trace.rpcs.get(key,0)+1)\n    with measure(\'rpc\'):yield\n\n\ndef timed(stage):\n    def decorate(function):\n        @wraps(function)\n        def observed(*args,**kwargs):\n            with measure(stage):return function(*args,**kwargs)\n        return observed\n    return decorate\n\n\ndef proxy_rate(function):\n    @wraps(function)\n    def observed(service,scope,actor,maximum):\n        with measure(\'pwa_global_rate\' if scope==\'global-http\' else \'pwa_account_rate\'):\n            return function(service,scope,actor,maximum)\n    return observed\n'
SCHEMA={'count_values': [0, 1, 10],
 'kinds': ['benefit_claim',
           'building_upgrade',
           'checkpoint_final',
           'checkpoint_proxy_final',
           'checkpoint_proxy_regular',
           'checkpoint_proxy_unclassified',
           'checkpoint_regular',
           'checkpoint_unclassified',
           'commerce_purchase',
           'daily_claim',
           'lottery_draw',
           'redemption_redeem',
           'vip_claim',
           'work_upgrade'],
 'lifetime_seconds': 86400,
 'max_process_records': 300,
 'max_process_records_per_minute': 60,
 'max_record_bytes': 4096,
 'outcomes': ['ok', 'http_error', 'exception'],
 'prefix': 'SURVIVAL_HTTP_TIMING ',
 'record_keys': ['at_ms',
                 'body_bytes',
                 'count',
                 'kind',
                 'outcome',
                 'rpcs',
                 'stages',
                 'status',
                 'total_ms',
                 'v'],
 'rpcs': ['archive_bind_leaderboard_identity',
          'archive_commit',
          'archive_commit_challenge',
          'archive_commit_lottery',
          'archive_online_pending',
          'archive_pending',
          'archive_prepare',
          'archive_resume',
          'checkpoint_online_time',
          'ensure_player_gameplay_stats',
          'get_fishing_profile',
          'match_profile_context',
          'other',
          'redemption_commit',
          'redemption_prepare'],
 'scope': 'same-process backend+proxy bounded samples; no per-request identifier or population percentile '
          'claims',
 'stages': ['archive_ensure',
            'archive_finish',
            'archive_prepare',
            'archive_public',
            'archive_snapshot',
            'authorize',
            'body',
            'checkpoint_app',
            'checkpoint_drain',
            'checkpoint_ensure',
            'checkpoint_profile',
            'checkpoint_sql',
            'command',
            'context',
            'db_close',
            'db_commit',
            'db_connect',
            'db_function_guard',
            'db_guard',
            'db_pool_wait',
            'db_query',
            'db_reset',
            'db_role_guard',
            'db_rollback',
            'lua_cache',
            'lua_encode',
            'lua_exec',
            'project',
            'pwa_account_rate',
            'pwa_body',
            'pwa_global_rate',
            'pwa_pack',
            'pwa_principal',
            'pwa_request_json',
            'pwa_serialize',
            'pwa_upstream',
            'pwa_upstream_json',
            'pwa_write',
            'rpc',
            'serialize',
            'settlement_commit',
            'settlement_decode',
            'settlement_resume',
            'settlement_wait',
            'settlement_worker',
            'write']}
REPLACEMENTS={'archive_backend/command_timing.py': [('                                round(min(86400000, previous[1] + elapsed), 3)]\n',
                                        '                                round(min(86400000, previous[1] + elapsed), 3)]\n'
                                        '\n'
                                        '\n'
                                        '# SURVIVAL_CHECKPOINT_OBSERVATION_V1\n'
                                        'from ._checkpoint_observation import measure as _checkpoint_measure\n'
                                        '_ORIGINAL_COMMAND_MEASURE = measure\n'
                                        '_HTTP_STAGE_MAP = '
                                        "{'ensure':'archive_ensure','prepare':'archive_prepare','finish':'archive_finish',\n"
                                        ' '
                                        "'public':'archive_public','snapshot':'archive_snapshot','worker_wait':'settlement_wait',\n"
                                        ' '
                                        "'worker':'settlement_worker','worker_decode':'settlement_decode','commit':'settlement_commit','resume':'settlement_resume'}\n"
                                        '\n'
                                        '\n'
                                        '@contextmanager\n'
                                        'def measure(stage):\n'
                                        "    with _checkpoint_measure(_HTTP_STAGE_MAP.get(stage, '')):\n"
                                        '        with _ORIGINAL_COMMAND_MEASURE(stage):\n'
                                        '            yield\n')],
 'archive_backend/http_request_timing.py': [("    with measure('rpc'):\n        yield\n",
                                             "    with measure('rpc'):\n"
                                             '        yield\n'
                                             '\n'
                                             '\n'
                                             '# SURVIVAL_CHECKPOINT_OBSERVATION_V1\n'
                                             'from ._checkpoint_observation import (request_span, identify, sent, measure, '
                                             'rpc_span, observation_stats)\n')],
 'archive_backend/settlement_runner.py': [('import time\n',
                                           'import time\n'
                                           '# SURVIVAL_CHECKPOINT_OBSERVATION_V1\n'
                                           'from ._checkpoint_observation import measure as _observation_measure\n'),
                                          ('    key, entry = _acquire(bundle, lua)\n',
                                           '    with _observation_measure("lua_cache"):\n'
                                           '        key, entry = _acquire(bundle, lua)\n'),
                                          ('    raw = json.dumps(payload, ensure_ascii=False, allow_nan=False, separators=(",", '
                                           '":")).encode("utf-8")\n',
                                           '    with _observation_measure("lua_encode"):\n'
                                           '        raw = json.dumps(payload, ensure_ascii=False, allow_nan=False, '
                                           'separators=(",", ":")).encode("utf-8")\n'),
                                          ('        return subprocess.run([cache.executable, str(RUNNER), str(cache.index)], '
                                           'cwd=bundle.directory,\n'
                                           '            input=raw, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10, '
                                           'check=True,\n'
                                           '            creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))\n',
                                           '        with _observation_measure("lua_exec"):\n'
                                           '            return subprocess.run([cache.executable, str(RUNNER), str(cache.index)], '
                                           'cwd=bundle.directory,\n'
                                           '                input=raw, stdout=subprocess.PIPE, stderr=subprocess.PIPE, '
                                           'timeout=10, check=True,\n'
                                           '                creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))\n')],
 'fishing_api/application.py': [('from .definitions import DefinitionSet\n',
                                 'from .definitions import DefinitionSet\n'
                                 '# SURVIVAL_CHECKPOINT_OBSERVATION_V1\n'
                                 'from archive_backend._checkpoint_observation import measure as _observation_measure\n'),
                                ('    def online_checkpoint(self, payload: dict[str, Any]) -> Any:\n'
                                 '        account_id = _string(payload, "account_id", ACCOUNT_ID)\n'
                                 '        database_account_id = self._database_account_id(account_id)\n'
                                 '        session_id = _string(payload, "session_id", OPAQUE_ID)\n'
                                 '        request_id = _string(payload, "request_id", OPAQUE_ID)\n'
                                 '        final = payload.get("final", False)\n'
                                 '        if type(final) is not bool:\n'
                                 '            raise ApiError("final_invalid", 400)\n'
                                 '        self._ensure_gameplay_stats(database_account_id)\n'
                                 '        response = self.rpc_client.rpc("checkpoint_online_time", {\n'
                                 '            "p_account_id": database_account_id,\n'
                                 '            "p_session_id": session_id,\n'
                                 '            "p_request_id": request_id,\n'
                                 '            "p_lease_seconds": self.online_time_lease_seconds,\n'
                                 '            "p_definition_version": self.definitions.version,\n'
                                 '            "p_interval_min_seconds": self.interval_min_seconds,\n'
                                 '            "p_interval_max_seconds": self.interval_max_seconds,\n'
                                 '            "p_final": final,\n'
                                 '        })\n'
                                 '        return self._compact_grant_response(response)\n',
                                 '    def online_checkpoint(self, payload: dict[str, Any]) -> Any:\n'
                                 '        account_id = _string(payload, "account_id", ACCOUNT_ID)\n'
                                 '        database_account_id = self._database_account_id(account_id)\n'
                                 '        session_id = _string(payload, "session_id", OPAQUE_ID)\n'
                                 '        request_id = _string(payload, "request_id", OPAQUE_ID)\n'
                                 '        final = payload.get("final", False)\n'
                                 '        if type(final) is not bool:\n'
                                 '            raise ApiError("final_invalid", 400)\n'
                                 '        with _observation_measure("checkpoint_ensure"):\n'
                                 '            self._ensure_gameplay_stats(database_account_id)\n'
                                 '        with _observation_measure("checkpoint_sql"):\n'
                                 '            response = self.rpc_client.rpc("checkpoint_online_time", {\n'
                                 '                "p_account_id": database_account_id,\n'
                                 '                "p_session_id": session_id,\n'
                                 '                "p_request_id": request_id,\n'
                                 '                "p_lease_seconds": self.online_time_lease_seconds,\n'
                                 '                "p_definition_version": self.definitions.version,\n'
                                 '                "p_interval_min_seconds": self.interval_min_seconds,\n'
                                 '                "p_interval_max_seconds": self.interval_max_seconds,\n'
                                 '                "p_final": final,\n'
                                 '            })\n'
                                 '        return self._compact_grant_response(response)\n')],
 'fishing_api/server.py': [('                elif self.path == "/v1/online-time/checkpoint":\n'
                            '                    response = application.online_checkpoint(payload)\n'
                            '                    _log_checkpoint_summary(payload, response)\n'
                            '                    if archive:\n'
                            '                        account = application._database_account_id(payload["account_id"])\n'
                            '                        archive.drain_online(account)\n'
                            '                        response["profile"] = archive.profile({"account_id": '
                            'payload["account_id"]})\n',
                            '                elif self.path == "/v1/online-time/checkpoint":\n'
                            '                    # SURVIVAL_CHECKPOINT_OBSERVATION_V1\n'
                            '                    with measure("checkpoint_app"):\n'
                            '                        response = application.online_checkpoint(payload)\n'
                            '                    _log_checkpoint_summary(payload, response)\n'
                            '                    if archive:\n'
                            '                        account = application._database_account_id(payload["account_id"])\n'
                            '                        with measure("checkpoint_drain"):\n'
                            '                            archive.drain_online(account)\n'
                            '                        with measure("checkpoint_profile"):\n'
                            '                            response["profile"] = archive.profile({"account_id": '
                            'payload["account_id"]})\n')],
 'player_web_auth/http_api.py': [('from .business_wire import pack_bytes\n',
                                  'from .business_wire import pack_bytes\n'
                                  '# SURVIVAL_CHECKPOINT_OBSERVATION_V1\n'
                                  'from archive_backend._checkpoint_observation import (proxy_span as _observation_proxy_span, '
                                  'identify as _observation_identify, sent as _observation_sent, measure as '
                                  '_observation_measure)\n'),
                                 ('        def do_POST(self):\n',
                                  '        @_observation_proxy_span\n        def do_POST(self):\n'),
                                 ('                payload = self.body()\n',
                                  '                with _observation_measure("pwa_body"):\n'
                                  '                    payload = self.body()\n'
                                  '                _observation_identify(payload)\n'),
                                 ('                            body = pack_bytes(body, versions[0])\n',
                                  '                            with _observation_measure("pwa_pack"):\n'
                                  '                                body = pack_bytes(body, versions[0])\n'),
                                 ('            if not isinstance(body, bytes):\n'
                                  '                body = json.dumps(body, separators=(",", ":")).encode()\n',
                                  '            with _observation_measure("pwa_serialize"):\n'
                                  '                if not isinstance(body, bytes):\n'
                                  '                    body = json.dumps(body, separators=(",", ":")).encode()\n'),
                                 ('            self.wfile.write(body)\n',
                                  '            _observation_sent(status, len(body))\n'
                                  '            with _observation_measure("pwa_write"):\n'
                                  '                self.wfile.write(body)\n')],
 'player_web_auth/service.py': [('import urllib.request\n',
                                 'import urllib.request\n'
                                 '# SURVIVAL_CHECKPOINT_OBSERVATION_V1\n'
                                 'from archive_backend._checkpoint_observation import (measure as _observation_measure, timed as '
                                 '_observation_timed, proxy_rate as _observation_proxy_rate)\n'),
                                ('    def rate(self, scope, actor, maximum):\n',
                                 '    @_observation_proxy_rate\n    def rate(self, scope, actor, maximum):\n'),
                                ('    def principal(self, bearer, payload):\n',
                                 '    @_observation_timed("pwa_principal")\n    def principal(self, bearer, payload):\n'),
                                ('        raw = json.dumps(payload, separators=(",", ":"), ensure_ascii=False).encode("utf-8")\n',
                                 '        with _observation_measure("pwa_request_json"):\n'
                                 '            raw = json.dumps(payload, separators=(",", ":"), '
                                 'ensure_ascii=False).encode("utf-8")\n'),
                                ('        status, body = self.forward(path, raw)\n',
                                 '        with _observation_measure("pwa_upstream"):\n'
                                 '            status, body = self.forward(path, raw)\n'),
                                ('        try:\n'
                                 '            result = json.loads(body)\n'
                                 '            if not isinstance(result, dict):\n'
                                 '                raise ValueError()\n'
                                 '        except (ValueError, UnicodeError):\n'
                                 '            raise AuthError("upstream_response_invalid", 502) from None\n',
                                 '        try:\n'
                                 '            with _observation_measure("pwa_upstream_json"):\n'
                                 '                result = json.loads(body)\n'
                                 '                if not isinstance(result, dict):\n'
                                 '                    raise ValueError()\n'
                                 '        except (ValueError, UnicodeError):\n'
                                 '            raise AuthError("upstream_response_invalid", 502) from None\n')]}

PREFIX=SCHEMA['prefix']
KINDS=frozenset(SCHEMA['kinds'])
STAGES=frozenset(SCHEMA['stages'])
RPCS=frozenset(SCHEMA['rpcs'])
RECORD_KEYS=frozenset(SCHEMA['record_keys'])


def _normalized(source):
    if type(source)is not str:raise ValueError('checkpoint_observation_source_invalid')
    source=source.replace('\r\n','\n')
    if '\r' in source:raise ValueError('checkpoint_observation_source_invalid')
    return source


def _sha(source):return hashlib.sha256(source.encode('utf8')).hexdigest()


def _parent_sha_matches(name,digest):
    if name=='player_web_auth/service.py':return digest in _SERVICE_PARENT_SHA256
    return digest==PARENT_SHA256[name]


def _replace(source,pairs,reverse=False):
    result=source
    for old,new in ([(new,old) for old,new in reversed(pairs)] if reverse else pairs):
        if result.count(old)!=1:raise ValueError('checkpoint_observation_anchor_invalid')
        result=result.replace(old,new,1)
    return result


def helper_source():return HELPER_SOURCE

def schema():return deepcopy(SCHEMA)


def patch_sources(sources):
    if type(sources)is not dict or set(sources) not in (set(PARENT_SHA256),set(PARENT_SHA256)|{HELPER_PATH}):
        raise ValueError('checkpoint_observation_source_set_invalid')
    already=HELPER_PATH in sources
    if already and _normalized(sources[HELPER_PATH])!=HELPER_SOURCE:
        raise ValueError('checkpoint_observation_helper_changed')
    outputs={}
    for name in PARENT_SHA256:
        source=_normalized(sources[name]);pairs=REPLACEMENTS[name]
        if MARKER in source:
            if not already or source.count(MARKER)!=1:raise ValueError('checkpoint_observation_partial_patch')
            original=_replace(source,pairs,True)
            if not _parent_sha_matches(name,_sha(original)) or _replace(original,pairs)!=source:
                raise ValueError('checkpoint_observation_patched_source_changed')
            outputs[name]=source
        else:
            if already or not _parent_sha_matches(name,_sha(source)):raise ValueError('checkpoint_observation_parent_changed')
            outputs[name]=_replace(source,pairs)
            original=_replace(outputs[name],pairs,True)
            if original!=source or ast.dump(ast.parse(original))!=ast.dump(ast.parse(source)):
                raise ValueError('checkpoint_observation_unrelated_change')
        compile(outputs[name],name,'exec')
    compile(HELPER_SOURCE,HELPER_PATH,'exec')
    outputs[HELPER_PATH]=HELPER_SOURCE
    return outputs
