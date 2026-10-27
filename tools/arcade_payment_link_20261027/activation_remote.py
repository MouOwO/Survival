"""Reviewed fixed WS4 activation. Invoked only with an exact activation capsule."""
import csv
import copy
from decimal import Decimal
import io
import hashlib
import json
import os
from pathlib import Path
try:
    import pwd
except ImportError:  # Planning and pure guard tests also run on Windows.
    pwd = None
import re
import secrets
import shutil
import sqlite3
import stat
import sys
import time
import urllib.request

from remote_review import (SHA, SERVICES, audit, baseline, canonical, command, decode_files,
                           env_values, function_semantics, need, regular, sql, validate_plan)
from remote_review import payment_role_permissions

PAYMENT_USER = 'goufayu-ws4-payment'
PAYMENT_BASE = Path('/opt/goufayu-ws4-payment')
PAYMENT_CONFIG = Path('/etc/goufayu-ws4-payment')
PAYMENT_UNIT = Path('/etc/systemd/system/goufayu-ws4-payment.service')
PAYMENT_LOCATIONS = Path('/etc/nginx/goufayu-ws4-payment.locations')
PWA_BASE = Path('/opt/goufayu-ws4-web')
PWA_UNIT = Path('/etc/systemd/system/goufayu-ws4-web.service')
PWA_ENV = Path('/etc/goufayu-ws4-web/auth.env')
NGINX = Path('/etc/nginx/nginx.conf')
LEGACY_CONFIG = Path('/etc/goufayu-payment/config.json')
KEY_NAMES = {'wechat': ('apiclient_key.pem','pub_key.pem','api_v3_key.txt'),
             'alipay': ('应用私钥RSA2048-敏感数据，请妥善保管.txt','支付宝公钥RSA2.txt')}
ENTRYPOINTS = {'catalog','create_order','create_order_channel','create_order_quantity','get_order','pending',
               'update_gateway','deliver','begin_reset','finish_reset'}
TABLES = ('catalog_state','cleared_reward_grants','orders','products','providers','stat_rules','test_accounts',
          'test_resets','test_settings','vip_recharge_credits','vip_recharge_levels')


def capsule_identity(capsule):
    value = copy.deepcopy(capsule)
    value.pop('activation_sha256', None)
    value.pop('activation_stage', None)
    return hashlib.sha256(canonical(value)).hexdigest()


def validate_capsule(capsule):
    identity = capsule.get('activation_sha256')
    need(isinstance(identity,str) and SHA.fullmatch(identity) and capsule_identity(capsule)==identity,'activation_hash_mismatch')
    need(capsule['activation_stage']=='/root/goufayu_upload/ws4-payment-activation-'+identity[:20],'fixed_activation_stage_required')
    validate_plan(capsule['candidate'])
    need(capsule['candidate'].get('cloud_authority',{}).get('bundle_sha256')==
         '47accd81d92265b93c243efc876cbd588e9f260ed8a8d7ff9e9afa1943ec9a9e','cloud_authority_required')
    need(capsule.get('payments_initially_enabled') is False and capsule.get('database_strategy')=='SEED_EMPTY_TABLES_ONLY_NO_MIGRATIONS','activation_strategy_invalid')
    need(capsule['audit']['function_semantics']['exact_project_sources_match'] is True,'reviewed_function_semantics_required')
    need(capsule['audit'].get('pwa_payment_prefix_proxy_verified') is True,'reviewed_pwa_payment_prefix_proxy_required')
    need(set(capsule['audit']['ws4_schema']['aggregate_counts'])==set(TABLES) and
         not any(capsule['audit']['ws4_schema']['aggregate_counts'].values()),'reviewed_empty_payment_namespace_required')


def secure_directory(path,gid=0):
    path=Path(path)
    need(not path.exists() and not path.is_symlink(),'new_private_directory_required')
    path.mkdir(parents=True,mode=0o750 if gid else 0o700)
    os.chown(path,0,gid)
    path.chmod(0o750 if gid else 0o700)


def private_file(path,raw,gid=0,mode=0o600,replace=False):
    path=Path(path)
    need(not path.is_symlink() and path.parent.is_dir(),'private_file_path_invalid')
    if not replace:
        descriptor=os.open(path,os.O_CREAT|os.O_EXCL|os.O_WRONLY|getattr(os,'O_NOFOLLOW',0),mode)
        with os.fdopen(descriptor,'wb') as output:
            output.write(raw);output.flush();os.fsync(output.fileno())
        os.chown(path,0,gid);path.chmod(mode)
        return
    temporary=path.with_name(path.name+'.ws4-new')
    private_file(temporary,raw,gid,mode)
    os.replace(temporary,path)


def fixed_psql(body,*,commit=False):
    # The only mutation transport is the isolated container's local Unix socket.
    need(isinstance(body,str) and '\0' not in body,'fixed_sql_body_invalid')
    prefix="BEGIN ISOLATION LEVEL SERIALIZABLE;\nSET LOCAL lock_timeout='1500ms';\nSET LOCAL statement_timeout='15000ms';\n"
    suffix='COMMIT;\n' if commit else 'ROLLBACK;\n'
    return command(['podman','exec','-i','--user','postgres','--env','PGPASSFILE=/dev/null','--env',
                    'PGSERVICEFILE=/dev/null','goufayu-ws4-db','psql','-X','-w','-qAt','-v','ON_ERROR_STOP=1',
                    '-U','postgres','-d','goufayu_ws4'],(prefix+body+'\n'+suffix).encode(),timeout=50)


def literal(value):
    if value is None:return 'NULL'
    if type(value) is bool:return 'true' if value else 'false'
    if isinstance(value,(int,Decimal)):
        need(Decimal(value).is_finite(),'sql_numeric_invalid')
        return str(value)
    need(isinstance(value,str) and '\0' not in value,'sql_literal_invalid')
    return "'"+value.replace("'","''")+"'"


def json_literal(value):
    return literal(canonical(value).decode())+'::jsonb'


def legacy_unchanged(expected):
    current=baseline()
    for name in SERVICES:
        if name!='goufayu-ws4-web.service':
            need(current['services'][name]==expected['services'][name],'existing_service_changed')
    need(current['pointers']==expected['pointers'],'legacy_release_pointer_changed')


def key_fingerprints():
    result={}
    for provider,names in KEY_NAMES.items():
        for name in names:
            path=Path('/etc/goufayu-payment')/provider/name
            raw=regular(path);info=path.stat()
            result[provider+'/'+name]={'sha256':hashlib.sha256(raw).hexdigest(),'mode':stat.S_IMODE(info.st_mode),
                                    'uid':info.st_uid,'gid':info.st_gid}
    return result


def privilege_state():
    return payment_role_permissions()


def validate_privileges(value,*,active=False):
    need(value and value['unprivileged'] and not value['memberships'] and not value['direct_tables'],'isolated_payment_role_not_minimal')
    need(set(value['execute_functions'])<=ENTRYPOINTS and {'catalog','create_order_quantity','get_order','pending','update_gateway','deliver'}<=set(value['execute_functions']),
         'isolated_payment_rpc_permissions_unexpected')
    need(value['login'] is active and value['connect'] is active,'isolated_payment_role_phase_unexpected')


def stage_capsule(capsule,encoded):
    validate_capsule(capsule)
    files=decode_files(capsule['candidate'],encoded)
    stage=Path(capsule['activation_stage'])
    need(stage.parent==Path('/root/goufayu_upload') and stage.parent.is_dir(),'fixed_activation_parent_required')
    secure_directory(stage)
    for name,raw in files.items():
        path=stage/name
        path.parent.mkdir(parents=True,exist_ok=True,mode=0o700)
        private_file(path,raw)
    private_file(stage/'activation-plan.json',canonical(capsule))
    return {'ok':True,'phase':'WS4_ACTIVATION_STAGED_ONLY','activation_sha256':capsule['activation_sha256'],
            'files':len(files),'remote_stage':str(stage),'payments_enabled':False,'database_writes':False}


def checked_stage(capsule):
    validate_capsule(capsule)
    stage=Path(capsule['activation_stage'])
    need(regular(stage/'activation-plan.json')==canonical(capsule),'activation_capsule_changed')
    for name,digest in capsule['candidate']['source_hashes'].items():
        need(hashlib.sha256(regular(stage/name)).hexdigest()==digest,'activation_source_changed')
    return stage


def nginx_rules():
    routes=('/checkout','/checkout/alipay','/checkout/status','/checkout/qr','/checkout/return','/checkout.js','/checkout.css','/alipay-redirect.js',
            '/v1/payments/wechat/notify','/v1/payments/alipay/notify')
    blocks=['# Dedicated WS4 cashier: no game catalog/create/status/cancel API is public.']
    for path in routes:
        method='POST' if path.endswith('/notify') else 'GET HEAD'
        blocks.append('location = /ws4-payments'+path+' {\n    limit_except '+method+' { deny all; }\n'
                      '    proxy_pass http://127.0.0.1:18769'+path+';\n    proxy_set_header Host pay.xiaofengnet.com;\n'
                      '    proxy_connect_timeout 3s;\n    proxy_read_timeout 30s;\n    client_max_body_size 64k;\n}')
    blocks.append('location ^~ /ws4-payments/ { return 404; }')
    return ('\n'.join(blocks)+'\n').encode()


def nginx_candidate(raw):
    needle=b'include /etc/nginx/goufayu-ws4-web.locations;'
    need(raw.count(needle)==1 and b'goufayu-ws4-payment.locations' not in raw and b'/ws4-payments' not in raw,'nginx_ws4_insertion_target_changed')
    return raw.replace(needle,needle+b'\n    include /etc/nginx/goufayu-ws4-payment.locations;')


def payment_unit(release):
    need(str(release).startswith('/opt/goufayu-ws4-payment/releases/20261027-'),'fixed_payment_release_required')
    return ('''[Unit]
Description=Isolated WS4 verified payments
After=network-online.target goufayu-ws4-db.service
Requires=goufayu-ws4-db.service
[Service]
User=goufayu-ws4-payment
Group=goufayu-ws4-payment
WorkingDirectory=RELEASE
Environment=PYTHONUNBUFFERED=1 PYTHONDONTWRITEBYTECODE=1
ExecStart=RELEASE/.venv/bin/python -B -m payment_backend.service --config /etc/goufayu-ws4-payment/config.json --port 18769
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
'''.replace('RELEASE',str(release))).encode()


def pwa_unit(old,release):
    lines=old.decode().splitlines();seen={'work':0,'exec':0}
    for index,line in enumerate(lines):
        if line.startswith('WorkingDirectory='):
            value=line.split('=',1)[1]
            need(value.startswith('/opt/goufayu-ws4-web/releases/') and '..' not in Path(value).parts,'old_pwa_working_directory_unexpected')
            lines[index]='WorkingDirectory='+str(release);seen['work']+=1
        if line.startswith('ExecStart='):
            need(line in ('ExecStart=/usr/bin/python3.11 -B -m player_web_auth.run','ExecStart=/usr/bin/python3.11 -m player_web_auth.run'),
                 'old_pwa_executable_unexpected')
            seen['exec']+=1
    need(seen=={'work':1,'exec':1} and 'User=goufayu-ws4-web' in lines and
         'EnvironmentFile=/etc/goufayu-ws4-web/auth.env' in lines,'old_pwa_unit_unexpected')
    return ('\n'.join(lines)+'\n').encode()


def payment_env(raw,token,enabled):
    need(type(enabled) is bool and re.fullmatch(r'[a-f0-9]{64}',token),'payment_environment_input_invalid')
    values={'PLAYER_WEB_AUTH_PAYMENTS_ENABLED':'1' if enabled else '0',
            'PLAYER_WEB_AUTH_PAYMENT_UPSTREAM':'http://127.0.0.1:18769','PLAYER_WEB_AUTH_PAYMENT_BEARER':token}
    lines=raw.decode().splitlines();seen=set();result=[]
    for line in lines:
        key=line.partition('=')[0]
        if key in values:
            need(key not in seen,'payment_environment_duplicate')
            result.append(key+'='+json.dumps(values[key]));seen.add(key)
        else:result.append(line)
    result.extend(key+'='+json.dumps(value) for key,value in values.items() if key not in seen)
    return ('\n'.join(result)+'\n').encode()


def seed_source(stage,legacy):
    package=json.loads(regular(stage/'catalog-package.json'))
    catalog=package['catalog']
    def rows(name):
        return [row for row in csv.DictReader(io.StringIO(regular(stage/'reference_csv'/name).decode('utf-8-sig')))
                if next(iter(row.values()),'') and not next(iter(row.values())).startswith('#')]
    statements=["SET ROLE goufayu_owner;", "SELECT pg_advisory_xact_lock(hashtext('ws4.payments.first.publish'));",
                'LOCK TABLE '+','.join('payments.'+name for name in TABLES)+' IN ACCESS EXCLUSIVE MODE;']
    for table in TABLES:
        statements.append("DO $guard$ BEGIN IF EXISTS(SELECT 1 FROM payments."+table+") THEN RAISE EXCEPTION 'ws4_payments_not_empty'; END IF; END; $guard$;")
    stats=rows('玩家档案系统/player_gameplay_stats.csv')
    for row in stats:
        if row['enabled'] not in ('1','true'):continue
        values=[row['field_id'],Decimal(row['default_value']),Decimal(row['min_value']),Decimal(row['max_value']) if row['max_value'] else None]
        statements.append('INSERT INTO payments.stat_rules(field_id,default_value,minimum,maximum) VALUES('+','.join(literal(x) for x in values)+');')
    vip=rows('存档系统/archive_vip_levels.csv')
    need(len(vip)==12 and {int(row['level']) for row in vip}==set(range(1,13)),'reviewed_vip_levels_incomplete')
    for row in vip:
        statements.append('INSERT INTO payments.vip_recharge_levels(level,required_fen) VALUES('+literal(int(row['level']))+','+literal(int(row['required_recharge_fen']))+');')
    seller=legacy.get('alipay_seller_id')
    need(legacy.get('alipay_enabled') is True and isinstance(seller,str) and re.fullmatch(r'2088[0-9]{12}',seller),'legacy_merchant_configuration_incomplete')
    for values in (('wechat','wx164e25a570fb636a','1117928493',True),('alipay','2021007102660118',seller,True)):
        statements.append('INSERT INTO payments.providers(provider,appid,mchid,enabled) VALUES('+','.join(literal(x) for x in values)+');')
    statements.append('INSERT INTO payments.test_settings(singleton,enabled) VALUES(true,false);')
    for product in catalog['products']:
        if product['enabled'] and ('components' in product['grants'] or 'vip_claims' in product['grants']):
            statements.append('SELECT payments.validate_commerce_bundle('+json_literal(product['grants'])+','+json_literal(product['effects'])+');')
        fields=('sku','item_id','title','description','amount','effects','enabled','sort_order','grants','category_id','product_type','icon','purchase_limit')
        values=[json_literal(product[field]) if field in ('effects','grants') else literal(product[field]) for field in fields]
        statements.append('INSERT INTO payments.products('+','.join(fields)+') VALUES('+','.join(values)+');')
    statements.append('INSERT INTO payments.catalog_state(singleton,catalog_hash,categories) VALUES(true,'+literal(package['catalog_hash'])+','+json_literal(catalog['categories'])+');')
    statements.append('RESET ROLE;')
    return '\n'.join(statements)


def assert_seed_rows(stage,legacy):
    """Read only pure published configuration, never an order or player row."""
    package=json.loads(regular(stage/'catalog-package.json'))
    fields=('sku','item_id','title','description','amount','effects','enabled','sort_order','grants','category_id','product_type','icon','purchase_limit')
    actual=sql("SELECT coalesce(json_agg(json_build_object("+','.join(literal(field)+',p.'+field for field in fields)+") ORDER BY p.sku),'[]'::json) FROM payments.products p;")
    expected=sorted([{field:product[field] for field in fields} for product in package['catalog']['products']],key=lambda value:value['sku'])
    need(actual==expected,'published_payment_products_changed')
    reference=csv.DictReader(io.StringIO(regular(stage/'reference_csv/玩家档案系统/player_gameplay_stats.csv').decode('utf-8-sig')))
    stats=[]
    def number(text):
        value=Decimal(text)
        return int(value) if value==value.to_integral() else float(value)
    for row in reference:
        if row['field_id'].startswith('#') or row['enabled'] not in ('1','true'):continue
        stats.append({'field_id':row['field_id'],'default_value':number(row['default_value']),
                      'minimum':number(row['min_value']),'maximum':number(row['max_value']) if row['max_value'] else None})
    actual_stats=sql("SELECT coalesce(json_agg(to_jsonb(r) ORDER BY field_id),'[]'::json) FROM payments.stat_rules r;")
    need(actual_stats==sorted(stats,key=lambda value:value['field_id']),'published_stat_rules_changed')
    actual_vip=sql("SELECT coalesce(json_agg(to_jsonb(r) ORDER BY level),'[]'::json) FROM payments.vip_recharge_levels r;")
    vip_reference=csv.DictReader(io.StringIO(regular(stage/'reference_csv/存档系统/archive_vip_levels.csv').decode('utf-8-sig')))
    vip=[{'level':int(row['level']),'required_fen':int(row['required_recharge_fen'])} for row in vip_reference if not row['level_id'].startswith('#')]
    need(actual_vip==sorted(vip,key=lambda value:value['level']),'published_vip_levels_changed')
    providers=sql("SELECT coalesce(json_agg(to_jsonb(r) ORDER BY provider),'[]'::json) FROM payments.providers r;")
    need(providers==[{'provider':'alipay','appid':'2021007102660118','mchid':legacy['alipay_seller_id'],'enabled':True},
                      {'provider':'wechat','appid':'wx164e25a570fb636a','mchid':'1117928493','enabled':True}],'published_provider_identity_changed')


def backup(stage,capsule):
    directory=stage/'private-backup';secure_directory(directory)
    for name,path in (('web.env',PWA_ENV),('web.unit',PWA_UNIT),('nginx.conf',NGINX)):
        private_file(directory/name,regular(path))
    # Metadata and this still-empty isolated payment ledger only, not public
    # player rows or anything from the production container.
    dump=command(['podman','exec','--user','postgres','--env','PGPASSFILE=/dev/null','--env','PGSERVICEFILE=/dev/null',
                  'goufayu-ws4-db','pg_dump','-U','postgres','-d','goufayu_ws4','--schema=payments','--format=custom'],timeout=45)
    private_file(directory/'empty-payments.dump',dump)
    metadata=command(['podman','exec','--user','postgres','goufayu-ws4-db','pg_dump','-U','postgres','-d','goufayu_ws4',
                      '--schema=public','--schema-only','--format=custom'],timeout=45)
    private_file(directory/'public-metadata.dump',metadata)
    role=sql("SELECT json_build_object('login',r.rolcanlogin,'password',r.rolpassword,'connect',has_database_privilege(r.rolname,current_database(),'CONNECT')) FROM pg_authid r WHERE r.rolname='goufayu_payment';")
    private_file(directory/'role.json',canonical(role))
    private_file(directory/'legacy-keys.json',canonical(key_fingerprints()))
    private_file(directory/'privileges.json',canonical(privilege_state()))
    private_file(directory/'baseline.json',canonical(capsule['audit']['baseline']))
    return directory


def create_release(stage,capsule,gid):
    release=Path(capsule['candidate']['payment']['release'])
    secure_directory(PAYMENT_BASE,gid);secure_directory(PAYMENT_BASE/'releases',gid);secure_directory(release,gid)
    for name in capsule['candidate']['source_hashes']:
        if name.startswith(('payment_backend/','reference_csv/','payment_csv/')) or name in ('catalog-package.json','wallet-catalog.json','catalog_validation.py','cloud-bundle.json','cloud-source-provenance.json'):
            target=release/name;target.parent.mkdir(parents=True,exist_ok=True,mode=0o750)
            for parent in target.parents:
                if parent==release:break
                os.chown(parent,0,gid);parent.chmod(0o750)
            private_file(target,regular(stage/name),gid,0o640)
    command(['/usr/bin/python3.11','-m','venv','--copies',str(release/'.venv')],timeout=45)
    # Copy only installed dependency code into a separate venv. No pip/network,
    # shared old service group, credential or old release mutation is needed.
    old=Path('/opt/goufayu/payments/current').resolve(strict=True)/'.venv/lib/python3.11/site-packages'
    need(old.is_dir() and not any(path.is_symlink() for path in old.rglob('*')),'dependency_source_tree_unexpected')
    shutil.copytree(old,release/'.venv/lib/python3.11/site-packages',dirs_exist_ok=True,ignore=shutil.ignore_patterns('__pycache__'))
    command([str(release/'.venv/bin/python'),'-B','-c',"import importlib.metadata as m;assert {n:m.version(n) for n in ('cryptography','psycopg','qrcode')}=={'cryptography':'46.0.5','psycopg':'3.2.13','qrcode':'8.2'}"],timeout=15)
    for path in release.rglob('*'):
        if not path.is_symlink():
            os.chown(path,0,gid);path.chmod(0o750 if path.is_dir() or path.parent.name=='bin' else 0o640)
    return release


def install_pwa(stage,capsule,token):
    user=pwd.getpwnam('goufayu-ws4-web');need(user.pw_uid>0 and user.pw_gid>0,'existing_pwa_user_invalid')
    release=PWA_BASE/'releases'/('20261027-payment-'+capsule['activation_sha256'][:20]);secure_directory(release,user.pw_gid)
    for name in capsule['candidate']['source_hashes']:
        if name.startswith(('player_web_auth/','lobby_backend/')):
            target=release/name;target.parent.mkdir(parents=True,exist_ok=True,mode=0o750);os.chown(target.parent,0,user.pw_gid)
            private_file(target,regular(stage/name),user.pw_gid,0o640)
    raw_env=regular(PWA_ENV);before=env_values(PWA_ENV)
    need(before.get('PLAYER_WEB_AUTH_DATABASE')=='/var/lib/goufayu-ws4-web/auth.sqlite3','existing_pwa_database_path_unexpected')
    need(before.get('PLAYER_WEB_AUTH_PUBLIC_BASE')=='https://pay.xiaofengnet.com/ws4-web','existing_pwa_public_base_unexpected')
    after=payment_env(raw_env,token,False)
    private_file(stage/'pwa.env.after',after)
    unit=pwa_unit(regular(PWA_UNIT),release)
    private_file(stage/'pwa.unit.after',unit)
    private_file(PWA_ENV,after,user.pw_gid,0o640,replace=True)
    private_file(PWA_UNIT,unit,0,0o644,replace=True)
    # Existing SQLite file, browser secret, upstream bearer and cookie remain.
    command(['systemctl','daemon-reload']);command(['systemctl','restart','goufayu-ws4-web.service'])
    for key in ('PLAYER_WEB_AUTH_DATABASE','PLAYER_WEB_AUTH_SECRET','PLAYER_WEB_AUTH_UPSTREAM_BEARER','PLAYER_WEB_AUTH_STEAM_IDS'):
        need(env_values(PWA_ENV).get(key)==before.get(key),'existing_pwa_identity_material_changed')
    return release


def health(url):
    with urllib.request.urlopen(url,timeout=3) as response:
        need(response.status==200,'new_service_health_failed');raw=response.read(65537)
    need(len(raw)<=65536 and json.loads(raw).get('ok') is True,'new_service_health_failed')


def wait_health(url):
    for attempt in range(20):
        try:health(url);return
        except Exception:
            if attempt==19:raise RuntimeError('new_service_health_failed')
            time.sleep(.25)


def activate_capsule(capsule):
    stage=checked_stage(capsule);need(not (stage/'activated.json').exists() and not (stage/'activation-started.json').exists(),'activation_already_attempted')
    current=audit(capsule['candidate'])
    need(current['function_semantics']['exact_project_sources_match'] and current['bundle']['all_sources_match'] and
         current['pwa_payment_prefix_proxy_verified'],'activation_semantic_preflight_failed')
    need(current['ws4_schema']['aggregate_counts']==capsule['audit']['ws4_schema']['aggregate_counts'],'payment_namespace_changed')
    need(current['activation_pins']==capsule['audit']['activation_pins'],'activation_configuration_changed')
    legacy_unchanged(capsule['audit']['baseline']);validate_privileges(privilege_state())
    need(current['new_payment_paths_absent'] and current['payment_port_free'] and not PAYMENT_LOCATIONS.exists(),'new_payment_namespace_required')
    need(current['ws4_schema']['order_triggers']==capsule['audit']['ws4_schema']['order_triggers'],'payment_triggers_changed')
    try:pwd.getpwnam(PAYMENT_USER)
    except KeyError:pass
    else:raise RuntimeError('new_payment_user_required')
    env=env_values('/etc/goufayu-ws4/api.env');steam=env['SURVIVAL_TEST_STEAM_IDS64'].split(',')
    need(set(env_values(PWA_ENV).get('PLAYER_WEB_AUTH_STEAM_IDS','').split(','))==set(steam),'pwa_four_account_roster_changed')
    accounts=sorted(str(int(value)-76561197960265728) for value in steam)
    need(len(set(accounts))==4 and all(re.fullmatch(r'[1-9][0-9]{0,9}',value) for value in accounts),'four_accounts_invalid')
    legacy=json.loads(regular(LEGACY_CONFIG));before_keys=key_fingerprints();before_config=regular(LEGACY_CONFIG)
    directory=backup(stage,capsule)
    source=seed_source(stage,legacy)
    fixed_psql(source,commit=False)  # No transaction/order/player fixtures.
    command(['useradd','--system','--user-group','--no-create-home','--home-dir','/nonexistent','--shell','/sbin/nologin',PAYMENT_USER])
    user=pwd.getpwnam(PAYMENT_USER);need(user.pw_uid>0 and user.pw_gid>0,'new_payment_user_invalid')
    secure_directory(PAYMENT_CONFIG,user.pw_gid)
    release=create_release(stage,capsule,user.pw_gid)
    for provider,names in KEY_NAMES.items():
        secure_directory(PAYMENT_CONFIG/provider,user.pw_gid)
        for name in names:private_file(PAYMENT_CONFIG/provider/name,regular(Path('/etc/goufayu-payment')/provider/name),user.pw_gid,0o640)
    password=secrets.token_hex(48);token=secrets.token_hex(32);checkout=secrets.token_hex(32)
    need(len({token,checkout,password,env['FISHING_ACCOUNT_ID_PEPPER'],legacy['game_token'],legacy['checkout_key']})==6,'new_payment_secrets_not_distinct')
    from psycopg.conninfo import make_conninfo
    config={key:legacy[key] for key in ('alipay_enabled','alipay_seller_id','alipay_checkout_mode') if key in legacy}
    config.update(allowed_accounts=accounts,pepper=env['FISHING_ACCOUNT_ID_PEPPER'],game_token=token,checkout_key=checkout,
                  test_reset_enabled=False,public_base='https://pay.xiaofengnet.com/ws4-payments',bind='127.0.0.1',
                  wechat_key_directory=str(PAYMENT_CONFIG/'wechat'),alipay_key_directory=str(PAYMENT_CONFIG/'alipay'),
                  dsn=make_conninfo(host='127.0.0.1',hostaddr='127.0.0.1',port=15432,dbname='goufayu_ws4',user='goufayu_payment',password=password))
    private_file(PAYMENT_CONFIG/'config.json',canonical(config),user.pw_gid,0o640)
    # Record phase before the first committed mutation so failures remain
    # reviewable and a second attempt can never seed a partially populated DB.
    private_file(stage/'activation-started.json',canonical({'activation_sha256':capsule['activation_sha256'],'backup':str(directory)}))
    fixed_psql(source+"\nALTER ROLE goufayu_payment LOGIN PASSWORD "+literal(password)+";\nGRANT CONNECT ON DATABASE goufayu_ws4 TO goufayu_payment;",commit=True)
    private_file(PAYMENT_UNIT,payment_unit(release),0,0o644)
    command(['systemctl','daemon-reload']);command(['systemctl','enable','--now','goufayu-ws4-payment.service'])
    wait_health('http://127.0.0.1:18769/health')
    after_nginx=nginx_candidate(regular(NGINX));private_file(stage/'nginx.after',after_nginx)
    private_file(PAYMENT_LOCATIONS,nginx_rules(),0,0o644)
    private_file(NGINX,after_nginx,0,0o644,replace=True)
    command(['nginx','-t']);command(['systemctl','reload','nginx'])
    pwa=install_pwa(stage,capsule,token);wait_health('http://127.0.0.1:18767/health')
    need(key_fingerprints()==before_keys and regular(LEGACY_CONFIG)==before_config,'legacy_merchant_material_changed')
    legacy_unchanged(capsule['audit']['baseline']);validate_privileges(privilege_state(),active=True)
    private_file(stage/'activated.json',canonical({'activation_sha256':capsule['activation_sha256'],'payment_release':str(release),
                 'pwa_release':str(pwa),'payments_enabled':False,'seeded_tables_only':True,
                 'config_sha256':hashlib.sha256(regular(PAYMENT_CONFIG/'config.json')).hexdigest()}))
    return verify_capsule(capsule)


def verify_capsule(capsule):
    stage=checked_stage(capsule);need((stage/'activated.json').is_file(),'activation_receipt_required')
    receipt=json.loads(regular(stage/'activated.json'));need(receipt['activation_sha256']==capsule['activation_sha256'],'activation_receipt_changed')
    legacy_unchanged(capsule['audit']['baseline'])
    need(function_semantics(capsule['candidate']['payment_function_contract'])['exact_project_sources_match'],'payment_function_semantics_changed')
    validate_privileges(privilege_state(),active=True)
    config=json.loads(regular(PAYMENT_CONFIG/'config.json'));web=env_values(PWA_ENV)
    need(hashlib.sha256(regular(PAYMENT_CONFIG/'config.json')).hexdigest()==receipt['config_sha256'],'new_payment_configuration_changed')
    need(regular(PAYMENT_UNIT)==payment_unit(Path(receipt['payment_release'])) and
         regular(PWA_UNIT)==regular(stage/'pwa.unit.after'),'new_service_unit_changed')
    enabled=web.get('PLAYER_WEB_AUTH_PAYMENTS_ENABLED','0')=='1'
    need(regular(PWA_ENV)==payment_env(regular(stage/'private-backup/web.env'),config['game_token'],enabled),'pwa_environment_changed')
    for name,digest in capsule['candidate']['source_hashes'].items():
        if name.startswith(('payment_backend/','reference_csv/','payment_csv/')) or name in ('catalog-package.json','wallet-catalog.json','catalog_validation.py','cloud-bundle.json','cloud-source-provenance.json'):
            target=Path(receipt['payment_release'])/name
        elif name.startswith(('player_web_auth/','lobby_backend/')):
            target=Path(receipt['pwa_release'])/name
        else:continue
        need(hashlib.sha256(regular(target)).hexdigest()==digest,'new_release_source_changed')
    expected_accounts=sorted(str(int(value)-76561197960265728) for value in env_values('/etc/goufayu-ws4/api.env')['SURVIVAL_TEST_STEAM_IDS64'].split(','))
    need(config['allowed_accounts']==expected_accounts,'new_payment_account_gate_changed')
    need(hashlib.sha256(regular(LEGACY_CONFIG)).hexdigest()==capsule['audit']['activation_pins']['legacy_payment_config_sha256'],'legacy_payment_configuration_changed')
    assert_seed_rows(stage,config)
    need(web.get('PLAYER_WEB_AUTH_PAYMENT_BEARER')==config['game_token'] and config['test_reset_enabled'] is False,'new_payment_secret_alignment_failed')
    need(config['pepper']==env_values('/etc/goufayu-ws4/api.env')['FISHING_ACCOUNT_ID_PEPPER'],'ws4_profile_pepper_alignment_failed')
    need(key_fingerprints()==json.loads(regular(stage/'private-backup/legacy-keys.json')),'legacy_key_acl_changed')
    need(regular(NGINX)==regular(stage/'nginx.after') and regular(PAYMENT_LOCATIONS)==nginx_rules(),'new_payment_routes_changed')
    wait_health('http://127.0.0.1:18769/health');wait_health('http://127.0.0.1:18767/health')
    catalog=sql("SELECT json_build_object('hash',(SELECT catalog_hash FROM payments.catalog_state WHERE singleton),'all',(SELECT count(*) FROM payments.products),'enabled',(SELECT count(*) FROM payments.products WHERE enabled),'vip_levels',(SELECT count(*) FROM payments.vip_recharge_levels),'reset',(SELECT enabled FROM payments.test_settings WHERE singleton),'orders',(SELECT count(*) FROM payments.orders));")
    expected=capsule['candidate']['catalog']
    need(catalog['hash']==expected['cash_catalog_hash'] and (catalog['all'],catalog['enabled'],catalog['vip_levels'],catalog['reset'])==(50,48,12,False),'published_payment_catalog_changed')
    return {'ok':True,'phase':'WS4_PAYMENT_LINK_VERIFIED','activation_sha256':capsule['activation_sha256'],
            'payments_enabled':enabled,'cash_enabled':48,'wallet_enabled':125,
            'orders':catalog['orders'],'gateway_calls_by_operator':0,'player_rows_written_by_operator':0,'existing_services_unchanged':True,
            'secrets_exported':False,'next':'AUTHENTIC_HELPER_CLOUD_PROFILE_READBACK_THEN_SEPARATE_ENABLE'}


def set_enabled(capsule,enabled,evidence=None):
    stage=checked_stage(capsule);need((stage/'activated.json').is_file(),'activation_receipt_required')
    if enabled:
        need(isinstance(evidence,dict) and evidence.get('ok') is True and evidence.get('real_player_grant') is True and
             evidence.get('cloud_profile_readback') is True and SHA.fullmatch(evidence.get('record_sha256','')),'authentic_cloud_readback_evidence_required')
        verify_capsule(capsule)
    user=pwd.getpwnam('goufayu-ws4-web');config=json.loads(regular(PAYMENT_CONFIG/'config.json'))
    before=regular(PWA_ENV);after=payment_env(before,config['game_token'],enabled)
    private_file(PWA_ENV,after,user.pw_gid,0o640,replace=True)
    command(['systemctl','restart','goufayu-ws4-web.service']);wait_health('http://127.0.0.1:18767/health')
    if enabled:
        receipt=stage/'enabled-after-readback.json';raw=canonical({'evidence':evidence,'activation_sha256':capsule['activation_sha256']})
        if receipt.exists():need(regular(receipt)==raw,'enable_readback_evidence_changed')
        else:private_file(receipt,raw)
    return {'ok':True,'phase':'WS4_PAYMENT_FLAG_UPDATED','activation_sha256':capsule['activation_sha256'],
            'payments_enabled':enabled,'gateway_called':False,'orders_changed':False,'ledger_retained':True}


def disable_capsule(capsule):
    # Safe during paid traffic: revoke new intents through the PWA flag while
    # keeping the verified callback worker and all existing receipts available.
    return set_enabled(capsule,False)


def rollback_no_orders(capsule):
    """Explicit operator-only rollback; paid ledgers are always retained."""
    stage=checked_stage(capsule);directory=stage/'private-backup'
    need(directory.is_dir(),'private_activation_backup_required')
    counts=database_counts()
    need(not any(counts[name] for name in ('orders','vip_recharge_credits','test_accounts','test_resets','cleared_reward_grants')),
         'payment_ledger_exists_retain_and_repair_forward')
    # Never overwrite another administrator's unit/environment/routing edits.
    for current,after,before in ((PWA_ENV,stage/'pwa.env.after',directory/'web.env'),
                                 (PWA_UNIT,stage/'pwa.unit.after',directory/'web.unit'),
                                 (NGINX,stage/'nginx.after',directory/'nginx.conf')):
        raw=regular(current)
        need(raw==regular(before) or after.is_file() and raw==regular(after),'rollback_configuration_conflict')
    if PAYMENT_UNIT.exists():
        need(regular(PAYMENT_UNIT)==payment_unit(Path(capsule['candidate']['payment']['release'])),'rollback_payment_unit_conflict')
        command(['systemctl','disable','--now','goufayu-ws4-payment.service'])
    if regular(PWA_ENV)!=regular(directory/'web.env'):
        user=pwd.getpwnam('goufayu-ws4-web');private_file(PWA_ENV,regular(directory/'web.env'),user.pw_gid,0o640,replace=True)
    private_file(PWA_UNIT,regular(directory/'web.unit'),0,0o644,replace=True)
    private_file(NGINX,regular(directory/'nginx.conf'),0,0o644,replace=True)
    command(['nginx','-t']);command(['systemctl','reload','nginx'])
    command(['systemctl','daemon-reload']);command(['systemctl','restart','goufayu-ws4-web.service'])
    # No pg_restore, schema replay, ledger truncation, player edit or DROP.
    # Empty pre-seed is valid too; otherwise seed counts/hash must be exact.
    expected=capsule['candidate']['catalog']
    if any(counts.values()):
        assert_seed_rows(stage,json.loads(regular(LEGACY_CONFIG)))
        actual=sql("SELECT json_build_object('hash',(SELECT catalog_hash FROM payments.catalog_state WHERE singleton),'products',(SELECT count(*) FROM payments.products),'vip',(SELECT count(*) FROM payments.vip_recharge_levels),'providers',(SELECT count(*) FROM payments.providers),'settings',(SELECT count(*) FROM payments.test_settings));")
        need(actual=={'hash':expected['cash_catalog_hash'],'products':50,'vip':12,'providers':2,'settings':1},'rollback_seed_state_conflict')
    old=json.loads(regular(directory/'role.json'))
    need(old['login'] is False and old['connect'] is False,'rollback_initial_role_state_unexpected')
    password='NULL' if old['password'] is None else literal(old['password'])
    body='SET ROLE goufayu_owner;\n'
    for table in ('catalog_state','products','providers','stat_rules','test_settings','vip_recharge_levels'):
        body+='DELETE FROM payments.'+table+';\n'
    body+='RESET ROLE;\nALTER ROLE goufayu_payment NOLOGIN PASSWORD '+password+';\nREVOKE CONNECT ON DATABASE goufayu_ws4 FROM goufayu_payment;'
    # Hold all payment tables to make the zero-ledger assertion and cleanup one
    # serializable operation; recheck in SQL after taking the locks.
    guard='LOCK TABLE '+','.join('payments.'+name for name in TABLES)+' IN ACCESS EXCLUSIVE MODE;\n'
    for table in ('orders','vip_recharge_credits','test_accounts','test_resets','cleared_reward_grants'):
        guard+="DO $guard$ BEGIN IF EXISTS(SELECT 1 FROM payments."+table+") THEN RAISE EXCEPTION 'retain_payment_ledger'; END IF; END; $guard$;\n"
    fixed_psql(guard+body,commit=True)
    validate_privileges(privilege_state());legacy_unchanged(capsule['audit']['baseline'])
    need(not any(database_counts().values()),'rollback_seed_cleanup_incomplete')
    private_file(stage/'rolled-back-no-orders.json',canonical({'activation_sha256':capsule['activation_sha256'],'ledger_was_empty':True}))
    return {'ok':True,'phase':'WS4_PAYMENT_ROLLED_BACK_WITH_EMPTY_LEDGER','activation_sha256':capsule['activation_sha256'],
            'legacy_services_unchanged':True,'private_sources_and_backups_retained':True,'player_rows_changed':False}


def database_counts():
    return sql('SELECT json_build_object('+','.join(literal(name)+',(SELECT count(*) FROM payments.'+name+')' for name in TABLES)+');')


def activation_main(mode,capsule,encoded=None,evidence=None):
    need(mode in ('stage','activate','verify','enable','disable','rollback-no-orders'),'fixed_activation_mode_required')
    need(os.geteuid()==0,'root_operator_required')
    try:
        if mode=='stage':result=stage_capsule(capsule,encoded)
        elif mode=='activate':result=activate_capsule(capsule)
        elif mode=='verify':result=verify_capsule(capsule)
        elif mode=='enable':result=set_enabled(capsule,True,evidence)
        elif mode=='disable':result=disable_capsule(capsule)
        else:result=rollback_no_orders(capsule)
    except Exception as error:
        code=str(error) if isinstance(error,RuntimeError) and re.fullmatch(r'[a-z][a-z0-9_]{1,95}',str(error)) else 'host_activation_failed'
        print(json.dumps({'ok':False,'phase':'WS4_PAYMENT_ACTIVATION_STOPPED','error':code,'mode':mode,
                          'activation_sha256':capsule.get('activation_sha256'),'secrets_exported':False,
                          'next':'REVIEW_PRIVATE_PHASE_AND_BACKUP_BEFORE_EXPLICIT_RECOVERY'}))
        raise SystemExit(1) from None
    print(json.dumps(result,separators=(',',':')))
