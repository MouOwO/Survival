"""Pinned test-host operator; prepare/validate never commit or activate.

This script is invoked with MODE/P or MODE/STAGE set by deploy.py. It never
prints credentials, player accounts, profile data, DSNs or subprocess stderr.
"""
from pathlib import Path, PurePosixPath
import copy
import hashlib
import json
import os
import re
import secrets
import shutil
import subprocess
import sys
import time
import urllib.request

sha = lambda raw: hashlib.sha256(raw).hexdigest()
canonical = lambda value: json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(',', ':'), allow_nan=False).encode()
if STAGE is not None:
    STAGE = Path(STAGE)
    P = json.loads((STAGE / 'plan.json').read_bytes())
OLD = Path('/opt/goufayu/releases') / P['archive_release']
CURRENT = OLD.parent / 'current'
PAY = Path('/opt/goufayu/payments') / P['payment_release']
sys.path.insert(0, str(PAY))
from deploy import connection, backup
from psycopg.types.json import Jsonb


def need(condition, code):
    if not condition: raise RuntimeError(code)


def safe(root, name):
    value = PurePosixPath(name)
    need(not value.is_absolute() and '..' not in value.parts and ':' not in name and '\\' not in name
         and value.as_posix() == name, 'unsafe_release_path')
    result = root / name
    need(all(not root.joinpath(*value.parts[:index]).is_symlink() for index in range(1, len(value.parts)+1)), 'release_symlink')
    return result


def save(name, value):
    target = STAGE / (name + '.json'); need(not target.is_symlink(), 'report_symlink')
    target.write_bytes(canonical(value)); target.chmod(0o600)
    return value


def payment_pin():
    need(Path('/opt/goufayu/payments/current').resolve() == PAY, 'payment_pointer_drift')
    need(sha((PAY / 'manifest.json').read_bytes()) == P['payment_manifest_sha256'], 'payment_manifest_drift')
    pid = subprocess.check_output(['systemctl','show','--property=MainPID','--value','goufayu-payment.service'], text=True).strip()
    need(pid == P['payment_pid'], 'payment_process_changed')


def manifest(root):
    result = json.loads((root / 'release_manifest.json').read_bytes())
    for name, digest in result['files'].items(): need(sha(safe(root,name).read_bytes()) == digest, 'release_file_drift')
    return result


def db_state(conn):
    need(conn.info.dbname == 'goufayu_test', 'database_scope_changed')
    functions = {}
    for signature, definition in conn.execute("SELECT p.oid::regprocedure::text,pg_get_functiondef(p.oid) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' ORDER BY 1"):
        signature = signature if signature.startswith('public.') else 'public.' + signature
        functions[signature] = dict(sha256=sha(definition.encode()), definition=definition)
    constraints = {name: definition for name,definition in conn.execute("SELECT conname,pg_get_constraintdef(oid) FROM pg_constraint WHERE conrelid='public.player_archive_state'::regclass ORDER BY conname")}
    ledger = dict(conn.execute('SELECT migration_id,sha256 FROM public._goufayu_migrations ORDER BY migration_id'))
    configs = dict(conn.execute("SELECT config_hash,encode(sha256(convert_to(config::text,'UTF8')),'hex') FROM public.archive_config_sets ORDER BY config_hash"))
    return dict(functions=functions, constraints=constraints, ledger=ledger, configs=configs)


def baseline(conn):
    need(CURRENT.resolve() == OLD, 'archive_pointer_drift'); payment_pin()
    need(sha((OLD / 'release_manifest.json').read_bytes()) == P['archive_manifest_sha256'], 'parent_manifest_drift')
    state = db_state(conn)
    if P.get('audit'):
        need(state == {key:P['audit'][key] for key in state}, 'pinned_database_schema_drift')
    return state


def audit():
    with connection() as conn:
        conn.execute('SET TRANSACTION ISOLATION LEVEL REPEATABLE READ, READ ONLY')
        result = baseline(conn); conn.rollback()
    return dict(ok=True, phase='AUDITED_READ_ONLY', **result)


def bundles():
    result = {}
    for key in ('bundle','rollback_bundle'):
        digest = P[key]; name = 'addon/server/bundles/' + digest + '/bundle.json'
        raw = safe(STAGE / 'overlay',name).read_bytes(); need(sha(raw) == digest, 'bundle_digest_changed')
        result[key] = json.loads(raw)
    active, rollback = result['bundle'], copy.deepcopy(result['rollback_bundle'])
    for row in rollback['configs']['archive_benefit_rewards']['rows']: row['enabled'] = True
    rollback['compatible_config_hashes'].pop(P['bundle'],None)
    need(rollback == active, 'safe_rollback_not_benefits_only')
    need(len(active['configs']['archive_benefit_rewards']['rows']) == 19, 'benefit_tier_count_changed')
    return result


def release_path(rollback=False):
    return OLD.parent / P['rollback_release' if rollback else 'new_release']


def prepare():
    with connection() as conn:
        conn.execute('SET TRANSACTION READ ONLY'); baseline(conn); conn.rollback()
    data = bundles(); old = manifest(OLD)
    for rollback in (False,True):
        target = release_path(rollback); need(not target.exists(), 'candidate_release_exists')
        target.mkdir(mode=0o755)
        for name in old['files']:
            destination=safe(target,name); destination.parent.mkdir(parents=True,exist_ok=True)
            source=safe(OLD,name);shutil.copyfile(source,destination);destination.chmod(source.stat().st_mode & 0o777)
        for source in (OLD/'backend').rglob('*.py'):
            need(not source.is_symlink(), 'backend_symlink')
            destination=target/source.relative_to(OLD);destination.parent.mkdir(parents=True,exist_ok=True)
            shutil.copyfile(source,destination);destination.chmod(0o644)
        (target/'.venv').symlink_to(OLD/'.venv',target_is_directory=True)
        for name,digest in P['overlay'].items():
            source=safe(STAGE/'overlay',name);need(sha(source.read_bytes())==digest,'overlay_digest_changed')
            destination=safe(target,name);destination.parent.mkdir(parents=True,exist_ok=True)
            shutil.copyfile(source,destination);destination.chmod(0o644)
        pointer='addon/server/bundles/current.json'
        raw=canonical(dict(hash=P['rollback_bundle' if rollback else 'bundle'],protocol=1))
        safe(target,pointer).write_bytes(raw)
        result=copy.deepcopy(old);result['files'].update(P['overlay']);result['files'][pointer]=sha(raw)
        result.update(release=target.name,archive_bundle=P['rollback_bundle' if rollback else 'bundle'],benefits_parent=P['archive_release'],safe_stackable_rollback=rollback)
        (target/'release_manifest.json').write_bytes(canonical(result))
        manifest(target)
    return save('prepared',dict(ok=True,phase='PREPARED_NOT_ACTIVATED',release=P['new_release'],rollback_release=P['rollback_release'],payment_pid=P['payment_pid'],database_committed=False))


def sql_body(raw):
    source=raw.decode('utf-8-sig')
    start=re.match(r'\A(?:\s|--[^\n]*(?:\n|$))*begin\s*;',source,re.I)
    end=re.search(r'\bcommit\s*;\s*\Z',source,re.I)
    need(start and end and start.end()<end.start(),'migration_transaction_wrapper_invalid')
    return source[start.end():end.start()]


def rows_state(conn):
    from psycopg import sql
    tables=conn.execute("SELECT schemaname,tablename FROM pg_tables WHERE schemaname IN ('public','payments') ORDER BY 1,2").fetchall()
    return {schema+'.'+table:conn.execute(sql.SQL("SELECT count(*),md5(coalesce(string_agg(to_jsonb(t)::text,chr(10) ORDER BY to_jsonb(t)::text),'')) FROM {}.{} t").format(sql.Identifier(schema),sql.Identifier(table))).fetchone() for schema,table in tables}


def apply(conn):
    need(conn.info.dbname=='goufayu_test','database_scope_changed')
    conn.execute('SET LOCAL ROLE goufayu_owner')
    conn.execute('SELECT pg_advisory_xact_lock(719232014021)')
    conn.execute('LOCK TABLE public._goufayu_migrations,public.archive_config_sets IN SHARE ROW EXCLUSIVE MODE')
    before=db_state(conn)
    need(before['ledger']==P['audit']['ledger'],'historical_ledger_changed')
    for migration in P['migrations']:
        raw=safe(STAGE/'overlay',migration['path']).read_bytes();need(sha(raw)==migration['sha256'],'migration_digest_changed')
        need(migration['id'] not in before['ledger'],'migration_already_applied')
        conn.execute(sql_body(raw))
        conn.execute('INSERT INTO public._goufayu_migrations(migration_id,sha256) VALUES(%s,%s)',(migration['id'],migration['sha256']))
    definition=conn.execute("SELECT pg_get_functiondef('public.archive_sync_config(text,jsonb)'::regprocedure)").fetchone()[0]
    marker=' -- Reviewed monthly challenge tickets and requested fragment/cage quotas.'
    need(definition.count(marker)==1,'sync_policy_anchor_changed')
    branches=[]
    for key,data in bundles().items():
        digest=P[key];config=dict(configs=data['configs'],compatible_config_hashes=data['compatible_config_hashes'])
        config_sha=conn.execute("SELECT encode(sha256(convert_to(%s::jsonb::text,'UTF8')),'hex')",(Jsonb(config),)).fetchone()[0]
        branch=""" -- Reviewed benefits 20261021: exact immutable configuration.
 if p_hash='%s' then
  if encode(sha256(convert_to(p_config::text,'UTF8')),'hex')<>'%s' then raise exception 'archive_benefits_configuration_mismatch'; end if;
  insert into archive_config_sets(config_hash,config) values(p_hash,p_config) on conflict do nothing;
  select config into v from archive_config_sets where config_hash=p_hash;
  if v is distinct from p_config then raise exception 'archive_config_immutable'; end if;
  return jsonb_build_object('ok',true);
 end if;
"""%(digest,config_sha)
        branches.append(branch)
    updated=definition.replace(marker,''.join(branches)+marker,1)
    need(updated.replace(''.join(branches),'',1)==definition,'old_sync_policy_changed')
    conn.execute(updated)
    for key,data in bundles().items():
        config=dict(configs=data['configs'],compatible_config_hashes=data['compatible_config_hashes'])
        need(conn.execute('SELECT public.archive_sync_config(%s,%s)',(P[key],Jsonb(config))).fetchone()[0]['ok'],'configuration_registration_failed')
    after=db_state(conn)
    need(after['ledger']=={**before['ledger'],**{item['id']:item['sha256'] for item in P['migrations']}},'old_ledger_modified')
    need(all(after['configs'].get(key)==value for key,value in before['configs'].items()),'old_config_changed')
    changed={key.split('(')[0].split('.')[-1] for key in before['functions'] if before['functions'][key]!=after['functions'].get(key)}
    need(changed<={'archive_prepare','archive_online_pending','archive_fishing_daily_limit','archive_capture_online','archive_resume','archive_commit_lottery','archive_sync_config','archive_unique_points_20261019_valid'},'unrelated_sql_function_changed')
    for signature in ('public.archive_prepare(text,text,text,text,jsonb)','public.archive_online_pending(text,text)','public.archive_fishing_daily_limit(text)'):
        need('10800' in after['functions'][signature]['definition'],'reset_offset_not_05')
    need("'benefit_claim'" in after['functions']['public.archive_commit_lottery(text,text,bigint,jsonb,jsonb,text,jsonb,jsonb)']['definition'],'benefit_inventory_commit_missing')
    signature='public.archive_unique_points_20261019_valid(jsonb,jsonb)'
    def unique_rules(definition):
        match=re.search(r"rules\s+constant\s+jsonb\s*:=\s*'([^']+)'::jsonb",definition,re.I)
        need(match is not None,'unique_rules_anchor_changed')
        return json.loads(match.group(1))
    old_rules=unique_rules(before['functions'][signature]['definition'])
    expected_rules=copy.deepcopy(old_rules);expected_rules['lottery'].pop('lottery_ember_of_legacy',None)
    need(unique_rules(after['functions'][signature]['definition'])==expected_rules,'unrelated_unique_whitelist_changed')
    for name in ('verify_stackable_constraints.sql','verify_benefit_api.sql'):
        source=safe(STAGE/'overlay','validation/'+name)
        if source.is_file(): conn.execute(source.read_text(encoding='utf-8-sig'))
    probe=safe(STAGE/'overlay','validation/archive_benefits_database.sql')
    need(probe.is_file(),'real_sql_api_probe_required')
    conn.execute('SAVEPOINT benefits_synthetic_account_probe')
    conn.execute(probe.read_text(encoding='utf-8-sig').replace('__CONFIG_HASH__',P['bundle']))
    conn.execute('ROLLBACK TO SAVEPOINT benefits_synthetic_account_probe')
    return dict(functions_changed=sorted(changed),new_ledger_entries=len(P['migrations']),configuration_count=2)


def worker_checks():
    now=int(time.time());day=str((now+10800)//86400);results=[]
    for rollback in (False,True):
        root=release_path(rollback);digest=P['rollback_bundle' if rollback else 'bundle'];directory=root/'addon/server/bundles'/digest
        data=json.loads((directory/'bundle.json').read_bytes())
        defaults={row['field_id']:row['default_value'] for row in data['configs']['player_gameplay_stats']['rows']}
        profile=dict(save=dict(archive=dict(benefits=dict(version=1,days={day:dict(seconds=9000,wins=5,claimed={})},weeks={})),content_inventory={},gameplay_stats=defaults))
        command=dict(id='benefit_review_memory_20261021',kind='benefit_claim',track='daily_time',tier_id='daily_time_150',event_at=now)
        payload=dict(configs=data['configs'],profile=profile,command=command,has_pass=True,seed=1,server_time=now)
        result=subprocess.run([shutil.which('lua5.1') or shutil.which('lua'),'worker.lua'],cwd=directory,input=canonical(payload),capture_output=True,timeout=15)
        need(result.returncode==0,'memory_worker_failed')
        value=json.loads(result.stdout)
        if rollback: need(not value.get('ok'),'safe_rollback_claim_enabled')
        else:
            need(value.get('ok'),'memory_benefit_claim_failed')
            inventory=value['content_inventory']
            need(all(inventory.get(key)==count for key,count in {'lottery_ticket':4,'welfare_zongzi':4,'lottery_ember_of_legacy':3,'special_lottery_ticket':2}.items()),'monthly_150_reward_wrong')
        results.append(dict(rollback=rollback,ok=True))
    return dict(synthetic_memory_only=True,real_player_writes=0,cases=results)


def validate():
    need((STAGE/'prepared.json').is_file(),'prepare_required');bundles();manifest(release_path());manifest(release_path(True))
    worker=worker_checks()
    with connection() as conn:
        try:
            conn.execute('SET TRANSACTION ISOLATION LEVEL REPEATABLE READ')
            conn.execute("SET LOCAL lock_timeout='5s'");conn.execute("SET LOCAL statement_timeout='90s'")
            baseline(conn);before=rows_state(conn);result=apply(conn);after=rows_state(conn)
            allowed={'public._goufayu_migrations','public.archive_config_sets'}
            need(before.keys()==after.keys() and all(before[key]==after[key] for key in before if key not in allowed),'validation_changed_real_rows')
        finally: conn.rollback()
    with connection() as conn:
        conn.execute('SET TRANSACTION READ ONLY');baseline(conn);conn.rollback()
    return save('validated',dict(ok=True,phase='VALIDATED_ROLLED_BACK',rolled_back=True,worker=worker,player_writes=0,**result))


def systemctl(action):
    need(action in ('stop','start'),'service_action_invalid')
    result=subprocess.run(['systemctl',action,'goufayu-api.service'],capture_output=True,timeout=45)
    need(result.returncode==0,'archive_service_action_failed')


def switch(target):
    need(target in (OLD,release_path(),release_path(True)),'pointer_target_invalid')
    need(CURRENT.resolve() in (OLD,release_path(),release_path(True)),'pointer_owned_by_other_release')
    temporary=CURRENT.with_name('current.benefits.'+secrets.token_hex(8));temporary.symlink_to(target,target_is_directory=True);os.replace(temporary,CURRENT)


def health():
    for attempt in range(30):
        try:
            for port in (8765,8766):
                with urllib.request.urlopen('http://127.0.0.1:'+str(port)+'/health',timeout=2) as response:
                    need(json.load(response).get('ok') is True,'health_unready')
            return
        except Exception:
            if attempt==29:raise
            time.sleep(.5)


def activate():
    import contextlib,io
    need(json.loads((STAGE/'validated.json').read_bytes())['rolled_back'] is True,'validation_required')
    with connection() as conn:
        conn.execute('SET TRANSACTION READ ONLY');baseline(conn);conn.rollback()
    stopped=False;committed=False
    try:
        systemctl('stop');stopped=True
        captured=io.StringIO()
        with contextlib.redirect_stdout(captured): backup()
        record=json.loads(captured.getvalue().splitlines()[-1]);save('private_backup',record)
        with connection() as conn:
            baseline(conn);before=rows_state(conn);result=apply(conn);after=rows_state(conn)
            need(all(before[key]==after[key] for key in before if key not in {'public._goufayu_migrations','public.archive_config_sets'}),'activation_changed_real_rows')
            conn.commit()
        committed=True
        switch(release_path());systemctl('start');health();payment_pin()
    except Exception:
        if stopped:
            systemctl('stop')
            # Once COMMIT could have succeeded the old unique backend is unsafe.
            # Keep stackable support even if the COMMIT acknowledgement was lost.
            target=release_path(True) if committed else OLD
            if not committed:
                with connection() as conn:
                    conn.execute('SET TRANSACTION READ ONLY')
                    registered=conn.execute('SELECT EXISTS(SELECT 1 FROM archive_config_sets WHERE config_hash=%s)',(P['rollback_bundle'],)).fetchone()[0]
                    conn.rollback()
                if registered:target=release_path(True)
            switch(target);systemctl('start');health()
            save('activation_recovery',dict(commit_acknowledged=committed,target=target.name,player_data_restored=False))
        raise
    return save('activated',dict(ok=True,phase='ACTIVATED',release=P['new_release'],bundle=P['bundle'],payment_untouched=True,**result))


def rollback_safe():
    need(CURRENT.resolve()==release_path(),'rollback_pointer_not_ours');payment_pin();manifest(release_path(True))
    systemctl('stop');switch(release_path(True));systemctl('start');health();payment_pin()
    return save('rollback_safe',dict(ok=True,phase='BENEFITS_DISABLED_STACKABLE_PRESERVED',release=P['rollback_release'],bundle=P['rollback_bundle'],database_restored=False,inventory_preserved=True,old_unique_backend_restored=False))


def verify():
    need(CURRENT.resolve() in (release_path(),release_path(True)),'candidate_not_active');payment_pin();manifest(CURRENT.resolve());health()
    return dict(ok=True,phase='VERIFIED',release=CURRENT.resolve().name,payment_pid=P['payment_pid'],player_writes=0)


actions={'audit':audit,'prepare':prepare,'validate':validate,'activate':activate,'verify':verify,'rollback-safe':rollback_safe}
try:
    print(json.dumps(actions[MODE](),ensure_ascii=False))
except Exception as error:
    message=str(error).splitlines()[0] if str(error) else ''
    code=message if re.fullmatch(r'[a-z0-9_]{1,100}',message) else 'private_operator_error'
    print(json.dumps(dict(ok=False,error=code,error_type=type(error).__name__,sqlstate=getattr(error,'sqlstate',None))))
    raise SystemExit(1)
