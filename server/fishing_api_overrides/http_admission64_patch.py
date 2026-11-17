"""Explicit isolated HTTP64 preparation overlay; original SQL/DB budget unchanged.

Cold O(source bytes), once at prepare; stable requests O(1) admission, <=64 active
backend slots/128 frontend. Original bounded2s admission, 50ms reject drain,
48 RPC in-flight and per-request absolute deadline remain unchanged. Shutdown
visits <=64 owned sockets once, no account scans or new HTTP/SQL calls.
"""
from pathlib import Path
import hashlib,runpy
ORIGINAL_PATCH_SHA='3434dc6d35b629e1300bdf2187823d7823044b05bb02ae95f7f37599c0946b84'
CONFIG_PARENT_SHA='968bba08eed222031e9f5b8740a5db35f790d2d3be1803d78ba0702aa22013aa'
def patch_sources(sources):
 keys={'fishing_api/server.py','player_web_auth/http_api.py','fishing_api/config.py'}
 if type(sources)is not dict or set(sources)!=keys:raise ValueError('http64_exact_source_set_required')
 config=sources['fishing_api/config.py'].replace('\r\n','\n')
 if hashlib.sha256(config.encode()).hexdigest()!=CONFIG_PARENT_SHA:raise ValueError('http64_exact_config_parent_required')
 path=Path(__file__).with_name('http_admission_patch.py');raw=path.read_bytes().replace(b'\r\n',b'\n')
 if hashlib.sha256(raw).hexdigest()!=ORIGINAL_PATCH_SHA:raise ValueError('http64_original_patch_changed')
 module=runpy.run_path(str(path),run_name='original_bounded_admission_for_explicit64')
 result=module['patch_sources']({key:sources[key]for key in module['KEYS']})
 server=result['fishing_api/server.py']
 for before,after in [('not 1 <= max_concurrency <= 32','not 1 <= max_concurrency <= 64'),('HTTP concurrency must be between 1 and 32','HTTP concurrency must be between 1 and 64')]:
  if server.count(before)!=1:raise ValueError('http64_exact_backend_anchor_required')
  server=server.replace(before,after,1)
 before='("FISHING_HTTP_MAX_CONCURRENCY", self.http_max_concurrency, 1, 32)'
 if config.count(before)!=1:raise ValueError('http64_exact_settings_anchor_required')
 config=config.replace(before,before[:-3]+'64)',1)
 result['fishing_api/server.py']=server;result['fishing_api/config.py']=config
 for name,source in result.items():compile(source,name,'exec')
 return result
