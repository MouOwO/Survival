"""Release and function digests after the rollback-only VIP rehearsal."""
from pathlib import Path
import importlib.util
ROOT=Path(__file__).resolve().parents[2]
spec=importlib.util.spec_from_file_location('vip_audit_transport',Path(__file__).with_name('payment_audit.py'))
mod=importlib.util.module_from_spec(spec);spec.loader.exec_module(mod)
mod.OUT=ROOT/'design_refs/vip_recharge_20261016/deployment'
CODE=r'''
from pathlib import Path
import hashlib,json,sys
sys.dont_write_bytecode=True
archive=Path('/opt/goufayu/releases/current').resolve(strict=True)
payment=Path('/opt/goufayu/payments/current').resolve(strict=True)
assert archive.name=='20261016-shop-functional-v2' and payment.name=='20261016-shop-functional-v2'
sys.path.insert(0,str(payment));from deploy import connection
with connection() as c:
 c.execute('SET TRANSACTION READ ONLY')
 cash=c.execute('SELECT catalog_hash FROM payments.catalog_state WHERE singleton').fetchone()[0]
 fn=c.execute("SELECT pg_get_functiondef('public.archive_endless_leaderboard()'::regprocedure)").fetchone()[0]
 credit=c.execute("SELECT pg_get_functiondef('payments.credit_vip_recharge()'::regprocedure)").fetchone()[0]
 c.rollback()
print(json.dumps({'status':'READONLY_VERSIONS_AFTER_ROLLBACK','archive_release':str(archive),
 'payment_release':str(payment),'archive_bundle':json.loads((archive/'addon/server/bundles/current.json').read_text())['hash'],
 'archive_manifest_sha256':hashlib.sha256((archive/'release_manifest.json').read_bytes()).hexdigest(),
 'payment_manifest_sha256':hashlib.sha256((payment/'manifest.json').read_bytes()).hexdigest(),
 'cash_catalog_hash':cash,'leaderboard_function_sha256':hashlib.sha256(fn.encode()).hexdigest(),
 'vip_recharge_trigger_sha256':hashlib.sha256(credit.encode()).hexdigest(),
 'database_writes':0,'individual_player_rows_read':False,'gateway_requests':0}))
'''
if __name__=='__main__':mod.remote('readonly_versions',CODE)
