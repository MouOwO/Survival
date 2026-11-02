"""Undo only our mistaken legacy API pointer change; preserve both releases."""
from pathlib import Path
import importlib.util
import hashlib
import json

ROOT = Path(__file__).resolve().parents[1]
transport_path=ROOT/'tools/archive_release_20261029/server_deploy.py'
assert hashlib.sha256(transport_path.read_bytes()).hexdigest()=='66413c174fb6fe27d5ae84dc267ceea07366c6f6a855a9406e5ffdaf388b1cc5'
spec = importlib.util.spec_from_file_location('legacy_transport', transport_path)
transport = importlib.util.module_from_spec(spec)
spec.loader.exec_module(transport)
SOURCE = r'''
from pathlib import Path, PurePosixPath
import hashlib,json,os,subprocess,time,urllib.request
sha=lambda raw:hashlib.sha256(raw).hexdigest()
base=Path('/opt/goufayu/releases');pointer=base/'current'
old=base/'20261029-redemption-2f918e4c0edd'
ours=base/'20261102-lottery-receipt-d2c7c2e85920'
assert pointer.is_symlink() and pointer.resolve()==ours
assert sha((ours/'release_manifest.json').read_bytes())=='04f03ebdc6681c00a76fdc0ed239e7f59066de39bb873bd1020908562e73051a'
raw=(old/'release_manifest.json').read_bytes()
assert sha(raw)=='a70ec3b61bc56321751892982f0a79c6244836348084e1e350b80b737fc76138'
for name,digest in json.loads(raw)['files'].items():
 p=PurePosixPath(name);assert not p.is_absolute() and '..' not in p.parts
 target=old/name;assert not target.is_symlink() and target.resolve().is_relative_to(old)
 assert sha(target.read_bytes())==digest
def pid(unit):return subprocess.check_output(['systemctl','show',unit,'--property=MainPID','--value'],text=True).strip()
retained={u:pid(u) for u in ('goufayu-payment.service','goufayu-db.service','goufayu-ws4.service','goufayu-ws4-payment.service')}
assert pid('goufayu-api.service')=='577091'
temp=base/('current.rollback.receipt.'+str(os.getpid()))
assert not temp.exists() and not temp.is_symlink()
temp.symlink_to(old,target_is_directory=True);os.replace(temp,pointer)
assert subprocess.run(['systemctl','restart','goufayu-api.service'],capture_output=True,timeout=45).returncode==0
for attempt in range(40):
 try:
  with urllib.request.urlopen('http://127.0.0.1:8765/health',timeout=3) as response:assert response.status==200
  break
 except Exception:
  if attempt==39:raise
  time.sleep(.25)
assert pointer.resolve()==old and all(pid(u)==p for u,p in retained.items())
print(json.dumps(dict(ok=True,status='LEGACY_API_OWN_CHANGE_ROLLED_BACK',current=old.name,prepared_release_preserved=ours.is_dir(),retained_services_unchanged=True,sql_writes=0)))
'''
if __name__ == '__main__':
    result=transport.remote(SOURCE,timeout=120)
    path=ROOT/'output/lottery_replay_release_20261102/backend/rollback_legacy.json'
    path.write_text(json.dumps(result,indent=2)+'\n',encoding='utf8')
    print(json.dumps(result))
