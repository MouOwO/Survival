"""Replay the real configured migration chain in a new private PostgreSQL 17.

Only loopback connections to this script's own cluster are used. Historical SQL
bytes come from the reviewed collector sequence; no business schema is mocked.
"""
from __future__ import annotations
import argparse
import concurrent.futures
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil
import socket
import subprocess
import sys
import uuid

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location('daily_limits_chain_dbtool', ROOT/'server/aliyun/database/dbtool.py')
dbtool = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(dbtool)


def run(pg_bin, legacy_root, dependencies=None):
    if dependencies:
        sys.path.insert(0, str(dependencies))
    import psycopg
    from psycopg.types.json import Jsonb
    base = ROOT/'output/daily_limits_20261020/full_chain'
    base.mkdir(parents=True, exist_ok=True)
    # Inherit output ACLs so pg_ctl's restricted Windows child can open files.
    work = base/('isolated_'+uuid.uuid4().hex[:12])
    work.mkdir()
    data = work/'cluster'
    database = 'goufayu_restore_daily_caps_'+uuid.uuid4().hex[:12]
    with socket.socket() as listener:
        listener.bind(('127.0.0.1',0))
        port = listener.getsockname()[1]
    environment = dict(os.environ)
    for key in ('PGSERVICE','PGHOST','PGUSER','PGDATABASE','PGPASSWORD','PGOPTIONS'):
        environment.pop(key,None)
    environment['PGCLIENTENCODING']='UTF8'
    log=[]

    def command(program, arguments):
        capture = work/('command_'+str(len(log))+'.log')
        with capture.open('wb') as stream:
            result = subprocess.run([str(pg_bin/(program+'.exe')),*map(str,arguments)],
                stdout=stream,stderr=subprocess.STDOUT,env=environment,cwd=work,timeout=60,
                creationflags=getattr(subprocess,'CREATE_NO_WINDOW',0))
        log.append({'program':program,'returncode':result.returncode})
        if result.returncode:
            raise RuntimeError(program+'_failed_see_private_test_log')

    def local_connection(user):
        return psycopg.connect(host='127.0.0.1',port=port,user=user,dbname=database,
                              connect_timeout=5,autocommit=True)

    def app_sql(query,parameters=()):
        with local_connection('goufayu_app') as connection:
            return connection.execute(query,parameters).fetchone()[0]

    command('initdb',['-D',data,'-U','postgres','-A','trust','--encoding=UTF8','--no-locale'])
    started=False
    try:
        command('pg_ctl',['-D',data,'-l',work/'postgres.log','-o',f'-h 127.0.0.1 -p {port} -F','-w','-t','15','start'])
        started=True
        command('createdb',['-h','127.0.0.1','-p',port,'-U','postgres',database])
        command('psql',['-X','-v','ON_ERROR_STOP=1','-h','127.0.0.1','-p',port,'-U','postgres','-d',database,
                        '-f',dbtool.HERE/'init_roles.sql'])
        stage=work/'approved_addon_sources'
        for name in (*dbtool.ARCHIVE_FILES,*(name for name,_ in dbtool.UPGRADE_FILES)):
            target=stage/'server/migrations'/name
            target.parent.mkdir(parents=True,exist_ok=True)
            shutil.copyfile(ROOT/'server/migrations'/name,target)
        manual=Path('tools/sql/202609060001_archive_fishing_inventory.sql')
        (stage/manual).parent.mkdir(parents=True,exist_ok=True)
        shutil.copyfile(ROOT/manual,stage/manual)
        bundle=work/'database_bundle'
        dbtool.collect(legacy_root,stage,bundle)
        service_file=work/'local_services.conf'
        service_file.write_text('[daily_caps_private_test]\nhost=127.0.0.1\nport='+str(port)
            +'\nuser=goufayu_migrator\ndbname='+database+'\n',encoding='utf-8')
        os.environ['PGSERVICEFILE']=str(service_file)
        os.environ['PGPASSFILE']=str(work/'unused_password_file')
        for key in ('PGSERVICE','PGHOST','PGUSER','PGDATABASE','PGPASSWORD','PGOPTIONS'):
            os.environ.pop(key,None)
        first=dbtool.migrate(bundle,'daily_caps_private_test')
        second=dbtool.migrate(bundle,'daily_caps_private_test')
        assert second['new_migrations']==0,'second_migration_replayed_history'
        with local_connection('goufayu_migrator') as connection:
            connection.execute('SET ROLE goufayu_owner')
            inventory=dbtool.inventory(connection)
            manifest=dbtool.load_bundle(bundle)
            dbtool.verify_ledger_schema(connection,bundle,manifest['entries'])
        account=hashlib.sha256(b'synthetic-daily-cap-full-chain-account').hexdigest()
        app_sql('SELECT public.ensure_player_gameplay_stats(%s,%s)',(account,Jsonb({})))
        definitions=[dict(reward_id='star_blessing_local_daily_limit',display_name='Synthetic test',
            weight=1,effect_key='initial_wood',effect_scope='permanent',value_min=1,value_max=1,
            stacking_rule='add',cap_value=None)]
        version=32191
        digest=hashlib.sha256(json.dumps(definitions,sort_keys=True).encode()).hexdigest()
        app_sql('SELECT public.sync_star_blessing_reward_definitions(%s,%s,%s)',(version,digest,Jsonb(definitions)))
        before=app_sql('SELECT public.get_fishing_profile(%s)',(account,))['save']['gameplay_stats']['initial_wood']
        grant_query='SELECT public.grant_out_of_match_reward(%s,%s,%s,%s,%s)'

        def grant(identifier):
            return app_sql(grant_query,(account,identifier,'star_blessing_local_daily_limit',version,1))

        first_identifier=uuid.uuid4()
        first_grant=grant(first_identifier)
        for _ in range(78):
            assert grant(uuid.uuid4()).get('grant')
        with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
            results=list(pool.map(grant,[uuid.uuid4() for _ in range(4)]))
        assert sum(bool(result.get('grant')) for result in results)==1,'concurrent_fishing_quota_exceeded'
        assert grant(first_identifier)==first_grant,'accepted_receipt_changed_at_cap'
        profile=app_sql('SELECT public.get_fishing_profile(%s)',(account,))
        assert profile['save']['gameplay_stats']['initial_wood']==before+80,'grant_effect_count_mismatch'
        assert profile['save']['daily_limits']['by_key']['fishing']['earned']==80,'profile_daily_count_missing'
        query='SELECT public.checkpoint_online_time(%s,%s,%s,%s,%s,%s,%s,%s)'
        app_sql(query,(account,'full-chain-session','full-chain-first',180,version,1,1,False))
        with local_connection('goufayu_migrator') as connection:
            connection.execute('SET ROLE goufayu_owner')
            connection.execute("UPDATE public.online_time_sessions SET last_checkpoint_at=clock_timestamp()-interval '2 seconds' WHERE account_id=%s",(account,))
        final=app_sql(query,(account,'full-chain-session','full-chain-final',180,version,1,1,True))
        assert final['elapsed_seconds']>=1,'capped_fishing_stopped_online_clock'
        assert final['grants']==[],'final_checkpoint_advertised_uncommitted_reward'
        assert app_sql(query,(account,'full-chain-session','full-chain-final',180,version,1,1,True))==final,'final_receipt_changed'
        with local_connection('goufayu_migrator') as connection:
            connection.execute('SET ROLE goufayu_owner')
            assert connection.execute('SELECT count(*) FROM public.online_time_sessions WHERE account_id=%s',(account,)).fetchone()[0]==0
            assert connection.execute('SELECT count(*) FROM public.reward_grants WHERE account_id=%s',(account,)).fetchone()[0]==80
        report={'status':'PASS','kind':'complete_configured_migration_chain_postgresql17',
            'migration_entries':len(manifest['entries']),'first_migrate':first,'second_migrate':second,
            'inventory_tables':len(inventory['tables']),'inventory_functions':len(inventory['functions']),
            'checks':['full historical migration replay','idempotent rerun','real schema inventory',
                      'least privilege runtime RPC count','original grant helper effects and receipts',
                      'concurrent final fishing slot','eight-argument final checkpoint and retry',
                      'online clock continues at cap','no uncommitted reward announcements'],
            'existing_accounts_read':0,'external_connections':0,'processes':log,'cluster_stopped':False}
    finally:
        if started or (data/'postmaster.pid').exists():
            command('pg_ctl',['-D',data,'-m','fast','-w','-t','15','stop'])
    report['cluster_stopped']=True
    (work/'report.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
    print(json.dumps({'status':'PASS','report':str((work/'report.json').relative_to(ROOT)),
                      'migrations':report['migration_entries'],'cluster_stopped':True}))


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--pg-bin',required=True,type=Path)
    parser.add_argument('--legacy-root',required=True,type=Path)
    parser.add_argument('--dependencies',type=Path)
    arguments=parser.parse_args()
    run(arguments.pg_bin.resolve(),arguments.legacy_root.resolve(),
        arguments.dependencies.resolve() if arguments.dependencies else None)
