"""Existing formal HTTP/commerce/full-sync regression suite; only localhost fixture HTTP."""
import io,json,os,sys,unittest,hashlib
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2];sys.path[:0]=[str(ROOT),str(ROOT/'server'),str(ROOT/'output/video_shop_20261015/deps')]
os.environ['LUA_EXECUTABLE']='C:/Program Files/lua/bin/lua5.1.exe'
os.environ['FISHING_BACKEND_ROOT']=str(ROOT/'output/endless_batch_20261010/baseline/backend')
assert sys.flags.utf8_mode,'Invoke with PYTHONUTF8=1 or Python -X utf8 to decode Lua UTF8 JSON on Windows'
mods=['tests.test_archive_backend','tests.test_commerce','tools.test_archive_full_sync']
suite=unittest.TestSuite(unittest.defaultTestLoader.loadTestsFromName(n) for n in mods)
class Result(unittest.TextTestResult):
 def __init__(self,*a,**kw):super().__init__(*a,**kw);self.successes=[]
 def addSuccess(self,test):self.successes.append(test.id());super().addSuccess(test)
stream=io.StringIO();result=unittest.TextTestRunner(stream=stream,verbosity=2,resultclass=Result).run(suite)
out=ROOT/'design_refs/commerce_points_20261016';(out/'existing_regression.log').write_text(stream.getvalue(),encoding='utf-8')
files=['server/tests/test_commerce.py','server/tests/test_archive_backend.py','tools/test_archive_full_sync.py']
report={'status':'PASS' if result.wasSuccessful() else 'FAIL','tests_run':result.testsRun,'success_count':len(result.successes),'failures':[{'test':str(t),'trace':msg} for t,msg in result.failures],'errors':[{'test':str(t),'trace':msg} for t,msg in result.errors],'skips':[{'test':str(t),'reason':msg} for t,msg in result.skipped],'successes':result.successes,'environment':{'utf8':True,'LUA_EXECUTABLE':os.environ['LUA_EXECUTABLE'],'FISHING_BACKEND_ROOT':os.environ['FISHING_BACKEND_ROOT']},'scope':'Current production Lua worker and ArchiveService, fake in-memory accounts/receipts, localhost-only HTTP auth fixture, no real game/orders/DB/server.','source_sha256':{f:hashlib.sha256((ROOT/f).read_bytes()).hexdigest() for f in files},'modified_test_files':['server/tests/test_commerce.py'],'unchanged_rules_tested':['Lottery exchange still debits gameplay_stats.starjoy_points.','Gift starjoy rewards remain distinct from commerce shop_points and trigger their formal tier rewards.','Closed gold products neither debit nor grant even with funded balances.'],'baseline_environment_failures_resolved':['Missing FISHING_BACKEND_ROOT and partial server/staged fixture import; use existing complete local baseline backend.','Windows default GBK decoding external Lua JSON; invoke Python UTF8 mode.']}
(out/'existing_regression_validation.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8');print(json.dumps({k:v for k,v in report.items() if k not in ['successes','source_sha256']},ensure_ascii=True,indent=2));sys.exit(0 if result.wasSuccessful() else 1)
