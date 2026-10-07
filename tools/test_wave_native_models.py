"""Verify named wave models and rebuild stability in a temporary copy."""
from pathlib import Path
import csv, tempfile, shutil, sys, re, contextlib, io
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tools'))
import sync_wave_unit_names as sync
from build_wave_monster_cosmetics import parse_kv

def rows(path):
    return list(csv.DictReader(line for line in path.read_text(encoding='utf-8-sig').splitlines() if line and not line.startswith('#')))

archetypes=rows(ROOT/'data/csv/怪物与波次系统/monster_archetypes.csv')
npc=parse_kv((ROOT/'scripts/npc/npc_units_custom.txt').read_text(encoding='utf-8-sig'))['DOTAUnits']
selected=[r for r in archetypes if r['unit_name'].startswith('npc_survival_wave_named_')]
for r in selected: assert npc[r['unit_name']]['Model']==r['model_path'],r['archetype_id']
for wave in (5, 10):
    boss = npc[f'npc_survival_wave_named_boss_dreadlord_wave_name_{wave}']
    assert boss['MovementSpeedActivityModifiers'] == {'walk': '0', 'run': '395'}, \
        f'wave {wave} Underlord needs native locomotion tags (including slowed walk)'
    assert boss['MovementCapabilities'] == 'DOTA_UNIT_CAP_MOVE_GROUND'
with tempfile.TemporaryDirectory(prefix='survival_wave_models_') as tmp:
    target=Path(tmp)
    for rel in ['data/csv/怪物与波次系统/monster_archetypes.csv','data/csv/怪物与波次系统/wave_definitions.csv','scripts/npc/npc_units_custom.txt','resource/addon_schinese.txt','resource/localization/addon_schinese.txt']:
        p=target/rel;p.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(ROOT/rel,p)
    (target/'scripts/vscripts/config/generated').mkdir(parents=True)
    sync.ROOT=target
    with contextlib.redirect_stdout(io.StringIO()):sync.main()
    rebuilt=parse_kv((target/'scripts/npc/npc_units_custom.txt').read_text(encoding='utf-8-sig'))['DOTAUnits']
    for r in selected:
        assert rebuilt[r['unit_name']]['Model']==r['model_path'], 'rebuild changed outfit '+r['archetype_id']
        assert {k:v for k,v in npc[r['unit_name']].items() if k!='Model'}=={k:v for k,v in rebuilt[r['unit_name']].items() if k!='Model'}
print(f'WAVE_NATIVE_MODEL_REBUILD_PASS units={len(selected)}; wave10 Bloodseeker and Underlord; combat KV unchanged')
