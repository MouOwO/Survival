"""Sanitized read-only service stderr and candidate permission diagnostics."""
from pathlib import Path
import contextlib
import importlib.util
import io
import json

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'output/points_daily_unique_20261019/release_v2'
plan = json.loads((OUT / 'plan.json').read_bytes())
source = 'RELEASE=' + repr(plan['archive_release']) + '\nDIGEST=' + repr(plan['bundle']) + '\n' + r'''
from pathlib import Path
import json,os,re,stat,subprocess
new=Path('/opt/goufayu/releases')/RELEASE
properties=('User','Group','Type','WorkingDirectory','StandardOutput','StandardError','FragmentPath',
 'ActiveState','SubState','ActiveEnterTimestamp','ExecMainStartTimestamp','ExecMainExitTimestamp','TimeoutStartUSec')
result=subprocess.run(['systemctl','show','goufayu-api.service',*[arg for p in properties for arg in ('-p',p)]],capture_output=True,text=True,timeout=10)
unit=dict(line.split('=',1) for line in result.stdout.splitlines() if '=' in line)
logs=[]
for key in ('StandardOutput','StandardError'):
 value=unit.get(key,'')
 if value.startswith(('append:/','file:/','truncate:/')):logs.append(Path(value.split(':',1)[1]))
for directory in (Path('/var/log/goufayu'),Path('/opt/goufayu/logs')):
 if directory.is_dir():logs.extend(path for path in directory.iterdir() if path.is_file() and path.suffix in ('.log','.err','.out'))
logs.extend(path for path in Path('/var/log').glob('*goufayu*') if path.is_file())
records=[]
for path in dict.fromkeys(logs):
 if not path.is_file():continue
 with path.open('rb') as stream:
  stream.seek(max(0,path.stat().st_size-240000));text=stream.read().decode('utf-8','replace')
 errors=[];frames=[]
 for line in text.splitlines():
  match=re.match(r'^\s*File "(/opt/goufayu/[A-Za-z0-9_./-]+\.py)", line ([0-9]+), in ([A-Za-z0-9_<>]+)',line)
  if match:frames.append({'file':Path(match.group(1)).name,'line':int(match.group(2)),'function':match.group(3)})
  match=re.search(r'\b([A-Za-z_][A-Za-z0-9_.]*(?:Error|Exception)):\s*(.*)',line)
  if match:
   detail=match.group(2).strip();code='details_suppressed'
   if re.fullmatch(r'[A-Za-z_][A-Za-z0-9_.:-]{0,140}',detail):code=detail
   elif 'Permission denied' in detail:code='permission_denied'
   elif detail.startswith('No module named '):code='module_not_found:'+detail[len('No module named '):].strip("'\"")
   elif 'No such file or directory' in detail:code='file_not_found'
   errors.append({'type':match.group(1),'code':code})
 records.append({'file':str(path),'size':path.stat().st_size,'errors':errors[-12:],'frames':frames[-12:]})
journal=subprocess.run(['journalctl','-u','goufayu-api.service','--since','25 minutes ago','--no-pager','-o','json'],capture_output=True,text=True,timeout=10).stdout
events=[];structured=[];codes=[]
for line in journal.splitlines():
 try:record=json.loads(line)
 except ValueError:continue
 message=str(record.get('MESSAGE',''))
 for phrase in ('Starting ','Started ','Stopping ','Stopped ','Main process exited','Failed with result','Failed at step','Scheduled restart job'):
  if phrase in message:
   row={'event':phrase.strip(),'timestamp_microseconds':record.get('__REALTIME_TIMESTAMP')}
   status=re.search(r'status=([0-9]+/[A-Z_]+)',message)
   if status:row['status']=status.group(1)
   events.append(row);break
 try:entry=json.loads(message[message.index('{'):])
 except (ValueError,TypeError):entry=None
 if isinstance(entry,dict):
  safe={}
  for key in ('event','status','error','error_code','error_type','level','code'):
   if key in entry and isinstance(entry[key],str) and re.fullmatch(r'[A-Za-z_][A-Za-z0-9_.:-]{0,140}',entry[key]):safe[key]=entry[key]
  if safe:structured.append(safe)
 for token in re.findall(r'\b[A-Za-z_][A-Za-z0-9_.:-]{2,140}\b',message):
  if any(word in token.lower() for word in ('error','exception','mismatch','invalid','denied','refused','unavailable','missing','failed')):
   if token not in codes:codes.append(token)
launch=subprocess.run(['systemctl','show','goufayu-api.service','-p','ExecStart'],capture_output=True,text=True,timeout=10).stdout
launcher=re.search(r'path=([^ ;]+)',launch)
launcher_info={}
if launcher:
 path=Path(launcher.group(1));launcher_info['executable']=str(path)
 if path.is_file() and path.suffix in ('.sh','.py'):
  content=path.read_text('utf-8',errors='replace')
  launcher_info['redirect_log_paths']=re.findall(r'(?:>>?|2>>?)\s*(/var/log/[A-Za-z0-9_./-]+)',content)
  launcher_info['wait_or_retry_keywords']=sorted(set(re.findall(r'\b(?:sleep|retry|health|curl|until|timeout)\b',content)))
targets=[new,new/'backend',new/'backend/archive_backend',new/'backend/fishing_api',
 new/'backend/archive_backend/service.py',new/'backend/archive_backend/unique_points.py',new/'backend/archive_backend/daily_unique.py',
 new/'addon',new/'addon/server',new/'addon/server/bundles',new/'addon/server/bundles'/DIGEST,
 new/'addon/server/bundles'/DIGEST/'bundle.json',new/'addon/server/bundles'/DIGEST/'worker.lua',new/'.venv',new/'.venv/bin/python']
permissions=[]
for path in targets:
 record={'path':str(path.relative_to(new)) or '.', 'exists':path.exists()}
 if path.exists():
  info=path.stat();record.update(mode=oct(stat.S_IMODE(info.st_mode)),uid=info.st_uid,gid=info.st_gid,is_directory=path.is_dir())
 permissions.append(record)
user=unit.get('User') or 'root'
probe="import os,json; p="+repr([str(path) for path in targets])+"; print(json.dumps([{'path':x,'readable':os.access(x,os.R_OK),'traversable':os.access(x,os.X_OK)} for x in p]))"
args=[str(new/'.venv/bin/python'),'-B','-c',probe]
if user!='root':args=['runuser','-u',user,'--',*args]
result=subprocess.run(args,capture_output=True,text=True,timeout=10)
readability={'exit':result.returncode}
if result.returncode==0:
 readability['paths']=[dict(path=str(Path(row['path']).relative_to(new)) or '.',readable=row['readable'],traversable=row['traversable']) for row in json.loads(result.stdout)]
else:
 readability['error_code']='permission_denied' if 'Permission denied' in result.stderr else 'probe_failed_details_suppressed'
print(json.dumps({'status':'READONLY_STARTUP_LOG_DIAGNOSTIC','unit':unit,'logs':records,'candidate_permissions':permissions,
 'service_user_readability':readability,'journal_events':events[-25:],'journal_structured':structured[-15:],
 'journal_error_codes':codes[-30:],'launcher':launcher_info,'database_writes':0,'service_actions':0}))
'''


def main():
    spec = importlib.util.spec_from_file_location('daily_startup_diagnostic_transport', ROOT / 'tools/shop_pricing_half_20261017/remote.py')
    transport = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(transport)
    transport.OUT = OUT / 'remote'
    with contextlib.redirect_stdout(io.StringIO()):
        result = transport.execute(source, 'startup_diagnostic', timeout=60)
    print(json.dumps(result['records'][0], ensure_ascii=False))


if __name__ == '__main__':
    main()
