"""Read-only check of the active Steam account's authoritative resource fields."""
import json
import os
import urllib.request
import winreg
from pathlib import Path

with winreg.OpenKey(winreg.HKEY_CURRENT_USER, r'Software\Valve\Steam\ActiveProcess') as key:
    account=str(winreg.QueryValueEx(key,'ActiveUser')[0])
assert int(account)>0
opener=urllib.request.build_opener(urllib.request.ProxyHandler({}))
def post(path,payload):
    request=urllib.request.Request('http://127.0.0.1:8765'+path,data=json.dumps(payload).encode(),
        headers={'Authorization':'Bearer '+os.environ['FISHING_API_TOKEN'],'Content-Type':'application/json'})
    with opener.open(request,timeout=30) as response:return json.load(response)
bundle=json.loads((Path(__file__).resolve().parents[1]/'server/bundles/current.json').read_text())
assert post('/v1/archive/config',{})['config_hash']==bundle['hash']
profile=post('/v1/profile',{'account_id':account})
stats=profile['save']['gameplay_stats']
print(json.dumps({'config_matches':True,'initial_wood':stats['initial_wood'],
    'wood_per_second':stats['wood_per_second'],'revision':profile['revision']}))
