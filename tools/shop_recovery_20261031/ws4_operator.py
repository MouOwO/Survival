"""Sealed WS4-only additive redemption operator; no real-data test clones."""
from pathlib import Path
import ast, contextlib, hashlib, importlib.util, json, os, re, secrets, shutil, subprocess, time

STAGE = Path(STAGE_PATH)
PLAN = PLAN_DATA
OLD = Path('/opt/goufayu-ws4/releases/20261031-catalog-d573588b64d2')
NEW = OLD.parent / PLAN['release']
UNIT = Path('/etc/systemd/system/goufayu-ws4.service')
ENV = Path('/etc/goufayu-ws4/api.env')
HASH = 'd573588b64d2ea6d1431c856d52e0515b5ed471cfdf6af4456ff618d0f568488'
sha = lambda value: hashlib.sha256(value).hexdigest()


def need(value, code):
    if not value: raise RuntimeError(code)


def command(argv, *, data=None, env=None):
    result = subprocess.run(argv, input=data, capture_output=True, env=env, timeout=120)
    need(result.returncode == 0, 'ws4_subprocess_failed')
    return result.stdout


def save(name, value):
    path = STAGE / (name + '.json'); need(not path.exists(), 'new_receipt_required')
    with path.open('x') as stream: json.dump(value, stream, sort_keys=True)
    path.chmod(0o600); return value


def connect(database='goufayu_ws4', *, autocommit=False):
    need(database == 'goufayu_ws4' or re.fullmatch(r'goufayu_ws4_redeem_[a-f0-9]{12}', database), 'database_scope_invalid')
    import psycopg
    return psycopg.connect(host='127.0.0.1', port=15432, dbname=database, user='postgres',
        password=Path('/etc/goufayu-ws4/admin-password').read_text().strip(), autocommit=autocommit)


def services():
    return {name: command(['systemctl','show',name,'--property=MainPID','--value']).decode().strip()
            for name in PLAN['retained_services']}


def state(conn):
    query = "SELECT p.oid::regprocedure::text,pg_get_functiondef(p.oid),coalesce(array_to_string(ARRAY(SELECT a::text FROM unnest(p.proacl) a ORDER BY a::text),'|'),'') FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND NOT EXISTS(SELECT 1 FROM pg_depend d WHERE d.classid='pg_proc'::regclass AND d.objid=p.oid AND d.deptype='e')"
    return {'functions': {name: [sha(body.encode()), acl] for name, body, acl in conn.execute(query)},
        'ledger': dict(conn.execute('SELECT migration_id,sha256 FROM public._goufayu_migrations')),
        'configs': dict(conn.execute("SELECT config_hash,encode(sha256(convert_to(config::text,'UTF8')),'hex') FROM public.archive_config_sets"))}


def rows(conn):
    from psycopg import sql
    result = {}
    for schema, table in conn.execute("SELECT schemaname,tablename FROM pg_tables WHERE schemaname IN ('public','payments') ORDER BY 1,2").fetchall():
        result[schema+'.'+table] = list(conn.execute(sql.SQL("SELECT count(*),md5(coalesce(string_agg(to_jsonb(t)::text,chr(10) ORDER BY to_jsonb(t)::text),'')) FROM {}.{} t").format(sql.Identifier(schema),sql.Identifier(table))).fetchone())
    return result


def pending(conn):
    need(conn.execute('SELECT count(*) FROM public.archive_operations WHERE NOT done').fetchone()[0] == 0, 'pending_archive_operations')
    need(conn.execute("SELECT count(*) FROM payments.orders WHERE state IN ('created','pending','paid_review')").fetchone()[0] == 0, 'pending_payment_orders')


def verify_parent():
    need(sha(UNIT.read_bytes()) == PLAN['unit_sha256'] and sha(ENV.read_bytes()) == PLAN['env_sha256'], 'launch_baseline_changed')
    need(sha((OLD/'release_manifest.json').read_bytes()) == PLAN['parent_manifest_sha256'], 'parent_manifest_changed')
    need(services() == PLAN['retained_services'], 'protected_service_changed')
    for name, digest in PLAN['source_files'].items():
        path = OLD/name
        need(not path.is_symlink() and path.resolve().is_relative_to(OLD) and sha(path.read_bytes()) == digest, 'parent_source_changed')


def prepare():
    verify_parent()
    with connect() as conn:
        conn.execute('SET TRANSACTION READ ONLY'); need(state(conn) == PLAN['database_state'], 'database_baseline_changed')
    need(not NEW.exists(), 'new_immutable_release_required'); NEW.mkdir(mode=0o755)
    info=OLD.stat();os.chmod(NEW,info.st_mode&0o777);os.chown(NEW,info.st_uid,info.st_gid)
    directories={NEW}
    def ensure_directory(relative):
        current=NEW
        for part in relative.parts:
            current=current/part
            if current in directories:continue
            original=OLD/current.relative_to(NEW);info=original.stat()
            current.mkdir();os.chmod(current,info.st_mode&0o777);os.chown(current,info.st_uid,info.st_gid);directories.add(current)
    for name, digest in PLAN['source_files'].items():
        source = OLD/name; target = NEW/name
        ensure_directory(Path(name).parent)
        shutil.copy2(source, target)
        info=source.stat(); os.chown(target,info.st_uid,info.st_gid)
    for name, digest in PLAN['overlay'].items():
        source=STAGE/'overlay'/name; target=NEW/name
        need(sha(source.read_bytes()) == digest, 'sealed_overlay_changed')
        ensure_directory(Path(name).parent);shutil.copyfile(source,target)
        reference=OLD/name if (OLD/name).exists() else OLD/'backend/archive_backend/service.py'
        info=reference.stat();os.chmod(target,info.st_mode&0o777);os.chown(target,info.st_uid,info.st_gid)
    (NEW/'.venv').symlink_to('/opt/goufayu-ws4/.venv',target_is_directory=True)
    manifest=json.loads((OLD/'release_manifest.json').read_bytes())
    manifest['files']={**PLAN['source_files'],**PLAN['overlay']}
    manifest.update(release=NEW.name,previous_release=OLD.name,redemption_codes=True)
    (NEW/'release_manifest.json').write_text(json.dumps(manifest,sort_keys=True,indent=2)+'\n')
    for name,digest in manifest['files'].items(): need(sha((NEW/name).read_bytes())==digest,'candidate_source_changed')
    for source,name in [(UNIT,'unit.original'),(ENV,'env.original')]:
        with (STAGE/name).open('xb') as stream: stream.write(source.read_bytes())
        (STAGE/name).chmod(0o600)
    return save('prepared',{'ok':True,'status':'PREPARED_NOT_ACTIVE','files':len(manifest['files']),'live_changed':False})


def sql_body(raw):
    text=raw.decode('utf8'); opening=re.match(r'\A(?:\s|--[^\n]*(?:\n|$))*begin\s*;',text,re.I); ending=re.search(r'\bcommit\s*;\s*\Z',text,re.I)
    need(opening and ending,'sql_transaction_wrapper_invalid'); return text[opening.end():ending.start()]


def migrate(conn, *, register):
    from psycopg.types.json import Jsonb
    before=rows(conn); previous=state(conn)
    need(previous==PLAN['database_state'],'database_baseline_changed')
    conn.execute('SELECT pg_advisory_xact_lock(719232014021)')
    conn.execute(sql_body((STAGE/'migration.sql').read_bytes()))
    conn.execute('INSERT INTO public._goufayu_migrations(migration_id,sha256) VALUES(%s,%s)',('ws4/redemption_20261031',PLAN['files']['migration.sql']))
    if register:
        for code in json.loads((STAGE/'codes.json').read_bytes())['codes']:
            conn.execute('INSERT INTO public.redemption_codes(code_id,code_hash,label,rewards,enabled,starts_at,expires_at,max_redemptions) VALUES(%s,%s,%s,%s,%s,coalesce(%s::timestamptz,clock_timestamp()),%s::timestamptz,%s)',
                (code['code_id'],code['code_hash'],code['label'],Jsonb(code['rewards']),code['enabled'],code['starts_at'],code['expires_at'],code['max_redemptions']))
    after=rows(conn); current=state(conn)
    need(all(after.get(name)==value for name,value in before.items() if name!='public._goufayu_migrations'),'original_business_rows_changed')
    need(all(current['functions'].get(name)==value for name,value in previous['functions'].items()),'existing_function_or_acl_changed')
    need(set(current['functions'])-set(previous['functions'])=={'redemption_prepare(text,text,text,text,text)','redemption_commit(text,text,bigint,jsonb,jsonb,jsonb,jsonb)'},'unexpected_new_function')
    need(current['configs']==previous['configs'],'archive_configuration_changed')
    return {'old_business_tables_unchanged':len(before)-1,'existing_functions_and_acls_unchanged':True,
        'codes_registered':PLAN['registry_count'] if register else 0,'schema_state':current}


def dump(name, *, schema_only=False):
    target=STAGE/(name+'.dump'); need(not target.exists(),'new_backup_required')
    argv=['podman','exec','-i','--env','PGPASSWORD','goufayu-ws4-db','pg_dump','-h','127.0.0.1','-U','postgres','-d','goufayu_ws4','-Fc']
    if schema_only: argv.append('--schema-only')
    raw=command(argv,env={**os.environ,'PGPASSWORD':Path('/etc/goufayu-ws4/admin-password').read_text().strip()})
    need(raw.startswith(b'PGDMP') and len(raw)<128*1024*1024,'backup_format_invalid')
    with target.open('xb') as stream: stream.write(raw)
    target.chmod(0o600); return {'path':str(target),'bytes':len(raw),'sha256':sha(raw),'at':time.time()}


def clone():
    from psycopg import sql
    from psycopg.types.json import Jsonb
    verify_parent(); need((STAGE/'prepared.json').exists(),'preparation_required')
    backup=dump('schema_'+secrets.token_hex(6),schema_only=True); name='goufayu_ws4_redeem_'+secrets.token_hex(6)
    with connect(autocommit=True) as admin:
        admin.execute(sql.SQL('CREATE DATABASE {} OWNER goufayu_owner TEMPLATE template0').format(sql.Identifier(name)))
        admin.execute(sql.SQL('REVOKE ALL ON DATABASE {} FROM PUBLIC').format(sql.Identifier(name)))
        admin.execute(sql.SQL('GRANT CONNECT ON DATABASE {} TO goufayu_app,goufayu_owner').format(sql.Identifier(name)))
    with connect(name) as empty:
        need(empty.execute("SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname NOT LIKE 'pg_%' AND n.nspname<>'information_schema'").fetchone()[0]==0,'clone_not_empty')
    container='/tmp/'+name+'.dump'; command(['podman','exec','goufayu-ws4-db','test','!','-e',container]);command(['podman','cp',backup['path'],'goufayu-ws4-db:'+container])
    toc=command(['podman','exec','goufayu-ws4-db','pg_restore','--list',container])
    need(b'TABLE DATA' not in toc and b'SEQUENCE SET' not in toc,'schema_dump_contains_data')
    command(['podman','exec','--env','PGPASSWORD','goufayu-ws4-db','pg_restore','-h','127.0.0.1','-U','postgres','-d',name,'--exit-on-error','--single-transaction',container],env={**os.environ,'PGPASSWORD':Path('/etc/goufayu-ws4/admin-password').read_text().strip()})
    with connect() as live:
        live.execute('SET TRANSACTION READ ONLY'); configs=live.execute('SELECT config_hash,config FROM public.archive_config_sets').fetchall()
    with connect(name) as conn:
        need(all(value[0]==0 for value in rows(conn).values()),'schema_clone_contains_live_rows')
        for key,value in configs: conn.execute('INSERT INTO public.archive_config_sets(config_hash,config) VALUES(%s,%s)',(key,Jsonb(value)))
        for key,value in PLAN['database_state']['ledger'].items():conn.execute('INSERT INTO public._goufayu_migrations(migration_id,sha256) VALUES(%s,%s)',(key,value))
        applied=migrate(conn,register=False)
    spec=importlib.util.spec_from_file_location('ws4_redemption_database_checks',STAGE/'database_checks.py'); checks=importlib.util.module_from_spec(spec);spec.loader.exec_module(checks)
    registry=json.loads((STAGE/'codes.json').read_bytes())
    synthetic_spec={'codes':[{'rewards':registry['codes'][0]['rewards']}]}
    result=checks.run(lambda:connect(name),NEW,synthetic_spec)
    applied.pop('schema_state')
    return save('validated_clone',{'ok':True,'clone':name,'checks':result,**applied,
        'production_player_data_copied':False,'real_code_definitions_copied_to_clone':False,'schema_dump':backup})


def control(action):
    need(action in ('stop','start'),'invalid_service_action');command(['systemctl',action,'goufayu-ws4.service'])


def launch_bytes(root):
    need(root in (OLD,NEW),'launch_scope_invalid')
    unit,count=re.subn(rb'(?m)^(\s*WorkingDirectory=)[^\r\n]+',lambda m:m[1]+str(root/'backend').encode(),(STAGE/'unit.original').read_bytes());need(count==1,'workdir_anchor_invalid')
    env,count=re.subn(rb'(?m)^(SURVIVAL_ADDON_ROOT=)[^\r\n]+',lambda m:m[1]+json.dumps(str(root/'addon')).encode(),(STAGE/'env.original').read_bytes());need(count==1,'addon_anchor_invalid')
    return unit,env


def switch(root):
    for target,raw in zip((UNIT,ENV),launch_bytes(root)):
        info=target.stat();temporary=target.with_name(target.name+'.redeem-'+secrets.token_hex(6))
        with temporary.open('xb') as stream:stream.write(raw);stream.flush();os.fsync(stream.fileno())
        os.chmod(temporary,info.st_mode&0o777);os.chown(temporary,info.st_uid,info.st_gid);os.replace(temporary,target)
    command(['systemctl','daemon-reload'])


def health():
    import urllib.request
    pid=command(['systemctl','show','goufayu-ws4-web.service','--property=MainPID','--value']).decode().strip()
    env=dict(row.split(b'=',1) for row in Path('/proc/'+pid+'/environ').read_bytes().split(b'\0') if b'=' in row)
    token=env[b'PLAYER_WEB_AUTH_UPSTREAM_BEARER'].decode('ascii');pins=json.loads(Path('/etc/goufayu-ws4/pins.json').read_bytes())
    need(pins.get('workshop_id')=='3824360109' and sha(token.encode()) in pins.get('sha256',[]),'approved_upstream_pin_required')
    for _ in range(20):
        try:
            req=urllib.request.Request('http://127.0.0.1:18765/v1/archive/config',data=b'{}',headers={'Authorization':'Bearer '+token,'Content-Type':'application/json'})
            with urllib.request.urlopen(req,timeout=3) as response:value=json.load(response)
            if value.get('ok') and value.get('config_hash')==HASH:return
        except Exception:pass
        time.sleep(.5)
    raise RuntimeError('ws4_expected_bundle_unhealthy')


def quiesce():
    verify_parent();need((STAGE/'validated_clone.json').is_file(),'clone_validation_required')
    with connect() as conn:conn.execute('SET TRANSACTION READ ONLY');pending(conn);need(state(conn)==PLAN['database_state'],'database_baseline_changed')
    control('stop')
    try:
        with connect() as conn:conn.execute('SET TRANSACTION READ ONLY');pending(conn)
        return save('final_backup',dump('final_backup'))
    except Exception:control('start');health();raise


def activate():
    verify_parent();need((STAGE/'validated_clone.json').is_file(),'clone_validation_required')
    backup=json.loads((STAGE/'final_backup.json').read_bytes());ack=json.loads((STAGE/'offsite_ack.json').read_bytes())
    need(ack['encrypted_verified'] and ack['sha256']==backup['sha256'] and sha(Path(backup['path']).read_bytes())==backup['sha256'] and time.time()-backup['at']<900,'verified_fresh_encrypted_backup_required')
    need(command(['systemctl','show','goufayu-ws4.service','--property=MainPID','--value']).strip()==b'0','api_must_be_quiesced')
    committed=False
    try:
        with connect() as conn:
            conn.execute('SET TRANSACTION ISOLATION LEVEL REPEATABLE READ');pending(conn);result=migrate(conn,register=True)
        committed=True;switch(NEW);control('start');health()
        need(services()==PLAN['retained_services'],'protected_service_changed')
        result.update(ok=True,status='WS4_REDEMPTION_ACTIVATED',release=NEW.name,payment_untouched=True,bundle=HASH)
        return save('activated',result)
    except Exception:
        control('stop');switch(OLD);control('start');health()
        save('activation_failure',{'database_migrated':committed,'old_api_resumed':True,'database_restored':False})
        raise


def resume():
    need((STAGE/'prepared.json').exists() and ((STAGE/'final_backup.json').exists() or (STAGE/'activation_failure.json').exists()),'owned_maintenance_receipt_required')
    control('stop');switch(OLD);control('start');health()
    return {'status':'OLD_WS4_API_RESUMED','database_restored':False}


def verify():
    need((STAGE/'activated.json').exists(),'activation_required')
    need((UNIT.read_bytes(),ENV.read_bytes())==launch_bytes(NEW),'active_launch_changed');health()
    need(services()==PLAN['retained_services'],'protected_service_changed')
    registry=json.loads((STAGE/'codes.json').read_bytes())['codes'];expected={row['code_id']:row for row in registry}
    with connect() as conn:
        conn.execute('SET TRANSACTION READ ONLY')
        actual=conn.execute('SELECT code_id,code_hash,label,rewards,enabled,max_redemptions FROM public.redemption_codes').fetchall()
        need(len(actual)==len(expected),'code_count_changed')
        for identifier,digest,label,rewards,enabled,maximum in actual:
            row=expected.get(identifier);need(row and [digest,label,rewards,enabled,maximum]==[row['code_hash'],row['label'],row['rewards'],row['enabled'],row['max_redemptions']],'registered_definition_changed')
        need(state(conn)==json.loads((STAGE/'activated.json').read_bytes())['schema_state'],'active_schema_changed')
    return save('verified',{'ok':True,'status':'WS4_REDEMPTION_VERIFIED','codes':len(actual),'bundle':HASH,
        'payment_untouched':True,'real_player_redemption':False,'synthetic_schema_validation':True})


def run(action):
    import fcntl
    need(STAGE.parent==Path('/root/goufayu_upload') and not STAGE.is_symlink(),'stage_scope_invalid')
    need(re.fullmatch(r'20261031-redemption-ws4-[a-f0-9]{12}',PLAN['release']) and NEW.parent==OLD.parent,'release_scope_invalid')
    for name,digest in PLAN['files'].items():
        path=STAGE/name
        need(not Path(name).is_absolute() and '..' not in Path(name).parts and not path.is_symlink()
            and path.resolve().is_relative_to(STAGE) and sha(path.read_bytes())==digest,'sealed_input_changed')
    with Path('/var/lock/goufayu_ws4_redemption.lock').open('a') as lock:
        fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
        return {'prepare':prepare,'clone':clone,'quiesce':quiesce,'activate':activate,'resume':resume,'verify':verify}[action]()
