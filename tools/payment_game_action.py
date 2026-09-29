"""Send a scoped action through a live Tools game, verifying its player first."""
import argparse
import json
from pathlib import Path
import re
import subprocess

parser=argparse.ArgumentParser()
parser.add_argument('action',choices=('catalog','create','status','show'))
parser.add_argument('--account',required=True)
args=parser.parse_args()
if not re.fullmatch(r'[1-9][0-9]{0,9}',args.account):raise SystemExit('invalid_account')
root=Path(__file__).resolve().parents[1]
code="""
local found=nil
for id=0,23 do
 if PlayerResource:IsValidPlayerID(id) and not PlayerResource:IsFakeClient(id)
  and tostring(PlayerResource:GetSteamAccountID(id))==EXPECTED_ACCOUNT then found=id end
end
if found~=nil and require('systems/player_profile_service').get_profile(found) then
 if REQUEST_ACTION=='show' then
  CustomGameEventManager:Send_ServerToPlayer(PlayerResource:GetPlayer(found),'survival_payment_open',{})
 else require('systems/payment_service').handle({PlayerID=found,action=REQUEST_ACTION}) end
 print('PAYMENT_GAME_ACTION:{"sent":true}')
else print('PAYMENT_GAME_ACTION:{"sent":false,"error":"player_not_loaded"}') end
""".replace('EXPECTED_ACCOUNT',json.dumps(args.account)).replace('REQUEST_ACTION',json.dumps(args.action))
path=root/'output/payment_game_action.json'
path.write_text(json.dumps([{'name':'dota_run_lua','arguments':{'code':code}}]),encoding='utf-8')
try:
    result=subprocess.run(['node',str(root/'tools/map_c6/console.cjs'),'--file',str(path),'--timeout-ms','3500'],
        capture_output=True,timeout=15,creationflags=getattr(subprocess,'CREATE_NO_WINDOW',0))
    lines=result.stdout.decode('utf-8','replace').splitlines()
    found=[line[len('PAYMENT_GAME_ACTION:'):] for line in lines if line.startswith('PAYMENT_GAME_ACTION:')]
    print(found[-1] if found else json.dumps({'sent':False,'error':'game_console_unavailable'}))
finally:path.unlink(missing_ok=True)
