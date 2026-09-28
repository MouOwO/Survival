"""Export portrait background hues from the installed Valve portraits and unit models.
Only UI colors are generated; this never changes cameras, lighting or world models.
"""
from pathlib import Path
import csv
import json
import colorsys
from build_wave_monster_cosmetics import Vpk, parse_kv
ROOT = Path(__file__).resolve().parents[1]
ENGINE = ROOT.parents[2]
DEFAULT = '#29424b'
# Art direction for the requested examples and the six playable hero portraits.
OVERRIDES = {
    'npc_dota_hero_ember_spirit':'#b57924', 'npc_dota_hero_rubick':'#285b27',
    'npc_dota_hero_dark_willow':'#532d69', 'npc_dota_hero_doom_bringer':'#943d20',
    'npc_dota_hero_nevermore':'#792a20', 'npc_dota_hero_axe':'#7c302b',
    'npc_dota_hero_drow_ranger':'#355979', 'npc_dota_hero_monkey_king':'#916324',
    'npc_dota_hero_juggernaut':'#885c31', 'npc_dota_hero_treant':'#3d5f2b',
    'npc_dota_hero_terrorblade':'#254e63', 'npc_dota_hero_spectre':'#513b72',
    'npc_dota_hero_primal_beast':'#705638', 'npc_dota_hero_morphling':'#286876',
    'npc_dota_hero_beastmaster':'#776039',
}
# Hero-themed fills where Valve authors the color inside a texture (white tint).
TEXTURE_HUES = {
 'abyssal_underlord':'#3b5931','alchemist':'#686334','chen':'#7c693b',
 'crystal_maiden':'#3b7195','dark_seer':'#614278','death_prophet':'#3d7267',
 'enchantress':'#54783a','faceless_void':'#544173','hoodwink':'#6a6533',
 'invoker':'#785c83','largo':'#507343','lycan':'#72472e','magnataur':'#635943',
 'mirana':'#475780','night_stalker':'#303969','oracle':'#437c79',
 'pangolier':'#86543b','phantom_assassin':'#316469','phantom_lancer':'#756439',
 'ringmaster':'#742f36','sand_king':'#7e672f','shadow_demon':'#752c47',
 'shadow_shaman':'#856024','silencer':'#584477','skeleton_king':'#3e6a38',
 'slark':'#335c74','storm_spirit':'#3e6590','tinker':'#74663b','tiny':'#57664c',
 'undying':'#526333','venomancer':'#687337','visage':'#35656c',
 'windrunner':'#4d7738','wisp':'#477e9a',
}
def rows(name):
    return list(csv.DictReader(next((ROOT/'data/csv').rglob(name)).open(encoding='utf-8-sig')))
def authored_color(entry):
    colors=[]
    for i in range(1,5):
        try: c=[float(x) for x in entry.get('PortraitBackgroundColor'+str(i),'').split()]
        except ValueError: continue
        if len(c)!=3: continue
        if max(c)>1: c=[x/255 for x in c]
        if max(c)-min(c)>.06 and max(c)>.08: colors.append(c)
    if not colors: return None  # White tints carry no hue; use the model family fallback.
    rgb=[sum(c[i] for c in colors)/len(colors) for i in range(3)]
    h,s,v=colorsys.rgb_to_hsv(*rgb)
    rgb=colorsys.hsv_to_rgb(h,min(.82,max(.32,s)),min(.60,max(.32,v*.75)))
    return '#'+''.join(f'{round(x*255):02x}' for x in rgb)
def main():
    vpk=Vpk(ENGINE/'game/dota/pak01_dir.vpk')
    portraits=parse_kv(vpk.read('scripts/npc/portraits.txt').decode('utf-8'))['Portraits']
    model_colors={model:color for model,row in portraits.items() if isinstance(row,dict) and (color:=authored_color(row))}
    heroes={}; family_colors={}
    for path in sorted(vpk.entries):
        if not path.startswith('scripts/npc/heroes/npc_dota_hero_') or not path.endswith('.txt'): continue
        data=parse_kv(vpk.read(path).decode('utf-8')).get('DOTAHeroes',{})
        for name,row in data.items():
            if not isinstance(row,dict) or not name.startswith('npc_dota_hero_') or name=='npc_dota_hero_base': continue
            model=row.get('Model','')
            color=OVERRIDES.get(name) or model_colors.get(model) or TEXTURE_HUES.get(name.removeprefix('npc_dota_hero_')) or DEFAULT
            heroes[name]=color
            if model:
                model_colors[model]=color
                if '/heroes/' in model: family_colors[model.split('/heroes/')[1].split('/')[0]]=color
    def model_color(model):
        if model in model_colors: return model_colors[model]
        for prefix in ('models/heroes/','models/items/'):
            if model.startswith(prefix):
                family=model[len(prefix):].split('/')[0]
                if family in family_colors: return family_colors[family]
        if 'survival_buildings/' in model:
            # Muted companions to the authored stone, slate, timber and brass.
            if 'population_farm' in model: return '#4b5935'
            if 'gold_mine' in model: return '#75603b'
            if 'research_lab' in model: return '#526066'
            if 'hero_altar' in model: return '#68614a'
            if 'challenge_arena' in model: return '#63584a'
            if '/wall_' in model: return '#505c59'
            return '#3b5e61'
        if '/zuus/' in model: return '#566b87'
        if 'mango_tree' in model: return '#42652b'
        for token,color in [('crystal','#426e89'),('kobold','#746136'),('centaur','#6b4934'),
            ('furbolg','#566e50'),('ogre','#45606d'),('worg','#5d6471'),('eimermole','#735f47'),
            ('greevil','#54753d'),('roshan','#61503a'),('bad_melee','#664234')]:
            if token in model: return color
        if 'treant' in model or 'furion' in model: return '#3d5f2b'
        if 'dire' in model: return '#664234'
        if 'radiant' in model: return '#416854'
        return DEFAULT
    assets={}
    for row in rows('asset_catalog.csv'):
        if row.get('enabled')!='1' or not row.get('primary_model','').startswith('models/'): continue
        assets[row['asset_id']]=heroes.get(row.get('portrait_unit_name','')) or model_color(row['primary_model'])
    units={}
    for path in (ROOT/'scripts/npc').glob('*.txt'):
        data=parse_kv(path.read_text(encoding='utf-8-sig')).get('DOTAUnits',{})
        for name,row in data.items():
            if isinstance(row,dict) and row.get('Model'): units[name]=model_color(row['Model'])
    for row in rows('training_definitions.csv'):
        if row.get('unit_name') and row.get('model_name'): units[row['unit_name']]=model_color(row['model_name'])
    # Audit every model path used by configured friend/enemy unit data, including
    # runtime model replacements whose engine unit name is just a shared proxy.
    configured_models=set()
    for name in ['monster_archetypes.csv','monster_visual_assets.csv','training_definitions.csv','asset_catalog.csv']:
        for row in rows(name):
            for key in ['model_path','normal_flying_model_path','model_name','primary_model']:
                model=row.get(key,'')
                if model.startswith('models/') and model.endswith('.vmdl'):
                    configured_models.add(model)
                    model_colors[model]=model_color(model)
            model=row.get('model_path','') or row.get('model_name','')
            if row.get('unit_name') and model.startswith('models/'):
                units[row['unit_name']]=model_color(model)
    for path in (ROOT/'scripts/npc').glob('*.txt'):
        for name,row in parse_kv(path.read_text(encoding='utf-8-sig')).get('DOTAUnits',{}).items():
            if isinstance(row,dict) and row.get('Model'):
                configured_models.add(row['Model']);model_colors[row['Model']]=model_color(row['Model'])
    audit={'configured_models':len(configured_models),'mapped_models':len(model_colors),
        'unmapped_models':sorted(configured_models-set(model_colors)),
        'neutral_models':sorted(m for m in configured_models if model_colors[m]==DEFAULT)}
    audit_path=ROOT/'output/portrait_all_units_20260927/palette_audit.json'
    audit_path.parent.mkdir(parents=True,exist_ok=True)
    audit_path.write_text(json.dumps(audit,indent=2),encoding='utf-8')
    data={'defaultColor':DEFAULT,'heroes':heroes,'assets':assets,'units':units,'models':model_colors}

    out=ROOT/'panorama/src/scripts/custom_game/portrait_palette.js'
    out.write_text('// Generated by tools/build_portrait_palette.py from local Valve resources.\n'
        +'(function(){GameUI.CustomUIConfig().SurvivalPortraitPalette='
        +json.dumps(data,ensure_ascii=True,sort_keys=True,separators=(',',':'))+';})();\n',encoding='utf-8')
    print('PORTRAIT_PALETTE',len(heroes),'heroes',len(assets),'assets',len(units),'unit aliases')
if __name__=='__main__': main()
