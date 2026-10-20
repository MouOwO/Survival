"""Reviewed archive-only phases. Import has no remote or filesystem effects."""
import contextlib
import copy
import hashlib
import importlib.util
import io
import json
import os
from pathlib import Path, PurePosixPath
import re
import secrets
import shutil
import subprocess
import sys
import tarfile
import time
import urllib.request

sys.dont_write_bytecode=True
SYNC='public.archive_sync_config(text,jsonb)'
LOGIN='public.match_profile_login(text,text,text,jsonb)'


def need(value,code):
    if not value:
        raise RuntimeError(code)


def canonical(value):
    return json.dumps(value,ensure_ascii=False,sort_keys=True,separators=(',',':'),allow_nan=False).encode()


def digest(raw):
    return hashlib.sha256(raw).hexdigest()


def sha(path):
    return digest(Path(path).read_bytes())


def safe(root,name):
    relative=PurePosixPath(name)
    need(name and relative.parts and not relative.is_absolute() and '..' not in relative.parts and '\\' not in name
         and ':' not in name and '\x00' not in name and relative.as_posix()==name,'unsafe_release_path')
    p=root
    for part in relative.parts:
        p=p/part;need(not p.is_symlink(),'release_member_symlink')
    return p


def sql_body(raw):
    # Canonical whole-file hashes are checked before removing only the outer
    # transaction. Both mode SQL files and registration share one real COMMIT.
    text=raw.decode('utf-8-sig').replace('\r\n','\n')
    start=re.match(r'\A(?:\s|--[^\n]*(?:\n|$))*BEGIN\s*;',text,re.I)
    end=re.search(r'\bCOMMIT\s*;\s*\Z',text,re.I)
    need(start and end and start.end()<end.start(),'sql_transaction_wrapper_changed')
    return text[start.end():end.start()]


def outcome(observed,old,new):
    """Never infer an interrupted COMMIT from a missing client acknowledgement."""
    if observed==new:return 'COMMITTED'
    if observed==old:return 'NOT_COMMITTED'
    return 'UNKNOWN'


def archive_http_probe(token,expected_hash,opener=None):
    """Use only existing bearer auth and read-only endpoints; no login/profile."""
    opener=opener or urllib.request.urlopen
    headers={'Authorization':'Bearer '+token,'Content-Type':'application/json'}
    request=urllib.request.Request('http://127.0.0.1:8765/ready',headers=headers,method='GET')
    with opener(request,timeout=2) as response:
        value=json.load(response)
        need(response.status==200 and value.get('ok') is True and value.get('database')=='ready','archive_database_not_ready')
    request=urllib.request.Request('http://127.0.0.1:8765/v1/archive/config',headers=headers,data=b'{}',method='POST')
    with opener(request,timeout=2) as response:
        value=json.load(response)
        need(response.status==200 and value.get('ok') is True and value.get('config_hash')==expected_hash,'archive_loaded_bundle_mismatch')
    return {'database_ready':True,'loaded_bundle':expected_hash}


def running_release_probe(directory,runner=None,resolver=None):
    # The deployed unit runs with WorkingDirectory at the release root.
    # Check the live process against that exact root, independently of HTTP.
    runner=runner or subprocess.run
    resolver=resolver or (lambda path:path.resolve())
    process=runner(['systemctl','show','goufayu-api.service','--property=MainPID','--value'],capture_output=True,text=True,timeout=3)
    pid=process.stdout.strip()
    need(process.returncode==0 and pid.isdigit() and int(pid)>1,'archive_main_pid_invalid')
    need(resolver(Path('/proc/'+pid+'/cwd'))==directory,'archive_running_wrong_release')
    return True


class Operator:
    def __init__(self,stage):
        self.stage=Path(stage)
        need(self.stage.parent==Path('/tmp') and self.stage.name.startswith('survival-mode-release-20261020-')
             and not self.stage.is_symlink(),'stage_path_refused')
        self.p=json.loads((self.stage/'plan.json').read_bytes())
        need(self.p['archive_baseline']=='20261020-archive-caps-v1'
             and self.p['archive_release']=='20261020-mode-chain-'+self.p['bundle'][:12]+'-v1'
             and self.p['payment_release']=='20261018-checkout-gcoin-v1','release_name_changed')
        self.old=Path('/opt/goufayu/releases')/self.p['archive_baseline']
        self.new=self.old.parent/self.p['archive_release']
        self.pay=Path('/opt/goufayu/payments')/self.p['payment_release']
        need(self.old.name=='20261020-archive-caps-v1'
             and self.new.name=='20261020-mode-chain-'+self.p['bundle'][:12]+'-v1'
             and self.pay.name=='20261018-checkout-gcoin-v1','release_scope_changed')
        self.pins=json.loads((self.stage/'baseline_pins.json').read_bytes())
        for name,expected in self.p['files'].items():
            need(sha(safe(self.stage,name))==expected,'payload_digest_changed:'+name)
        need(self.p['remote_operator_sha256']==sha(self.stage/'operator.py'),'operator_digest_changed')
        need(self.p['no_payment_changes'] is True and self.p['no_player_updates'] is True,'release_scope_changed')
        need(not any('202610200003' in name or '202610200002' in name or '202610170001' in name
             or '/daily_limits.py' in name or '/clear_receipts.py' in name for name in self.p['files']),'applied_schema_or_daily_overlay_refused')
        need(set(self.p['new_function_hashes'])=={LOGIN,SYNC},'mode_function_scope_changed')
        need([m['id'] for m in self.p['mode_migrations']]==['target/202610200004_mode_unlock_chain.sql'],'mode_migration_scope_changed')

    def save(self,name,value):
        path=self.stage/(name+'.json');temporary=self.stage/(name+'.'+secrets.token_hex(8)+'.tmp')
        with temporary.open('xb') as stream:
            temporary.chmod(0o600);stream.write(canonical(value));stream.flush();os.fsync(stream.fileno())
        os.replace(temporary,path)
        fd=os.open(self.stage,os.O_RDONLY|os.O_DIRECTORY)
        try:os.fsync(fd)
        finally:os.close(fd)
        return value

    def connection(self):
        spec=importlib.util.spec_from_file_location('reviewed_mode_payment_deploy',self.pay/'deploy.py')
        module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
        return module.connection()

    def payment_module(self):
        spec=importlib.util.spec_from_file_location('reviewed_mode_payment_backup',self.pay/'deploy.py')
        module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
        return module

    def pointers(self,new=False):
        need(Path('/opt/goufayu/releases/current').resolve(strict=True)==(self.new if new else self.old),'archive_pointer_changed')
        need(Path('/opt/goufayu/payments/current').resolve(strict=True)==self.pay,'payment_pointer_changed')
        need(sha(self.pay/'manifest.json')==self.p['payment_manifest_sha256'],'payment_manifest_changed')
        for name,expected in json.loads((self.pay/'manifest.json').read_bytes()).items():
            need(sha(safe(self.pay,name))==expected,'payment_release_member_changed')

    def manifest(self,root):
        m=json.loads((root/'release_manifest.json').read_bytes())
        for name,value in m['files'].items():need(sha(safe(root,name))==value,'release_member_digest_changed:'+name)
        return m

    def db_state(self,conn):
        need(conn.execute('SELECT current_database()').fetchone()[0]=='goufayu_test','database_scope_changed')
        ledger=dict(conn.execute('SELECT migration_id,sha256 FROM public._goufayu_migrations ORDER BY migration_id'))
        configs={k:digest(canonical(v)) for k,v in conn.execute('SELECT config_hash,config FROM public.archive_config_sets')}
        functions={}
        for signature,definition in conn.execute("SELECT p.oid::regprocedure::text,pg_get_functiondef(p.oid) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND (p.proowner='goufayu_owner'::regrole OR has_function_privilege('goufayu_app',p.oid,'EXECUTE')) AND p.prokind='f' ORDER BY 1"):
            functions['public.'+signature if not signature.startswith('public.') else signature]=digest(definition.encode())
        constraints={name:definition for name,definition in conn.execute("SELECT c.conrelid::regclass::text||':'||c.conname,pg_get_constraintdef(c.oid) FROM pg_constraint c JOIN pg_namespace n ON n.oid=c.connamespace WHERE n.nspname='public' ORDER BY 1")}
        return {'ledger':ledger,'configs':configs,'functions':functions,'constraints':constraints}

    def expected_state(self,new=False):
        state={'ledger':dict(self.p['old_ledger']),'configs':dict(self.p['old_config_rows']),
            'functions':{name:entry['sha256'] for name,entry in self.pins['functions'].items()},'constraints':dict(self.pins['constraints'])}
        if new:
            state['ledger'].update({m['id']:m['sha256'] for m in self.p['mode_migrations']})
            state['configs'][self.p['bundle']]=self.p['configuration_sha256']
            state['functions'].update(self.p['new_function_hashes'])
        return state

    def privileges(self,conn):
        rpc=[r[0] for r in conn.execute("SELECT p.oid::regprocedure::text FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND has_function_privilege('goufayu_app',p.oid,'EXECUTE') ORDER BY 1")]
        flags=list(conn.execute("SELECT rolsuper,rolcreaterole,rolcreatedb,rolreplication,rolbypassrls FROM pg_roles WHERE rolname='goufayu_app'").fetchone())
        members=[r[0] for r in conn.execute("SELECT r.rolname FROM pg_auth_members m JOIN pg_roles r ON r.oid=m.roleid WHERE m.member='goufayu_app'::regrole ORDER BY 1")]
        tables=conn.execute("SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname IN ('public','payments') AND c.relkind IN ('r','p','v','m','f') AND has_table_privilege('goufayu_app',c.oid,'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER')").fetchone()[0]
        create=conn.execute("SELECT has_schema_privilege('goufayu_app','public','CREATE')").fetchone()[0]
        need(dict(rpc=rpc,role_flags=flags,memberships=members,table_access_count=tables,schema_create=create)==self.p['permissions'],'application_privileges_changed')
        need(conn.execute('SELECT catalog_hash FROM payments.catalog_state WHERE singleton').fetchone()[0]==self.p['payment_catalog_hash'],'payment_catalog_changed')
        functions={r[0]:digest(r[1].encode()) for r in conn.execute("SELECT p.oid::regprocedure::text,pg_get_functiondef(p.oid) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='payments' ORDER BY 1")}
        need(functions==self.p['payment_function_hashes'],'payment_functions_changed')
        for signature,expected in self.pins['functions'].items():
            owner,acl,security=conn.execute("SELECT pg_get_userbyid(proowner),proacl::text,prosecdef FROM pg_proc WHERE oid=to_regprocedure(%s)",(signature,)).fetchone()
            need((owner,acl,security)==(expected['owner'],expected['acl'],expected['security_definer']),'function_permissions_changed')

    def baseline(self):
        self.pointers();need(sha(self.old/'release_manifest.json')==self.p['archive_manifest_sha256'],'archive_manifest_changed')
        m=self.manifest(self.old)
        need(json.loads((self.old/'addon/server/bundles/current.json').read_bytes())['hash']==self.p['parent_bundle'],'parent_bundle_changed')
        with self.connection() as conn:
            conn.execute('SET TRANSACTION ISOLATION LEVEL REPEATABLE READ, READ ONLY');conn.execute('SET ROLE goufayu_owner')
            need(self.db_state(conn)==self.expected_state(),'database_baseline_changed');self.privileges(conn);conn.rollback()
        return m

    def backup(self):
        self.baseline()
        folder=Path('/var/backups/goufayu-mode-progression')/self.p['bundle']/self.new.name
        need(not folder.exists() and not folder.is_symlink(),'backup_exists')
        folder.mkdir(mode=0o700,parents=True)
        captured=io.StringIO()
        with contextlib.redirect_stdout(captured):self.payment_module().backup()
        result=json.loads(captured.getvalue().splitlines()[-1]);dump=Path(result['local_backup'])
        need(dump.is_file() and dump.stat().st_size>0 and dump.with_suffix('.sha256').read_text().strip()==sha(dump),'database_backup_invalid')
        source=folder/'archive_sources.tar.gz'
        with tarfile.open(source,'w:gz') as stream:
            stream.add(self.old/'release_manifest.json',arcname='release_manifest.json',recursive=False)
            for name in self.manifest(self.old)['files']:stream.add(safe(self.old,name),arcname=name,recursive=False)
        source.chmod(0o600)
        return self.save('backup',dict(status='MODE_BACKUP_COMPLETE_NOT_DEPLOYED',database_backup=str(dump),database_sha256=sha(dump),source_backup=str(source),source_sha256=sha(source),database_writes=0))

    def backup_verified(self):
        p=json.loads((self.stage/'backup.json').read_bytes())
        need(sha(p['database_backup'])==p['database_sha256'] and sha(p['source_backup'])==p['source_sha256'],'backup_digest_changed')

    def candidate(self):
        need(sha(self.old/'release_manifest.json')==self.p['archive_manifest_sha256'],'archive_baseline_manifest_changed')
        old=self.manifest(self.old);new=self.manifest(self.new)
        need(new['files']=={**old['files'],**self.p['archive_files']},'new_release_file_scope_changed')
        need(new['release']==self.new.name and new['archive_bundle']==self.p['bundle'],'candidate_metadata_changed')
        need(sha(self.new/'addon/server/bundles'/self.p['bundle']/'bundle.json')==self.p['bundle'],'candidate_bundle_changed')
        for name in self.p['archive_files']:
            if name.endswith('.py'):compile((self.new/name).read_text('utf-8'),name,'exec')
        # Every baseline catalog/leaderboard/API/old-hash byte is copied intact
        # unless its exact path appears in the reviewed mode-only allowlist.
        return new

    def prepare(self):
        original=self.baseline();self.backup_verified()
        need(not self.new.exists() and not self.new.is_symlink(),'immutable_release_exists')
        self.new.mkdir(mode=0o755)
        for name in original['files']:
            source=safe(self.old,name);target=safe(self.new,name);target.parent.mkdir(parents=True,exist_ok=True)
            shutil.copyfile(source,target);target.chmod(source.stat().st_mode&0o777)
        need((self.old/'.venv').is_dir(),'archive_venv_missing')
        (self.new/'.venv').symlink_to(self.old/'.venv',target_is_directory=True)
        for name in self.p['archive_files']:
            target=safe(self.new,name);target.parent.mkdir(parents=True,exist_ok=True)
            shutil.copyfile(safe(self.stage/'archive',name),target);target.chmod(0o644)
        m=copy.deepcopy(original);m['files'].update(self.p['archive_files']);m.update(release=self.new.name,archive_bundle=self.p['bundle'],
            mode_chain_parent=self.p['parent_bundle'],mode_chain_baseline_release=self.old.name,
            mode_chain_changed_backend_files=sorted(n for n in self.p['archive_files'] if n.startswith('backend/')),
            mode_chain_migrations={entry['id']:entry['sha256'] for entry in self.p['mode_migrations']})
        (self.new/'release_manifest.json').write_bytes(json.dumps(m,ensure_ascii=False,indent=2).encode()+b'\n')
        self.candidate();self.pointers()
        return self.save('prepared',dict(status='MODE_PREPARED_NOT_ACTIVATED',bundle=self.p['bundle'],database_writes=0))

    def validate(self):
        self.baseline();self.backup_verified();self.candidate()
        need(json.loads((self.stage/'verification/mode_only.json').read_bytes())['status']=='PASS','isolated_http_checks_missing')
        return self.save('validated',dict(status='MODE_VALIDATED_NOT_ACTIVATED',bundle=self.p['bundle'],database_writes=0,validation='sealed local PG/HTTP + live read-only pins + immutable release hashes'))

    def admit(self):
        from psycopg.types.json import Jsonb
        config=json.loads((self.stage/'configuration.json').read_bytes())
        with self.connection() as conn:
            conn.execute('SET TRANSACTION ISOLATION LEVEL REPEATABLE READ')
            conn.execute("SET LOCAL lock_timeout='5s'");conn.execute("SET LOCAL statement_timeout='90s'");conn.execute('SET ROLE goufayu_owner')
            conn.execute('LOCK TABLE public._goufayu_migrations IN EXCLUSIVE MODE')
            conn.execute('LOCK TABLE public.archive_config_sets IN SHARE ROW EXCLUSIVE MODE')
            need(self.db_state(conn)==self.expected_state(),'database_changed_before_admission');self.privileges(conn)
            for migration in self.p['mode_migrations']:
                raw=safe(self.stage,migration['file']).read_bytes();need(digest(raw)==migration['sha256'],'mode_sql_changed')
                conn.execute(sql_body(raw))
                conn.execute('INSERT INTO public._goufayu_migrations(migration_id,sha256) VALUES(%s,%s)',(migration['id'],migration['sha256']))
            need(conn.execute("SELECT encode(sha256(convert_to(%s::jsonb::text,'UTF8')),'hex')",(Jsonb(config),)).fetchone()[0]==self.p['configuration_jsonb_sha256'],'configuration_postgres_digest_changed')
            conn.execute((self.stage/'archive_sync_candidate.sql').read_text('utf-8'))
            need(conn.execute('SELECT public.archive_sync_config(%s,%s)',(self.p['bundle'],Jsonb(config))).fetchone()[0].get('ok') is True,'mode_configuration_registration_failed')
            need(self.db_state(conn)==self.expected_state(True),'post_admission_state_changed');self.privileges(conn)
            self.save('commit_intent',dict(status='MODE_SCHEMA_COMMIT_INTENT',bundle=self.p['bundle'],migrations=self.p['mode_migrations'],no_player_updates=True))
            conn.commit()

    def resolve_commit(self):
        with self.connection() as conn:
            conn.execute('SET TRANSACTION ISOLATION LEVEL REPEATABLE READ, READ ONLY');conn.execute('SET ROLE goufayu_owner')
            state=self.db_state(conn);self.privileges(conn);conn.rollback()
        return outcome(state,self.expected_state(),self.expected_state(True))

    def systemctl(self,action):
        need(action in ('stop','start'),'unsupported_service_action')
        p=subprocess.run(['systemctl',action,'goufayu-api.service'],capture_output=True,timeout=45)
        need(p.returncode==0,'archive_service_'+action+'_failed')

    def switch(self,target):
        need(target in (self.old,self.new),'unsafe_pointer_target')
        temporary=self.old.parent/('current.mode-release.'+secrets.token_hex(6))
        temporary.symlink_to(target,target_is_directory=True);os.replace(temporary,self.old.parent/'current')

    def health(self,new=False):
        directory=self.new if new else self.old
        expected_hash=self.p['bundle'] if new else self.p['parent_bundle']
        spec=importlib.util.spec_from_file_location('reviewed_mode_health_environment',directory/'deploy/manage.py')
        module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
        token=module.read_environment(Path('/etc/goufayu/api.env'))['FISHING_API_TOKEN']
        until=time.monotonic()+15
        while time.monotonic()<until:
            try:
                state=archive_http_probe(token,expected_hash)
                running_release_probe(directory)
                with urllib.request.urlopen('http://127.0.0.1:8766/health',timeout=1) as response:
                    need(response.status==200 and json.load(response).get('ok') is True,'payment_health_not_ready')
                return {**state,'running_release_matches':True,'payment_healthy':True}
            except Exception:time.sleep(.5)
        raise RuntimeError('mode_service_health_failed')

    def activate(self):
        self.baseline();self.backup_verified();self.candidate()
        need(json.loads((self.stage/'validated.json').read_bytes())['bundle']==self.p['bundle'],'validated_plan_changed')
        self.systemctl('stop')
        try:
            self.pointers();self.admit();self.switch(self.new);self.systemctl('start');self.verify(save=False)
        except Exception:
            self.systemctl('stop')
            try:state=self.resolve_commit()
            except Exception:state='UNKNOWN'
            if state=='UNKNOWN':
                self.save('recovery',dict(status='MODE_COMMIT_OUTCOME_UNKNOWN_ARCHIVE_STOPPED',bundle=self.p['bundle'],payment_unchanged=True))
                raise RuntimeError('mode_commit_outcome_unknown_archive_stopped') from None
            if Path('/opt/goufayu/releases/current').resolve()==self.new:self.switch(self.old)
            self.systemctl('start');self.health()
            self.save('rollback',dict(status='OLD_ARCHIVE_RESTORED',database_state=state,additive_mode_schema_retained=state=='COMMITTED',player_data_reverted=False,payment_unchanged=True))
            raise RuntimeError('mode_activation_failed_old_archive_restored') from None
        return self.save('activated',dict(status='MODE_RELEASE_ACTIVATED',bundle=self.p['bundle'],archive_release=self.new.name,player_updates=0,payment_unchanged=True))

    def verify(self,save=True):
        self.pointers(True);self.candidate();health=self.health(new=True)
        with self.connection() as conn:
            conn.execute('SET TRANSACTION ISOLATION LEVEL REPEATABLE READ, READ ONLY');conn.execute('SET ROLE goufayu_owner')
            need(self.db_state(conn)==self.expected_state(True),'activated_database_state_changed');self.privileges(conn);conn.rollback()
        result=dict(status='MODE_RELEASE_VERIFIED',bundle=self.p['bundle'],archive_release=self.new.name,payment_release=self.pay.name,payment_unchanged=True,player_updates=0,health=health)
        return self.save('verified',result) if save else result

    def rollback(self):
        self.pointers(True);self.candidate();self.backup_verified()
        need(self.resolve_commit()=='COMMITTED','mode_database_state_unknown')
        self.systemctl('stop');self.switch(self.old);self.systemctl('start');self.health()
        # Mode schemas/counters are additive. Restoring a snapshot or narrowing
        # the mode constraint could discard a newly earned cold/scourge session.
        return self.save('rollback',dict(status='OLD_ARCHIVE_RESTORED_ADDITIVE_MODE_SCHEMA_RETAINED',player_data_reverted=False,payment_unchanged=True,game_hash_rollback_required_separately=True))


if globals().get('MODE') in {'backup','prepare','validate','activate','verify','rollback'}:
    operator=Operator(STAGE)
    result=operator.verify(save=False) if MODE=='verify' else getattr(operator,MODE)()
    print(json.dumps(result,ensure_ascii=False))
