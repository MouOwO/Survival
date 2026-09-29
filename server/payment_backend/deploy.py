"""Explicit isolated payment deployment. Existing game service is not restarted."""
import configparser
from datetime import datetime,timezone
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import pwd
import secrets
import shlex
import subprocess
import sys
import time
import urllib.request

ROOT=Path(__file__).resolve().parent
BASE=Path('/opt/goufayu/payments')
CONFIG=Path('/etc/goufayu-payment')
GAME=Path('/opt/goufayu/releases/current')


def run(args,timeout=60):
    result=subprocess.run([str(x) for x in args],capture_output=True,timeout=timeout)
    if result.returncode:raise RuntimeError('command_failed:'+str(args[0]))
    return result.stdout.decode('utf-8','replace').strip()


def write(path,data,mode=0o600,gid=0):
    path=Path(path);path.parent.mkdir(parents=True,exist_ok=True)
    if path.is_symlink():raise RuntimeError('symlink_refused')
    temporary=path.with_name(path.name+'.new')
    with open(temporary,'w',encoding='utf-8') as stream:
        os.chmod(temporary,mode);os.chown(temporary,0,gid)
        stream.write(data);stream.flush();os.fsync(stream.fileno())
    os.replace(temporary,path)


def game_env():
    values={}
    for line in Path('/etc/goufayu/api.env').read_text().splitlines():
        if line and not line.startswith('#'):
            name,value=line.split('=',1);values[name]=''.join(shlex.split(value))
    return values


def connection():
    import psycopg
    os.environ['PGSERVICEFILE']='/etc/goufayu/pg_service.conf'
    return psycopg.connect(service='goufayu_admin',passfile='/etc/goufayu/admin.pgpass')


def health():
    with urllib.request.urlopen('http://127.0.0.1:8765/health',timeout=5) as r:assert r.status==200
    return run(['systemctl','show','goufayu-api.service','--property=MainPID','--value'])


def prepare():
    if ROOT.parent!=BASE or ROOT.name=='current':raise RuntimeError('named_payment_release_required')
    manifest=json.loads((ROOT/'manifest.json').read_text())
    for name,digest in manifest.items():
        if Path(name).is_absolute() or '..' in Path(name).parts:raise RuntimeError('manifest_path_invalid')
        if hashlib.sha256((ROOT/name).read_bytes()).hexdigest()!=digest:raise RuntimeError('manifest_mismatch')
    try:account=pwd.getpwnam('goufayu-payment')
    except KeyError:
        run(['useradd','--system','--no-create-home','--shell','/sbin/nologin','goufayu-payment'])
        account=pwd.getpwnam('goufayu-payment')
    CONFIG.mkdir(mode=0o750,exist_ok=True);os.chown(CONFIG,0,account.pw_gid);os.chmod(CONFIG,0o750)
    (CONFIG/'wechat').mkdir(mode=0o700,exist_ok=True)
    if not (ROOT/'.venv/bin/python').exists():run(['python3.11','-m','venv',ROOT/'.venv'])
    run([ROOT/'.venv/bin/python','-m','pip','install','--disable-pip-version-check','-r',ROOT/'payment_backend/requirements.txt'],timeout=240)
    print(json.dumps({'phase':'prepared','keys_directory':str(CONFIG/'wechat')}))


def activate():
    from psycopg import sql
    from psycopg.conninfo import make_conninfo
    from payment_backend.test_database import run_checks
    from payment_backend.wechat import WeChat
    before=health();account=pwd.getpwnam('goufayu-payment');env=game_env()
    bundle_root=GAME/'addon/server/bundles'
    bundle_hash=json.loads((bundle_root/'current.json').read_text())['hash']
    bundle=json.loads((bundle_root/bundle_hash/'bundle.json').read_text())['configs']
    items=[row for table in bundle.values() for row in table['rows'] if row.get('item_id')=='lottery_monkey_king']
    expected_effects={'hero_attack_armor_reduction':10,'hero_basic_attack_growth':10,'hero_attribute_growth':20,
        'hero_attack_bonus_pct':10,'hero_final_damage_bonus_pct':10,'map_level':1}
    if len(items)!=1 or items[0].get('max_owned')!=1 or dict(zip(items[0]['effect_ids'],map(float,items[0]['effect_values'])))!=expected_effects:
        raise RuntimeError('running_reward_definition_changed')
    map_effects={row['target_field_id']:row['value_per_level'] for row in bundle['map_level_effect_rules']['rows'] if row.get('enabled') is not False}
    if map_effects!={'wall_initial_health':100,'wall_health_regen_per_second':5}:
        raise RuntimeError('running_map_level_effects_changed')
    for name in ('apiclient_key.pem','pub_key.pem','api_v3_key.txt'):
        path=CONFIG/'wechat'/name
        if not path.is_file() or path.is_symlink():raise RuntimeError('payment_key_missing')
        os.chmod(path,0o640);os.chown(path,0,account.pw_gid)
    os.chown(CONFIG/'wechat',0,account.pw_gid);os.chmod(CONFIG/'wechat',0o750)
    WeChat(CONFIG/'wechat')
    password_path=CONFIG/'database-password'
    if not password_path.exists():write(password_path,secrets.token_urlsafe(48)+'\n')
    password=password_path.read_text().strip()
    with connection() as conn:
        assert conn.info.dbname=='goufayu_test'
        role=conn.execute("SELECT rolsuper,rolcreatedb,rolcreaterole,rolreplication,rolbypassrls FROM pg_roles WHERE rolname='goufayu_payment'").fetchone()
        if role is None:conn.execute('CREATE ROLE goufayu_payment LOGIN NOINHERIT NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS')
        elif any(role):raise RuntimeError('privileged_payment_role_refused')
        conn.execute(sql.SQL('ALTER ROLE goufayu_payment PASSWORD {}').format(sql.Literal(password)))
        conn.execute('GRANT CONNECT ON DATABASE goufayu_test TO goufayu_payment')
        exists=conn.execute("SELECT to_regclass('payments.orders') IS NOT NULL").fetchone()[0]
        conn.execute('SET ROLE goufayu_owner')
        if not exists:conn.execute((ROOT/'payment_backend/schema.sql').read_text())
    schema_hash=hashlib.sha256((ROOT/'payment_backend/schema.sql').read_bytes()).hexdigest()
    marker=CONFIG/'schema.sha256'
    if marker.exists() and marker.read_text().strip()!=schema_hash:raise RuntimeError('schema_upgrade_requires_migration')
    write(marker,schema_hash+'\n')
    # Use the running backend's exact stat defaults, and reject a changed SKU.
    sys.path.insert(0,str(GAME/'backend'))
    from fishing_api.gameplay_stats import load_gameplay_stats
    defaults=load_gameplay_stats(GAME/'addon/data/csv/玩家档案系统/player_gameplay_stats.csv')
    conn=connection()
    try:
        conn.execute('SET ROLE goufayu_owner')
        report=run_checks(conn,defaults)
    finally:conn.rollback();conn.close()
    print(json.dumps({'database_test':report}))
    config_path=CONFIG/'config.json'
    if config_path.exists():config=json.loads(config_path.read_text())
    else:config={'allowed_accounts':[],'checkout_key':secrets.token_hex(32)}
    config.update(game_token=env['FISHING_API_TOKEN'],pepper=env['FISHING_ACCOUNT_ID_PEPPER'],
        dsn=make_conninfo(host='127.0.0.1',port=5432,dbname='goufayu_test',user='goufayu_payment',password=password))
    write(config_path,json.dumps(config)+'\n',0o640,account.pw_gid)
    current=BASE/'current'
    if current.exists() and not current.is_symlink():raise RuntimeError('unexpected_current_directory')
    temporary=BASE/'current.new';temporary.symlink_to(ROOT);os.replace(temporary,current)
    unit='''[Unit]
Description=Goufayu verified WeChat test payments
After=network-online.target goufayu-db.service
Requires=goufayu-db.service
[Service]
User=goufayu-payment
Group=goufayu-payment
WorkingDirectory=/opt/goufayu/payments/current
Environment=PYTHONUNBUFFERED=1 PYTHONDONTWRITEBYTECODE=1
ExecStart=/opt/goufayu/payments/current/.venv/bin/python -m payment_backend.service
Restart=on-failure
RestartSec=5
UMask=0077
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=true
PrivateTmp=true
PrivateDevices=true
ProtectKernelTunables=true
ProtectKernelModules=true
ProtectControlGroups=true
RestrictSUIDSGID=true
RestrictAddressFamilies=AF_UNIX AF_INET AF_INET6
CapabilityBoundingSet=
TasksMax=64
MemoryMax=256M
LimitNOFILE=1024
[Install]
WantedBy=multi-user.target
'''
    write('/etc/systemd/system/goufayu-payment.service',unit,0o644)
    run(['systemctl','daemon-reload']);run(['systemctl','enable','goufayu-payment.service'])
    run(['systemctl','restart','goufayu-payment.service'])
    for attempt in range(20):
        try:
            with urllib.request.urlopen('http://127.0.0.1:8766/health',timeout=2) as r:assert r.status==200
            break
        except Exception:
            if attempt==19:raise RuntimeError('payment_service_not_ready')
            time.sleep(.5)
    conf=Path('/etc/nginx/nginx.conf');old=conf.read_text()
    if '# Managed by survival/server/aliyun/deploy/payment_https.py' not in old:raise RuntimeError('unmanaged_nginx_refused')
    addition='''        # Verified payment routes; all other game APIs remain private.
        location ~ ^/v1/payments/(catalog|create|status|wechat/notify)$ {
            proxy_pass http://127.0.0.1:8766;
            proxy_set_header Host pay.xiaofengnet.com;
            proxy_connect_timeout 3s;
            proxy_read_timeout 30s;
        }
        location ~ ^/checkout(?:/(?:status|qr)|\\.(?:js|css))?$ {
            proxy_pass http://127.0.0.1:8766;
            proxy_set_header Host pay.xiaofengnet.com;
            proxy_read_timeout 10s;
        }
'''
    if '# Verified payment routes' not in old:
        import re
        new=re.sub(r'        # Fail closed.*?        location = /v1/payments/wechat/notify \{.*?\n        \}\n','',old,count=1,flags=re.S)
        if new==old:raise RuntimeError('expected_callback_placeholder_missing')
        new=new.replace('        location / { return 404; }',addition+'        location / { return 404; }')
        write(CONFIG/'nginx.before-payments.conf',old)
        write(conf,new,0o644)
        try:run(['nginx','-t']);run(['systemctl','reload','nginx'])
        except Exception:write(conf,old,0o644);raise
    state_path=Path('/etc/goufayu-payment-https/state.json');state=json.loads(state_path.read_text())
    state.update(phase='payments_ready',config_sha256=hashlib.sha256(conf.read_bytes()).hexdigest())
    write(state_path,json.dumps(state)+'\n')
    backup_unit='''[Unit]
Description=Consistent payment and game database backup
After=goufayu-db.service
[Service]
Type=oneshot
UMask=0077
ExecStart=/opt/goufayu/payments/current/.venv/bin/python /opt/goufayu/payments/current/deploy.py backup
'''
    write('/etc/systemd/system/goufayu-payment-backup.service',backup_unit,0o644)
    write('/etc/systemd/system/goufayu-payment-backup.timer','[Unit]\nDescription=Payment database backup every six hours\n[Timer]\nOnCalendar=*-*-* 00,06,12,18:35:00\nPersistent=true\n[Install]\nWantedBy=timers.target\n',0o644)
    run(['systemctl','daemon-reload']);run(['systemctl','enable','--now','goufayu-payment-backup.timer'])
    backup()
    print(json.dumps({'phase':'payments_ready','test_accounts':len(config['allowed_accounts']),
        'game_backend_pid_unchanged':health()==before,'orders_created':0,'grants_created':0}))


def backup():
    directory=Path('/var/backups/goufayu-payment');directory.mkdir(mode=0o700,parents=True,exist_ok=True)
    path=directory/('game-and-payments-'+datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ')+'.dump')
    if path.exists():raise RuntimeError('backup_already_exists')
    env={**os.environ,'PGSERVICEFILE':'/etc/goufayu/pg_service.conf','PGPASSFILE':'/etc/goufayu/admin.pgpass'}
    args=[str(GAME/'deploy/pg-bin/pg_dump'),'--dbname=service=goufayu_admin','--no-password','--format=custom',
        '--schema=public','--schema=extensions','--schema=payments','--no-owner','--no-acl','--no-publications','--no-subscriptions','--file='+str(path)]
    result=subprocess.run(args,capture_output=True,env=env,timeout=120)
    if result.returncode:raise RuntimeError('payment_backup_failed')
    os.chmod(path,0o600)
    listing=run([GAME/'deploy/pg-bin/pg_restore','--list',path])
    if 'payments orders' not in listing:raise RuntimeError('payment_backup_incomplete')
    write(path.with_suffix('.sha256'),hashlib.sha256(path.read_bytes()).hexdigest()+'\n')
    print(json.dumps({'local_backup':str(path),'includes_game_and_payments':True,'offsite':False}))


if __name__=='__main__':
    if os.geteuid()!=0:raise SystemExit('root_required')
    try:{'prepare':prepare,'activate':activate,'backup':backup}[sys.argv[1]]()
    except Exception as error:
        print(json.dumps({'ok':False,'error_type':type(error).__name__,'error':str(error) if type(error) is RuntimeError else 'deployment_check_failed'}))
        raise SystemExit(1)
