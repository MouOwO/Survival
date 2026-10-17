"""Scoped read-only VIP baseline and rolled-back SQL fixtures; no gateway calls."""
from pathlib import Path
import base64, hashlib, importlib.util, json, subprocess, sys

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'design_refs/vip_recharge_20261016/payment'
BASELINE_FOLDER = 'baseline'

BASELINE_CODE = r'''
from pathlib import Path
import base64,hashlib,json,sys
sys.dont_write_bytecode=True
archive=Path('/opt/goufayu/releases/current').resolve(strict=True)
payment=Path('/opt/goufayu/payments/current').resolve(strict=True)
assert str(archive)=='/opt/goufayu/releases/20261016-shop-functional-v2'
assert str(payment)=='/opt/goufayu/payments/20261016-shop-functional-v2'
digest=json.loads((archive/'addon/server/bundles/current.json').read_text())['hash']
assert digest=='ab2db559240bcb08d60bc982152bc869b729496cc2afcb71dabb973149c1f3fb'
files={}
for name in ['backend/archive_backend/service.py','backend/archive_backend/bundle.py',
             'addon/server/bundles/'+digest+'/bundle.json',
             'addon/server/bundles/'+digest+'/systems/archive_vip_rewards.lua',
             'addon/server/bundles/'+digest+'/systems/archive_settlement.lua']:
 files['archive/'+name]=(archive/name).read_bytes()
for name in ['payment_backend/service.py','payment_backend/upgrade_vip_recharge.sql',
             'payment_backend/upgrade_commerce_bundles.sql',
             'payment_backend/test_payments.py', 'payment_backend/test_commerce_bundles_database.py',
             'reference_csv/存档系统/archive_vip_levels.csv',
             'reference_csv/存档系统/archive_vip_rewards.csv']:
 files['payment/'+name]=(payment/name).read_bytes()
sys.path.insert(0,str(payment));from deploy import connection
signatures=['payments.credit_vip_recharge()','payments.deliver(text,text,integer,text,text)',
            'payments.commerce_purchase_block(text,jsonb)',
            'public.archive_prepare(text,text,text,text,jsonb)',
            'public.archive_commit(text,text,bigint,jsonb,jsonb,text)']
definitions={}
with connection() as c:
 c.execute('SET TRANSACTION READ ONLY')
 assert c.execute('SELECT current_database()').fetchone()[0]=='goufayu_test'
 thresholds=c.execute('SELECT level,required_fen FROM payments.vip_recharge_levels ORDER BY level').fetchall()
 for signature in signatures:
  oid=c.execute('SELECT to_regprocedure(%s)',(signature,)).fetchone()[0]
  if oid:
   definitions[signature]=c.execute('SELECT pg_get_functiondef(%s::regprocedure)',(signature,)).fetchone()[0]
 triggers=c.execute("SELECT tgname,pg_get_triggerdef(oid) FROM pg_trigger WHERE tgrelid='payments.orders'::regclass AND NOT tgisinternal ORDER BY tgname").fetchall()
 functions=c.execute("SELECT n.nspname,p.proname,pg_get_function_identity_arguments(p.oid) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname IN ('public','payments') AND (p.proname LIKE '%vip%' OR p.proname LIKE '%commerce%' OR p.proname IN ('archive_commit','archive_prepare')) ORDER BY 1,2").fetchall()
 c.rollback()
print(json.dumps({'status':'READONLY_BASELINE','archive_release':str(archive),
 'payment_release':str(payment),'bundle':digest,'thresholds':thresholds,
 'definitions':definitions,'functions':functions,'triggers':triggers,
 'public_files':{name:{'sha256':hashlib.sha256(raw).hexdigest(),
 'base64':base64.b64encode(raw).decode()} for name,raw in files.items()},
 'individual_player_rows_read':False,'database_writes':0,'gateway_requests':0},ensure_ascii=False))
'''

def remote(label, code):
    spec=importlib.util.spec_from_file_location('vip_pinned_transport',ROOT/'tools/endless_leaderboard_20261016/deploy_driver.py')
    mod=importlib.util.module_from_spec(spec);spec.loader.exec_module(mod)
    result=subprocess.run(mod.options(),input=code.encode(),capture_output=True,cwd=ROOT,timeout=180,
                          creationflags=getattr(subprocess,'CREATE_NO_WINDOW',0))
    OUT.mkdir(parents=True,exist_ok=True)
    (OUT/(label+'.stderr.txt')).write_bytes(result.stderr)
    if result.returncode:
        raise RuntimeError('remote_failed:'+label+':'+str(result.returncode))
    data=json.loads(result.stdout)
    for name,entry in data.pop('public_files',{}).items():
        raw=base64.b64decode(entry['base64'],validate=True)
        assert hashlib.sha256(raw).hexdigest()==entry['sha256']
        p=OUT/BASELINE_FOLDER/name;p.parent.mkdir(parents=True,exist_ok=True)
        if p.exists():assert p.read_bytes()==raw,'immutable_baseline_changed:'+name
        else:p.write_bytes(raw)
    (OUT/(label+'.json')).write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    visible={k:v for k,v in data.items() if k not in ('definitions','functions','triggers','checks','business_hashes_before','business_hashes_after')}
    if 'ranking_projection_tests' in visible:
        visible['ranking_projection_tests']={k:v for k,v in visible['ranking_projection_tests'].items() if k!='checks'}
    print(json.dumps(visible,ensure_ascii=False))
    return data

if __name__=='__main__':
    assert sys.argv[1:] in (['baseline'],['checks'])
    if sys.argv[1]=='baseline':remote('online_baseline',BASELINE_CODE)
    else:
        code=Path(__file__).with_name('payment_checks_remote.py').read_text(encoding='utf-8')
        rank_source=Path(__file__).with_name('test_leaderboard_vip_database.py').read_text(encoding='utf-8')
        rank_sql=(ROOT/'server/migrations/202610160002_leaderboard_vip_badges.sql').read_text(encoding='utf-8')
        code='RANK_TEST_SOURCE='+repr(rank_source)+'\nRANK_MIGRATION_SOURCE='+repr(rank_sql)+'\n'+code
        remote('online_checks',code)
