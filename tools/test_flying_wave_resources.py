"""Validate native flying attacks, resource attachments and config projection.

Run from the addon root. --baseline-ref additionally checks unchanged gameplay
and unselected outfits against a pre-change Git revision.
"""
import argparse
import csv
import re
import subprocess
from pathlib import Path
from build_wave_monster_cosmetics import FLYING_SPECS, ROOT, Vpk, parse_kv

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--baseline-ref')
args = parser.parse_args()

def table(relative, baseline=False):
    if baseline:
        text = subprocess.check_output(['git', 'show', args.baseline_ref + ':' + relative]).decode('utf-8-sig')
    else:
        text = (ROOT / relative).read_text(encoding='utf-8-sig')
    reader = csv.DictReader(line for line in text.splitlines() if line and not line.startswith('#'))
    return {row[reader.fieldnames[0]]: row for row in reader}

model = 'models/heroes/winterwyvern/winterwyvern.vmdl'
projectile = 'particles/units/heroes/hero_winter_wyvern/winter_wyvern_base_attack.vpcf'
archetype_path = 'data/csv/怪物与波次系统/monster_archetypes.csv'
archetypes = table(archetype_path)
resources = {name: table('data/csv/资源系统/' + name + '.csv') for name in (
    'asset_catalog', 'asset_components', 'asset_effects', 'asset_activity_modifiers')}
npc = parse_kv((ROOT/'scripts/npc/npc_units_custom.txt').read_text(encoding='utf-8-sig'))['DOTAUnits']
vpk = Vpk(ROOT.parents[1] / 'dota/pak01_dir.vpk')
vpk.verify(model); vpk.verify(projectile)
outfit_signatures = set()
for key in FLYING_SPECS:
    row = archetypes[key]
    assert row['model_path'] == model and row['attack_type'] == 'ranged', key
    assert row['projectile_model'] == projectile and row['projectile_speed'] == '700', key
    asset_id = 'monster_wave_' + key
    asset = resources['asset_catalog'][asset_id]
    assert asset['primary_model'] == model and asset['portrait_unit_name'] == 'npc_dota_hero_winter_wyvern'
    components = [r for r in resources['asset_components'].values() if r['asset_id'] == asset_id]
    assert len(components) == 2 and {r['component_id'] for r in components} == {'head', 'back'}, key
    signature = tuple(sorted((r['component_id'], r['model_path'], r['model_skin']) for r in components))
    assert signature not in outfit_signatures, 'repeated outfit: ' + key
    outfit_signatures.add(signature)
    effects = [r for r in resources['asset_effects'].values() if r['asset_id'] == asset_id]
    attacks = [r for r in effects if r['effect_role'] == 'attack_projectile']
    assert len(attacks) == 1 and attacks[0]['particle_path'] == projectile, key
    precache = (ROOT/'scripts/npc/npc_units_custom.txt').read_text(encoding='utf-8-sig')
    proxy_block = re.search('"' + asset['async_unit_name'] + r'"\s*\{[\s\S]*?\n    \}', precache)[0]
    assert projectile in proxy_block
    for r in components:
        vpk.verify(r['model_path']); assert r['model_path'] in proxy_block
    for r in effects:
        vpk.verify(r['particle_path']); assert r['particle_path'] in proxy_block
    unit = npc[row['unit_name']]
    assert unit['Model'] == model and unit['AttackCapabilities'] == 'DOTA_UNIT_CAP_RANGED_ATTACK'
    assert unit['AttackRange'] == row['attack_range'], key
    assert unit['ProjectileModel'] == projectile and unit['ProjectileSpeed'] == '700'
    assert unit['AttackAnimationPoint'] == '0.25'
workers = ['npc_survival_lumberjack'] + ['npc_survival_super_lumberjack_%02d' % n for n in range(1,9)]
for key in workers:
    assert npc[key]['AttackCapabilities'] == 'DOTA_UNIT_CAP_MELEE_ATTACK' and npc[key]['AttackRange'] == '400', key
tree_model = 'models/survival_resources/resource_tree.vmdl'
assert npc['enemy_tree']['Model'] == tree_model
assert table('data/csv/资源系统/world_visual_definitions.csv')['world_resource_tree']['model_name'] == tree_model
tree_info = subprocess.check_output([str(ROOT.parents[1]/'bin/win64/resourceinfo.exe'), '-i', str(ROOT/(tree_model+'_c')), '-all']).decode('utf-8',errors='replace')
assert 'key = "attach_hitloc"' in tree_info and '"tree_oak_01_root"' in tree_info
assert 'm_nVertexCount = 4444' in tree_info and 'm_nIndexCount = 20838' in tree_info
assert 'materials/models/props_tree/mango_tree.vmat' in tree_info
source = (ROOT/'art/resource_tree/source'/tree_model).read_text(encoding='utf-8')
assert source.count('_class = "Attachment"') == 1 and 'attach_hitloc' in source
if args.baseline_ref:
    old = table(archetype_path, True)
    allowed = {'model_path','normal_flying_model_path','default_wearable_asset_id','attack_type','projectile_model','projectile_speed'}
    assert old.keys() == archetypes.keys()
    for key,row in archetypes.items():
        assert {k:v for k,v in row.items() if k not in allowed or key not in FLYING_SPECS} == {
            k:v for k,v in old[key].items() if k not in allowed or key not in FLYING_SPECS},key
    assert table('data/csv/怪物与波次系统/wave_definitions.csv') == table('data/csv/怪物与波次系统/wave_definitions.csv',True)
    selected = {'monster_wave_' + key for key in FLYING_SPECS}
    for name,current in resources.items():
        previous = table('data/csv/资源系统/' + name + '.csv',True)
        assert {k:r for k,r in current.items() if r['asset_id'] not in selected} == {
            k:r for k,r in previous.items() if r['asset_id'] not in selected},name
    old_npc = parse_kv(subprocess.check_output(['git','show',args.baseline_ref+':scripts/npc/npc_units_custom.txt']).decode('utf-8-sig'))['DOTAUnits']
    unselected_proxies = {k:v for k,v in old_npc.items() if k.startswith('asset_proxy_monster_wave_') and k.replace('asset_proxy_','',1) not in selected}
    assert all(npc[k] == v for k,v in unselected_proxies.items())
    print('UNCHANGED_GAMEPLAY_AND_OUTFITS_PASS waves='+str(len(table('data/csv/怪物与波次系统/wave_definitions.csv')))+' unselected_proxies='+str(len(unselected_proxies)))
print('FLYING_NATIVE_RESOURCES_PASS archetypes=12 native_models_projectiles_and_preloads=verified workers=9 tree_attachment=compiled')
