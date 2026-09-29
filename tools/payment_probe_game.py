"""Read only the active local Tools player's payment readiness; no console history."""
import json
from pathlib import Path
import subprocess
ROOT=Path(__file__).resolve().parents[1]
request=ROOT/'output/payment_game_probe.json'
lua="""
local rows={}
local profiles=package.loaded['systems/player_profile_service']
local setup=package.loaded['systems/match_setup_service']
for id=0,23 do
 if PlayerResource:IsValidPlayerID(id) and not PlayerResource:IsFakeClient(id) then
  local p=profiles and profiles.get_account_profile(id)
  rows[#rows+1]={player_id=id,account_id=tostring(PlayerResource:GetSteamAccountID(id)),
   loaded=p~=nil,owned=p and p.save and p.save.content_inventory and p.save.content_inventory.lottery_monkey_king or 0}
 end
end
print('PAYMENT_GAME_PROBE:'..require('core/json_encoder').encode({players=rows,
 session=setup and setup.get_session_id() or '',tools=IsInToolsMode(),payment_loaded=package.loaded['systems/payment_service']~=nil}))
"""
request.parent.mkdir(parents=True,exist_ok=True)
request.write_text(json.dumps([{'name':'dota_run_lua','arguments':{'code':lua}}]),encoding='utf-8')
try:
    result=subprocess.run(['node',str(ROOT/'tools/map_c6/console.cjs'),'--file',str(request),'--timeout-ms','3500'],
        capture_output=True,timeout=15,creationflags=getattr(subprocess,'CREATE_NO_WINDOW',0))
    lines=result.stdout.decode('utf-8','replace').splitlines()
    found=[x[len('PAYMENT_GAME_PROBE:'):] for x in lines if x.startswith('PAYMENT_GAME_PROBE:')]
    print(found[-1] if found else json.dumps({'game_connected':False}))
finally:request.unlink(missing_ok=True)
