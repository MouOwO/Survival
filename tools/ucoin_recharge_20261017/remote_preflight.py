"""Pinned SSH read-only deployment preflight; no upload or server mutation."""
import hashlib
import json
from pathlib import Path
import subprocess
import sys

ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'design_refs/ucoin_recharge_20261017/remote'
EXPECTED_BASELINE='20261015-payment02'
EXPECTED_BASELINE_HASH='ab18979b1194a3a3877b3a0635ff9f970e2838ff97783227d2e27a06571b1419'
EXPECTED_TAR_HASH='f21218be1f431865bd339ae91136ac956e8e28f25924cafd7fb5745581f42043'
CODE=r'''
from pathlib import Path
import hashlib,json,subprocess,urllib.request
payment=Path('/opt/goufayu/payments/current').resolve(strict=True)
archive=Path('/opt/goufayu/releases/current').resolve(strict=True)
payment_manifest=hashlib.sha256((payment/'manifest.json').read_bytes()).hexdigest()
pointer=json.loads((archive/'addon/server/bundles/current.json').read_text())
services={}
for name,port in [('archive',8765),('payments',8766)]:
 with urllib.request.urlopen('http://127.0.0.1:'+str(port)+'/health',timeout=10) as response:
  body=json.load(response);services[name]=dict(http_status=response.status,ok=body.get('ok') is True)
matches=payment.name=='20261015-payment02' and payment_manifest=='ab18979b1194a3a3877b3a0635ff9f970e2838ff97783227d2e27a06571b1419'
print(json.dumps(dict(status='PASS' if matches else 'BASELINE_DRIFT_STOP',payment_release=payment.name,
 payment_manifest_sha256=payment_manifest,archive_release=archive.name,archive_bundle=pointer.get('hash'),health=services,
 expected_payment_release='20261015-payment02',baseline_matches=matches,read_only=True,
 uploads=0,mutations=0,orders_created=0,gateway_requests=0)))
'''


def main():
    tar=ROOT/'output/payment_release/20261017-payment01.tar.gz'
    assert hashlib.sha256(tar.read_bytes()).hexdigest()==EXPECTED_TAR_HASH,'frozen_tarball_changed'
    options=['-T','-F','none','-o','BatchMode=yes','-o','StrictHostKeyChecking=yes',
        '-o','UserKnownHostsFile=tools/deploy/goufayu_test_known_hosts','-o','IdentitiesOnly=yes',
        '-o','ConnectTimeout=10','-i',str(Path.home()/'.ssh/goufayu_ecs_ed25519_v2')]
    result=subprocess.run(['ssh.exe',*options,'root@47.110.238.248',
        '/opt/goufayu/payments/current/.venv/bin/python -B -'],input=CODE.encode(),capture_output=True,
        cwd=ROOT,timeout=45,creationflags=subprocess.CREATE_NO_WINDOW)
    if result.returncode:
        print(json.dumps(dict(status='PREFLIGHT_FAILED',ssh_exit=result.returncode,private_output_suppressed=True)))
        raise SystemExit(result.returncode)
    try:report=json.loads(result.stdout)
    except Exception:raise SystemExit('preflight_response_invalid_private_output_suppressed')
    OUT.mkdir(parents=True,exist_ok=True)
    (OUT/'preflight.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print(json.dumps(report,ensure_ascii=False))
    return 0 if report['baseline_matches'] else 3


if __name__=='__main__':sys.exit(main())
