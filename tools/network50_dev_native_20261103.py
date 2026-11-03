"""Own one explicitly prepared Tools/offline snapshot; never production install."""
from pathlib import Path
import importlib.util,json,subprocess,sys
ROOT=Path(__file__).resolve().parents[1]
def module(name,file):
    spec=importlib.util.spec_from_file_location(name,ROOT/'tools'/file)
    value=importlib.util.module_from_spec(spec);spec.loader.exec_module(value);return value
p=module('native_network50_base','network50_native_probe_20261103.py')
dev=module('native_network50_copy','prepare_network50_dev_20261103.py')
STORE=dev.STORE/'run01'
def launch():
    if p.clients():raise ValueError('existing_client_preserved')
    dev.verify(STORE.name)
    prepared=json.loads((STORE/'prepared.json').read_bytes())
    receipt=STORE/'process.json';log=ROOT/'output/network50_dev_20261103'/STORE.name/'engine.log'
    if receipt.exists() or log.exists():raise ValueError('fresh_process_and_log_required')
    log.parent.mkdir(parents=True,exist_ok=True)
    argv=prepared['suggested_argv']
    argv=argv[:1]+['-condebug','-con_logfile',str(log),'+net_showmsg','CUserMsg_CustomGameEvent',
        '+net_restrict_showmsg_socket','client']+argv[1:]
    child=subprocess.Popen(argv,cwd=p.GAME/'dota',creationflags=getattr(subprocess,'CREATE_NO_WINDOW',0))
    observed=p.clients();rows=observed if isinstance(observed,list)else[observed]
    identity=next((r for r in rows if r and r['pid']==child.pid),None)
    if not identity:raise ValueError('owned_process_identity_missing')
    report=dict(status='ACTUAL_PROJECT_TOOLS_OFFLINE_STARTED',**identity,argv=argv,
        snapshot_manifest_sha256=prepared['manifest_sha256'],log=str(log),
        transactions=0,backend_enabled=False,production_acceptance=False,workshop_install_written=False)
    p.write_new(receipt,(json.dumps(report,indent=2)+'\n').encode());return report
def close():
    p.STORE=STORE;return p.close()
def retire():
    if p.clients():raise ValueError('client_still_running_preserve_mounts')
    report=json.loads((STORE/'prepared.json').read_bytes())
    for row in report['mounts']:
        link,target=Path(row['path']),Path(row['target'])
        if not link.is_junction() or link.resolve()!=target.resolve():raise ValueError('exact_owned_dev_junction_required')
    for row in report['mounts']:Path(row['path']).rmdir()
    result=dict(status='TOOLS_DEV_MOUNTS_RETIRED_FILES_PRESERVED',run=STORE.name,transactions=0)
    p.write_new(STORE/'mounts_retired.json',(json.dumps(result,indent=2)+'\n').encode());return result
if __name__=='__main__':
    actions={'launch':launch,'close':close,'retire':retire}
    if len(sys.argv)not in (2,3)or sys.argv[1]not in actions:raise SystemExit('explicit launch/close/retire required')
    if len(sys.argv)==3:
        if sys.argv[2]not in ('run02','run03','run04','run05','run06'):raise SystemExit('known fresh development run required')
        STORE=dev.STORE/sys.argv[2]
    print(json.dumps(actions[sys.argv[1]]()))
