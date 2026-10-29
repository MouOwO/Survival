"""Register/update a validated Excel without redeploying gameplay or payments."""
import argparse
import base64
import json
from pathlib import Path
import sys

import deploy as deployment
from import_excel import compile_workbook


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('workbook',type=Path)
    parser.add_argument('--apply',action='store_true')
    parser.add_argument('--via-local-proxy',action='store_true')
    args=parser.parse_args()
    value=compile_workbook(args.workbook)
    if not args.apply:
        print(json.dumps({'ok':True,'codes':len(value['codes']),'server_modified':False}));return
    if args.via_local_proxy:
        original=deployment.transport.options
        proxy=Path(__file__).with_name('ssh_proxy.py').resolve().as_posix()
        command='ProxyCommand='+Path(sys.executable).as_posix()+' "'+proxy+'" %h %p'
        deployment.transport.options=lambda:[*original(),'-o',command]
    encoded=base64.b64encode(json.dumps(value,ensure_ascii=False,separators=(',',':')).encode()).decode()
    source='PAYLOAD='+repr(encoded)+'\n'+'''
from pathlib import Path
import base64,fcntl,json,sys
from psycopg.types.json import Jsonb
current=Path('/opt/goufayu/releases/current').resolve(strict=True)
assert current.parent==Path('/opt/goufayu/releases')
manifest=json.loads((current/'release_manifest.json').read_bytes())
assert manifest.get('redemption_codes') is True
pay=Path('/opt/goufayu/payments/current').resolve(strict=True)
assert pay.parent==Path('/opt/goufayu/payments')
sys.path.insert(0,str(pay))
from deploy import connection
codes=json.loads(base64.b64decode(PAYLOAD,validate=True))['codes']
with Path('/var/lock/survival_archive_release.lock').open('a')as lock:
 fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
 with connection()as conn:
  assert conn.info.dbname=='goufayu_test'
  conn.execute('SET LOCAL ROLE goufayu_owner')
  conn.execute('SELECT pg_advisory_xact_lock(719232014021)')
  for c in codes:
   conn.execute('INSERT INTO public.redemption_codes(code_id,code_hash,label,rewards,enabled,starts_at,expires_at,max_redemptions) '
    'VALUES(%s,%s,%s,%s,%s,coalesce(%s::timestamptz,clock_timestamp()),%s::timestamptz,%s) '
    'ON CONFLICT(code_hash) DO UPDATE SET label=excluded.label,rewards=excluded.rewards,enabled=excluded.enabled,'
    'starts_at=coalesce(%s::timestamptz,redemption_codes.starts_at),expires_at=excluded.expires_at,max_redemptions=excluded.max_redemptions',
    (c['code_id'],c['code_hash'],c['label'],Jsonb(c['rewards']),c['enabled'],c['starts_at'],c['expires_at'],c['max_redemptions'],c['starts_at']))
print(json.dumps({'ok':True,'codes':len(codes),'server_modified':True,'existing_claims_preserved':True,'plaintext_stored':False}))
'''
    print(json.dumps(deployment.transport.remote(source),ensure_ascii=False))


if __name__=='__main__':main()
