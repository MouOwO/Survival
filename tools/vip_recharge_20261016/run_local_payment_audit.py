"""Native Lua validation and formal-CSV consistency; never writes player saves."""
from pathlib import Path
import csv, hashlib, json, subprocess

ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'design_refs/vip_recharge_20261016/payment'
LUA=Path('C:/Program Files/lua/bin/lua5.1.exe')
def rows(name):
    with (ROOT/'data/csv/存档系统'/name).open(encoding='utf-8-sig',newline='') as stream:
        return [r for r in csv.DictReader(stream) if r and not next(iter(r.values()),'').startswith('#')]
levels=rows('archive_vip_levels.csv')
rewards=rows('archive_vip_rewards.csv')
baseline=json.loads((OUT/'online_baseline.json').read_text(encoding='utf-8'))
assert [(int(r['level']),int(r['required_recharge_fen'])) for r in levels]==[tuple(v) for v in baseline['thresholds']]
assert len(rewards)==33 and sum(r['group_id']=='privileges' for r in rewards)==12
source=(ROOT/'scripts/vscripts/tests/test_reward_effect_audit.lua').read_text(encoding='utf-8-sig')
# The saved 20261003 audit predates separation of landed attack from positive
# damage. Exercise today's real damage callback as well as attack-only armor.
source=source.replace("bus.emit(ev.TOWER_ATTACK_LANDED,{tower=tower,target=enemy,damage=100})",
                      "bus.emit(ev.TOWER_ATTACK_LANDED,{tower=tower,target=enemy,damage=100});bus.emit('commerce.tower_damage',{tower=tower,target=enemy,damage=100})")
vip_source=(ROOT/'scripts/vscripts/tests/test_vip_effect_consumers.lua').read_text(encoding='utf-8-sig')
vip_source=vip_source.replace("bus.emit(ev.TOWER_ATTACK_LANDED,{tower=tower,target=unit(951),damage=100})",
                              "bus.emit('commerce.tower_damage',{tower=tower,target=unit(951),damage=100})")
source+='\nassert(loadstring('+json.dumps(vip_source,ensure_ascii=False)+'))()({check=check,near=near,private=private,set=set,unit=unit,hero=hero,bus=bus,ev=ev,totals=totals})\n'
source+='''
require('tests/test_vip_audit_extra')({check=check,near=near,private=private,set=set,unit=unit,hero=hero,bus=bus,ev=ev,totals=totals})
check('vip_tower_damage_requires_actual_positive_damage',function()
 set({tower_damage_attack_growth=1.5})
 local tower=unit(999);tower.survival_player_id=0
 bus.emit(ev.TOWER_ATTACK_LANDED,{tower=tower,target=unit(998),damage=100})
 near(tower.survival_tower_personal_attack_growth or 0,0)
 bus.emit('commerce.tower_damage',{tower=tower,target=unit(998),damage=0})
 near(tower.survival_tower_personal_attack_growth or 0,0)
 bus.emit('commerce.tower_damage',{tower=tower,target=unit(998),damage=100})
 near(tower.survival_tower_personal_attack_growth,1.5)
 return 'attack-only and zero-damage events grant no growth; actual positive damage grants exact 1.5'
end)
local output=assert(io.open('design_refs/vip_recharge_20261016/payment/local_consumer_results.json','w'))
output:write(require('core/json_encoder').encode(AUDIT_RESULTS));output:close()
for _,result in ipairs(AUDIT_RESULTS)do
 if (result.name:match('^vip_') or result.name=='laser_cadence_from_saved_rewards') and not result.ok then
  error('vip_consumer_failed:'..result.name)
 end
end
'''
harness=ROOT/'tools/vip_recharge_20261016/consumer_harness.generated.lua'
harness.write_text(source,encoding='utf-8')
cases=[]
for label,path in [('vip_rewards',ROOT/'scripts/vscripts/tests/test_vip_rewards.lua'),
                   ('payment_stat_projection',ROOT/'scripts/vscripts/tests/test_payment_stat_projection.lua'),
                   ('vip_consumers',harness)]:
    result=subprocess.run([str(LUA),str(path.relative_to(ROOT))],cwd=ROOT,capture_output=True,timeout=60,
                          creationflags=getattr(subprocess,'CREATE_NO_WINDOW',0))
    (OUT/(label+'.stdout.txt')).write_bytes(result.stdout)
    (OUT/(label+'.stderr.txt')).write_bytes(result.stderr)
    cases.append({'name':label,'exit_code':result.returncode,'ok':result.returncode==0})
    assert result.returncode==0,label+' failed; see captured stderr'
consumers=json.loads((OUT/'local_consumer_results.json').read_text(encoding='utf-8'))
report={'status':'PASS','cases':cases,'formal_levels':len(levels),'formal_rewards':len(rewards),
        'csv_and_live_sql_thresholds_equal':True,
        'historical_fixture_adaptation':'Only temporary harness changed to use current commerce.tower_damage callback for damage-based tower growth; production source and original tests unchanged.',
        'vip_consumer_checks':[r for r in consumers if r['name'].startswith('vip_') or r['name']=='laser_cadence_from_saved_rewards'],
        'other_consumer_failures':[r for r in consumers if not r['ok']],
        'source_sha256':{str(p.relative_to(ROOT)).replace('\\','/'):hashlib.sha256(p.read_bytes()).hexdigest()
                         for p in [ROOT/'scripts/vscripts/systems/archive_vip_rewards.lua',ROOT/'scripts/vscripts/systems/archive_settlement.lua',
                                   ROOT/'data/csv/存档系统/archive_vip_levels.csv',ROOT/'data/csv/存档系统/archive_vip_rewards.csv']},
        'database_connections':0,'gateway_requests':0,'real_player_writes':0}
(OUT/'local_validation.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print(json.dumps({'status':report['status'],'cases':len(cases),'vip_consumer_checks':len(report['vip_consumer_checks']),
                  'other_failures':[r['name'] for r in report['other_consumer_failures']]},ensure_ascii=False))
