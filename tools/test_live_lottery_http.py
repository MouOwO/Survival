"""Real HTTP/Supabase smoke: read pools and persist a visit; never grants test funds."""
import json
import os
from pathlib import Path
import time
import urllib.request
import winreg

root = Path(__file__).resolve().parents[1]
with winreg.OpenKey(winreg.HKEY_CURRENT_USER, r"Software\Valve\Steam\ActiveProcess") as key:
    account = str(winreg.QueryValueEx(key, "ActiveUser")[0])
assert int(account)>0, "Steam account is not active"
opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
def post(path, data):
    request = urllib.request.Request("http://127.0.0.1:8765"+path,
        data=json.dumps(data).encode(),headers={"Authorization":"Bearer "+os.environ["FISHING_API_TOKEN"],"Content-Type":"application/json"})
    with opener.open(request, timeout=30) as response:
        return json.load(response)

bundle = json.loads((root/"server/bundles/current.json").read_text())["hash"]
assert post('/v1/archive/config',{})['config_hash']==bundle
payload={'account_id':account,'config_hash':bundle}
snapshot=post('/v1/lottery/snapshot',payload)
assert snapshot['ok'],snapshot.get('error')
selected=next(p for p in snapshot['snapshots'] if p['selected_pool_id']=='map')
operation='livevisit_'+str(time.time_ns())
command=dict(payload,command={'id':operation,'kind':'lottery_read','pool_id':'map',
    'read_action':'visit','revision':selected['selected_pool']['revision'],'request_id':operation})
first=post('/v1/archive/command',command)
assert first['ok'],first.get('error')
again=post('/v1/archive/command',command)
assert again['ok'] and first['response']==again['response']
profile=post('/v1/profile',{'account_id':account})
assert profile['save']['archive']['lottery_state']['pools']['map']['visited_revision']==selected['selected_pool']['revision']
assert first['profile']['save']['content_inventory']==again['profile']['save']['content_inventory']
empty_balance_checked=False
if selected['tickets']==0:
    rejected=post('/v1/archive/command',dict(payload,command={'id':operation+'_empty','kind':'lottery_draw',
        'pool_id':'map','count':1,'request_id':operation+'_empty'}))
    assert not rejected['ok'] and rejected['error']=='lottery_ticket_insufficient'
    assert rejected['profile']['save']['content_inventory']==profile['save']['content_inventory']
    empty_balance_checked=True
print(json.dumps({'live_http':'pass','pool_count':len(snapshot['snapshots']),
    'visit_persisted':True,'duplicate_receipt_identical':True,'profile_readback':True,
    'test_currency_granted':False,'empty_balance_rejected_without_grant':empty_balance_checked},ensure_ascii=False))
