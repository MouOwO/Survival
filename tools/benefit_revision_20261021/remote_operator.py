"""Config-only revision. No migration, backend edits or player-row mutation."""
from pathlib import Path,PurePosixPath
import copy,hashlib,json,os,re,secrets,shutil,subprocess,sys,time,urllib.request
STAGE=Path(STAGE)
P=json.loads((STAGE/'plan.json').read_bytes())
sha=lambda raw:hashlib.sha256(raw).hexdigest()
canonical=lambda value:json.dumps(value,ensure_ascii=False,sort_keys=True,separators=(',',':'),allow_nan=False).encode()
OLD=Path('/opt/goufayu/releases')/P['archive_release'];CURRENT=OLD.parent/'current'
NEW=OLD.parent/P['new_release'];SAFE=OLD.parent/P['rollback_release']
PAY=Path('/opt/goufayu/payments')/P['payment_release'];sys.path.insert(0,str(PAY))
from deploy import connection,backup
from psycopg.types.json import Jsonb


def need(value,code):
    if not value:raise RuntimeError(code)


def save(name,value):
    path=STAGE/(name+'.json');need(not path.is_symlink(),'report_symlink')
    path.write_bytes(canonical(value));path.chmod(0o600);return value


def safe(root,name):
    relative=PurePosixPath(name);need(not relative.is_absolute() and '..' not in relative.parts and ':' not in name and '\\' not in name and relative.as_posix()==name,'unsafe_relative_path')
    need(all(not root.joinpath(*relative.parts[:i]).is_symlink() for i in range(1,len(relative.parts)+1)),'release_symlink')
    return root/name


def payment():
    need(Path('/opt/goufayu/payments/current').resolve()==PAY,'payment_pointer_changed')
    need(sha((PAY/'manifest.json').read_bytes())==P['payment_manifest_sha256'],'payment_manifest_changed')
    pid=subprocess.check_output(['systemctl','show','--property=MainPID','--value','goufayu-payment.service'],text=True).strip()
    need(pid==P['payment_pid']=='5427','payment_pid_changed')


def manifest(root):
    value=json.loads((root/'release_manifest.json').read_bytes())
    for name,digest in value['files'].items():need(sha(safe(root,name).read_bytes())==digest,'manifest_file_changed')
    return value


def database(conn):
    need(conn.info.dbname=='goufayu_test','database_scope_changed')
    functions={signature:sha(definition.encode()) for signature,definition in conn.execute("SELECT p.oid::regprocedure::text,pg_get_functiondef(p.oid) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public'")}
    return dict(ledger=dict(conn.execute('SELECT migration_id,sha256 FROM _goufayu_migrations')),configs=dict(conn.execute("SELECT config_hash,encode(sha256(convert_to(config::text,'UTF8')),'hex') FROM archive_config_sets")),functions=functions)


def baseline(conn):
    payment();need(CURRENT.resolve()==OLD,'parent_pointer_changed')
    need(sha((OLD/'release_manifest.json').read_bytes())==P['archive_manifest_sha256'],'parent_manifest_changed')
    result=database(conn)
    need(all(result[key]==P[key] for key in result),'database_baseline_changed')
    return result


def configuration(data):return dict(configs=data['configs'],compatible_config_hashes=data['compatible_config_hashes'])


def scope():
    parent=json.loads((OLD/'addon/server/bundles'/P['archive_bundle']/'bundle.json').read_bytes())
    values={}
    for key in ('bundle','rollback_bundle'):
        raw=safe(STAGE/'overlay','addon/server/bundles/'+P[key]+'/bundle.json').read_bytes();need(sha(raw)==P[key],'bundle_digest_changed');values[key]=json.loads(raw)
    expected=copy.deepcopy(parent);rows={row['reward_id']:row for row in expected['configs']['archive_benefit_rewards']['rows']}
    need(len(P['row_changes'])==9,'changed_row_count_changed')
    for change in P['row_changes']:
        for field,diff in change['fields'].items():
            need(field in ('pass_item_ids','pass_counts'),'unapproved_reward_field')
            old=diff['before'].split('|') if diff['before'] else None;new=diff['after'].split('|') if diff['after'] else None
            need(rows[change['reward_id']].get(field)==old,'parent_reward_value_changed')
            if new is None:rows[change['reward_id']].pop(field,None)
            else:rows[change['reward_id']][field]=new
    csv='data/csv/存档系统/archive_benefit_rewards.csv'
    expected['csv_hashes'][csv]=sha(safe(STAGE/'overlay','addon/'+csv).read_bytes())
    commands=sorted({kind for rule in expected['compatible_config_hashes'].values() for kind in rule['commands']}-{'benefit_claim'})
    expected['compatible_config_hashes'][P['archive_bundle']]=dict(commands=commands,upgrade_commands=[])
    need(values['bundle']==expected,'unrelated_bundle_configuration_or_source_changed')
    disabled=copy.deepcopy(expected)
    for row in disabled['configs']['archive_benefit_rewards']['rows']:row['enabled']=False
    disabled['compatible_config_hashes'][P['bundle']]=dict(commands=commands,upgrade_commands=[])
    need(values['rollback_bundle']==disabled,'unsafe_disabled_bundle')
    need(not P['migrations'],'unexpected_migration')
    return values


def prepare():
    with connection() as conn:
        conn.execute('SET TRANSACTION READ ONLY');baseline(conn);conn.rollback()
    scope();parent=manifest(OLD)
    for root,key in ((NEW,'bundle'),(SAFE,'rollback_bundle')):
        need(not root.exists(),'candidate_release_exists');root.mkdir(mode=0o755)
        for name in parent['files']:
            source=safe(OLD,name);target=safe(root,name);target.parent.mkdir(parents=True,exist_ok=True)
            shutil.copyfile(source,target);target.chmod(source.stat().st_mode & 0o777)
        (root/'.venv').symlink_to(OLD/'.venv',target_is_directory=True)
        for name,digest in P['overlay'].items():
            need(name.startswith(('addon/server/bundles/','addon/data/csv/存档系统/archive_benefit_rewards.csv')),'non_configuration_overlay_refused')
            source=safe(STAGE/'overlay',name);need(sha(source.read_bytes())==digest,'overlay_digest_changed')
            target=safe(root,name);target.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(source,target);target.chmod(0o644)
        pointer='addon/server/bundles/current.json';raw=canonical(dict(hash=P[key],protocol=1));safe(root,pointer).write_bytes(raw)
        result=copy.deepcopy(parent);result['files'].update(P['overlay']);result['files'][pointer]=sha(raw)
        result.update(release=root.name,archive_bundle=P[key],benefit_revision_parent=P['archive_release'])
        (root/'release_manifest.json').write_bytes(canonical(result));manifest(root)
    return save('prepared',dict(ok=True,phase='PREPARED_NOT_ACTIVATED',release=NEW.name,bundle=P['bundle'],rollback_release=SAFE.name,payment_pid=P['payment_pid']))


def table_rows(conn):
    from psycopg import sql
    return {schema+'.'+table:conn.execute(sql.SQL("SELECT count(*),md5(coalesce(string_agg(to_jsonb(t)::text,chr(10) ORDER BY to_jsonb(t)::text),'')) FROM {}.{} t").format(sql.Identifier(schema),sql.Identifier(table))).fetchone() for schema,table in conn.execute("SELECT schemaname,tablename FROM pg_tables WHERE schemaname IN ('public','payments') ORDER BY 1,2").fetchall()}


def apply(conn):
    conn.execute('SET LOCAL ROLE goufayu_owner');conn.execute('SELECT pg_advisory_xact_lock(719232014022)')
    conn.execute('LOCK TABLE public.archive_config_sets IN SHARE ROW EXCLUSIVE MODE')
    before=database(conn);need(before['ledger']==P['ledger'] and before['configs']==P['configs'] and before['functions']==P['functions'],'database_baseline_changed')
    definition=conn.execute("SELECT pg_get_functiondef('public.archive_sync_config(text,jsonb)'::regprocedure)").fetchone()[0]
    need(sha(definition.encode())==P['sync_sha256'],'sync_definition_changed')
    marker=' -- Reviewed monthly challenge tickets and requested fragment/cage quotas.';need(definition.count(marker)==1,'sync_anchor_changed')
    branches=[];values=scope()
    for key,data in values.items():
        digest=P[key];value=configuration(data)
        pg_sha=conn.execute("SELECT encode(sha256(convert_to(%s::jsonb::text,'UTF8')),'hex')",(Jsonb(value),)).fetchone()[0]
        branches.append(""" -- Reviewed benefit-revision 20261021: exact configuration only.
 if p_hash='%s' then
  if encode(sha256(convert_to(p_config::text,'UTF8')),'hex')<>'%s' then raise exception 'benefit_revision_configuration_mismatch'; end if;
  insert into archive_config_sets(config_hash,config) values(p_hash,p_config) on conflict do nothing;
  select config into v from archive_config_sets where config_hash=p_hash;
  if v is distinct from p_config then raise exception 'archive_config_immutable'; end if;
  return jsonb_build_object('ok',true);
 end if;
"""%(digest,pg_sha))
    addition=''.join(branches);updated=definition.replace(marker,addition+marker,1)
    need(updated.replace(addition,'',1)==definition,'old_sync_branch_changed');conn.execute(updated)
    for key,data in values.items():need(conn.execute('SELECT public.archive_sync_config(%s,%s)',(P[key],Jsonb(configuration(data)))).fetchone()[0]['ok'],'configuration_registration_failed')
    after=database(conn)
    need(after['ledger']==before['ledger'],'migration_ledger_changed')
    need(all(after['configs'].get(key)==value for key,value in before['configs'].items()) and set(after['configs'])==set(before['configs'])|{P['bundle'],P['rollback_bundle']},'existing_configuration_changed')
    changed=[key for key in before['functions'] if before['functions'][key]!=after['functions'].get(key)]
    need(changed==['archive_sync_config(text,jsonb)'],'unrelated_sql_function_changed')
    return dict(new_configurations=2,new_migrations=0,sql_functions_changed=changed,old_configurations_preserved=True)


def worker():
    now=int(time.time());day=str((now+10800)//86400);week=str(((now+10800)//86400+3)//7)
    def claim(root,digest,track,tier,claimed=False):
        directory=root/'addon/server/bundles'/digest;data=json.loads((directory/'bundle.json').read_bytes())
        defaults={row['field_id']:row['default_value'] for row in data['configs']['player_gameplay_stats']['rows']}
        period=dict(seconds=1080*60,wins=5,claimed={tier:dict(at=now,has_pass=1)} if claimed else {})
        profile=dict(save=dict(archive=dict(benefits=dict(version=1,days={day:copy.deepcopy(period)},weeks={week:copy.deepcopy(period)})),content_inventory={},gameplay_stats=defaults))
        payload=dict(configs=data['configs'],profile=profile,command=dict(id='revision_memory_probe',kind='benefit_claim',track=track,tier_id=tier,event_at=now),has_pass=True,server_time=now,seed=1)
        result=subprocess.run([shutil.which('lua5.1') or shutil.which('lua'),'worker.lua'],cwd=directory,input=canonical(payload),capture_output=True,timeout=15)
        need(result.returncode==0,'memory_worker_failed');return json.loads(result.stdout)
    tests=[('daily_time','daily_time_150',4,1),('daily_wins','daily_win_3',2,1),('daily_wins','daily_win_4',1,0),('weekly_time','weekly_time_120',4,0),('weekly_time','weekly_time_840',10,1)]
    for track,tier,ordinary,gold in tests:
        value=claim(NEW,P['bundle'],track,tier);need(value.get('ok'),'revision_memory_claim_failed');inventory=value['content_inventory']
        need(inventory.get('lottery_ticket',0)==ordinary and inventory.get('special_lottery_ticket',0)==gold,'revision_reward_amount_wrong')
    old=claim(OLD,P['archive_bundle'],'daily_time','daily_time_150')
    need(old.get('ok') and old['content_inventory']['special_lottery_ticket']==2,'old_intent_reward_changed')
    need(not claim(NEW,P['bundle'],'daily_time','daily_time_150',True).get('ok'),'previous_claim_reset')
    need(not claim(SAFE,P['rollback_bundle'],'daily_time','daily_time_150').get('ok'),'safe_rollback_claim_enabled')
    return dict(cases=8,memory_only=True,real_player_writes=0,parent_intent_retains_original_reward=True,claimed_flags_retained=True)


def validate():
    need((STAGE/'prepared.json').is_file(),'prepare_required');manifest(NEW);manifest(SAFE);checks=worker()
    with connection() as conn:
        try:
            conn.execute('SET TRANSACTION ISOLATION LEVEL REPEATABLE READ');conn.execute("SET LOCAL lock_timeout='5s'")
            baseline(conn);before=table_rows(conn);result=apply(conn);after=table_rows(conn)
            need(before.keys()==after.keys() and all(before[key]==after[key] for key in before if key!='public.archive_config_sets'),'non_config_database_rows_changed')
        finally:conn.rollback()
    with connection() as conn:
        conn.execute('SET TRANSACTION READ ONLY');baseline(conn);conn.rollback()
    return save('validated',dict(ok=True,phase='VALIDATED_ROLLED_BACK',rolled_back=True,worker=checks,claims_and_counters_unchanged=True,payment_untouched=True,**result))


def control(action):
    need(action in ('start','stop'),'invalid_service_action')
    need(subprocess.run(['systemctl',action,'goufayu-api.service'],capture_output=True,timeout=45).returncode==0,'archive_service_action_failed')


def switch(target):
    need(target in (OLD,NEW,SAFE) and CURRENT.resolve() in (OLD,NEW,SAFE),'unsafe_pointer')
    temporary=CURRENT.with_name('current.benefit-revision.'+secrets.token_hex(8));temporary.symlink_to(target,target_is_directory=True);os.replace(temporary,CURRENT)


def health():
    for attempt in range(30):
        try:
            for port in (8765,8766):
                with urllib.request.urlopen('http://127.0.0.1:'+str(port)+'/health',timeout=2) as response:need(json.load(response)['ok'] is True,'health_unready')
            return
        except Exception:
            if attempt==29:raise
            time.sleep(.5)


def activate():
    import contextlib,io
    need(json.loads((STAGE/'validated.json').read_bytes())['rolled_back'],'validation_required')
    with connection() as conn:
        conn.execute('SET TRANSACTION READ ONLY');baseline(conn);conn.rollback()
    stopped=False;committed=False
    try:
        control('stop');stopped=True;captured=io.StringIO()
        with contextlib.redirect_stdout(captured):backup()
        save('private_backup',json.loads(captured.getvalue().splitlines()[-1]))
        with connection() as conn:
            baseline(conn);before=table_rows(conn);result=apply(conn);after=table_rows(conn)
            need(all(before[key]==after[key] for key in before if key!='public.archive_config_sets'),'activation_changed_non_config_rows');conn.commit()
        committed=True;switch(NEW);control('start');health();payment()
    except Exception:
        if stopped:
            control('stop');target=SAFE if committed else OLD
            if not committed:
                with connection() as conn:
                    conn.execute('SET TRANSACTION READ ONLY');registered=conn.execute('SELECT EXISTS(SELECT 1 FROM archive_config_sets WHERE config_hash=%s)',(P['rollback_bundle'],)).fetchone()[0];conn.rollback()
                if registered:target=SAFE
            switch(target);control('start');health();save('recovery',dict(target=target.name,database_restored=False))
        raise
    return save('activated',dict(ok=True,phase='ACTIVATED',release=NEW.name,bundle=P['bundle'],payment_untouched=True,**result))


def verify():
    need(CURRENT.resolve()==NEW,'active_pointer_changed');payment();value=manifest(NEW);scope();health()
    config=json.loads(Path('/etc/goufayu-payment/config.json').read_bytes())
    request=urllib.request.Request('http://127.0.0.1:8765/v1/lottery/catalog',data=b'{"md5":""}',method='POST',headers={'Content-Type':'application/json','Authorization':'Bearer '+config['game_token']})
    with urllib.request.urlopen(request,timeout=20) as response:catalog=json.load(response)
    need(catalog.get('ok') is True and catalog['config_hash']==P['bundle'] and catalog['catalog_md5']=='ca9954922ebfa93d83d646187d1068d1','live_catalog_changed')
    with connection() as conn:
        conn.execute('SET TRANSACTION READ ONLY');state=database(conn);conn.rollback()
    need(state['ledger']==P['ledger'],'ledger_changed')
    need(all(state['configs'].get(key)==value for key,value in P['configs'].items()) and set(state['configs'])==set(P['configs'])|{P['bundle'],P['rollback_bundle']},'configuration_scope_changed')
    changed=[key for key in P['functions'] if P['functions'][key]!=state['functions'].get(key)];need(changed==['archive_sync_config(text,jsonb)'],'sql_scope_changed')
    return save('verified',dict(ok=True,phase='LIVE_VERIFIED',release=NEW.name,bundle=P['bundle'],manifest_sha256=sha((NEW/'release_manifest.json').read_bytes()),catalog_md5=catalog['catalog_md5'],payment_pid=P['payment_pid'],ledger_entries=len(state['ledger']),new_migrations=0,new_configurations=2,sql_functions_changed=changed,player_rows_changed=0))


def rollback_safe():
    need(CURRENT.resolve()==NEW,'rollback_pointer_not_ours');manifest(SAFE);payment();control('stop');switch(SAFE);control('start');health();payment()
    return save('rollback_safe',dict(ok=True,phase='BENEFITS_DISABLED',release=SAFE.name,bundle=P['rollback_bundle'],inventory_and_claims_preserved=True,backend_unchanged=True))


try:
    print(json.dumps({'prepare':prepare,'validate':validate,'activate':activate,'verify':verify,'rollback-safe':rollback_safe}[MODE](),ensure_ascii=False))
except Exception as error:
    message=str(error).splitlines()[0] if str(error) else '';code=message if re.fullmatch('[a-z0-9_]{1,100}',message) else 'private_operator_error'
    print(json.dumps(dict(ok=False,error=code,error_type=type(error).__name__)));raise SystemExit(1)
