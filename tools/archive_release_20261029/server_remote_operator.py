"""Sealed archive deployment operator. Only the root driver invokes actions.

No secrets, account rows, raw SQL diagnostics or subprocess stderr are printed.
The existing payment and PostgreSQL services are never stopped or restarted.
"""
from __future__ import annotations
from pathlib import Path, PurePosixPath
import contextlib, copy, hashlib, importlib.util, io, json, os, re, secrets, shutil, subprocess, sys, time, urllib.request

sha=lambda raw:hashlib.sha256(raw).hexdigest()
canonical=lambda value:json.dumps(value,ensure_ascii=False,sort_keys=True,separators=(',',':'),allow_nan=False).encode()
def need(value,code):
    if not value:raise RuntimeError(code)
def sql_body(raw):
    text=raw.decode('utf-8-sig')
    start=re.match(r'\A(?:\s|--[^\n]*(?:\n|$))*begin\s*;',text,re.I)
    end=re.search(r'\bcommit\s*;\s*\Z',text,re.I)
    need(start and end and start.end()<end.start(),'sql_transaction_wrapper_invalid')
    return text[start.end():end.start()]
def safe(root,name):
    p=PurePosixPath(name)
    need(not p.is_absolute() and '..' not in p.parts and ':' not in name and '\\' not in name and p.as_posix()==name,'unsafe_release_path')
    need(all(not root.joinpath(*p.parts[:i]).is_symlink() for i in range(1,len(p.parts)+1)),'release_symlink')
    return root/name
def restore_arguments(user,clone):
    # Podman exec defaults to a Unix socket, whose peer identity is root.
    # Match the established PG17 bridge's TCP/password authentication instead.
    return ['podman','exec','-i','--env','PGPASSWORD','--env','PGHOST=127.0.0.1','--env','PGPORT=5432',
        'goufayu-db','pg_restore','--username',user,'--dbname',clone,'--role=goufayu_owner',
        '--no-owner','--no-acl','--single-transaction','--exit-on-error']
def prepare_empty_clone(conn,clone,creates_public):
    row=conn.execute("SELECT current_database(),(SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname NOT LIKE 'pg_%' AND n.nspname<>'information_schema'),(SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname NOT LIKE 'pg_%' AND n.nspname<>'information_schema'),(SELECT count(*) FROM pg_extension WHERE extname<>'plpgsql')").fetchone()
    need(re.fullmatch(r'goufayu_restore_archive_[0-9a-f]{12}_[0-9a-f]{6}',clone) and row[0]==clone,'empty_clone_identity_invalid')
    need(tuple(row[1:])==(0,0,0),'empty_clone_business_objects_exist')
    if creates_public:
        # Only the newly created, verified empty isolated DB. No CASCADE,
        # --clean, live schema deletion or existing clone reuse is permitted.
        conn.execute('DROP SCHEMA public')

class Operator:
    def __init__(self,stage):
        self.stage=Path(stage)
        need(self.stage.parent==Path('/root/goufayu_upload') and not self.stage.is_symlink(),'invalid_stage')
        self.p=json.loads((self.stage/'plan.json').read_bytes());p=self.p
        for key in ('archive_release','new_release','rollback_release','payment_release'):
            need(re.fullmatch(r'[A-Za-z0-9_.-]{1,96}',p[key]) and p[key]!='current','invalid_release_id')
        self.old=Path('/opt/goufayu/releases')/p['archive_release'];self.new=self.old.parent/p['new_release'];self.safe=self.old.parent/p['rollback_release'];self.current=self.old.parent/'current'
        self.pay=Path('/opt/goufayu/payments')/p['payment_release'];sys.path.insert(0,str(self.pay))
        from deploy import connection,backup
        self.connection,self.backup_fn=connection,backup
    def save(self,name,data):
        path=self.stage/(name+'.json');need(not path.is_symlink(),'report_symlink')
        path.write_bytes(canonical(data));path.chmod(0o600);return data
    def payment_pin(self):
        need(Path('/opt/goufayu/payments/current').resolve()==self.pay,'payment_pointer_changed')
        need(sha((self.pay/'manifest.json').read_bytes())==self.p['payment_manifest_sha256'],'payment_manifest_changed')
        need(subprocess.check_output(['systemctl','show','--property=MainPID','--value','goufayu-payment.service'],text=True).strip()==self.p['payment_pid'],'payment_pid_changed')
    def manifest(self,root):
        value=json.loads((root/'release_manifest.json').read_bytes())
        for name,digest in value['files'].items():need(sha(safe(root,name).read_bytes())==digest,'manifest_file_changed')
        return value
    def db_state(self,conn):
        need(conn.info.dbname=='goufayu_test' or conn.info.dbname.startswith('goufayu_restore_archive_'),'database_scope_invalid')
        need(int(conn.execute('SHOW server_version_num').fetchone()[0])//10000==17,'postgres17_required')
        return dict(ledger=dict(conn.execute('SELECT migration_id,sha256 FROM public._goufayu_migrations')),
            functions={s:sha(d.encode()) for s,d in conn.execute("SELECT p.oid::regprocedure::text,pg_get_functiondef(p.oid) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public'")},
            configs=dict(conn.execute("SELECT config_hash,encode(sha256(convert_to(config::text,'UTF8')),'hex') FROM public.archive_config_sets")))
    def baseline(self,conn):
        self.payment_pin();need(self.current.resolve()==self.old,'parent_pointer_changed')
        need(sha((self.old/'release_manifest.json').read_bytes())==self.p['archive_manifest_sha256'],'parent_manifest_changed')
        state=self.db_state(conn)
        need(all(state[key]==self.p[key] for key in ('ledger','functions','configs')),'database_baseline_changed')
        return state
    def pending(self,conn):
        need(conn.execute('SELECT count(*) FROM public.archive_operations WHERE NOT done').fetchone()[0]==0,'pending_archive_intents_exist')
    def rows(self,conn):
        from psycopg import sql
        return {s+'.'+t:conn.execute(sql.SQL("SELECT count(*),md5(coalesce(string_agg(to_jsonb(t)::text,chr(10) ORDER BY to_jsonb(t)::text),'')) FROM {}.{} t").format(sql.Identifier(s),sql.Identifier(t))).fetchone() for s,t in conn.execute("SELECT schemaname,tablename FROM pg_tables WHERE schemaname IN ('public','payments') ORDER BY 1,2").fetchall()}
    def prepare(self):
        with self.connection() as conn:
            conn.execute('SET TRANSACTION READ ONLY');self.baseline(conn);conn.rollback()
        parent=self.manifest(self.old);originals={**parent['files'],**self.p['all_backend_hashes']}
        for root,folder,key in ((self.new,'overlay','bundle'),(self.safe,'safe_overlay','archive_bundle')):
            overlay=self.p[folder];value=copy.deepcopy(parent);value['files']={**originals,**overlay};value.update(release=root.name,archive_bundle=self.p[key],archive_parent=self.old.name)
            if root.exists():need(not root.is_symlink() and self.manifest(root)==value,'candidate_already_exists_or_changed');continue
            root.mkdir(mode=0o755)
            for name,digest in originals.items():
                source=safe(self.old,name);need(sha(source.read_bytes())==digest,'copy_source_drift')
                dest=safe(root,name);dest.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(source,dest);dest.chmod(source.stat().st_mode & 0o777)
            (root/'.venv').symlink_to(self.old/'.venv',target_is_directory=True)
            for name,digest in overlay.items():
                source=safe(self.stage/folder,name);need(sha(source.read_bytes())==digest,'overlay_source_drift')
                dest=safe(root,name);dest.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(source,dest);dest.chmod(0o644)
            (root/'release_manifest.json').write_bytes(canonical(value));self.manifest(root)
        return self.save('prepared',dict(ok=True,phase='PREPARED_NOT_ACTIVATED',release=self.new.name,safe_release=self.safe.name,payment_untouched=True))
    def apply(self,conn):
        from psycopg.types.json import Jsonb
        conn.execute('SET LOCAL ROLE goufayu_owner');conn.execute('SELECT pg_advisory_xact_lock(719232014021)')
        conn.execute('LOCK TABLE public._goufayu_migrations,public.archive_config_sets IN SHARE ROW EXCLUSIVE MODE')
        before=self.db_state(conn);need(all(before[k]==self.p[k] for k in before),'database_baseline_changed')
        for item in self.p['migrations']:
            raw=safe(self.stage/'overlay',item['path']).read_bytes();need(sha(raw)==item['sha256'],'migration_source_drift')
            conn.execute(sql_body(raw) if item['transaction_wrapper'] else raw.decode('utf-8'))
            conn.execute('INSERT INTO public._goufayu_migrations(migration_id,sha256) VALUES(%s,%s)',(item['id'],item['sha256']))
        # Preserve every deployed strict-config branch; add only the exact new
        # immutable config, matching ArchiveService.sync's omitted empty aliases.
        data=json.loads((self.new/'addon/server/bundles'/self.p['bundle']/'bundle.json').read_bytes())
        config=dict(configs=data['configs'])
        if data.get('compatible_config_hashes'):config['compatible_config_hashes']=data['compatible_config_hashes']
        signature='public.archive_sync_config(text,jsonb)'
        definition=conn.execute('SELECT pg_get_functiondef(%s::regprocedure)',(signature,)).fetchone()[0]
        marker=' -- Reviewed monthly challenge tickets and requested fragment/cage quotas.'
        need(definition.count(marker)==1,'sync_policy_anchor_changed')
        digest=conn.execute("SELECT encode(sha256(convert_to(%s::jsonb::text,'UTF8')),'hex')",(Jsonb(config),)).fetchone()[0]
        branch=" -- Reviewed archive challenges 20261029: exact immutable config.\n if p_hash='%s' then\n  if encode(sha256(convert_to(p_config::text,'UTF8')),'hex')<>'%s' then raise exception 'archive_release_configuration_mismatch'; end if;\n  insert into archive_config_sets(config_hash,config) values(p_hash,p_config) on conflict do nothing;\n  select config into v from archive_config_sets where config_hash=p_hash;\n  if v is distinct from p_config then raise exception 'archive_config_immutable'; end if;\n  return jsonb_build_object('ok',true);\n end if;\n"%(self.p['bundle'],digest)
        updated=definition.replace(marker,branch+marker,1);need(updated.replace(branch,'',1)==definition,'old_sync_policy_changed');conn.execute(updated)
        need(conn.execute('SELECT public.archive_sync_config(%s,%s)',(self.p['bundle'],Jsonb(config))).fetchone()[0]['ok'],'new_config_registration_failed')
        after=self.db_state(conn)
        need(after['ledger']=={**before['ledger'],**{m['id']:m['sha256'] for m in self.p['migrations']}},'old_ledger_changed')
        changed={k for k,v in before['functions'].items() if after['functions'].get(k)!=v}
        need(changed=={'match_profile_login(text,text,text,jsonb)','archive_sync_config(text,jsonb)'},'unexpected_old_sql_change')
        need(set(after['functions'])-set(before['functions'])=={'archive_commit_challenge(text,text,bigint,jsonb,jsonb,text,jsonb)'},'unexpected_new_sql_function')
        need(all(after['configs'].get(k)==v for k,v in before['configs'].items()) and set(after['configs'])==set(before['configs'])|{self.p['bundle']},'old_config_changed')
        rpcs=[r[0] for r in conn.execute("SELECT p.oid::regprocedure::text FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND has_function_privilege('goufayu_app',p.oid,'EXECUTE') AND NOT EXISTS(SELECT 1 FROM pg_depend d WHERE d.classid='pg_proc'::regclass AND d.objid=p.oid AND d.deptype='e') ORDER BY 1")]
        need(set(rpcs)==set(self.p['app_rpcs'])|{'archive_commit_challenge(text,text,bigint,jsonb,jsonb,text,jsonb)'},'old_rpc_privileges_changed')
        return dict(new_migrations=len(self.p['migrations']),application_rpcs=len(rpcs),config_digest=digest)
    def control(self,action):
        need(action in ('start','stop'),'invalid_service_action')
        need(subprocess.run(['systemctl',action,'goufayu-api.service'],capture_output=True,timeout=40).returncode==0,'archive_service_action_failed')
    def backup(self):
        need((self.stage/'prepared.json').is_file(),'prepare_required')
        with self.connection() as conn:
            conn.execute('SET TRANSACTION READ ONLY');self.baseline(conn);self.pending(conn);conn.rollback()
        self.control('stop')
        try:
            with self.connection() as conn:
                conn.execute('SET TRANSACTION READ ONLY');self.baseline(conn);self.pending(conn);conn.rollback()
            stream=io.StringIO()
            with contextlib.redirect_stdout(stream):self.backup_fn()
            record=json.loads(stream.getvalue().splitlines()[-1]);path=Path(record['local_backup'])
            need(path.parent==Path('/var/backups/goufayu-payment') and not path.is_symlink() and path.is_file(),'private_backup_path_invalid')
            digest=sha(path.read_bytes());need(path.with_suffix('.sha256').read_text().strip()==digest,'private_backup_checksum_invalid')
            return self.save('private_backup',dict(ok=True,phase='QUIESCED_BACKUP_READY',path=str(path),sha256=digest,size=path.stat().st_size,at=time.time(),payment_untouched=True))
        except Exception:
            self.control('start');raise
    def validate_clone(self):
        import psycopg
        from psycopg import sql
        saved=json.loads((self.stage/'private_backup.json').read_bytes());path=Path(saved['path'])
        need(sha(path.read_bytes())==saved['sha256'],'private_backup_changed')
        clone='goufayu_restore_archive_'+sha((self.stage/'plan.json').read_bytes())[:12]+'_'+secrets.token_hex(3)
        with self.connection() as admin:
            admin.rollback();admin.autocommit=True
            need(not admin.execute('SELECT 1 FROM pg_database WHERE datname=%s',(clone,)).fetchone(),'clone_database_exists')
            params=admin.info.get_parameters();password=admin.info.password;params.pop('dbname',None);params.pop('password',None);params.pop('service',None);params.pop('passfile',None)
            admin.execute(sql.SQL('CREATE DATABASE {} OWNER goufayu_owner TEMPLATE template0').format(sql.Identifier(clone)))
            admin.execute(sql.SQL('REVOKE ALL ON DATABASE {} FROM PUBLIC').format(sql.Identifier(clone)))
            admin.execute(sql.SQL('GRANT CONNECT ON DATABASE {} TO goufayu_app,goufayu_migrator').format(sql.Identifier(clone)))
        raw_dump=path.read_bytes()
        schema=subprocess.run(['podman','exec','-i','goufayu-db','pg_restore','--schema-only','--file=-'],input=raw_dump,capture_output=True,timeout=45)
        need(schema.returncode==0,'isolated_dump_schema_read_failed')
        creates_public=bool(re.search(r'^CREATE SCHEMA (?:public|"public");\s*$',schema.stdout.decode('utf-8','replace'),re.M))
        with psycopg.connect(**params,password=password,dbname=clone) as empty:
            prepare_empty_clone(empty,clone,creates_public)
            empty.commit()
        self.save('clone_created',dict(ok=True,database=clone,public_schema_recreated_from_dump=creates_public,restore_transport='loopback_tcp',live_database_modified=False))
        restored=subprocess.run(restore_arguments(params['user'],clone),input=raw_dump,capture_output=True,env={**os.environ,'PGPASSWORD':password},timeout=120)
        if restored.returncode:
            diagnostic=restored.stderr.decode('utf-8','replace').lower()
            error=next((name for name,needle in [('peer_authentication','peer authentication failed'),('password_authentication','password authentication failed'),('public_schema_exists','schema "public" already exists'),('schema_permission','permission denied for schema'),('extension_permission','permission denied to create extension')] if needle in diagnostic),'unclassified')
            self.save('clone_restore_failure',dict(ok=False,database=clone,error_class=error,stderr_sha256=sha(restored.stderr),live_database_modified=False))
            raise RuntimeError('isolated_clone_restore_failed_'+error)
        with psycopg.connect(**params,password=password,dbname=clone) as conn:
            conn.execute('SET TRANSACTION ISOLATION LEVEL REPEATABLE READ')
            # The private backup deliberately omits ACLs. Reconstruct only the
            # audited effective app allowlist in the disposable clone, never
            # run generic hardening against the live leaderboard extension.
            conn.execute('REVOKE ALL ON ALL TABLES IN SCHEMA public FROM PUBLIC,goufayu_app,anon,authenticated,service_role')
            conn.execute('REVOKE ALL ON ALL SEQUENCES IN SCHEMA public FROM PUBLIC,goufayu_app,anon,authenticated,service_role')
            conn.execute('REVOKE ALL ON ALL FUNCTIONS IN SCHEMA public FROM PUBLIC,goufayu_app,anon,authenticated,service_role')
            conn.execute('REVOKE ALL ON SCHEMA public FROM PUBLIC,goufayu_app,anon,authenticated,service_role');conn.execute('GRANT USAGE ON SCHEMA public TO goufayu_app')
            for signature in self.p['app_rpcs']:
                need(re.fullmatch(r'[a-z_]+\([a-z0-9_, ]*\)',signature),'audited_signature_invalid')
                conn.execute('GRANT EXECUTE ON FUNCTION public.'+signature+' TO goufayu_app')
            before=self.rows(conn);result=self.apply(conn)
            spec=importlib.util.spec_from_file_location('archive_release_runtime_probe',self.stage/'overlay/validation/runtime_probe.py');module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
            probes=module.run(conn,self.new)
            after=self.rows(conn);need(set(before)==set(after) and all(after[k]==v for k,v in before.items() if k not in ('public._goufayu_migrations','public.archive_config_sets')),'clone_original_rows_changed')
            conn.commit()
        # A separate actual app connection exercises the candidate transport's
        # session_user/current_user/complete RPC readiness and RLS/DML checks.
        sys.path.insert(0,str(self.new/'backend'))
        from fishing_api.postgres import PostgresRpcClient
        from psycopg.conninfo import make_conninfo
        app_password=Path('/etc/goufayu/app-password').read_text().strip()
        client=PostgresRpcClient(make_conninfo(host='127.0.0.1',port=5432,dbname=clone,user='goufayu_app',password=app_password))
        need(client.ready(),'clone_actual_app_transport_not_ready')
        return self.save('validated_clone',dict(ok=True,phase='PG17_CLONE_VALIDATED',database=clone,live_database_modified=False,original_player_rows_unchanged=True,actual_app_transport_ready=True,probes=probes,**result))
    def switch(self,target,expected):
        need(target in (self.old,self.new,self.safe) and self.current.resolve()==expected,'pointer_ownership_changed')
        temporary=self.current.with_name('current.archive.'+secrets.token_hex(8));temporary.symlink_to(target,target_is_directory=True);os.replace(temporary,self.current)
    def health(self,expected):
        import shlex
        env={}
        for line in Path('/etc/goufayu/api.env').read_text().splitlines():
            if line and not line.startswith('#'):
                key,value=line.split('=',1);env[key]=''.join(shlex.split(value))
        for attempt in range(40):
            try:
                for port in (8765,8766):
                    with urllib.request.urlopen('http://127.0.0.1:'+str(port)+'/health',timeout=2) as response:need(json.load(response)['ok'],'health_unready')
                headers={'Authorization':'Bearer '+env['FISHING_API_TOKEN']}
                with urllib.request.urlopen(urllib.request.Request('http://127.0.0.1:8765/ready',headers=headers),timeout=10) as response:need(json.load(response).get('database')=='ready','database_not_ready')
                with urllib.request.urlopen(urllib.request.Request('http://127.0.0.1:8765/v1/archive/config',data=b'{}',headers={**headers,'Content-Type':'application/json'}),timeout=10) as response:need(json.load(response).get('config_hash')==expected,'bundle_http_hash_mismatch')
                return
            except Exception:
                if attempt==39:raise
                time.sleep(.5)
    def activate(self):
        need(json.loads((self.stage/'validated_clone.json').read_bytes())['actual_app_transport_ready'],'clone_validation_required')
        saved=json.loads((self.stage/'private_backup.json').read_bytes());ack=json.loads((self.stage/'offsite_ack.json').read_bytes())
        need(ack['sha256']==saved['sha256'] and ack['encrypted_verified'],'encrypted_offsite_backup_required')
        need(sha(Path(saved['path']).read_bytes())==saved['sha256'],'private_backup_changed')
        need(time.time()-saved['at']<1800,'quiesced_backup_expired')
        need(subprocess.check_output(['systemctl','show','--property=ActiveState','--value','goufayu-api.service'],text=True).strip()=='inactive','archive_not_quiesced')
        self.manifest(self.new);self.manifest(self.safe);committed=False;mutation_started=False
        try:
            with self.connection() as conn:
                conn.execute('SET TRANSACTION ISOLATION LEVEL REPEATABLE READ');self.baseline(conn);self.pending(conn);before=self.rows(conn);mutation_started=True;result=self.apply(conn);after=self.rows(conn)
                need(set(before)==set(after) and all(after[k]==v for k,v in before.items() if k not in ('public._goufayu_migrations','public.archive_config_sets')),'live_original_rows_changed');conn.commit()
            committed=True;self.switch(self.new,self.old);self.control('start');self.health(self.p['bundle']);self.payment_pin()
        except Exception:
            # A failed preflight or an unrelated operator's pointer is not
            # ownership of its API process. Never stop/revert that release.
            if not mutation_started:raise
            observed=self.current.resolve()
            if observed not in (self.old,self.new,self.safe):
                self.save('activation_recovery',dict(ok=False,phase='FOREIGN_RELEASE_REQUIRES_MANUAL_RECOVERY',database_may_be_committed=True));raise
            self.control('stop')
            with self.connection() as conn:
                conn.execute('SET TRANSACTION READ ONLY');present=conn.execute('SELECT EXISTS(SELECT 1 FROM public._goufayu_migrations WHERE migration_id=%s)',(self.p['migrations'][-1]['id'],)).fetchone()[0];conn.rollback()
            target=self.safe if present else self.old;self.switch(target,observed);self.control('start');self.health(self.p['archive_bundle'])
            self.save('activation_recovery',dict(ok=True,commit_acknowledged=committed,safe_recovery=present,release=target.name,database_restored=False));raise
        return self.save('activated',dict(ok=True,phase='ACTIVATED',release=self.new.name,bundle=self.p['bundle'],old_player_rows_unchanged=True,payment_untouched=True,**result))
    def verify(self):
        need(self.current.resolve()==self.new,'candidate_not_active');self.manifest(self.new);self.payment_pin();self.health(self.p['bundle'])
        with self.connection() as conn:
            conn.execute('SET TRANSACTION READ ONLY');state=self.db_state(conn)
            need(state['ledger']=={**self.p['ledger'],**{m['id']:m['sha256'] for m in self.p['migrations']}},'postdeploy_ledger_changed');conn.rollback()
        return self.save('verified',dict(ok=True,phase='LIVE_VERIFIED',release=self.new.name,bundle=self.p['bundle'],ledger_entries=len(state['ledger']),payment_untouched=True,native_real_player_reward_verified=False))
    def resume(self):
        with self.connection() as conn:
            conn.execute('SET TRANSACTION READ ONLY');self.baseline(conn);conn.rollback()
        self.control('start');self.health(self.p['archive_bundle']);return dict(ok=True,phase='OLD_API_RESUMED')
    def rollback_safe(self):
        need(self.current.resolve()==self.new,'candidate_not_active');self.manifest(self.safe);self.payment_pin();self.control('stop');self.switch(self.safe,self.new);self.control('start');self.health(self.p['archive_bundle']);self.payment_pin()
        return self.save('rollback_safe',dict(ok=True,phase='SAFE_CODE_ROLLBACK_NEW_RPC_RETAINED',database_restored=False,inventory_preserved=True))
    def dispatch(self,mode):
        import fcntl
        actions={'prepare':self.prepare,'backup':self.backup,'validate-clone':self.validate_clone,'activate':self.activate,'verify':self.verify,'resume':self.resume,'rollback-safe':self.rollback_safe}
        need(mode in actions,'unsupported_action')
        with Path('/var/lock/survival_archive_release.lock').open('a') as lock:
            try:fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
            except BlockingIOError:raise RuntimeError('another_archive_release_action_is_running') from None
            return actions[mode]()
