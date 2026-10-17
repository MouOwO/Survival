"""Read-only authenticated config hash and collection metadata after activation."""
from __future__ import annotations
import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import deploy_driver

def run(candidate):
    source = '''from pathlib import Path
import importlib.util,json,urllib.request
expected=EXPECTED
root=Path('/opt/goufayu/releases/current').resolve()
spec=importlib.util.spec_from_file_location('rarity_readonly_http',root/'deploy/manage.py')
manage=importlib.util.module_from_spec(spec);spec.loader.exec_module(manage)
environment=manage.read_environment(Path('/etc/goufayu/api.env'))
request=urllib.request.Request('http://127.0.0.1:8765/v1/archive/config',data=b'{}',method='POST',headers={'Content-Type':'application/json','Authorization':'Bearer '+environment['FISHING_API_TOKEN']})
with urllib.request.urlopen(request,timeout=10) as response:
 result=json.load(response)
 assert response.status==200 and result.get('ok') is True and result.get('config_hash')==expected
pointer=json.loads((root/'addon/server/bundles/current.json').read_bytes())
assert pointer['hash']==expected
bundle=json.loads((root/'addon/server/bundles'/expected/'bundle.json').read_bytes())
items=bundle['configs']['archive_social_items']['rows']
rules=bundle['configs']['archive_social_rules']['rows']
pools={}
for pool in ['ex','friend','wife','beast']:
 rows=[row for row in items if row['pool_id']==pool]
 rule=next(row for row in rules if row['pool_id']==pool)
 pools[pool]={'count':len(rows),'drawable_count':len([row for row in rows if row.get('draw_enabled') is not False]),'qualities':{q:len([row for row in rows if row['quality']==q]) for q in ['N','R','SR','SSR','UR']},'weights':{q:rule['quality_weight_'+q.lower()] for q in ['N','R','SR','SSR','UR']}}
print(json.dumps({'status':'PASS_LIVE_CONFIG_HASH','api_config_hash':result['config_hash'],'archive_release':str(root),'collections':pools,'player_api_commands':0,'persistent_writes':0}))
'''.replace("EXPECTED", repr(candidate), 1)
    # The config directory is fixed by the current release's manage module.
    source = source.replace("Path('/etc/goufayu/api.env')", "manage.CONFIG / 'api.env'")
    return deploy_driver.remote(candidate, "postflight", source)

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("candidate")
    arguments = parser.parse_args()
    print(json.dumps(run(arguments.candidate), ensure_ascii=False))
