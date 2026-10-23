"""Host-side isolated Workshop test provisioner. Inject MODE/OVERLAY explicitly.

The existing API, database, payment processes and release pointers are pinned
and never restarted or edited. Only a separate namespace is added to HTTPS.
No credentials or database rows are emitted to stdout.
"""
from pathlib import Path
import configparser
import hashlib
import json
import os
import pwd
import re
import secrets
import shutil
import socket
import subprocess
import sys
import time
import urllib.request

BASE = Path('/opt/goufayu-ws4')
CONFIG = Path('/etc/goufayu-ws4')
STATE = Path('/var/lib/goufayu-ws4')
RELEASE = BASE / 'releases/20261023-auth-v1'
SOURCE = Path('/opt/goufayu/releases/20261021-benefits-47accd81d922')
SOURCE_HASH = '39e845fd37a2966bbc57a616e661970a0736a0959ee9b00f2e1caf8ebdbae0fe'
USER = 'goufayu-ws4'
CONTAINER = 'goufayu-ws4-db'
VOLUME = 'goufayu-ws4-data'
ACCOUNTS = '76561198424163156,76561198845461206,76561198104787442,76561198974301984'
sha = lambda raw: hashlib.sha256(raw).hexdigest()


def need(value, code):
    if not value:
        raise RuntimeError(code)


def run(args, *, data=None, timeout=90):
    p = subprocess.run(args, input=data, capture_output=True, timeout=timeout)
    need(p.returncode == 0, 'host_command_failed:' + Path(args[0]).name)
    return p.stdout


def private(path, raw, *, group=0, mode=0o600):
    need(not path.is_symlink(), 'private_path_symlink')
    with path.open('xb') as f:
        f.write(raw)
        f.flush()
        os.fsync(f.fileno())
    path.chmod(mode)
    os.chown(path, 0, group)


def database_command(container, arguments, password_file, *, data=b'', timeout=120):
    # Password travels only through a private stdin pipe, never argv/logs.
    command=['podman','exec','-i',container,'/bin/sh','-c',
             'IFS= read -r PGPASSWORD; export PGPASSWORD; exec "$@"','ws4-db',*arguments]
    return run(command,data=password_file.read_bytes().strip()+b'\n'+data,timeout=timeout)


def baseline():
    need(Path('/opt/goufayu/releases/current').resolve() == SOURCE, 'production_release_changed')
    need(sha((SOURCE / 'release_manifest.json').read_bytes()) == SOURCE_HASH, 'production_manifest_changed')
    result = {'archive_release': SOURCE.name, 'archive_manifest_sha256': SOURCE_HASH}
    for service in ('goufayu-api.service', 'goufayu-payment.service', 'goufayu-db.service'):
        need(run(['systemctl','is-active',service]).strip() == b'active', 'existing_service_not_active')
        result[service] = run(['systemctl','show',service,'--property=MainPID','--value']).decode().strip()
    result['payment_release'] = str(Path('/opt/goufayu/payments/current').resolve())
    return result


def unchanged():
    need(json.loads((STATE / 'baseline.json').read_bytes()) == baseline(), 'existing_process_or_release_changed')


def prepare():
    before = baseline()
    for root in (BASE, CONFIG, STATE):
        need(not root.exists() and not root.is_symlink(), 'isolated_path_already_exists')
    for port in (15432,18765):
        with socket.socket() as sock:
            need(sock.connect_ex(('127.0.0.1',port)) != 0, 'isolated_port_occupied')
    manifest = json.loads((SOURCE / 'release_manifest.json').read_bytes())
    for name,digest in manifest['files'].items():
        path = SOURCE / name
        need(path.is_relative_to(SOURCE) and not path.is_symlink() and sha(path.read_bytes()) == digest,
             'source_release_file_changed')
    try:
        pwd.getpwnam(USER)
        raise RuntimeError('isolated_account_exists')
    except KeyError:
        run(['useradd','--system','--user-group','--home-dir',str(STATE),'--shell','/sbin/nologin',USER])
    user = pwd.getpwnam(USER)
    need(user.pw_uid > 0 and user.pw_gid > 0, 'invalid_isolated_user')
    for root in (BASE,CONFIG,STATE):
        root.mkdir(mode=0o750)
        os.chown(root,0,user.pw_gid)
    pairing = STATE/'pairing'
    pairing.mkdir(mode=0o770)
    os.chown(pairing,0,user.pw_gid)
    pairing.chmod(0o770)
    private(STATE/'baseline.json',json.dumps(before).encode())
    RELEASE.mkdir(parents=True,mode=0o750)
    for name in manifest['files']:
        source = SOURCE / name
        dest = RELEASE / name
        dest.parent.mkdir(parents=True,exist_ok=True)
        shutil.copyfile(source,dest)
        dest.chmod(source.stat().st_mode & 0o777)
    import base64
    for name,encoded in OVERLAY.items():
        need(name in {'backend/workshop_test/auth.py','backend/workshop_test/run_api.py',
                      'backend/workshop_test/__init__.py','backend/archive_backend/test_access.py'}, 'unexpected_overlay')
        dest = RELEASE / name
        dest.parent.mkdir(parents=True,exist_ok=True)
        dest.write_bytes(base64.b64decode(encoded,validate=True))
    # Reuse installed, verified dependencies without network package installs.
    run(['/usr/bin/python3.11','-m','venv',str(BASE/'.venv')])
    oldsite = next((SOURCE/'.venv/lib').glob('python*/site-packages'))
    newsite = next((BASE/'.venv/lib').glob('python*/site-packages'))
    for item in oldsite.iterdir():
        if item.name.startswith(('psycopg','typing_extensions')):
            if item.is_dir():
                shutil.copytree(item,newsite/item.name,ignore=shutil.ignore_patterns('__pycache__'))
            else:
                shutil.copyfile(item,newsite/item.name)
    run([str(BASE/'.venv/bin/python'),'-B','-c','import psycopg,typing_extensions'])
    image = run(['podman','inspect','goufayu-db','--format','{{.Image}}']).decode().strip()
    if re.fullmatch(r'[a-f0-9]{64}',image):image='sha256:'+image
    need(re.fullmatch(r'sha256:[a-f0-9]{64}',image), 'postgres_image_not_pinned')
    private(CONFIG/'image',image.encode())
    admin_password,app_password = secrets.token_urlsafe(48),secrets.token_urlsafe(48)
    private(CONFIG/'postgres.env',('POSTGRES_DB=goufayu_ws4\nPOSTGRES_PASSWORD='+admin_password+'\n').encode())
    private(CONFIG/'admin-password',admin_password.encode())
    private(CONFIG/'app-password',app_password.encode())
    env = {'FISHING_API_HOST':'127.0.0.1','FISHING_API_PORT':'18765',
           'FISHING_API_TOKEN':secrets.token_urlsafe(48),'FISHING_ACCOUNT_ID_PEPPER':secrets.token_urlsafe(48),
           'FISHING_DATABASE_BACKEND':'postgres','POSTGRES_DSN':
           'postgresql://goufayu_app:'+app_password+'@127.0.0.1:15432/goufayu_ws4',
           'SURVIVAL_ADDON_ROOT':str(RELEASE/'addon'),'SURVIVAL_ARCHIVE_HTTP':'1',
           'ARCHIVE_LUA_PATH':'/usr/bin/lua','PAYMENT_MODE':'test','SURVIVAL_TEST_STEAM_IDS64':ACCOUNTS,
           'POSTGRES_MAX_CONCURRENCY':'4','FISHING_HTTP_MAX_CONCURRENCY':'8',
           'PYTHONDONTWRITEBYTECODE':'1','PYTHONUNBUFFERED':'1'}
    private(CONFIG/'api.env',''.join(k+'='+json.dumps(v)+'\n' for k,v in env.items()).encode(),group=user.pw_gid,mode=0o640)
    private(CONFIG/'pins.json',json.dumps({'workshop_id':'3824360109','sha256':[]}).encode(),group=user.pw_gid,mode=0o640)
    return finish_prepare()


def finish_prepare():
    unchanged()
    need((CONFIG/'api.env').is_file() and not (STATE/'prepared.json').exists(), 'prepare_state_invalid')
    import base64
    for name,encoded in OVERLAY.items():
        need((RELEASE/name).read_bytes()==base64.b64decode(encoded), 'prepared_overlay_changed')
    manifest=json.loads((SOURCE/'release_manifest.json').read_bytes())
    # Only schema is read from the old DB. No production rows or credentials
    # are copied to the new instance or exported to the developer machine.
    schema = database_command('goufayu-db',['pg_dump','-h','127.0.0.1','-U','postgres','-d','goufayu_test',
                  '--schema-only','--no-owner'],Path('/etc/goufayu/postgres-password'))
    private(STATE/'schema.sql',schema)
    roles = database_command('goufayu-db',['psql','-h','127.0.0.1','-U','postgres','-d','goufayu_test','-Atc',
                 "SELECT rolname FROM pg_roles WHERE rolname LIKE 'goufayu_%' ORDER BY rolname"],
                 Path('/etc/goufayu/postgres-password')).decode().splitlines()
    need('goufayu_app' in roles and 'goufayu_migrator' in roles and
         all(re.fullmatch(r'goufayu_[a-z0-9_]+',r) for r in roles), 'schema_roles_invalid')
    private(STATE/'roles.json',json.dumps(roles).encode())
    private(STATE/'prepared.json',json.dumps({'schema_sha256':sha(schema),'source_files':len(manifest['files']),
        'overlay':{n:sha(base64.b64decode(v)) for n,v in OVERLAY.items()},'player_rows_copied':0}).encode())
    unchanged()
    return {'ok':True,'phase':'ISOLATED_CODE_AND_SCHEMA_PREPARED','player_rows_copied':0,'public_enabled':False}


def initialize_database():
    need(not (STATE/'database-ready.json').exists(), 'database_already_initialized')
    need(not run(['podman','volume','ls','--format','{{.Name}}']).decode().splitlines().count(VOLUME), 'volume_exists')
    run(['podman','volume','create',VOLUME])
    run(['podman','create','--name',CONTAINER,'--env-file',str(CONFIG/'postgres.env'),
         '-p','127.0.0.1:15432:5432','-v',VOLUME+':/var/lib/postgresql/data:Z',(CONFIG/'image').read_text()])
    run(['podman','start',CONTAINER])
    deadline = time.monotonic()+60
    while time.monotonic()<deadline:
        ready = subprocess.run(['podman','exec',CONTAINER,'pg_isready','-h','127.0.0.1','-U','postgres','-d','goufayu_ws4'],capture_output=True)
        if ready.returncode==0:break
        time.sleep(1)
    need(ready.returncode==0, 'isolated_database_not_ready')
    finish_database()


def finish_database():
    unchanged()
    need(not (STATE/'database-ready.json').exists(), 'database_already_initialized')
    need(run(['podman','inspect',CONTAINER,'--format','{{.Id}}']) !=
         run(['podman','inspect','goufayu-db','--format','{{.Id}}']), 'isolated_container_required')
    import psycopg
    from psycopg import sql as pgsql
    # Recovery is limited to this newly created, not-yet-exposed empty test
    # database. Refuse to replace any schema containing even one user row.
    with psycopg.connect(host='127.0.0.1',port=15432,user='postgres',
             password=(CONFIG/'admin-password').read_text(),dbname='goufayu_ws4',autocommit=True) as conn:
        need(conn.info.dbname=='goufayu_ws4' and conn.info.port==15432,'isolated_database_required')
        schemas=[row[0] for row in conn.execute("SELECT nspname FROM pg_namespace WHERE nspname NOT LIKE 'pg_%' AND nspname<>'information_schema'")]
        need(set(schemas)<= {'public','payments','extensions'},'unexpected_test_schema')
        tables=conn.execute("SELECT schemaname,tablename FROM pg_tables WHERE schemaname IN ('public','payments','extensions')").fetchall()
        for schema,table in tables:
            count=conn.execute(pgsql.SQL('SELECT count(*) FROM {}.{}').format(pgsql.Identifier(schema),pgsql.Identifier(table))).fetchone()[0]
            need(count==0,'nonempty_test_database_preserved')
        for schema in schemas:
            conn.execute(pgsql.SQL('DROP SCHEMA {} CASCADE').format(pgsql.Identifier(schema)))
        conn.execute('CREATE SCHEMA public')
    roles = json.loads((STATE/'roles.json').read_bytes())
    # The archived schema retains its original ACLs; this Supabase-compatible
    # no-login grant target is needed even though the new DB has no Supabase.
    roles=sorted(set(roles)|{'service_role'})
    statements = []
    for role in roles:
        statements.append("DO $$ BEGIN IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='"+role+"') THEN CREATE ROLE "+role+" NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE; END IF; END $$;")
    statements.append("ALTER ROLE goufayu_app LOGIN PASSWORD '"+(CONFIG/'app-password').read_text()+"';")
    command=['psql','-h','127.0.0.1','-U','postgres','-d','goufayu_ws4','-v','ON_ERROR_STOP=1']
    database_command(CONTAINER,command,CONFIG/'admin-password',data=('\n'.join(statements)+'\n').encode())
    database_command(CONTAINER,command,CONFIG/'admin-password',data=(STATE/'schema.sql').read_bytes())
    # Restored application objects use the dedicated non-login migrator owner,
    # not the new PostgreSQL superuser as SECURITY DEFINER.
    sql=b'''DO $$ DECLARE r record; BEGIN
FOR r IN SELECT p.oid::regprocedure AS signature FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
WHERE n.nspname='public' AND NOT EXISTS(SELECT 1 FROM pg_depend d WHERE d.objid=p.oid AND d.deptype='e')
LOOP EXECUTE 'ALTER FUNCTION '||r.signature||' OWNER TO goufayu_owner'; END LOOP;
FOR r IN SELECT c.relname,c.relkind FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
WHERE n.nspname='public' AND c.relkind IN ('r','S')
LOOP EXECUTE 'ALTER '||(CASE WHEN r.relkind='S' THEN 'SEQUENCE ' ELSE 'TABLE ' END)||quote_ident(r.relname)||' OWNER TO goufayu_owner'; END LOOP;
END $$;
REVOKE ALL ON DATABASE goufayu_ws4 FROM PUBLIC;
GRANT CONNECT ON DATABASE goufayu_ws4 TO goufayu_app,goufayu_migrator;
ALTER SCHEMA public OWNER TO goufayu_owner;
ALTER ROLE goufayu_app NOINHERIT NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS;
GRANT USAGE ON SCHEMA public TO goufayu_app;
'''
    database_command(CONTAINER,command,CONFIG/'admin-password',data=sql)
    restore_ownership()
    private(STATE/'database-ready.json',json.dumps({'database':'goufayu_ws4','port':15432,'rows_copied':0}).encode())
    unchanged()


def harden_database():
    unchanged()
    # This correction adjusts only the new cluster's privilege boundary; it
    # neither recreates schemas nor removes any test rows.
    sql=b'''REVOKE ALL ON DATABASE goufayu_ws4 FROM PUBLIC;
GRANT CONNECT ON DATABASE goufayu_ws4 TO goufayu_app,goufayu_migrator;
ALTER ROLE goufayu_app NOINHERIT NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS;
ALTER SCHEMA public OWNER TO goufayu_owner;
DO $$ DECLARE r record; BEGIN
FOR r IN SELECT p.oid::regprocedure AS signature FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
WHERE n.nspname='public' AND NOT EXISTS(SELECT 1 FROM pg_depend d WHERE d.objid=p.oid AND d.deptype='e')
LOOP EXECUTE 'ALTER FUNCTION '||r.signature||' OWNER TO goufayu_owner'; END LOOP;
FOR r IN SELECT c.relname,c.relkind FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
WHERE n.nspname='public' AND c.relkind IN ('r','S')
LOOP EXECUTE 'ALTER '||(CASE WHEN r.relkind='S' THEN 'SEQUENCE ' ELSE 'TABLE ' END)||quote_ident(r.relname)||' OWNER TO goufayu_owner'; END LOOP;
END $$;'''
    database_command(CONTAINER,['psql','-h','127.0.0.1','-U','postgres','-d','goufayu_ws4','-v','ON_ERROR_STOP=1'],
                     CONFIG/'admin-password',data=sql)
    restore_ownership()
    unchanged()
    return {'ok':True,'phase':'ISOLATED_RPC_PRIVILEGES_HARDENED'}


def restore_ownership():
    # pg_dump --no-owner omits implicit owner privileges. Reproduce only
    # catalog ownership metadata in the new instance, never original rows.
    unchanged()
    query="""SELECT json_build_object(
      'schemas',(SELECT json_agg(json_build_array(nspname,pg_get_userbyid(nspowner))) FROM pg_namespace WHERE nspname IN ('public','payments','extensions')),
      'relations',(SELECT json_agg(json_build_array(n.nspname,c.relname,c.relkind,pg_get_userbyid(c.relowner))) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname IN ('public','payments','extensions') AND c.relkind IN ('r','S','v','m')),
      'functions',(SELECT json_agg(json_build_array(p.oid::regprocedure::text,pg_get_userbyid(p.proowner))) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname IN ('public','payments','extensions') AND p.prokind='f' AND NOT EXISTS(SELECT 1 FROM pg_depend d WHERE d.classid='pg_proc'::regclass AND d.objid=p.oid AND d.deptype='e')))
    """
    raw=database_command('goufayu-db',['psql','-h','127.0.0.1','-U','postgres','-d','goufayu_test','-Atc',query],Path('/etc/goufayu/postgres-password'))
    ownership=json.loads(raw)
    import psycopg
    from psycopg import sql
    def owner(name):
        need(re.fullmatch('goufayu_[a-z0-9_]+|postgres|pg_database_owner',name),'unexpected_owner_role')
        return sql.Identifier(name)
    with psycopg.connect(host='127.0.0.1',port=15432,user='postgres',
              password=(CONFIG/'admin-password').read_text(),dbname='goufayu_ws4') as conn:
        need(conn.info.dbname=='goufayu_ws4' and conn.info.port==15432,'isolated_database_required')
        for schema,role in ownership['schemas']:
            conn.execute(sql.SQL('ALTER SCHEMA {} OWNER TO {}').format(sql.Identifier(schema),owner(role)))
        kinds={'r':'TABLE','S':'SEQUENCE','v':'VIEW','m':'MATERIALIZED VIEW'}
        for schema,name,kind,role in ownership['relations'] or []:
            conn.execute(sql.SQL('ALTER '+kinds[kind]+' {}.{} OWNER TO {}').format(sql.Identifier(schema),sql.Identifier(name),owner(role)))
        for signature,role in ownership['functions'] or []:
            canonical=conn.execute('SELECT to_regprocedure(%s)::text',(signature,)).fetchone()[0]
            need(canonical is not None,'restored_function_missing')
            conn.execute(sql.SQL('ALTER FUNCTION {} OWNER TO {}').format(sql.SQL(canonical),owner(role)))
    unchanged()
    return {'ok':True,'phase':'ISOLATED_SCHEMA_OWNERSHIP_RESTORED','player_rows_copied':0}


def start_service():
    user = pwd.getpwnam(USER)
    for path in RELEASE.rglob('*'):
        if path.is_dir():path.chmod(0o755)
        elif path.is_file():path.chmod(path.stat().st_mode & 0o777 | 0o044)
    RELEASE.chmod(0o755)
    unit='''[Unit]
Description=Survival isolated four-account Workshop archive API
After=network-online.target goufayu-ws4-db.service
Requires=goufayu-ws4-db.service
[Service]
User=goufayu-ws4
Group=goufayu-ws4
WorkingDirectory=/opt/goufayu-ws4/releases/20261023-auth-v1/backend
EnvironmentFile=/etc/goufayu-ws4/api.env
ExecStart=/opt/goufayu-ws4/.venv/bin/python -B -m workshop_test.run_api
Restart=on-failure
RestartSec=5
UMask=0077
NoNewPrivileges=true
PrivateTmp=true
PrivateDevices=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=/var/lib/goufayu-ws4/pairing
RestrictAddressFamilies=AF_UNIX AF_INET AF_INET6
IPAddressDeny=any
IPAddressAllow=localhost
MemoryMax=512M
TasksMax=64
[Install]
WantedBy=multi-user.target
'''
    dbunit='''[Unit]
Description=Isolated PostgreSQL for Survival four-account Workshop test
After=network-online.target
[Service]
Type=simple
ExecStart=/usr/bin/podman start --attach goufayu-ws4-db
ExecStop=/usr/bin/podman stop --time 20 goufayu-ws4-db
Restart=on-failure
TimeoutStopSec=35
[Install]
WantedBy=multi-user.target
'''
    for name,raw in (('goufayu-ws4.service',unit),('goufayu-ws4-db.service',dbunit)):
        private(Path('/etc/systemd/system')/name,raw.encode(),mode=0o644)
    # Hand over only our newly created database to its independent unit.
    run(['podman','stop','--time','20',CONTAINER])
    run(['systemctl','daemon-reload'])
    run(['systemctl','enable','--now','goufayu-ws4-db.service','goufayu-ws4.service'])
    deadline=time.monotonic()+45
    while time.monotonic()<deadline:
        try:
            with urllib.request.urlopen('http://127.0.0.1:18765/health',timeout=2) as r:
                if json.load(r).get('ok') is True:break
        except Exception:time.sleep(1)
    else:raise RuntimeError('isolated_api_unready')
    unchanged()
    return {'ok':True,'phase':'ISOLATED_API_RUNNING_LOOPBACK','pairing_required':True,'public_enabled':False}


def verify_api():
    unchanged()
    original=(CONFIG/'pins.json').read_bytes()
    need(json.loads(original)['sha256']==[], 'initial_verification_requires_unpaired_service')
    key=secrets.token_urlsafe(48)
    digest=sha(key.encode())
    user=pwd.getpwnam(USER)
    def pins(raw):
        temporary=CONFIG/'pins.verify-new'
        private(temporary,raw,group=user.pw_gid,mode=0o640)
        os.replace(temporary,CONFIG/'pins.json')
    def request(account,header=None):
        body=json.dumps({'account_id':account,'match_session_id':'ws4-operator-preflight-20261023'}).encode()
        headers={'Content-Type':'application/json'}
        if header:headers['Authorization']=header
        request=urllib.request.Request('http://127.0.0.1:18765/v1/session/authenticate',data=body,headers=headers)
        try:
            with urllib.request.urlopen(request,timeout=25) as response:return response.status,json.load(response)
        except urllib.error.HTTPError as response:return response.code,json.load(response)
    need(request('885195478')[0]==403,'anonymous_request_accepted')
    need(request('885195478','Bearer '+key)[0]==403,'unregistered_request_accepted')
    pins(json.dumps({'workshop_id':'3824360109','sha256':[digest]}).encode())
    results=[]
    diagnostics=[]
    try:
        for identity in ACCOUNTS.split(','):
            account=str(int(identity)-76561197960265728)
            status,body=request(account,'Bearer '+key)
            results.append(status==200 and body.get('authenticated') is True and body.get('account_id')==account)
            error=body.get('error')
            diagnostics.append({'status':status,'authenticated':body.get('authenticated') is True,
                'account_matches':body.get('account_id')==account,
                'error':error if isinstance(error,str) and re.fullmatch('[a-z_0-9]{1,80}',error) else None})
        status,body=request('42','Bearer '+key)
        need(status==403 and body.get('error')=='test_account_not_allowed','fifth_account_not_rejected')
        if not all(results):
            print(json.dumps({'phase':'ISOLATED_ACCOUNT_DIAGNOSTICS','results':diagnostics}),flush=True)
        need(all(results),'allowed_account_authentication_failed')
    finally:
        pins(original)
    unchanged()
    result={'ok':True,'phase':'FOUR_ACCOUNT_ISOLATED_API_VERIFIED','allowed_accounts':results,
            'anonymous_rejected':True,'unregistered_key_rejected':True,'fifth_account_rejected':True,
            'temporary_test_pin_removed':True,'existing_services_unchanged':True}
    private(STATE/'api-verification.json',json.dumps(result).encode())
    return result


def https_enable():
    unchanged()
    need((STATE/'api-verification.json').is_file(), 'api_acceptance_required')
    output=run(['nginx','-T']).decode()
    candidates=[]
    for name in sorted(set(re.findall(r'^# configuration file (.+):$',output,re.M))):
        path=Path(name)
        if not path.is_file() or path.is_symlink() or not path.is_relative_to('/etc/nginx'):continue
        raw=path.read_text()
        for match in re.finditer(r'\bserver\s*\{',raw):
            depth,quote,comment,escape,index=1,None,False,False,match.end()
            while index<len(raw) and depth:
                c=raw[index]
                if comment:
                    if c=='\n':comment=False
                elif quote:
                    if escape:escape=False
                    elif c=='\\':escape=True
                    elif c==quote:quote=None
                elif c=='#':comment=True
                elif c in ('"',"'"):quote=c
                elif c=='{':depth+=1
                elif c=='}':depth-=1
                index+=1
            body=raw[match.end():index-1]
            if (re.search(r'\bserver_name\s+pay\.xiaofengnet\.com\s*;',body)
                    and re.search(r'\blisten\s+[^;]*\b443\b[^;]*;',body)):
                candidates.append((path,raw,index-1))
    need(len(candidates)==1,'unique_existing_tls_server_required')
    path,raw,close=candidates[0]
    need('/ws4' not in raw and 'goufayu-ws4.locations' not in raw,'ws4_location_already_present')
    locations=Path('/etc/nginx/goufayu-ws4.locations')
    need(not locations.exists(),'ws4_nginx_files_exist')
    rules=r'''
location ~ ^/ws4/v1/(session/(authenticate|login)|profile|lottery/(catalog|snapshot)|archive/(config|command|endless-batch|endless-leaderboard)|online-time/checkpoint|rewards/grant)$ {
    limit_except POST { deny all; }
    client_max_body_size 16k;
    client_body_timeout 10s;
    limit_req zone=goufayu_ws4 burst=30 nodelay;
    rewrite ^/ws4(/v1/.*)$ $1 break;
    proxy_pass http://127.0.0.1:18765;
    proxy_set_header Host $host;
    proxy_set_header Authorization $http_authorization;
    proxy_set_header Connection "";
    proxy_http_version 1.1;
    proxy_connect_timeout 3s;
    proxy_send_timeout 15s;
    proxy_read_timeout 25s;
    access_log off;
}
location /ws4/ { return 404; }
'''
    if (STATE/'nginx.before').exists():
        need((STATE/'nginx.before').read_bytes()==path.read_bytes()
             and (STATE/'nginx-path').read_text()==str(path),'nginx_retry_baseline_changed')
    else:
        private(STATE/'nginx.before',path.read_bytes())
        private(STATE/'nginx-path',str(path).encode())
    private(locations,rules.encode(),mode=0o644)
    metadata=path.stat()
    changed=raw[:close]+'\n    include /etc/nginx/goufayu-ws4.locations;\n'+raw[close:]
    # Keep the zone declaration in the same loaded HTTP configuration. Some
    # hosts include a specific vhost file rather than conf.d/*.conf.
    rate='\nlimit_req_zone $binary_remote_addr zone=goufayu_ws4:10m rate=10r/s;\n'
    http=re.search(r'\bhttp\s*\{',changed)
    changed=(changed[:http.end()]+rate+changed[http.end():] if http else rate+changed).encode()
    temporary=path.with_name(path.name+'.ws4-new')
    private(temporary,changed,group=metadata.st_gid,mode=metadata.st_mode & 0o777)
    os.replace(temporary,path)
    test=subprocess.run(['nginx','-t'],capture_output=True)
    if test.returncode!=0:
        path.write_bytes((STATE/'nginx.before').read_bytes())
        locations.unlink()
        error_path=STATE/'nginx-test-error.txt'
        error_path.write_bytes(test.stderr);error_path.chmod(0o600)
        raise RuntimeError('isolated_nginx_validation_failed_original_restored')
    run(['systemctl','reload','nginx'])
    unchanged()
    private(STATE/'https-enabled.json',json.dumps({'host':'pay.xiaofengnet.com','prefix':'/ws4',
            'upstream':'127.0.0.1:18765','pairing_required':True,'original_nginx_sha256':sha(raw.encode()),
            'changed_nginx_sha256':sha(changed)}).encode())
    return {'ok':True,'phase':'ISOLATED_HTTPS_ENABLED','base_url':'https://pay.xiaofengnet.com/ws4',
            'existing_services_unchanged':True,'pairing_required':True}


def pairing(approve=False):
    unchanged()
    path=STATE/'pairing/pending.json'
    rows=json.loads(path.read_bytes()) if path.is_file() else {}
    now=int(time.time())
    recent={d:t for d,t in rows.items() if re.fullmatch('[a-f0-9]{64}',d) and now-1800<=t<=now}
    if not approve:
        return {'ok':True,'pending':[{'fingerprint':d[:16],'age_seconds':now-t} for d,t in recent.items()],
                'automatic_approval':False}
    need(isinstance(FINGERPRINT,str) and re.fullmatch('[a-f0-9]{16}',FINGERPRINT),'owner_fingerprint_required')
    matches=[d for d in recent if d.startswith(FINGERPRINT)]
    need(len(matches)==1,'unique_recent_owner_fingerprint_required')
    pins=json.loads((CONFIG/'pins.json').read_bytes())
    need(pins['workshop_id']=='3824360109' and len(pins['sha256'])<4,'pins_state_invalid')
    need(matches[0] not in pins['sha256'],'key_already_pinned')
    pins['sha256'].append(matches[0])
    temporary=CONFIG/'pins.approved-new'
    private(temporary,json.dumps(pins).encode(),group=pwd.getpwnam(USER).pw_gid,mode=0o640)
    os.replace(temporary,CONFIG/'pins.json')
    return {'ok':True,'phase':'OWNER_CONFIRMED_SERVER_PINNED','fingerprint':FINGERPRINT,'restart_required':False}


def update_overlay():
    unchanged()
    need(json.loads((CONFIG/'pins.json').read_bytes())['sha256']==[], 'only_unpaired_service_update_allowed')
    import base64
    previous=json.loads((STATE/'prepared.json').read_bytes())
    for name,encoded in OVERLAY.items():
        need(name in previous['overlay'] and sha((RELEASE/name).read_bytes())==previous['overlay'][name],
             'isolated_overlay_changed')
    for name,encoded in OVERLAY.items():
        raw=base64.b64decode(encoded,validate=True)
        target=RELEASE/name
        temporary=target.with_name(target.name+'.update-new')
        private(temporary,raw,mode=0o644)
        os.replace(temporary,target)
        previous['overlay'][name]=sha(raw)
    temporary=STATE/'prepared.update-new'
    private(temporary,json.dumps(previous).encode())
    os.replace(temporary,STATE/'prepared.json')
    (STATE/'pairing').chmod(0o770)
    run(['systemctl','restart','goufayu-ws4.service'])
    unchanged()
    return {'ok':True,'phase':'ISOLATED_UNPAIRED_SERVICE_UPDATED','existing_services_unchanged':True}


def audit():
    unchanged()
    for service in ('goufayu-ws4.service','goufayu-ws4-db.service'):
        need(run(['systemctl','is-active',service]).strip()==b'active','isolated_service_not_active')
    with urllib.request.urlopen('http://127.0.0.1:18765/health',timeout=3) as response:
        need(json.load(response).get('ok') is True,'isolated_health_failed')
    need(run(['nginx','-t']) is not None,'nginx_invalid')
    pins=json.loads((CONFIG/'pins.json').read_bytes())
    return {'ok':True,'phase':'ISOLATED_DEPLOYMENT_AUDITED','existing_services_unchanged':True,
            'independent_api_active':True,'independent_database_active':True,'https_enabled':(STATE/'https-enabled.json').is_file(),
            'four_account_api_verified':(STATE/'api-verification.json').is_file(),'approved_server_keys':len(pins['sha256']),
            'original_player_rows_copied':0,'database':'goufayu_ws4','database_port':15432,'api_port':18765}


def main():
    if MODE=='prepare':result=prepare()
    elif MODE=='finish_prepare':result=finish_prepare()
    elif MODE=='initialize_database':initialize_database();result={'ok':True,'phase':'ISOLATED_DATABASE_READY'}
    elif MODE=='finish_database':finish_database();result={'ok':True,'phase':'ISOLATED_DATABASE_READY'}
    elif MODE=='harden_database':result=harden_database()
    elif MODE=='restore_ownership':result=restore_ownership()
    elif MODE=='start':result=start_service()
    elif MODE=='verify':result=verify_api()
    elif MODE=='https_enable':result=https_enable()
    elif MODE=='pending':result=pairing()
    elif MODE=='approve':result=pairing(approve=True)
    elif MODE=='update_overlay':result=update_overlay()
    elif MODE=='audit':result=audit()
    else:raise RuntimeError('unknown_operator_mode')
    print(json.dumps(result),flush=True)


try:
    main()
except Exception as error:
    import traceback
    print(json.dumps({'ok':False,'error':'isolated_action_failed','type':type(error).__name__,
                      'code':str(error) if isinstance(error,RuntimeError) else 'host_operation_failed',
                      'frames':[{'function':f.name,'line':f.lineno}
                                for f in traceback.extract_tb(error.__traceback__)[-4:]]}),flush=True)
    raise SystemExit(1)
