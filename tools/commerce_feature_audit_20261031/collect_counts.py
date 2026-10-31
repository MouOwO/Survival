"""Collect bounded real-module synthetic traces; never claim native/FPS data."""
from pathlib import Path
import argparse,hashlib,json,re,subprocess

ROOT=Path(__file__).resolve().parents[2]
VIEW=Path('D:/Survival_发布候选/20261031_ws4_shop_recovery_v01_view')
CONTENT='318491d5f839653d888c350dcaa7fb639189ec427779004879819d3ac9b45352'


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output',type=Path,required=True)
    args=parser.parse_args();manifest=json.loads((VIEW/'_release_manifest.json').read_bytes())
    assert manifest['content_sha256']==CONTENT
    pins={row['path']:row for row in manifest['files']}
    names=['systems/commerce_runtime','systems/commerce_effects','systems/permanent_reward_effect_service',
        'systems/hero_progression_system','systems/training_room_service','systems/lottery_dynamic_effects']
    sources={}
    for name in names:
        path='scripts/vscripts/'+name+'.lua';digest=hashlib.sha256((VIEW/path).read_bytes()).hexdigest()
        assert digest==pins[path]['sha256'];sources[path]=digest
    scripts=['reproduce_privilege_edges.lua','count_commerce_stable_calls.lua','count_projection_refresh.lua'];traces={}
    for name in scripts:
        path=Path(__file__).with_name(name)
        result=subprocess.run(['C:/Program Files/lua/bin/lua5.1.exe',str(path),str(VIEW)],cwd=ROOT,
            capture_output=True,encoding='utf8',timeout=30)
        assert result.returncode==0,result.stderr
        traces[name]=dict(script_sha256=hashlib.sha256(path.read_bytes()).hexdigest(),stdout=result.stdout)
    stable=[dict((key,int(value)) for key,value in re.findall(r'([a-z_]+)=(\d+)',line))
        for line in traces[scripts[1]]['stdout'].splitlines() if line.startswith('COMMERCE_STABLE_CALLS ')]
    projection=next(line for line in traces[scripts[2]]['stdout'].splitlines() if line.startswith('IDENTICAL_PROFILE_PROJECTION '))
    projection=dict((key,int(value)) for key,value in re.findall(r'([a-z_]+)=(\d+)',projection))
    assert len(stable)==4 and projection['commerce_full_projections']==60 and projection['emitted_changed_outputs']==1
    for row in stable:assert row['actual_native_calls']==row['actual_network_calls']==0
    record=dict(schema=1,kind='BOUNDED_SYNTHETIC_ACTUAL_LUA_MODULE_COUNTS',baseline_release_sequence=2026103102,
        content_sha256=CONTENT,real_player_mutations=0,native_fps_measured=False,source_sha256=sources,
        stable_commerce_counts=stable,identical_profile_projection=projection,traces=traces)
    args.output.parent.mkdir(parents=True,exist_ok=True)
    args.output.write_text(json.dumps(record,ensure_ascii=False,indent=2)+'\n',encoding='utf8',newline='\n')
    print(json.dumps(dict(status='ACTUAL_MODULE_SYNTHETIC_COUNTERS_COLLECTED',stable_cases=len(stable),
        partial_feature_cases=4,actual_native_calls=0,actual_network_calls=0,native_fps_measured=False)))


if __name__=='__main__':main()
