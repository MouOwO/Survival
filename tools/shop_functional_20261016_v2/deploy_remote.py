"""Pinned archive+cash catalog publication; existing reducers and prices retained.

All fixture orders are synthetic SQL rows inside a rolled-back savepoint.
No payment gateway, real player command, or schema migration is invoked.
"""
from pathlib import Path,PurePosixPath
import argparse,contextlib,copy,fcntl,hashlib,importlib.util,io,json,os,re,secrets,shutil,subprocess,sys,tarfile,time,urllib.request
STAGE=Path(__file__).resolve().parent
PLAN_PIN=None;OPERATOR_PIN=None
def need(value,reason):
    if not value:raise RuntimeError(reason)
def sha(path):return hashlib.sha256(Path(path).read_bytes()).hexdigest()
def load(name,path):
    spec=importlib.util.spec_from_file_location(name,path);m=importlib.util.module_from_spec(spec);sys.modules[name]=m;spec.loader.exec_module(m);return m
def save(name,data):
    path=STAGE/(name+'.json');need(not path.is_symlink(),'report_symlink')
    temporary=path.with_name(path.name+'.'+secrets.token_hex(4));temporary.write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n');temporary.chmod(0o600);os.replace(temporary,path)
def plan():
    need(sha(STAGE/'release_plan.json')==PLAN_PIN and sha(__file__)==OPERATOR_PIN,'deployment_pin_changed')
    p=json.loads((STAGE/'release_plan.json').read_bytes())
    need(p['kind']=='functional_commerce' and p['version']==1,'plan_kind')
    for name in ['base','candidate','old_cash_hash','cash_hash','old_sync','new_sync','cfg_pg_sha','apply_sha','tar_sha256']:
        need(re.fullmatch('[0-9a-f]{64}',p[name]),'plan_digest:'+name)
    need(p['target_release']=='/opt/goufayu/releases/20261016-shop-functional-v2','target_archive_scope')
    need(p['target_payment']=='/opt/goufayu/payments/20261016-shop-functional-v2','target_payment_scope')
    return p
def stamp(data):return dict(data,plan_sha256=PLAN_PIN,operator_sha256=OPERATOR_PIN)
def record(name):
    d=json.loads((STAGE/(name+'.json')).read_bytes());need(d['plan_sha256']==PLAN_PIN and d['operator_sha256']==OPERATOR_PIN,'record_changed:'+name);return d
def relative(name):
    p=PurePosixPath(name);need(not p.is_absolute() and '..' not in p.parts and '\\' not in name and ':' not in name and p.as_posix()==name,'unsafe_path');return p
def manifest(directory,files):
    for name,digest in files.items():
        path=directory.joinpath(*relative(name).parts)
        need(not path.is_symlink() and path.is_file() and sha(path)==digest,'manifest_mismatch:'+name)
def pointers(archive,payment):
    need(Path('/opt/goufayu/releases/current').resolve()==Path(archive),'archive_pointer_changed')
    need(Path('/opt/goufayu/payments/current').resolve()==Path(payment),'payment_pointer_changed')
def payment():
    p=plan();sys.path.insert(0,p['old_payment']);return load('functional_payment_deploy',Path(p['old_payment'])/'deploy.py')
def function(c,signature):
    row=c.execute('SELECT pg_get_functiondef(oid),pg_get_userbyid(proowner),prosecdef,proconfig,proacl::text FROM pg_proc WHERE oid=%s::regprocedure',(signature,)).fetchone()
    return dict(sha256=hashlib.sha256(row[0].encode()).hexdigest(),owner=row[1],security_definer=row[2],config=row[3],acl=row[4])
def invariant(c,new=False):
    p=plan();need(c.execute('SELECT current_database()').fetchone()[0]=='goufayu_test','database_scope')
    sync=function(c,'public.archive_sync_config(text,jsonb)');apply=function(c,'payments.apply_effects(text,jsonb,boolean)')
    need(sync['sha256']==p['new_sync' if new else 'old_sync'],'sync_definition_changed')
    need(apply['sha256']==p['apply_sha'],'payment_reducer_changed')
    need(sync['security_definer'] and apply['security_definer'],'security_definer_changed')
    need(c.execute('SELECT catalog_hash FROM payments.catalog_state WHERE singleton').fetchone()[0]==p['cash_hash' if new else 'old_cash_hash'],'cash_catalog_changed')
    return {'sync':sync,'apply':apply}
def business(c):
    from psycopg import sql
    result={}
    tables=c.execute("SELECT schemaname,tablename FROM pg_tables WHERE schemaname IN ('public','payments') ORDER BY 1,2").fetchall()
    for schema,name in tables:
        if (schema,name) in [('payments','products'),('payments','catalog_state'),('public','archive_config_sets')]:continue
        query=sql.SQL("SELECT md5(coalesce(jsonb_agg(to_jsonb(t) ORDER BY to_jsonb(t)::text)::text,'[]')) FROM {}.{} t").format(sql.Identifier(schema),sql.Identifier(name))
        result[schema+'.'+name]=c.execute(query).fetchone()[0]
    return result
def health():
    d={}
    for name,port in [('archive',8765),('payment',8766)]:
        with urllib.request.urlopen('http://127.0.0.1:'+str(port)+'/health',timeout=5) as r:
            b=json.load(r);need(r.status==200 and b.get('ok') is True,'health_failed:'+name);d[name]={'ok':True,'service':b.get('service')}
    return d
def baseline():
    p=plan();pointers(p['old_release'],p['old_payment'])
    a=Path(p['old_release']);pay=Path(p['old_payment'])
    need(sha(a/'release_manifest.json')==p['old_manifest'] and sha(pay/'manifest.json')==p['old_payment_manifest'],'baseline_manifest_changed')
    manifest(a,json.loads((a/'release_manifest.json').read_bytes())['files']);manifest(pay,json.loads((pay/'manifest.json').read_bytes()))
    need(json.loads((a/'addon/server/bundles/current.json').read_bytes())['hash']==p['base'],'baseline_bundle_changed')
    return a,pay
def backup():
    p=plan();a,pay=baseline();health()
    directory=Path('/var/backups/goufayu-shop-functional-v2')/p['candidate'];need(not directory.exists(),'backup_exists');directory.mkdir(mode=0o700,parents=True)
    with payment().connection() as c:
        c.execute('SET TRANSACTION READ ONLY');state=invariant(c);c.rollback()
    capture=io.StringIO()
    with contextlib.redirect_stdout(capture):payment().backup()
    result=json.loads(capture.getvalue().splitlines()[-1]);dump=Path(result['local_backup'])
    need(dump.is_file() and dump.stat().st_size>0 and dump.with_suffix('.sha256').read_text().strip()==sha(dump),'database_backup_invalid')
    with tarfile.open(directory/'sources.tar.gz','x:gz') as tar:
        for prefix,root,names in [('archive',a,[*json.loads((a/'release_manifest.json').read_bytes())['files'],'release_manifest.json']),('payment',pay,[*json.loads((pay/'manifest.json').read_bytes()),'manifest.json'])]:
            for name in names:tar.add(root/name,arcname=prefix+'/'+name,recursive=False)
    d=stamp({'status':'BACKED_UP','database_backup':str(dump),'database_sha256':sha(dump),'source_backup':str(directory/'sources.tar.gz'),'source_sha256':sha(directory/'sources.tar.gz'),'function_security':state})
    save('backup',d);return d
def backup_verified():
    d=record('backup');need(sha(d['database_backup'])==d['database_sha256'] and sha(d['source_backup'])==d['source_sha256'],'backup_changed')
def unpack():
    p=plan();need(sha(STAGE/'overlay.tar.gz')==p['tar_sha256'],'tar_changed');dest=STAGE/'payload';need(not dest.exists(),'payload_exists');dest.mkdir(mode=0o700)
    with tarfile.open(STAGE/'overlay.tar.gz') as tar:
        seen=set()
        for member in tar.getmembers():
            relative(member.name);need(member.isfile() and member.name not in seen,'unsafe_tar');seen.add(member.name)
            target=dest/member.name;target.parent.mkdir(parents=True,exist_ok=True)
            with tar.extractfile(member) as source,target.open('xb') as out:shutil.copyfileobj(source,out)
    need(seen==set(p['files']),'tar_manifest_scope');manifest(dest,p['files'])
def prepare():
    p=plan();a,pay=baseline();backup_verified();unpack();payload=STAGE/'payload'
    target=Path(p['target_release']);target_pay=Path(p['target_payment']);need(not target.exists() and not target_pay.exists(),'release_exists')
    am=json.loads((a/'release_manifest.json').read_bytes());pm=json.loads((pay/'manifest.json').read_bytes())
    for source,dest,files in [(a,target,am['files']),(pay,target_pay,pm)]:
        dest.mkdir(mode=0o755)
        for name in files:
            q=dest/name;q.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(source/name,q)
        (dest/'.venv').symlink_to(source/'.venv',target_is_directory=True)
    shutil.copytree(payload/'bundle'/p['candidate'],target/'addon/server/bundles'/p['candidate'],dirs_exist_ok=True)
    (target/'addon/server/bundles/current.json').write_text(json.dumps({'hash':p['candidate'],'protocol':1}))
    for source in (payload/'payment_reference').rglob('*'):
        if source.is_file():shutil.copyfile(source,target_pay/'reference_csv'/source.relative_to(payload/'payment_reference'))
    changed_archive=[n for n in am['files'] if sha(target/n)!=am['files'][n]]
    changed_payment=[n for n in pm if sha(target_pay/n)!=pm[n]]
    need(changed_archive==['addon/server/bundles/current.json'],'unrelated_archive_source_changed')
    allowed={'reference_csv/商城兑换系统/'+n+'.csv' for n in ['commerce_products','commerce_rewards','commerce_import_status','commerce_bundle_members']}
    allowed.add('reference_csv/抽奖系统/lottery_item_definitions.csv')
    need(set(changed_payment)==allowed,'unrelated_payment_source_changed')
    am.update(release=target.name,previous_release=a.name,archive_bundle=p['candidate'],description='Four functional imports and starter pack, existing prices/reducers retained')
    am['files']={q.relative_to(target).as_posix():sha(q) for q in target.rglob('*') if q.is_file() and not q.is_symlink()}
    (target/'release_manifest.json').write_text(json.dumps(am,ensure_ascii=False,indent=2)+'\n')
    pm={n:sha(target_pay/n) for n in pm};(target_pay/'manifest.json').write_text(json.dumps(pm,ensure_ascii=False,indent=2)+'\n')
    # New Python sources/schema are deliberately absent from this release.
    for dest in [target,target_pay]:
        for q in dest.rglob('*'):
            if not q.is_symlink():q.chmod(0o755 if q.is_dir() or q.stat().st_mode&0o111 else 0o644)
    load('functional_manage_prepare',target/'deploy/manage.py').validated_release(str(target))
    rollback=Path(p['target_release']+'-rollback');need(not rollback.exists(),'rollback_release_exists')
    shutil.copytree(target,rollback,symlinks=True)
    shutil.copyfile(a/'addon/server/bundles/current.json',rollback/'addon/server/bundles/current.json')
    rm=copy.deepcopy(am);rm.update(release=rollback.name,archive_bundle=p['base'],description='Old code/config reader with the additive immutable functional bundle retained')
    rm['files']={n:sha(rollback/n) for n in am['files']}
    (rollback/'release_manifest.json').write_text(json.dumps(rm,ensure_ascii=False,indent=2)+'\n')
    load('functional_rollback_prepare',rollback/'deploy/manage.py').validated_release(str(rollback))
    d=stamp({'status':'PREPARED','archive_manifest':sha(target/'release_manifest.json'),'payment_manifest':sha(target_pay/'manifest.json'),'rollback_archive':str(rollback),'rollback_manifest':sha(rollback/'release_manifest.json'),'archive_changed':changed_archive,'payment_changed':changed_payment})
    save('prepared',d);return d
def prepared():
    p=plan();d=record('prepared');manifest(STAGE/'payload',p['files'])
    for root,name,field in [(Path(p['target_release']),'release_manifest.json','archive_manifest'),(Path(p['target_payment']),'manifest.json','payment_manifest')]:
        need(sha(root/name)==d[field],'prepared_manifest_changed');m=json.loads((root/name).read_bytes());manifest(root,m['files'] if name=='release_manifest.json' else m)
    rollback=Path(d['rollback_archive']);need(sha(rollback/'release_manifest.json')==d['rollback_manifest'],'rollback_manifest_changed')
    manifest(rollback,json.loads((rollback/'release_manifest.json').read_bytes())['files'])
    return p
def package():return json.loads((STAGE/'payload/payment_package.json').read_bytes())
def archive_cfg():return json.loads((STAGE/'payload/archive_config.json').read_bytes())
def database(commit=False):
    p=prepared();baseline();pkg=package();need(pkg['catalog_hash']==p['cash_hash'],'package_hash_changed')
    sys.path.insert(0,p['old_payment']);from psycopg.types.json import Jsonb
    from payment_backend.sync_catalog import apply
    with payment().connection() as c:
        try:
            c.execute('SET TRANSACTION ISOLATION LEVEL REPEATABLE READ');c.execute("SET lock_timeout='5s'");c.execute('SET ROLE goufayu_owner')
            if commit:
                c.execute('LOCK TABLE public.survival_players,public.player_gameplay_stats,public.player_archive_state,payments.orders IN SHARE ROW EXCLUSIVE MODE')
            old=invariant(c);before=business(c)
            c.execute((STAGE/'payload/upgrade.sql').read_text())
            result=c.execute('SELECT public.archive_sync_config(%s,%s)',(p['candidate'],Jsonb(archive_cfg()))).fetchone()[0];need(result.get('ok') is True,'archive_registration_failed')
            apply(c,pkg);now=invariant(c,True)
            need({k:v for k,v in old['sync'].items() if k!='sha256'}=={k:v for k,v in now['sync'].items() if k!='sha256'},'sync_security_changed')
            need(old['apply']==now['apply'],'payment_function_security_changed')
            need(business(c)==before,'business_data_changed')
            if not commit:
                c.execute('SAVEPOINT synthetic_functional_fixtures')
                checks=load('functional_catalog_sql_checks',STAGE/'payload/test_functional_catalog_database.py').run_checks(c,pkg)
                c.execute('ROLLBACK TO SAVEPOINT synthetic_functional_fixtures')
                need(business(c)==before,'fixture_state_not_reverted')
                # A mutated config must fail the exact configuration guard.
                changed=copy.deepcopy(archive_cfg());changed['configs']['commerce_catalog']['rows'][0]['price']+=1
                rejected=False
                try:
                    with c.transaction():c.execute('SELECT public.archive_sync_config(%s,%s)',(p['candidate'],Jsonb(changed)))
                except Exception:rejected=True
                need(rejected,'mutated_archive_config_accepted')
                c.rollback()
                return {'status':'PASS','fixtures':checks,'exact_config_mutation_rejected':True,'all_other_business_tables_unchanged':True,'transaction_rolled_back':True}
            baseline()
        except BaseException:c.rollback();raise
    d=stamp({'status':'COMMITTED','catalog_hash':p['cash_hash'],'archive_bundle':p['candidate'],'business_tables_unchanged':True,'synthetic_rows_committed':0});save('committed',d);return d
def staged_reference_check(p):
    # Preserve the strict production validator; only point it at this verified
    # staged bundle for the read-only validation before pointer activation.
    source="""from pathlib import Path
import sys
sys.path.insert(0,str(Path.cwd()))
from payment_backend import sync_catalog
sync_catalog.GAME=Path(ARCHIVE)
sync_catalog.validate(PACKAGE,DIGEST)
print('STAGED_REFERENCE_CONTRACT_PASS')
""".replace('ARCHIVE',repr(p['target_release']),1).replace('PACKAGE',repr(str(STAGE/'payload/payment_package.json')),1).replace('DIGEST',repr(sha(STAGE/'payload/payment_package.json')),1)
    q=subprocess.run([str(Path(p['target_payment'])/'.venv/bin/python'),'-B','-c',source],cwd=p['target_payment'],capture_output=True,timeout=40)
    need(q.returncode==0 and b'STAGED_REFERENCE_CONTRACT_PASS' in q.stdout,'staged_reference_contract_failed')
def validate():
    p=prepared();baseline();backup_verified()
    staged_reference_check(p)
    lua=shutil.which('lua5.1') or shutil.which('lua');need(lua,'lua_missing')
    worker=load('functional_worker_smoke',STAGE/'payload/smoke.py').run_checks(Path(p['target_release'])/'addon/server/bundles'/p['candidate'],lua)
    d=stamp({'status':'VALIDATED','worker':worker,'database':database()});save('validation',d);return d
def service(action,name):subprocess.run(['systemctl',action,name],capture_output=True,check=True,timeout=40)
def switch(base,target):
    link=base/('.functional-next-'+secrets.token_hex(5));link.symlink_to(target,target_is_directory=True);os.replace(link,base/'current')
def ready(archive,pay):
    for attempt in range(25):
        try:
            with contextlib.redirect_stdout(io.StringIO()):load('functional_archive_ready',archive/'deploy/manage.py').health()
            health()
            for name,directory in [('goufayu-api.service',archive),('goufayu-payment.service',pay)]:
                pid=subprocess.run(['systemctl','show',name,'--property=MainPID','--value'],capture_output=True,text=True,check=True).stdout.strip()
                cwd=subprocess.run(['systemctl','show',name,'--property=WorkingDirectory','--value'],capture_output=True,text=True,check=True).stdout.strip()
                need(pid.isdigit() and int(pid)>1 and Path('/proc/'+pid+'/cwd').resolve()==directory and Path(cwd).resolve()==directory,'service_cwd_mismatch')
            return
        except Exception:
            if attempt==24:raise RuntimeError('strict_service_readiness_failed') from None
            time.sleep(.5)
def verify():
    p=prepared();a=Path(p['target_release']);pay=Path(p['target_payment']);pointers(a,pay);ready(a,pay)
    with payment().connection() as c:
        c.execute('SET TRANSACTION READ ONLY');invariant(c,True)
        actual=c.execute('SELECT config FROM public.archive_config_sets WHERE config_hash=%s',(p['candidate'],)).fetchone();need(actual and actual[0]==archive_cfg(),'archive_config_drift')
        pkg=package();rows={r[0]:r[1:] for r in c.execute('SELECT sku,item_id,amount,effects,enabled,grants FROM payments.products')}
        for product in pkg['catalog']['products']:
            need(rows[product['sku']]==(product['item_id'],product['amount'],product['effects'],product['enabled'],product['grants']),'published_catalog_drift:'+product['sku'])
        need(c.execute('SELECT count(*) FROM payments.products WHERE enabled').fetchone()[0]==47,'enabled_count_drift');c.rollback()
    # Validate both services' reference contracts with the exact new pointer.
    command=[str(pay/'.venv/bin/python'),'-B','-m','payment_backend.sync_catalog','check',str(STAGE/'payload/payment_package.json'),sha(STAGE/'payload/payment_package.json')]
    checked=subprocess.run(command,cwd=pay,capture_output=True,timeout=90);need(checked.returncode==0,'payment_reference_contract_failed')
    return stamp({'status':'VERIFIED','archive_release':str(a),'payment_release':str(pay),'archive_bundle':p['candidate'],'payment_catalog_hash':p['cash_hash'],'wallet_count':129,'wallet_enabled':126,'cash_enabled':47,'health':health(),'old_prices_unchanged':True,'old_reducers_unchanged':True,'gateway_requests':0,'real_player_commands':0,'synthetic_rows_committed':0})
def activate():
    p=prepared();baseline();backup_verified();need(record('validation')['status']=='VALIDATED','validation_missing')
    stopped=False;committed=False
    try:
        stopped=True
        service('stop','goufayu-api.service');service('stop','goufayu-payment.service')
        baseline();database(commit=True);committed=True
        pointers(p['old_release'],p['old_payment'])
        switch(Path('/opt/goufayu/releases'),p['target_release']);switch(Path('/opt/goufayu/payments'),p['target_payment'])
        service('start','goufayu-api.service');service('start','goufayu-payment.service')
        result=verify();save('activated',result);return result
    except BaseException:
        # Readers are unchanged and understand old/new immutable receipts. Keep
        # additive config compatibility, restore the old published catalog/code.
        recovery=[]
        try:
            # A commit can succeed before a report write/transport fails. Check
            # durable state rather than trusting the caller's in-memory flag.
            with payment().connection() as c:
                c.execute('SET TRANSACTION READ ONLY')
                actual_cash=c.execute('SELECT catalog_hash FROM payments.catalog_state WHERE singleton').fetchone()[0];c.rollback()
            need(actual_cash in [p['old_cash_hash'],p['cash_hash']],'external_catalog_change_during_recovery')
            committed=actual_cash==p['cash_hash']
            if committed:
                from psycopg.types.json import Jsonb
                snap=json.loads((STAGE/'old_catalog_snapshot.json').read_bytes())
                with payment().connection() as c:
                    c.execute('SET ROLE goufayu_owner')
                    c.execute("SELECT pg_advisory_xact_lock(hashtext('payments.catalog.publish'))")
                    current_hash=c.execute('SELECT catalog_hash FROM payments.catalog_state WHERE singleton FOR UPDATE').fetchone()[0]
                    need(current_hash==p['cash_hash'],'external_catalog_change_during_locked_recovery')
                    c.execute('UPDATE payments.products SET enabled=false')
                    for row in snap['products']:
                        c.execute('UPDATE payments.products SET title=%s,description=%s,amount=%s,effects=%s,enabled=%s,sort_order=%s,grants=%s,category_id=%s,product_type=%s,icon=%s,purchase_limit=%s WHERE sku=%s',tuple(Jsonb(row[k]) if k in ['effects','grants'] else row[k] for k in ['title','description','amount','effects','enabled','sort_order','grants','category_id','product_type','icon','purchase_limit','sku']))
                    c.execute('UPDATE payments.catalog_state SET catalog_hash=%s,categories=%s WHERE singleton',(p['old_cash_hash'],Jsonb(snap['categories'])))
        except Exception:recovery.append('catalog_recovery_failed')
        try:
            # The old reader contains all reducers; added config remains usable
            # for any immutable snapshot created just before service stop.
            rollback=Path(p['target_release']+'-rollback')
            if Path('/opt/goufayu/releases/current').resolve() in [Path(p['old_release']),Path(p['target_release'])]:switch(Path('/opt/goufayu/releases'),rollback)
            else:recovery.append('archive_pointer_external_change')
            if Path('/opt/goufayu/payments/current').resolve() in [Path(p['old_payment']),Path(p['target_payment'])]:switch(Path('/opt/goufayu/payments'),p['old_payment'])
            else:recovery.append('payment_pointer_external_change')
            if stopped:service('restart','goufayu-api.service');service('restart','goufayu-payment.service')
            ready(rollback,Path(p['old_payment']))
        except Exception:recovery.append('code_recovery_failed')
        save('activation_failed',stamp({'status':'RECOVERY_REQUIRED' if recovery else 'ROLLED_BACK','committed':committed,'recovery_errors':recovery}));raise
def main():
    global PLAN_PIN,OPERATOR_PIN
    parser=argparse.ArgumentParser();parser.add_argument('action',choices=['backup','prepare','validate','activate','verify']);parser.add_argument('--plan-sha',required=True);parser.add_argument('--operator-sha',required=True);args=parser.parse_args()
    PLAN_PIN=args.plan_sha;OPERATOR_PIN=args.operator_sha
    need(os.geteuid()==0 and STAGE==Path('/tmp/survival-shop-functional-20261016-v2'),'operator_scope')
    with open('/var/lock/goufayu-shop-functional.lock','w') as guard:
        fcntl.flock(guard,fcntl.LOCK_EX|fcntl.LOCK_NB);plan()
        if args.action=='backup':
            baseline()
            with payment().connection() as c:
                c.execute('SET TRANSACTION READ ONLY')
                snapshot={'products':[r[0] for r in c.execute('SELECT to_jsonb(p) FROM payments.products p ORDER BY sku')],'categories':c.execute('SELECT categories FROM payments.catalog_state WHERE singleton').fetchone()[0]};c.rollback()
            save('old_catalog_snapshot',snapshot)
        result=globals()[args.action]();save(args.action+'_result',stamp(result));print(json.dumps(result,ensure_ascii=False))
if __name__=='__main__':
    try:main()
    except Exception as error:
        detail=str(error) if type(error) is RuntimeError and re.fullmatch('[a-zA-Z0-9_./:, -]{1,240}',str(error)) else type(error).__name__
        print(json.dumps({'status':'FAILED','error':detail}));sys.exit(1)
