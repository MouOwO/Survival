"""Offline local lottery duplicate-currency regression; no network or game."""
from pathlib import Path
import argparse,hashlib,json,sys
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'output/video_shop_20261015/deps'))
from lupa.lua51 import LuaRuntime
ap=argparse.ArgumentParser();ap.add_argument('--baseline',action='store_true');a=ap.parse_args()
source=ROOT/('design_refs/commerce_logic_audit_20261016/baseline/local_lottery_service_before.lua' if a.baseline else 'scripts/vscripts/systems/lottery_service.lua')
lua=LuaRuntime(unpack_returned_tuples=True);logs=[];lua.globals().print=lambda *v:logs.append(' '.join(map(str,v)))
if a.baseline:
 lua.globals().SOURCE_TO_TEST=source.read_text('utf-8-sig')
 lua.execute("package.preload['systems/lottery_service']=function() return assert(loadstring(SOURCE_TO_TEST))() end")
import os;os.chdir(ROOT)
try:lua.execute((ROOT/'tools/commerce_logic_audit_20261016/test_local_lottery_duplicate_currency.lua').read_text('utf-8-sig'));error=None
except Exception as exc:error=str(exc)
raw=lua.globals().LOCAL_LOTTERY_DUPLICATE_RESULTS
checks=[dict(row.items()) for _,row in raw.items()] if raw else []
report={'status':('FAIL_REPRODUCED' if a.baseline else 'FAIL') if error else 'PASS','error':error,'source_sha256':hashlib.sha256(source.read_bytes()).hexdigest(),'scope':'offline local-only _test draw path; explicit engine/profile fixtures, no HTTP/game/account','checks':checks,'logs':logs}
output=ROOT/'design_refs/commerce_logic_audit_20261016'/('local_duplicate_currency_baseline.json' if a.baseline else 'local_duplicate_currency_fixed.json')
output.write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps({'status':report['status'],'total':len(checks),'passed':sum(row['ok'] for row in checks),'failed':[row['name'] for row in checks if not row['ok']],'source_sha256':report['source_sha256']}))
raise SystemExit(0 if report['status'] in ('PASS','FAIL_REPRODUCED') else 1)
