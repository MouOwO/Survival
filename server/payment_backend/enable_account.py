"""Root-only operator action: enable one explicit Steam account for the RMB .10 test.

Usage on the ECS: .venv/bin/python payment_backend/enable_account.py STEAM_ID
Accepts SteamID64 or the game's Steam account ID. No payment is created here.
"""
import json
import os
from pathlib import Path
import re
import subprocess
import sys

def main(value):
    if sys.platform!='linux' or os.geteuid()!=0:raise ValueError('linux_root_required')
    if not re.fullmatch(r'[0-9]{1,20}',value):raise ValueError('numeric_steam_id_required')
    account=int(value)
    if account>=76561197960265728:account-=76561197960265728
    if not 0<account<2**32:raise ValueError('steam_account_id_invalid')
    path=Path('/etc/goufayu-payment/config.json')
    if path.is_symlink():raise ValueError('config_symlink_refused')
    info=path.stat();config=json.loads(path.read_text())
    config['allowed_accounts']=sorted(set(config['allowed_accounts']+[str(account)]))
    temporary=path.with_suffix('.new')
    with temporary.open('w') as output:
        os.chmod(temporary,0o640);os.chown(temporary,0,info.st_gid)
        json.dump(config,output);output.flush();os.fsync(output.fileno())
    os.replace(temporary,path)
    subprocess.run(['systemctl','restart','goufayu-payment.service'],check=True)
    print(json.dumps({'enabled_account':str(account),'order_created':False}))

if __name__=='__main__':main(sys.argv[1])
