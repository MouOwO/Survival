"""Root-only, hash-pinned operator for the explicitly approved points deployment.

Back up before mutation. Fixture tests are rolled back. Activation commits only
one reviewed function and additive archive configuration, then swaps a symlink.
No payment gateway, real order, login or real-player archive command is called.
"""
from pathlib import Path,PurePosixPath
from datetime import datetime,timezone
import contextlib,copy,fcntl,hashlib,importlib.util,io,json,os,secrets,shutil,subprocess,sys,tarfile,time,urllib.request

BASE=Path('/opt/goufayu/releases')
OLD=BASE/'20261015-video-bundles-v1'
TARGET=BASE/'20261016-commerce-points-v1'
ROLLBACK=BASE/'20261016-commerce-points-rollback-v1'
PAY=Path('/opt/goufayu/payments/20261015-payment02')
STAGE=Path('/tmp/survival-commerce-points-20261016-caf4493bb7ad')
BACKUP=Path('/var/backups/goufayu-commerce-points/20261016-caf4493bb7ad')
BEFORE='dee53fe2e9fb8d1bc97ba6b822a86896e97e94b6bad84501fad5791920c3ca26'
AFTER='caf4493bb7ad373a43ca81c19f961d4fd288a47112866ba93df62013852f7a59'
OLD_MANIFEST='81acaf8341366bc56bfc286843242fd5a8cc21628a297bab4a3ab5857fb8eec3'
PAY_MANIFEST='ab18979b1194a3a3877b3a0635ff9f970e2838ff97783227d2e27a06571b1419'
OLD_SOURCE='cd6c95a9ec829ade90401dbbd3484ada39ea43adaf789e404f82079ca6067ca6'
NEW_SOURCE='3f87fd4b219c20fedac5176c2ea7153f4e639dced48badc571781019755b6993'
OLD_FN='3ea52ec1171407ed4f50793f1197b86b'
NEW_FN='c989f8a7d552028306058e6ab7099af2'
CATALOG='b56e72aaf6b1cd512ada1f5fe460be98a2f871e7d5dc1b7131701fb4654f4cbe'
ARCHIVE_TAR='00204767f881085d674a41cfdfa8fbf4ba5a7d2be3613d12868bf77b65d0d6f3'
PAYMENT_TAR='09dfe0928c3cff34a6a10da9fe722a2d3eabae29269ea9d131651e3c00da3ba4'
PATCH_SHA='6c18626023c15e494e9adf4bb084cb2a173b1294c965959657d2db9af2f8224f'
COMPAT_MANIFEST_SHA='364d810ae8b2f9f452b80fde37cf27e85a5e88a94d8ef6dcccb2f874a17a4992'
SYNC_OLD_SHA='21995acdd16a62e7da56a4cf6641e8b693688bf4b00a041f6afbcee08dba4ff2'
SYNC_NEW_SHA='fa656dc096838c8cf8a6df00bee570acb56469d9d561fdc090cf15db6dbe529b'

def need(value,reason):
    if not value:raise RuntimeError(reason)
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def load(name,p):
    spec=importlib.util.spec_from_file_location(name,p);module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module);return module
def save(path,data):
    need(not path.is_symlink(),'report_symlink_refused')
    tmp=path.with_name(path.name+'.'+secrets.token_hex(4));tmp.write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n');tmp.chmod(0o600);os.replace(tmp,path)
def pay_deploy():return load('points_payment_deploy',PAY/'deploy.py')
def current(expected=OLD):
    need((BASE/'current').is_symlink() and (BASE/'current').resolve()==expected,'archive_release_changed_since_review')
    need(Path('/opt/goufayu/payments/current').resolve()==PAY,'payment_release_changed_since_review')
def manifest_check(directory,files):
    for name,digest in files.items():
        relative=PurePosixPath(name);p=directory/name
        need(not relative.is_absolute() and '..' not in relative.parts and '\\' not in name,'unsafe_manifest_path')
        need(not any(q.is_symlink() for q in [p,*p.parents] if q!=directory.parent),'manifest_symlink_refused')
        need(p.is_file() and sha(p)==digest,'manifest_digest_mismatch:'+name)
def baseline():
    need(sha(OLD/'release_manifest.json')==OLD_MANIFEST,'baseline_manifest_changed')
    need(sha(OLD/'backend/archive_backend/service.py')==OLD_SOURCE,'baseline_source_changed')
    old=json.loads((OLD/'release_manifest.json').read_text());manifest_check(OLD,old['files'])
    need(sha(PAY/'manifest.json')==PAY_MANIFEST,'payment_manifest_changed')
    manifest_check(PAY,json.loads((PAY/'manifest.json').read_text()))
    need(json.loads((OLD/'addon/server/bundles/current.json').read_text())['hash']==BEFORE,'baseline_bundle_changed')
    return old
def function_meta(conn,signature='payments.apply_effects(text,jsonb,boolean)'):
    row=conn.execute("""SELECT md5(btrim(replace(prosrc,chr(13),''),chr(10)||chr(9)||' ')),
      pg_get_userbyid(proowner),prosecdef,proconfig,proacl::text,
      has_function_privilege('goufayu_payment',oid,'EXECUTE'),pg_get_functiondef(oid)
      FROM pg_proc WHERE oid=%s::regprocedure""",(signature,)).fetchone()
    return {'body_md5':row[0],'owner':row[1],'security_definer':row[2],'configuration':row[3],
            'acl':row[4],'payment_can_execute':row[5],'definition_sha256':hashlib.sha256(row[6].encode()).hexdigest()},row[6]
def invariants(conn,expected):
    need(conn.execute('SELECT current_database()').fetchone()[0]=='goufayu_test','unexpected_database')
    meta,_=function_meta(conn);need(meta['body_md5']==expected,'payment_function_changed_since_review')
    need(meta['security_definer'] and not meta['payment_can_execute'],'payment_function_privilege_invalid')
    need(conn.execute('SELECT catalog_hash FROM payments.catalog_state WHERE singleton').fetchone()[0]==CATALOG,'payment_catalog_changed')
    need(conn.execute('SELECT count(*) FROM payments.products WHERE enabled').fetchone()[0]==44,'cash_product_count_changed')
    if (BACKUP/'backup.json').exists():
        original=json.loads((BACKUP/'backup.json').read_text())['previous_function']
        fields={'owner','security_definer','configuration','acl','payment_can_execute'}
        need({k:meta[k] for k in fields}=={k:original[k] for k in fields},'function_security_changed_since_backup')
    return meta
def table_state(conn):
    from psycopg import sql
    rows=conn.execute("""SELECT schemaname,tablename FROM pg_tables WHERE schemaname IN ('public','payments') ORDER BY schemaname,tablename""").fetchall()
    return {s+'.'+t:conn.execute(sql.SQL("SELECT count(*),md5(coalesce(string_agg(to_jsonb(t)::text,chr(10) ORDER BY to_jsonb(t)::text),'')) FROM {}.{} t").format(sql.Identifier(s),sql.Identifier(t))).fetchone() for s,t in rows}
def phase_connection(conn,publish=False):
    conn.execute('SET TRANSACTION ISOLATION LEVEL '+('READ COMMITTED' if publish else 'REPEATABLE READ'))
    conn.execute("SET LOCAL lock_timeout='5s'");conn.execute("SET LOCAL statement_timeout='90s'");conn.execute('SET ROLE goufayu_owner')
    if publish:
        from psycopg import sql
        conn.execute("SELECT pg_advisory_xact_lock(hashtext('payments.order_quantity.publish'))")
        conn.execute("SELECT pg_advisory_xact_lock(hashtext('payments.catalog.publish'))")
        rows=conn.execute("SELECT schemaname,tablename FROM pg_tables WHERE schemaname IN ('public','payments') ORDER BY schemaname,tablename").fetchall()
        # Very brief metadata publication; stable before/after rows while plain
        # status SELECTs remain available. Lock acquisition fails closed after5s.
        conn.execute(sql.SQL('LOCK TABLE {} IN EXCLUSIVE MODE').format(sql.SQL(',').join(sql.Identifier(s,t) for s,t in rows)))
def inspect_http():
    result={}
    for name,port in [('archive',8765),('payment',8766)]:
        with urllib.request.urlopen('http://127.0.0.1:'+str(port)+'/health',timeout=5) as r:
            body=json.load(r);need(r.status==200 and body.get('ok') is True,'service_health_failed:'+name);result[name]=body
    return result

def backup():
    current();old=baseline();inspect_http()
    need(not BACKUP.exists(),'backup_directory_already_exists')
    BACKUP.mkdir(mode=0o700,parents=True);BACKUP.chmod(0o700)
    with pay_deploy().connection() as c:
        c.execute('SET TRANSACTION READ ONLY');meta,definition=function_meta(c);invariants(c,OLD_FN)
        (BACKUP/'apply_effects_before.sql').write_text(definition+'\n')
        (BACKUP/'archive_sync_config_before.sql').write_text(c.execute("SELECT pg_get_functiondef('public.archive_sync_config(text,jsonb)'::regprocedure)").fetchone()[0])
        c.rollback()
    sources=BACKUP/'release-sources.tar.gz'
    with tarfile.open(sources,'w:gz') as archive:
        for prefix,root,names in [('archive',OLD,[*old['files'],'release_manifest.json']),('payment',PAY,[*json.loads((PAY/'manifest.json').read_text()),'manifest.json'])]:
            for name in names:archive.add(root/name,arcname=prefix+'/'+name,recursive=False)
    captured=io.StringIO()
    with contextlib.redirect_stdout(captured):pay_deploy().backup()
    details=json.loads(captured.getvalue().splitlines()[-1]);db=Path(details['local_backup'])
    need(db.is_file() and db.stat().st_size>0,'database_backup_missing')
    need(db.with_suffix('.sha256').read_text().strip()==sha(db),'database_backup_digest_mismatch')
    record={'status':'BACKED_UP','created_utc':datetime.now(timezone.utc).isoformat(),
            'archive_previous':str(OLD),'payment_unchanged':str(PAY),'database_backup':str(db),'database_sha256':sha(db),
            'source_backup':str(sources),'source_sha256':sha(sources),'previous_function':meta,
            'archive_manifest_sha256':OLD_MANIFEST,'payment_manifest_sha256':PAY_MANIFEST,'offsite':False}
    save(BACKUP/'backup.json',record);save(STAGE/'backup.json',record)
    return record

def backup_verified():
    record=json.loads((BACKUP/'backup.json').read_text())
    need(sha(Path(record['database_backup']))==record['database_sha256'],'database_backup_changed')
    need(sha(Path(record['source_backup']))==record['source_sha256'],'source_backup_changed')
    return record

def unpack(name,digest,destination,manifest_name):
    need(sha(STAGE/name)==digest,'uploaded_tar_digest_mismatch')
    need(not destination.exists(),'unpack_destination_already_exists');destination.mkdir(mode=0o700)
    with tarfile.open(STAGE/name,'r:gz') as archive:
        for member in archive.getmembers():
            p=PurePosixPath(member.name)
            need(not p.is_absolute() and '..' not in p.parts and '\\' not in member.name,'unsafe_tar_path')
            need(member.isfile() or member.isdir(),'tar_link_or_special_file_refused')
        for member in archive.getmembers():
            target=destination/member.name
            if member.isdir():target.mkdir(mode=0o700,parents=True,exist_ok=True)
            else:
                target.parent.mkdir(mode=0o700,parents=True,exist_ok=True)
                with archive.extractfile(member) as source,target.open('xb') as sink:shutil.copyfileobj(source,sink)
                target.chmod(0o600)
    manifest=json.loads((destination/manifest_name).read_text())
    manifest_check(destination,manifest['files'])
    actual={p.relative_to(destination).as_posix() for p in destination.rglob('*') if p.is_file()}
    need(actual==set(manifest['files'])|{manifest_name},'unmanifested_package_file')
    return manifest

def clone_release(destination,old,patch=False):
    need(not destination.exists(),'release_destination_already_exists')
    destination.mkdir(mode=0o755)
    for name in old['files']:
        target=destination/name;target.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(OLD/name,target)
    bundle=STAGE/'archive/candidate/addon/server/bundles'/AFTER
    shutil.copytree(bundle,destination/'addon/server/bundles'/AFTER)
    if patch:
        patcher=load('exact_online_patch',STAGE/'deploy_online_patch.py')
        source=destination/'backend/archive_backend/service.py';raw=source.read_bytes();new=patcher.transform(raw)
        need(patcher.transform(new,True)==raw,'patch_reverse_not_exact');source.write_bytes(new)
        pointer=STAGE/'archive/candidate/addon/server/bundles/current.json'
        shutil.copy2(pointer,destination/'addon/server/bundles/current.json')
    changed=sorted(n for n,d in old['files'].items() if sha(destination/n)!=d)
    need(changed==(['addon/server/bundles/current.json','backend/archive_backend/service.py'] if patch else []),'unrelated_online_source_change')
    meta=copy.deepcopy(old);meta.update(release=destination.name,previous_release=OLD.name,
        archive_bundle=AFTER if patch else BEFORE,description='Reviewed commerce points and starjoy progress' if patch else 'Baseline rollback retaining new immutable receipt reducer')
    meta['files']={p.relative_to(destination).as_posix():sha(p) for p in destination.rglob('*') if p.is_file()}
    (destination/'release_manifest.json').write_text(json.dumps(meta,ensure_ascii=False,indent=2)+'\n')
    for p in destination.rglob('*'):p.chmod(0o755 if p.is_dir() or p.stat().st_mode&0o111 else 0o644)
    (destination/'.venv').symlink_to(OLD/'.venv',target_is_directory=True)
    load('verify_'+destination.name,destination/'deploy/manage.py').validated_release(str(destination))
    return {'release':str(destination),'changed_existing_files':changed,'old_bundle_siblings_preserved':True,'new_bundle_retained':True,'manifest_sha256':sha(destination/'release_manifest.json')}

def prepare():
    current();old=baseline();backup_verified()
    need(sha(STAGE/'deploy_online_patch.py')==PATCH_SHA,'online_patcher_changed')
    a=unpack('archive_patch.tar.gz',ARCHIVE_TAR,STAGE/'archive','manifest.json')
    p=unpack('payment_starjoy_progress_v1.tar.gz',PAYMENT_TAR,STAGE/'payment','manifest.json')
    need(a['candidate']==AFTER and a['base']==BEFORE,'unexpected_archive_candidate')
    need(p['kind']=='payment_starjoy_progress_only','unexpected_payment_patch')
    report={'status':'PREPARED_NOT_ACTIVATED','target':clone_release(TARGET,old,True),'rollback':clone_release(ROLLBACK,old,False)}
    save(STAGE/'prepared.json',report);return report

def prepared():
    baseline();backup_verified();record=json.loads((STAGE/'prepared.json').read_text())
    for key,path in [('target',TARGET),('rollback',ROLLBACK)]:
        need(sha(path/'release_manifest.json')==record[key]['manifest_sha256'],'staged_manifest_changed')
        load('validate_'+key,path/'deploy/manage.py').validated_release(str(path))
    need(sha(TARGET/'backend/archive_backend/service.py')==NEW_SOURCE,'staged_service_changed')
    need(sha(STAGE/'payment/upgrade_starjoy_progress.sql')=='8d880972b966783cdf514a3091446c4850e37285516ec90f5be7f37f22cbb813','migration_changed')
    need(sha(STAGE/'payment/test_starjoy_progress_database.py')=='4878e5d20174250c692e580cd3990ec037f8bc8b1b889851e6ec3c1fb0f6985a','fixture_test_changed')
    need(sha(STAGE/'earned_stat_rule.sql')=='cb0b836aa943d6e226dbc7567c6e572246d60b8978f5580af2810e296111850b','earned_rule_sql_changed')
    need(sha(STAGE/'archive_points_compat_manifest.json')==COMPAT_MANIFEST_SHA,'compat_manifest_changed')
    compat=json.loads((STAGE/'archive_points_compat_manifest.json').read_text())
    need(compat['old_definition_sha256']==SYNC_OLD_SHA and compat['new_definition_sha256']==SYNC_NEW_SHA,'compat_function_pin_changed')
    manifest_check(STAGE,compat['files'])
    sys.path.insert(0,str(TARGET/'backend'))
    from archive_backend.bundle import Bundle
    bundle=Bundle(TARGET/'addon/server/bundles'/AFTER);need(bundle.hash==AFTER,'staged_bundle_changed')
    original=Bundle(OLD/'addon/server/bundles'/BEFORE)
    need(all(bundle.compatible_config_hashes.get(k)==v for k,v in original.compatible_config_hashes.items()),'historical_compatibility_changed')
    need(not bundle.compatible_config_hashes[BEFORE]['upgrade_commands'],'financial_upgrade_allowlist_changed')
    return bundle

def configuration(bundle):
    return {'configs':bundle.configs,'compatible_config_hashes':{k:{n:sorted(v) for n,v in r.items()} for k,r in bundle.compatible_config_hashes.items()}}

def register(conn,bundle):
    from psycopg.types.json import Jsonb
    actual=conn.execute("SELECT pg_get_functiondef('public.archive_sync_config(text,jsonb)'::regprocedure)").fetchone()[0]
    need(hashlib.sha256(actual.encode()).hexdigest()==SYNC_NEW_SHA,'archive_sync_definition_changed')
    before={r[0]['config_hash']:r[0] for r in conn.execute('SELECT to_jsonb(c) FROM public.archive_config_sets c')}
    cfg=configuration(bundle)
    result=conn.execute('SELECT public.archive_sync_config(%s,%s)',(bundle.hash,Jsonb(cfg))).fetchone()[0]
    need(result.get('ok') is True,'archive_config_registration_failed')
    need(conn.execute('SELECT config=%s FROM public.archive_config_sets WHERE config_hash=%s',(Jsonb(cfg),bundle.hash)).fetchone()[0] is True,'registered_configuration_differs')
    after={r[0]['config_hash']:r[0] for r in conn.execute('SELECT to_jsonb(c) FROM public.archive_config_sets c')}
    need(all(after.get(k)==v for k,v in before.items()) and set(after)==set(before)|{bundle.hash},'registration_changed_existing_config_rows')
    return result

def same_business(before,after):
    changed=[key for key in before if before[key]!=after.get(key)]
    # Registration inserts only an immutable config plus approved aliases.
    need(set(changed)<= {'public.archive_config_sets','payments.stat_rules'},'registration_changed_business_tables:'+','.join(changed))
    return changed

def migrate(conn):
    prior_sync,_=function_meta(conn,'public.archive_sync_config(text,jsonb)')
    need(prior_sync['definition_sha256'] in {SYNC_OLD_SHA,SYNC_NEW_SHA},'archive_sync_changed_since_review')
    old={r[0]['field_id']:r[0] for r in conn.execute('SELECT to_jsonb(r) FROM payments.stat_rules r')}
    conn.execute((STAGE/'earned_stat_rule.sql').read_text())
    now={r[0]['field_id']:r[0] for r in conn.execute('SELECT to_jsonb(r) FROM payments.stat_rules r')}
    expected=dict(old);expected['starjoy_points_earned']={'field_id':'starjoy_points_earned','minimum':0,'maximum':None,'default_value':0}
    need(now==expected,'migration_changed_unrelated_stat_rules')
    conn.execute((STAGE/'payment/upgrade_starjoy_progress.sql').read_text())
    conn.execute((STAGE/'upgrade_archive_points_compat.sql').read_text())
    now_sync,_=function_meta(conn,'public.archive_sync_config(text,jsonb)')
    need(now_sync['definition_sha256']==SYNC_NEW_SHA,'archive_sync_migration_digest_incorrect')
    security={'owner','security_definer','configuration','acl','payment_can_execute'}
    need({k:prior_sync[k] for k in security}=={k:now_sync[k] for k in security},'archive_sync_security_metadata_changed')

def database_validate(bundle):
    with pay_deploy().connection() as c:
        try:
            phase_connection(c);prior=invariants(c,OLD_FN);before=table_state(c);prior_sync=function_meta(c,'public.archive_sync_config(text,jsonb)')[0]
            c.execute('SAVEPOINT rollback_fixtures')
            migrate(c)
            tests=load('rollback_only_starjoy_tests',STAGE/'payment/test_starjoy_progress_database.py')
            checked=tests.run_checks(c);need(checked['cases']==10,'unexpected_fixture_case_count')
            compat_tests=load('rollback_only_compat_tests',STAGE/'test_archive_points_compat.py')
            compat_checked=compat_tests.run_checks(c,configuration(bundle),AFTER,BEFORE)
            c.execute('ROLLBACK TO SAVEPOINT rollback_fixtures')
            need(table_state(c)==before,'fixture_rows_not_fully_rolled_back');need(function_meta(c)[0]==prior,'fixture_function_not_rolled_back')
            need(function_meta(c,'public.archive_sync_config(text,jsonb)')[0]==prior_sync,'fixture_sync_function_not_rolled_back')
            migrate(c);now=invariants(c,NEW_FN)
            need({k:v for k,v in now.items() if k not in {'body_md5','definition_sha256'}}=={k:v for k,v in prior.items() if k not in {'body_md5','definition_sha256'}},'function_security_metadata_changed')
            migrated=table_state(c)
            need(set(k for k,v in before.items() if migrated.get(k)!=v)<={'payments.stat_rules'},'migration_altered_existing_rows')
            registered=register(c,bundle);changed=same_business(before,table_state(c));current()
            c.rollback()
        except BaseException:c.rollback();raise
    return {'status':'PASS','fixture_checks':checked,'compatibility_guard_checks':compat_checked,'fixture_changes_rolled_back':True,'existing_player_order_catalog_rows_unchanged':True,'earned_stat_rule_added_only':True,
            'table_count':len(before),'registration_changed_only':changed,'registration':registered,'outer_transaction_rolled_back':True,'gateway_requests':0,'committed_test_orders':0}

def smoke(bundle):
    # Pure in-memory profile plus trusted Lua process. Never ArchiveService.profile/command.
    lua=shutil.which('lua5.1') or shutil.which('lua');need(lua is not None,'lua_interpreter_missing')
    configs=bundle.configs;items=configs['lottery_item_definitions']['rows'];rates={'n':5,'r':25,'sr':100,'ssr':400,'ur':1000}
    defaults={r['field_id']:r.get('default_value',0) for r in configs['player_gameplay_stats']['rows']}
    profile={'account_id':'synthetic-no-database','save':{'gameplay_stats':dict(defaults,starjoy_points=37,starjoy_points_earned=1000,starjoy_reward_level=5),
        'content_inventory':{r['item_id']:r.get('max_owned',1) for r in items},
        'archive':{'commerce':{'balances':{'shop_points':0,'shop_gold':1000000}},'lottery_state':{'pools':{'map':{'draws':100}}}}}}
    profile['save']['content_inventory'].update(lottery_ticket=100,special_lottery_ticket=100)
    def run(command,seed=1,source=profile):
        data={'configs':configs,'profile':source,'command':command,'has_pass':False,'seed':seed,'server_time':2000000000}
        p=subprocess.run([lua,'worker.lua'],cwd=bundle.directory,input=json.dumps(data,ensure_ascii=False).encode(),capture_output=True,check=True,timeout=10)
        return json.loads(p.stdout)
    summaries=[]
    for quality,rate in rates.items():
        pool='dragon_knight' if quality=='ur' else 'map';weights={r['quality']:r['weight'] for r in configs['lottery_quality_weights']['rows'] if r['pool_id']==pool};lo=1
        for q in rates:
            hi=lo+weights.get(q,0)-1
            if q==quality:break
            lo=hi+1
        seed=next(n for n in range(1,200000) if lo<=((n*48271)%2147483647)*10000//2147483647+1<=hi)
        result=run({'id':'deploy-smoke-'+quality,'kind':'lottery_draw','pool_id':pool,'count':1,'request_id':'deploy-smoke-'+quality},seed)
        need(result.get('ok') is True,'worker_draw_failed:'+quality)
        reward=result['response']['results'][0]
        need(reward['quality']==quality and reward['duplicate'] and reward['converted_points']==rate and reward['converted_currency']=='shop_points','worker_duplicate_rule_incorrect:'+quality)
        need(result['archive']['commerce']['balances']['shop_points']==rate and result['gameplay_stats']['starjoy_points']==37,'worker_wrong_currency')
        summaries.append({'quality':quality,'shop_points':rate})
    catalog=run({'id':'deploy-smoke-catalog','kind':'commerce_catalog'})
    need(catalog.get('ok') is True,'worker_catalog_failed')
    products=[p for p in configs['commerce_catalog']['rows'] if p.get('enabled') is not False]
    need(len(products)==119 and not any(p['currency']=='shop_gold' for p in products),'worker_gold_products_visible')
    for sku in ['video_p037','video_p038']:
        gold=run({'id':'deploy-smoke-gold-'+sku,'kind':'commerce_purchase','sku':sku,'request_id':'deploy-smoke-gold-'+sku})
        need(gold.get('error')=='shop_gold_not_open','worker_gold_not_blocked')
    return {'status':'PASS','synthetic_worker_rates':summaries,'enabled_commerce_products':len(products),'shop_gold_paused':True,'profile_or_command_api_calls':0,'gateway_requests':0,'persistent_writes':0}

def validate():
    current();bundle=prepared();result={'status':'VALIDATED_NOT_ACTIVATED','worker':smoke(bundle),'database':database_validate(bundle)}
    save(STAGE/'validation.json',result);return result

def switch(path):
    tmp=BASE/('.points-current-'+secrets.token_hex(8));tmp.symlink_to(path,target_is_directory=True)
    os.replace(tmp,BASE/'current')
    subprocess.run(['systemctl','restart','goufayu-api.service'],check=True,timeout=35)
    manage=load('active_health_'+path.name,path/'deploy/manage.py')
    for attempt in range(25):
        try:
            with contextlib.redirect_stdout(io.StringIO()):manage.health()
            return
        except Exception:
            if attempt==24:raise RuntimeError('archive_readiness_failed')
            time.sleep(.5)

def activate():
    current();bundle=prepared();report=json.loads((STAGE/'validation.json').read_text());need(report['status']=='VALIDATED_NOT_ACTIVATED','validate_before_activate')
    checked=smoke(bundle)
    with pay_deploy().connection() as c:
        try:
            phase_connection(c,publish=True);invariants(c,OLD_FN);before=table_state(c)
            migrate(c);invariants(c,NEW_FN)
            migrated=table_state(c)
            need(set(k for k,v in before.items() if migrated.get(k)!=v)<={'payments.stat_rules'},'activation_migration_changed_existing_rows')
            register(c,bundle);changed=same_business(before,table_state(c));current();c.commit()
        except BaseException:c.rollback();raise
    save(STAGE/'database_committed.json',{'migration_committed':True,'archive_hash_registered':AFTER,'changed_tables':changed,'test_fixtures_committed':False})
    try:
        current();switch(TARGET);result=verify();result.update(status='DEPLOYED',database_migration_committed=True,worker=checked,previous_release=str(OLD),rollback_release=str(ROLLBACK),backup=json.loads((BACKUP/'backup.json').read_text()))
        save(STAGE/'activated.json',result);return result
    except BaseException:
        # Keep SQL forward-compatible and every new receipt. Restore baseline code,
        # retaining the caf reducer sibling so prepared operations remain readable.
        if (BASE/'current').resolve()==TARGET:switch(ROLLBACK)
        save(STAGE/'activation_failed.json',{'status':'ROLLED_BACK_CODE','current':str((BASE/'current').resolve()),'sql_fix_retained':True,'existing_orders_and_rewards_preserved':True})
        raise

def verify():
    current(TARGET);bundle=prepared();health=inspect_http()
    load('verify_active_manage',TARGET/'deploy/manage.py').health()
    with pay_deploy().connection() as c:
        c.execute('SET TRANSACTION READ ONLY');meta=invariants(c,NEW_FN)
        sync_meta,_=function_meta(c,'public.archive_sync_config(text,jsonb)');need(sync_meta['definition_sha256']==SYNC_NEW_SHA,'active_sync_migration_changed')
        need(c.execute('SELECT count(*) FROM public.archive_config_sets WHERE config_hash=%s',(AFTER,)).fetchone()[0]==1,'deployed_archive_config_missing')
        c.rollback()
    return {'status':'VERIFIED','archive_release':str(TARGET),'payment_release':str(PAY),'archive_bundle':bundle.hash,
            'archive_service_sha256':sha(TARGET/'backend/archive_backend/service.py'),'apply_effects':meta,'archive_sync_config':sync_meta,
            'health':health,'payment_catalog_hash':CATALOG,'enabled_cash_products':44,'enabled_commerce_products':119,
            'committed_test_orders':0,'gateway_requests':0,'real_account_commands':0,'game_validation':False}

if __name__=='__main__':
    need(os.geteuid()==0,'root_required');os.umask(0o022);sys.dont_write_bytecode=True
    with open('/var/lock/goufayu-commerce-points-20261016.lock','w') as guard:
        fcntl.flock(guard,fcntl.LOCK_EX|fcntl.LOCK_NB)
        action=sys.argv[1];need(action in {'backup','prepare','validate','activate','verify'},'unsupported_action')
        result=globals()[action]();save(STAGE/(action+'_result.json'),result)
        print(json.dumps(result,ensure_ascii=False))
