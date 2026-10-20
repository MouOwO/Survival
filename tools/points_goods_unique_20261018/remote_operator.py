"""Explicit archive-only release phases. Nothing runs on import or without MODE."""
from pathlib import Path, PurePosixPath
import contextlib
import copy
import hashlib
import importlib.util
import io
import json
import os
import secrets
import shutil
import subprocess
import sys
import tarfile
import time
import urllib.request

sys.dont_write_bytecode = True

STAGE = Path(STAGE)
P = json.loads((STAGE / 'plan.json').read_bytes())
OLD = Path('/opt/goufayu/releases') / P['archive_baseline']
NEW = OLD.parent / P['archive_release']
PAY = Path('/opt/goufayu/payments') / P['payment_release']
SYNC = 'public.archive_sync_config(text,jsonb)'


def need(value, reason):
    if not value:
        raise RuntimeError(reason)


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def canonical(value):
    return json.dumps(value,ensure_ascii=False,sort_keys=True,separators=(',',':'),allow_nan=False).encode()


def save(name,value):
    target=STAGE/(name+'.json')
    target.write_bytes(canonical(value));target.chmod(0o600)
    return value


def safe(root,name):
    relative=PurePosixPath(name)
    need(not relative.is_absolute() and '..' not in relative.parts and '\\' not in name and ':' not in name
        and relative.as_posix()==name and bool(relative.parts),'unsafe_release_path')
    current=root
    for part in relative.parts:
        current=current/part
        need(not current.is_symlink(),'release_file_symlink_refused')
    return current


def manifest(root):
    value=json.loads((root/'release_manifest.json').read_bytes())
    for name,digest in value['files'].items():
        need(sha(safe(root,name))==digest,'release_file_digest_changed:'+name)
    return value


def pointers(new=False):
    need(Path('/opt/goufayu/releases/current').resolve(strict=True)==(NEW if new else OLD),'archive_pointer_changed')
    need(Path('/opt/goufayu/payments/current').resolve(strict=True)==PAY,'payment_pointer_changed')
    need(sha(PAY/'manifest.json')==P['payment_manifest_sha256'],'payment_manifest_changed')


def payment_deploy():
    sys.path.insert(0,str(PAY))
    spec=importlib.util.spec_from_file_location('points_payment_backup',PAY/'deploy.py')
    module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
    return module


def config_rows(conn):
    return {key:hashlib.sha256(canonical(value)).hexdigest() for key,value in conn.execute('SELECT config_hash,config FROM public.archive_config_sets')}


def database_pins(conn,new=False):
    need(conn.execute('SELECT current_database()').fetchone()[0]=='goufayu_test','database_scope_changed')
    need(conn.execute('SELECT catalog_hash FROM payments.catalog_state WHERE singleton').fetchone()[0]==P['payment_catalog_hash'],'payment_catalog_changed')
    definition=conn.execute('SELECT pg_get_functiondef(%s::regprocedure)',(SYNC,)).fetchone()[0]
    need(hashlib.sha256(definition.encode()).hexdigest()==P['new_sync_sha256' if new else 'old_sync_sha256'],'archive_sync_changed')


def baseline():
    pointers()
    need(sha(OLD/'release_manifest.json')==P['archive_manifest_sha256'],'archive_manifest_changed')
    value=manifest(OLD)
    need(json.loads((OLD/'addon/server/bundles/current.json').read_bytes())['hash']==P['parent_bundle'],'parent_bundle_changed')
    with payment_deploy().connection() as conn:
        conn.execute('SET TRANSACTION READ ONLY');database_pins(conn);conn.rollback()
    return value


def backup():
    baseline()
    directory=Path('/var/backups/goufayu-points-unique')/P['bundle']
    need(not directory.exists() and not directory.is_symlink(),'backup_directory_exists')
    directory.mkdir(mode=0o700,parents=True)
    captured=io.StringIO()
    with contextlib.redirect_stdout(captured):
        payment_deploy().backup()
    details=json.loads(captured.getvalue().splitlines()[-1])
    dump=Path(details['local_backup'])
    need(dump.is_file() and dump.stat().st_size>0,'database_backup_missing')
    need(dump.with_suffix('.sha256').read_text().strip()==sha(dump),'database_backup_digest_changed')
    sources=directory/'archive_sources.tar.gz'
    with tarfile.open(sources,'w:gz') as stream:
        stream.add(OLD/'release_manifest.json',arcname='release_manifest.json',recursive=False)
        for name in manifest(OLD)['files']:
            stream.add(safe(OLD,name),arcname=name,recursive=False)
    sources.chmod(0o600)
    value=dict(status='BACKED_UP_NOT_DEPLOYED',archive_release=OLD.name,payment_release=PAY.name,
        directory=str(directory),database_backup=str(dump),database_sha256=sha(dump),source_backup=str(sources),source_sha256=sha(sources),
        database_writes=0,player_updates=0,orders_created=0,gateway_requests=0)
    (directory/'backup.json').write_bytes(canonical(value))
    return save('backup',value)


def backup_verified():
    value=json.loads((STAGE/'backup.json').read_bytes())
    need(sha(value['database_backup'])==value['database_sha256'],'database_backup_changed')
    need(sha(value['source_backup'])==value['source_sha256'],'source_backup_changed')


def payload_verified():
    need(P['kind']=='unique_points_archive_only' and P['status']=='SEALED_NOT_DEPLOYED','release_plan_invalid')
    need(P['no_inventory_migration'] and P['no_player_updates'] and P['no_payment_changes'],'release_scope_changed')
    need(P['archive_release']=='20261018-points-unique-v1','release_name_changed')
    parent=json.loads((OLD/'addon/server/bundles'/P['parent_bundle']/'bundle.json').read_bytes())
    prefix='addon/server/bundles/'+P['bundle']+'/'
    approved={
        'backend/archive_backend/service.py','backend/archive_backend/unique_points.py',
        'addon/server/bundles/current.json','addon/scripts/vscripts/config/generated/archive_http_bundle.lua',
        'addon/data/csv/商城兑换系统/commerce_products.csv','addon/data/csv/抽奖系统/lottery_item_definitions.csv',
        prefix+'bundle.json',*(prefix+name for name in parent['sources']),
    }
    actual={path.relative_to(STAGE/'archive').as_posix() for path in (STAGE/'archive').rglob('*') if path.is_file()}
    need(set(P['archive_files'])==approved and actual==approved,'payload_file_whitelist_mismatch')
    need(not any(path.is_symlink() for path in (STAGE/'archive').rglob('*')),'payload_symlink_refused')
    for name,digest in P['archive_files'].items():
        need(sha(safe(STAGE/'archive',name))==digest,'payload_file_changed:'+name)
    need(sha(STAGE/'configuration.json')==P['configuration_sha256'],'configuration_payload_changed')
    need(sha(STAGE/'archive_sync_before.sql')==P['old_sync_sha256'],'baseline_sql_changed')
    need(sha(STAGE/'archive_sync_candidate.sql')==P['new_sync_sha256'],'candidate_sql_changed')


def candidate_scope():
    value=manifest(NEW)
    old=manifest(OLD)
    need(value['files']=={**old['files'],**P['archive_files']},'candidate_manifest_scope_changed')
    need(value['release']==P['archive_release'] and value['archive_bundle']==P['bundle'],'candidate_manifest_metadata_changed')
    need(sha(NEW/'addon/server/bundles'/P['bundle']/'bundle.json')==P['bundle'],'candidate_bundle_changed')
    need(json.loads((NEW/'addon/server/bundles/current.json').read_bytes())['hash']==P['bundle'],'candidate_pointer_changed')
    sys.path.insert(0,str(NEW/'backend'))
    from archive_backend.bundle import Bundle
    bundle=Bundle(NEW/'addon/server/bundles'/P['bundle'])
    need(bundle.hash==P['bundle'],'candidate_bundle_invalid')
    for name in ('service.py','unique_points.py'):
        compile((NEW/'backend/archive_backend'/name).read_text('utf-8'),name,'exec')
    return bundle


def prepare():
    original=baseline();backup_verified();payload_verified()
    need(not NEW.exists() and not NEW.is_symlink(),'candidate_release_exists')
    NEW.mkdir(mode=0o755)
    for name in original['files']:
        source=safe(OLD,name);target=safe(NEW,name)
        target.parent.mkdir(parents=True,exist_ok=True)
        shutil.copyfile(source,target);target.chmod(source.stat().st_mode&0o777)
    need((OLD/'.venv').exists(),'archive_venv_missing')
    (NEW/'.venv').symlink_to(OLD/'.venv',target_is_directory=True)
    for name in P['archive_files']:
        target=safe(NEW,name);target.parent.mkdir(parents=True,exist_ok=True)
        shutil.copyfile(safe(STAGE/'archive',name),target);target.chmod(0o644)
    value=copy.deepcopy(original)
    value['files'].update(P['archive_files']);value.update(release=P['archive_release'],archive_bundle=P['bundle'])
    (NEW/'release_manifest.json').write_text(json.dumps(value,ensure_ascii=False,indent=2)+'\n')
    candidate_scope();pointers()
    return save('prepared',dict(status='PREPARED_NOT_ACTIVATED',archive_release=NEW.name,bundle=P['bundle'],payment_unchanged=True,database_writes=0))


def table_state(conn):
    from psycopg import sql
    names=conn.execute("SELECT schemaname,tablename FROM pg_tables WHERE schemaname IN ('public','payments') ORDER BY 1,2").fetchall()
    return {schema+'.'+name:conn.execute(sql.SQL("SELECT count(*),md5(coalesce(string_agg(to_jsonb(t)::text,chr(10) ORDER BY to_jsonb(t)::text),'')) FROM {}.{} t").format(sql.Identifier(schema),sql.Identifier(name))).fetchone() for schema,name in names}


def admit(publish=False):
    from psycopg.types.json import Jsonb
    cfg=json.loads((STAGE/'configuration.json').read_bytes())
    with payment_deploy().connection() as conn:
        conn.execute('SET TRANSACTION ISOLATION LEVEL REPEATABLE READ')
        conn.execute("SET LOCAL lock_timeout='5s'");conn.execute("SET LOCAL statement_timeout='90s'")
        conn.execute('SET ROLE goufayu_owner')
        conn.execute('LOCK TABLE public.archive_config_sets IN SHARE ROW EXCLUSIVE MODE')
        database_pins(conn);before=table_state(conn);configs=config_rows(conn)
        digest=conn.execute("SELECT encode(sha256(convert_to(%s::jsonb::text,'UTF8')),'hex')",(Jsonb(cfg),)).fetchone()[0]
        need(digest==P['configuration_jsonb_sha256'],'configuration_postgres_digest_changed')
        conn.execute((STAGE/'archive_sync_candidate.sql').read_text('utf-8'))
        database_pins(conn,new=True)
        need(conn.execute('SELECT public.archive_sync_config(%s,%s)',(P['bundle'],Jsonb(cfg))).fetchone()[0]['ok'],'configuration_admission_failed')
        need(config_rows(conn)=={**configs,P['bundle']:P['configuration_sha256']},'existing_configuration_changed')
        after=table_state(conn)
        changed=[name for name in before if before[name]!=after[name]]
        need(set(changed)<={'public.archive_config_sets'},'player_or_payment_data_changed')
        if publish:conn.commit()
        else:conn.rollback()
    return dict(published=publish,changed_tables=changed,player_updates=0,payment_updates=0,orders_created=0)


def validate():
    baseline();backup_verified();payload_verified();candidate_scope()
    result=admit(False)
    baseline()
    return save('validated',dict(status='VALIDATED_NOT_ACTIVATED',bundle=P['bundle'],database=result,payment_unchanged=True))


def health():
    deadline=time.monotonic()+10
    while time.monotonic()<deadline:
        ready=True
        for port in (8765,8766):
            remaining=deadline-time.monotonic()
            if remaining<=0:
                ready=False;break
            try:
                with urllib.request.urlopen('http://127.0.0.1:'+str(port)+'/health',timeout=min(1,remaining)) as response:
                    ready=ready and response.status==200 and json.load(response).get('ok') is True
            except Exception:
                ready=False
        if ready:return
        remaining=deadline-time.monotonic()
        if remaining>0:time.sleep(min(.5,remaining))
    raise RuntimeError('service_unhealthy_after_startup_poll')


def switch(target):
    need(target in (OLD,NEW),'unsafe_release_switch')
    pointer=OLD.parent/'current'
    temporary=OLD.parent/('current.points-unique.'+secrets.token_hex(6))
    temporary.symlink_to(target,target_is_directory=True);os.replace(temporary,pointer)


def systemctl(action):
    result=subprocess.run(['systemctl',action,'goufayu-api.service'],capture_output=True,timeout=45)
    need(result.returncode==0,'archive_service_'+action+'_failed')


def activate():
    baseline();backup_verified();payload_verified();candidate_scope()
    need(json.loads((STAGE/'validated.json').read_bytes())['bundle']==P['bundle'],'validated_candidate_changed')
    systemctl('stop')
    try:
        pointers();result=admit(True);switch(NEW);systemctl('start');pointers(True);health()
    except Exception:
        # The old immutable release remains intact. The additive config admission
        # may remain recorded, but no player/order rows are modified or removed.
        if Path('/opt/goufayu/releases/current').resolve()==NEW:switch(OLD)
        systemctl('start')
        save('rollback',dict(status='OLD_ARCHIVE_RESTORED',player_updates=0,payment_unchanged=True))
        raise
    return save('activated',dict(status='ACTIVATED',bundle=P['bundle'],archive_release=NEW.name,database=result,payment_unchanged=True,player_updates=0))


def verify():
    pointers(True);payload_verified();candidate_scope();health()
    with payment_deploy().connection() as conn:
        conn.execute('SET TRANSACTION READ ONLY');database_pins(conn,new=True)
        rows=config_rows(conn)
        need(rows.get(P['bundle'])==P['configuration_sha256'],'registered_configuration_changed')
        need(all(rows.get(key)==digest for key,digest in P['old_config_rows'].items()),'old_configuration_changed')
        conn.rollback()
    return save('verified',dict(status='DEPLOYMENT_VERIFIED',archive_release=NEW.name,bundle=P['bundle'],payment_release=PAY.name,payment_unchanged=True,player_updates=0,orders_created=0,gateway_requests=0))


payload_verified()
need(MODE in {'backup','prepare','validate','activate','verify'},'unsupported_operator_mode')
print(json.dumps(globals()[MODE](),ensure_ascii=False))
