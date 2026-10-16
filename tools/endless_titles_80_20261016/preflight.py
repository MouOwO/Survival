"""Authorized read-only publication preflight; no network on import."""
from pathlib import Path
import json,subprocess,hashlib,sys,textwrap

def main():
    sys.dont_write_bytecode=True
    ROOT=Path(__file__).resolve().parents[2]
    OUT=ROOT/'output/endless_titles_80_20261016/deployment'
    OUT.mkdir(exist_ok=True)
    sys.path.insert(0,str(ROOT/'tools'))
    import aliyun_local_config
    from aliyun_test_connection import ECS_HOST, verify_known_hosts
    def ssh_options():
        known=ROOT/'tools/deploy/goufayu_test_known_hosts'
        verify_known_hosts(known)
        config=aliyun_local_config.load(ROOT)
        assert ECS_HOST=='47.110.238.248'
        return ['ssh.exe','-T','-F','none','-o','BatchMode=yes','-o','StrictHostKeyChecking=yes','-o','UserKnownHostsFile='+known.relative_to(ROOT).as_posix(),'-o','GlobalKnownHostsFile=none','-o','HostKeyAlgorithms=ssh-ed25519','-o','IdentitiesOnly=yes','-o','ConnectTimeout=10','-o','PreferredAuthentications=publickey','-o','PasswordAuthentication=no','-o','KbdInteractiveAuthentication=no','-i',str(config['ssh_key']),'root@'+ECS_HOST,'/opt/goufayu/payments/current/.venv/bin/python -B -']
    configuration=json.loads((OUT.parent/'release_fbf16/configuration.json').read_bytes())
    candidate=json.loads((OUT.parent/'release_fbf16/manifest.json').read_bytes())['candidate_hash']
    code='CONFIG='+repr(json.dumps(configuration,ensure_ascii=False,separators=(',',':')))+'\nCANDIDATE='+repr(candidate)+'\n'+textwrap.dedent(r'''
    from pathlib import Path
    import hashlib,json,sys,urllib.request
    a=Path('/opt/goufayu/releases/current').resolve(strict=True)
    p=Path('/opt/goufayu/payments/current').resolve(strict=True)
    def sha(raw):return hashlib.sha256(raw).hexdigest()
    manifest=(a/'release_manifest.json').read_bytes()
    sys.path.insert(0,str(p));from deploy import connection
    definitions={};states={}
    with connection() as c:
     c.execute('SET TRANSACTION READ ONLY')
     cfgsha=c.execute("SELECT encode(sha256(convert_to(%s::jsonb::text,'UTF8')),'hex')",(CONFIG,)).fetchone()[0]
     catalog=c.execute('SELECT catalog_hash FROM payments.catalog_state WHERE singleton').fetchone()[0]
     enabled=c.execute('SELECT count(*) FROM payments.products WHERE enabled').fetchone()[0]
     names=c.execute("SELECT schemaname,tablename FROM pg_tables WHERE schemaname IN ('public','payments') ORDER BY schemaname,tablename").fetchall()
     exists=c.execute('SELECT count(*) FROM public.archive_config_sets WHERE config_hash=%s',(CANDIDATE,)).fetchone()[0]
     for signature in ['public.archive_sync_config(text,jsonb)','payments.apply_effects(text,jsonb,boolean)']:
      row=c.execute('SELECT pg_get_functiondef(oid),pg_get_userbyid(proowner),prosecdef,proconfig,proacl::text FROM pg_proc WHERE oid=%s::regprocedure',(signature,)).fetchone()
      definitions[signature]=row[0];states[signature]={'definition_sha256':sha(row[0].encode()),'owner':row[1],'security_definer':row[2],'configuration':row[3],'acl':row[4]}
     c.rollback()
    health={}
    for name,port in [('archive',8765),('payment',8766)]:
     with urllib.request.urlopen('http://127.0.0.1:'+str(port)+'/health',timeout=5) as response:health[name]=json.load(response)
    print(json.dumps({'status':'READ_ONLY_PREFLIGHT','candidate':CANDIDATE,'cfg_pg_sha256':cfgsha,
     'metadata':{'archive_release':str(a),'payment_release':str(p),'bundle':json.loads((a/'addon/server/bundles/current.json').read_bytes())['hash'],'catalog_hash':catalog,'health':health},
     'archive_manifest':json.loads(manifest),'archive_manifest_sha256':sha(manifest),
     'archive_service_sha256':sha((a/'backend/archive_backend/service.py').read_bytes()),
     'payment_manifest_sha256':sha((p/'manifest.json').read_bytes()),
     'function_definitions':definitions,'function_states':states,'table_names':names,'cash_enabled':enabled,
     'candidate_config_registered':bool(exists),'player_data_read':False,'database_mutations':0,'gateway_requests':0},ensure_ascii=False))
    ''')
    result=subprocess.run(ssh_options(),input=code.encode('utf-8'),capture_output=True,cwd=ROOT,timeout=55,creationflags=getattr(subprocess,'CREATE_NO_WINDOW',0))
    (OUT/'preflight_live.stderr.txt').write_bytes(result.stderr)
    if result.returncode:raise RuntimeError('readonly_preflight_failed_'+str(result.returncode))
    data=json.loads(result.stdout)
    data['configuration_input_sha256']=hashlib.sha256((OUT.parent/'release_fbf16/configuration.json').read_bytes()).hexdigest()
    (OUT/'preflight_live.json').write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print(json.dumps({k:v for k,v in data.items() if k not in ('archive_manifest','function_definitions','table_names')},ensure_ascii=False))

if __name__ == "__main__":
    main()
