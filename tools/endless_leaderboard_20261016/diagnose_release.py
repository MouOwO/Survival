"""Read-only service/process/phase metadata, without environment values."""
import json
from deploy_driver import remote
CODE=r'''from pathlib import Path
import json,subprocess,urllib.request
directory=Path('/tmp/survival-endless-leaderboard-20261016-v2')
reports={}
for name in ['database_committed.json','activation_failed.json','activated.json']:
 p=directory/name
 if p.exists():reports[name]=json.loads(p.read_bytes())
pid=subprocess.run(['systemctl','show','goufayu-api.service','--property=MainPID','--value'],capture_output=True,text=True,check=True).stdout.strip()
state=subprocess.run(['systemctl','is-active','goufayu-api.service'],capture_output=True,text=True).stdout.strip()
configured=subprocess.run(['systemctl','show','goufayu-api.service','--property=WorkingDirectory','--value'],capture_output=True,text=True,check=True).stdout.strip()
cwd=str(Path('/proc/'+pid+'/cwd').resolve()) if pid.isdigit() and int(pid)>1 else None
health={}
for name,port in [('archive',8765),('payment',8766)]:
 try:
  with urllib.request.urlopen('http://127.0.0.1:'+str(port)+'/health',timeout=5) as r:health[name]=json.load(r)
 except Exception as error:health[name]={'error_type':type(error).__name__}
print(json.dumps({'status':'READ_ONLY_DIAGNOSIS','current':str(Path('/opt/goufayu/releases/current').resolve()),'pid':pid,'active_state':state,'configured_working_directory':configured,'physical_cwd':cwd,'health':health,'reports':reports}))
'''
if __name__=='__main__':print(json.dumps(remote('diagnosis',CODE),ensure_ascii=False))
