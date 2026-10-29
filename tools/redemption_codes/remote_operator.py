"""Additive redemption deployment; immutable parent and payment process are pinned."""
from pathlib import Path
import contextlib
import hashlib
import importlib.util
import io
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
def need(value, code):
    if not value: raise RuntimeError(code)

def sql_body(raw):
    text = raw.decode('utf-8-sig')
    start = re.match(r'\A(?:\s|--[^\n]*(?:\n|$))*begin\s*;', text, re.I)
    end = re.search(r'\bcommit\s*;\s*\Z', text, re.I)
    need(start and end, 'migration_wrapper_invalid')
    return text[start.end():end.start()]

class Operator:
    def __init__(self, stage):
        self.stage = Path(stage)
        need(self.stage.parent == Path('/root/goufayu_upload') and not self.stage.is_symlink(), 'stage_invalid')
        self.plan = json.loads((self.stage/'plan.json').read_bytes())
        p = self.plan
        for key in ('parent_release','release','payment_release'):
            need(re.fullmatch(r'[A-Za-z0-9_.-]{1,96}', p[key]) and p[key] != 'current', 'release_id_invalid')
        self.current = Path('/opt/goufayu/releases/current')
        self.old = self.current.parent/p['parent_release']
        self.new = self.current.parent/p['release']
        self.pay = Path('/opt/goufayu/payments')/p['payment_release']
        sys.path.insert(0, str(self.pay))
        from deploy import connection, backup
        self.connect, self.backup = connection, backup
        for name, digest in p['payload'].items():
            relative = Path(name)
            need(not relative.is_absolute() and '..' not in relative.parts, 'payload_path_invalid')
            need(sha((self.stage/name).read_bytes()) == digest, 'payload_changed')

    def save(self, name, value):
        target=self.stage/(name+'.json')
        need(not target.is_symlink(), 'report_symlink')
        target.write_text(json.dumps(value, ensure_ascii=False, indent=2)+'\n');target.chmod(0o600)
        return value

    def payment_pin(self):
        need(Path('/opt/goufayu/payments/current').resolve() == self.pay, 'payment_pointer_changed')
        need(subprocess.check_output(['systemctl','show','--property=MainPID','--value','goufayu-payment.service'],text=True).strip()
             == self.plan['payment_pid'], 'payment_process_changed')

    def verify_manifest(self, root):
        manifest=json.loads((root/'release_manifest.json').read_bytes())
        for name,digest in manifest['files'].items():
            relative=Path(name)
            need(not relative.is_absolute() and '..' not in relative.parts, 'manifest_path_invalid')
            target=root/relative
            need(not target.is_symlink() and target.resolve().is_relative_to(root), 'manifest_symlink')
            need(sha(target.read_bytes())==digest, 'manifest_file_changed')
        return manifest

    def baseline(self, conn):
        self.payment_pin()
        need(self.current.resolve()==self.old, 'parent_release_changed')
        need(sha((self.old/'release_manifest.json').read_bytes())==self.plan['parent_manifest_sha256'], 'parent_manifest_changed')
        need(conn.info.dbname=='goufayu_test', 'live_database_scope_invalid')
        ledger=dict(conn.execute('SELECT migration_id,sha256 FROM public._goufayu_migrations'))
        need(ledger==self.plan['ledger'], 'migration_baseline_changed')
        functions={s:sha(d.encode())for s,d in conn.execute("SELECT p.oid::regprocedure::text,pg_get_functiondef(p.oid) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public'")}
        need(functions==self.plan['functions'], 'function_baseline_changed')
        need(conn.execute('SELECT count(*) FROM public.archive_operations WHERE NOT done').fetchone()[0]==0, 'pending_archive_work')

    def rows(self, conn):
        from psycopg import sql
        return {s+'.'+t:conn.execute(sql.SQL("SELECT count(*),md5(coalesce(string_agg(to_jsonb(t)::text,chr(10) ORDER BY to_jsonb(t)::text),'')) FROM {}.{} t").format(sql.Identifier(s),sql.Identifier(t))).fetchone()
                for s,t in conn.execute("SELECT schemaname,tablename FROM pg_tables WHERE schemaname IN ('public','payments') ORDER BY 1,2").fetchall()}

    def apply(self, conn):
        from psycopg.types.json import Jsonb
        conn.execute('SET LOCAL ROLE goufayu_owner')
        conn.execute('SELECT pg_advisory_xact_lock(719232014021)')
        before=self.rows(conn)
        raw=(self.stage/'migration.sql').read_bytes()
        conn.execute(sql_body(raw))
        conn.execute('INSERT INTO public._goufayu_migrations(migration_id,sha256) VALUES(%s,%s)',
                     ('target/202610290002_redemption_codes.sql',sha(raw)))
        registry=json.loads((self.stage/'codes.json').read_bytes())
        for code in registry['codes']:
            conn.execute('INSERT INTO public.redemption_codes(code_id,code_hash,label,rewards,enabled,starts_at,expires_at,max_redemptions) '
                'VALUES(%s,%s,%s,%s,%s,coalesce(%s::timestamptz,clock_timestamp()),%s::timestamptz,%s)',
                (code['code_id'],code['code_hash'],code['label'],Jsonb(code['rewards']),code['enabled'],
                 code['starts_at'],code['expires_at'],code['max_redemptions']))
        after=self.rows(conn)
        need(all(after.get(k)==v for k,v in before.items() if k!='public._goufayu_migrations'), 'existing_rows_changed')
        functions={s:sha(d.encode())for s,d in conn.execute("SELECT p.oid::regprocedure::text,pg_get_functiondef(p.oid) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public'")}
        need(all(functions.get(s)==digest for s,digest in self.plan['functions'].items()), 'old_function_changed')
        need(set(functions)-set(self.plan['functions'])=={
            'redemption_prepare(text,text,text,text,text)',
            'redemption_commit(text,text,bigint,jsonb,jsonb,jsonb,jsonb)'}, 'unexpected_new_function')
        return {'codes':len(registry['codes']),'original_rows_unchanged':True,'existing_sql_functions_unchanged':True}

    def prepare(self):
        self.verify_manifest(self.old)
        with self.connect() as conn:
            conn.execute('SET TRANSACTION READ ONLY');self.baseline(conn);conn.rollback()
        need(not self.new.exists(), 'candidate_release_exists')
        manifest=json.loads((self.old/'release_manifest.json').read_bytes())
        originals={**manifest['files'],**self.plan['all_backend_hashes']}
        self.new.mkdir(mode=0o755)
        for name,digest in originals.items():
            source=self.old/name;target=self.new/name
            need(not source.is_symlink() and sha(source.read_bytes())==digest,'source_copy_drift')
            target.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(source,target)
            target.chmod(source.stat().st_mode & 0o777)
        (self.new/'.venv').symlink_to(self.old/'.venv',target_is_directory=True)
        manifest['files']=originals
        for name,digest in self.plan['overlay'].items():
            source=self.stage/'overlay'/name;target=self.new/name
            need(not target.is_symlink() and target.resolve().is_relative_to(self.new), 'overlay_path_invalid')
            target.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(source,target)
            need(sha(target.read_bytes())==digest,'overlay_changed');manifest['files'][name]=digest
        manifest.update(release=self.plan['release'],previous_release=self.old.name,
                        redemption_codes=True,redemption_parent=self.old.name,redemption_migration='target/202610290002_redemption_codes.sql')
        (self.new/'release_manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,sort_keys=True,indent=2)+'\n')
        self.verify_manifest(self.new)
        with contextlib.redirect_stdout(io.StringIO()) as capture: self.backup()
        record=json.loads(capture.getvalue().splitlines()[-1]);backup=Path(record['local_backup'])
        need(backup.is_file() and backup.parent==Path('/var/backups/goufayu-payment'),'backup_invalid')
        return self.save('prepared',{'ok':True,'release':self.new.name,'backup':str(backup),'backup_sha256':sha(backup.read_bytes()),
                                     'live_database_modified':False,'payment_untouched':True})

    def validate_clone(self):
        import psycopg
        from psycopg import sql
        saved=json.loads((self.stage/'prepared.json').read_bytes());backup=Path(saved['backup'])
        need(sha(backup.read_bytes())==saved['backup_sha256'],'backup_changed')
        clone='goufayu_redeem_clone_'+secrets.token_hex(6)
        with self.connect() as admin:
            admin.rollback();admin.autocommit=True
            params=admin.info.get_parameters();password=admin.info.password
            for key in ('dbname','password','service','passfile'):params.pop(key,None)
            admin.execute(sql.SQL('CREATE DATABASE {} OWNER goufayu_owner TEMPLATE template0').format(sql.Identifier(clone)))
            admin.execute(sql.SQL('REVOKE ALL ON DATABASE {} FROM PUBLIC').format(sql.Identifier(clone)))
            admin.execute(sql.SQL('GRANT CONNECT ON DATABASE {} TO goufayu_app,goufayu_migrator').format(sql.Identifier(clone)))
        raw=backup.read_bytes()
        schema=subprocess.run(['podman','exec','-i','goufayu-db','pg_restore','--schema-only','--file=-'],input=raw,capture_output=True,timeout=45)
        need(schema.returncode==0,'backup_schema_read_failed')
        creates_public=bool(re.search(r'^CREATE SCHEMA (?:public|"public");\s*$',schema.stdout.decode('utf-8','replace'),re.M))
        def connect():return psycopg.connect(**params,password=password,dbname=clone)
        with connect() as empty:
            count=empty.execute("SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname NOT LIKE 'pg_%' AND n.nspname<>'information_schema'").fetchone()[0]
            need(empty.info.dbname==clone and count==0,'clone_not_empty')
            if creates_public:empty.execute('DROP SCHEMA public')
        args=['podman','exec','-i','--env','PGPASSWORD','--env','PGHOST=127.0.0.1','--env','PGPORT=5432','goufayu-db','pg_restore',
              '--username',params['user'],'--dbname',clone,'--role=goufayu_owner','--no-owner','--no-acl','--single-transaction','--exit-on-error']
        restored=subprocess.run(args,input=raw,capture_output=True,env={**os.environ,'PGPASSWORD':password},timeout=120)
        need(restored.returncode==0,'clone_restore_failed')
        with connect() as conn:
            conn.execute('REVOKE ALL ON ALL TABLES IN SCHEMA public FROM PUBLIC,goufayu_app,anon,authenticated,service_role')
            conn.execute('REVOKE ALL ON ALL SEQUENCES IN SCHEMA public FROM PUBLIC,goufayu_app,anon,authenticated,service_role')
            conn.execute('REVOKE ALL ON ALL FUNCTIONS IN SCHEMA public FROM PUBLIC,goufayu_app,anon,authenticated,service_role')
            conn.execute('REVOKE ALL ON SCHEMA public FROM PUBLIC,goufayu_app,anon,authenticated,service_role')
            conn.execute('GRANT USAGE ON SCHEMA public TO goufayu_app')
            for signature in self.plan['app_rpcs']:
                need(re.fullmatch(r'[a-z_]+\([a-z0-9_, ]*\)',signature),'rpc_signature_invalid')
                conn.execute('GRANT EXECUTE ON FUNCTION public.'+signature+' TO goufayu_app')
            applied=self.apply(conn)
        spec=importlib.util.spec_from_file_location('redemption_database_checks',self.stage/'database_checks.py')
        module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
        checks=module.run(connect,self.new,json.loads((self.stage/'codes.json').read_bytes()))
        return self.save('validated',{'ok':True,'database':clone,'checks':checks,**applied,'live_database_modified':False})

    def control(self, action):
        need(action in ('start','stop'),'control_invalid')
        need(subprocess.run(['systemctl',action,'goufayu-api.service'],capture_output=True,timeout=40).returncode==0,'api_control_failed')

    def switch(self, target, expected):
        need(target in (self.old,self.new) and self.current.resolve()==expected,'release_pointer_changed')
        temporary=self.current.with_name('current.redeem.'+secrets.token_hex(6));temporary.symlink_to(target,target_is_directory=True)
        os.replace(temporary,self.current)

    def health(self):
        import shlex
        env={}
        for line in Path('/etc/goufayu/api.env').read_text().splitlines():
            if line and not line.startswith('#'):
                k,v=line.split('=',1);env[k]=''.join(shlex.split(v))
        for attempt in range(40):
            try:
                for port in (8765,8766):
                    with urllib.request.urlopen('http://127.0.0.1:'+str(port)+'/health',timeout=2) as r:need(json.load(r).get('ok'),'health_unready')
                headers={'Authorization':'Bearer '+env['FISHING_API_TOKEN']}
                with urllib.request.urlopen(urllib.request.Request('http://127.0.0.1:8765/ready',headers=headers),timeout=5) as r:need(json.load(r).get('database')=='ready','database_not_ready')
                self.payment_pin();return
            except Exception:
                if attempt==39:raise RuntimeError('candidate_health_unready') from None
                time.sleep(.5)

    def activate(self):
        need(json.loads((self.stage/'validated.json').read_bytes())['ok'],'clone_validation_required')
        with self.connect() as conn:
            conn.execute('SET TRANSACTION READ ONLY');self.baseline(conn);conn.rollback()
        self.control('stop');committed=False
        try:
            with self.connect() as conn:
                conn.execute('SET TRANSACTION ISOLATION LEVEL REPEATABLE READ');self.baseline(conn);result=self.apply(conn)
            committed=True;self.switch(self.new,self.old);self.control('start');self.health()
        except Exception:
            # No player writes are made by this deployment. Preserve all data;
            # if startup fails, the old transport can run after revoking only
            # the two additive RPC privileges, provided no new work is pending.
            observed=self.current.resolve()
            if observed in (self.old,self.new):
                self.control('stop')
                if committed:
                    with self.connect() as conn:
                        need(conn.execute("SELECT count(*) FROM public.archive_operations WHERE NOT done AND command->>'kind'='redemption_redeem'").fetchone()[0]==0,'new_pending_work_requires_recovery')
                        conn.execute('REVOKE ALL ON FUNCTION public.redemption_prepare(text,text,text,text,text),public.redemption_commit(text,text,bigint,jsonb,jsonb,jsonb,jsonb) FROM goufayu_app')
                if observed==self.new:self.switch(self.old,self.new)
                self.control('start')
            raise
        return self.save('activated',{'ok':True,'release':self.new.name,'payment_untouched':True,**result})

    def verify(self):
        need(self.current.resolve()==self.new,'candidate_not_active');self.verify_manifest(self.new);self.health()
        with self.connect() as conn:
            conn.execute('SET TRANSACTION READ ONLY')
            count=conn.execute('SELECT count(*) FROM public.redemption_codes').fetchone()[0]
            need(count==len(json.loads((self.stage/'codes.json').read_bytes())['codes']),'registered_codes_mismatch')
            conn.rollback()
        return self.save('verified',{'ok':True,'release':self.new.name,'codes':count,'payment_untouched':True,
            'old_archive_bundle_preserved':self.plan['bundle'],'real_player_redemption':False})

    def dispatch(self, mode):
        import fcntl
        with Path('/var/lock/survival_archive_release.lock').open('a') as lock:
            try:fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
            except BlockingIOError:raise RuntimeError('another_release_action_running') from None
            return {'prepare':self.prepare,'validate':self.validate_clone,'activate':self.activate,'verify':self.verify}[mode]()
