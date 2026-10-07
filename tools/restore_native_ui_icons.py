"""Restore native Dota icons from a reviewable CSV and keep all UI consumers aligned."""
from __future__ import annotations
import argparse, csv, io, json, re, struct, subprocess, sys
from pathlib import Path
import build_configs

ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / 'data/csv'
MAPPING = DATA / '资源系统/native_ui_icon_mapping.csv'
MANIFEST = ROOT / 'panorama/src/images/custom_game/shop_v2/inventory_manifest.json'

ALIASES = {
    'skill_fire':'lina_dragon_slave', 'skill_frost':'ancient_apparition_ice_blast',
    'skill_lightning':'zuus_lightning_bolt', 'skill_poison':'alchemist_acid_spray',
    'skill_blade_spin':'juggernaut_blade_fury', 'skill_echo_slash':'magnataur_shockwave',
    'skill_earth':'earth_spirit_boulder_smash', 'skill_meteor':'invoker_chaos_meteor',
    'skill_arcane':'skywrath_mage_mystic_flare', 'skill_holy':'skywrath_mage_arcane_bolt',
    'skill_void':'invoker_tornado', 'skill_infernal':'warlock_rain_of_chaos',
    'skill_drow_companion':'drow_ranger_multishot', 'skill_monkey_staff':'monkey_king_boundless_strike',
    'skill_monkey_agility':'monkey_king_wukongs_command', 'skill_blademaster':'juggernaut_blade_dance',
    'skill_bone_cannon':'sniper_assassinate', 'skill_laser':'tinker_laser',
    'skill_arcane_eye':'luna_lucent_beam', 'skill_grenade':'snapfire_scatterblast',
    'skill_machine_gun':'windrunner_focusfire', 'skill_bounty_gun':'bounty_hunter_jinada',
    'skill_take_aim':'sniper_take_aim', 'skill_assassinate':'sniper_assassinate',
    'skill_multi_arrow':'medusa_split_shot', 'skill_ballista':'templar_assassin_psi_blades',
    'skill_flak_cannon':'gyrocopter_flak_cannon', 'skill_searing_arrow':'clinkz_searing_arrows',
    'skill_missile':'gyrocopter_homing_missile', 'skill_air_overlord':'ancient_apparition_ice_vortex',
    'skill_ice_obelisk':'ancient_apparition_ice_vortex', 'skill_ball_lightning':'storm_spirit_ball_lightning',
    'skill_shadow':'dark_willow_shadow_realm', 'skill_destroy':'techies_suicide',
    'skill_return':'furion_teleportation', 'skill_blink':'antimage_blink',
    'skill_endless':'skeleton_king_reincarnation', 'skill_fusion':'alchemist_chemical_rage',
    'skill_wish':'ogre_magi_multicast', 'skill_auto':'tinker_rearm',
    'skill_morale':'legion_commander_press_the_attack', 'skill_network':'luna_lunar_blessing',
    'skill_potion_blood':'bloodseeker_bloodrage', 'skill_potion_burst':'alchemist_chemical_rage',
    'skill_ion_shield':'abaddon_aphotic_shield', 'skill_corrosive_shield':'viper_corrosive_skin',
    'skill_nuclear':'techies_remote_mines', 'skill_dummy':'axe_berserkers_call',
    'skill_pie':'ogre_magi_bloodlust',
    'building_wall':'dark_seer_wall_of_replica', 'building_main_city':'chen_divine_favor',
    'building_arrow_tower':'clinkz_strafe', 'building_research_lab':'invoker_invoke',
    'building_advanced_research_lab':'rubick_spell_steal', 'building_farm':'chen_holy_persuasion',
    'building_gold_mine':'alchemist_goblins_greed', 'building_hero_altar':'chen_hand_of_god',
    'building_challenge':'doom_bringer_doom', 'population':'meepo_divided_we_stand',
    'upgrade_one':'omniknight_repel', 'upgrade_large':'sven_gods_strength',
    'train_lumberjack_01':'furion_force_of_nature', 'train_repairer_01':'treant_living_armor',
    'train_repairer_02':'omniknight_purification',
    'gloves':'troll_warlord_fervor', 'hyperstone':'alchemist_chemical_rage',
    'lesser_crit':'juggernaut_blade_dance', 'greater_crit':'phantom_assassin_coup_de_grace',
    'wood':'shredder_whirling_death', 'wood_stack':'shredder_chakram',
    'vitality_booster':'centaur_great_fortitude', 'reaver':'pudge_flesh_heap',
    'javelin':'legion_commander_duel', 'desolator':'slardar_amplify_damage',
    'heart':'dragon_knight_dragon_blood', 'shivas_guard':'lich_frost_shield',
    'overwhelming_blink':'sven_gods_strength', 'swift_blink':'templar_assassin_meld',
    'arcane_blink':'sven_gods_strength', 'platemail':'sven_warcry',
    'point_booster':'morphling_morph_str', 'gold':'alchemist_goblins_greed',
    'gold_stack':'bounty_hunter_track', 'hand_of_midas':'alchemist_goblins_greed',
    'mithril_hammer':'magnataur_empower', 'recipe':'tinker_rearm',
    'tome_of_knowledge':'invoker_invoke', 'extreme_cold_blade_v2':'ancient_apparition_chilling_touch',
    'talent_question':'ogre_magi_multicast', 'talent_wealthy_start':'alchemist_goblins_greed',
    'talent_sharp_volley':'clinkz_strafe', 'talent_lumberjack_assault':'troll_warlord_fervor',
    'talent_fortified_defense':'sven_warcry', 'talent_infrastructure_maniac_start':'tinker_rearm',
    'talent_precision_lumber':'shredder_whirling_death', 'talent_peaceful_labor':'treant_living_armor',
    'talent_woodcutting_bounty':'furion_wrath_of_nature', 'talent_instant_wood':'shredder_chakram',
    'talent_gold_mining_secret':'bounty_hunter_track', 'talent_hero_descent':'chen_hand_of_god',
    'talent_population_expansion':'meepo_divided_we_stand', 'talent_natures_gift':'furion_force_of_nature',
    'talent_emergency_reinforcement':'huskar_berserkers_blood', 'talent_wind_strategy':'windrunner_focusfire',
    'talent_allround_tempering':'invoker_exort', 'talent_heavy_hand':'ogre_magi_multicast',
    'talent_first_to_strike':'tiny_tree_grab', 'talent_endless_rebirth':'skeleton_king_reincarnation',
    'talent_long_range_volley':'sniper_take_aim', 'talent_wall_recovery':'dragon_knight_dragon_blood',
}
PORTRAITS = {
    'axe':'axe_counter_helix', 'doom_bringer':'doom_bringer_doom', 'nevermore':'nevermore_requiem',
    'keeper_of_the_light':'keeper_of_the_light_blinding_light', 'drow_ranger':'drow_ranger_multishot',
    'monkey_king':'monkey_king_wukongs_command', 'juggernaut':'juggernaut_omni_slash',
    'tiny':'tiny_avalanche', 'treant':'treant_living_armor', 'visage':'visage_summon_familiars',
    'alchemist':'alchemist_goblins_greed', 'undying':'undying_tombstone', 'clinkz':'clinkz_strafe',
    'beastmaster':'beastmaster_primal_roar', 'morphling':'morphling_waveform',
    'ember_spirit':'ember_spirit_sleight_of_fist', 'primal_beast':'primal_beast_pulverize',
    'spectre':'spectre_haunt', 'terrorblade':'terrorblade_metamorphosis',
    'necrolyte':'necrolyte_reapers_scythe',
}
ALIASES.update({'portrait_'+k:v for k,v in PORTRAITS.items()})
SPECIAL_ABILITIES = {
    'ability_survival_ice_cone':'crystal_maiden_freezing_field',
    'ability_survival_magic_slingshot':'tiny_avalanche',
    'ability_survival_blade_nova':'magnataur_shockwave',
    'ability_survival_axe_counter_helix':'axe_counter_helix',
    'ability_survival_monkey_king_fury':'monkey_king_wukongs_command',
    'ability_survival_monkey_king_swiftness':'monkey_king_jingu_mastery',
    'ability_survival_blademaster_agility':'terrorblade_conjure_image',
    'ability_survival_blademaster_mobility':'juggernaut_omni_slash',
    'ability_summon_shadow_fiend':'keeper_of_the_light_blinding_light',
    'ability_research_ars_08':'sven_gods_strength',
    'ability_research_ars_09':'templar_assassin_meld',
    'ability_research_ars_10':'legion_commander_duel',
}
FAMILIES = {
    'critical_strike':'phantom_assassin_coup_de_grace', 'bone_cannon':'sniper_assassinate',
    'death_grenade':'snapfire_scatterblast', 'laser':'tinker_laser',
    'arcane_cannon':'necrolyte_sadist', 'arcane_eye':'luna_lucent_beam',
    'lightning_strike':'zuus_arc_lightning', 'lightning_storm':'zuus_lightning_bolt',
    'lightning_diffusion':'disruptor_static_storm', 'machine_gun':'windrunner_focusfire',
    'bounty_machine_gun':'bounty_hunter_jinada', 'explosive_gatling':'clinkz_strafe',
    'multi_attack':'medusa_split_shot', 'piercing_ballista':'templar_assassin_psi_blades',
    'burning_great_arrow':'clinkz_searing_arrows', 'frost_attack':'drow_ranger_frost_arrows',
    'ice_blizzard':'crystal_maiden_freezing_field', 'polar_obelisk':'ancient_apparition_ice_vortex',
    'anti_air_missile':'gyrocopter_homing_missile', 'drag_net':'naga_siren_ensnare',
    'airspace_overlord':'ancient_apparition_ice_vortex',
}
ITEMS = {
    'item_death_mask':'lifesteal', 'item_forging_hammer':'mithril_hammer',
    'item_small_polar_crystal':'point_booster', 'item_large_polar_crystal':'ultimate_orb',
    'material_synthesis_gem':'gem', 'challenge_synthesis_gem':'gem',
    'item_molten_upgrade_gem_01_03':'gem', 'item_molten_upgrade_gem_04':'octarine_core',
    'material_ice_soul_ember':'shivas_guard', 'item_knowledge_book':'tome_of_knowledge',
    'item_super_knowledge_book':'book_of_shadows', 'service_early_final_boss':'necronomicon_3',
    'shop_proxy_attack_gloves_01':'gloves', 'shop_proxy_burning_blade_01':'radiance',
    'shop_proxy_iron_armor_01':'chainmail',
}
SOURCE_NAMES = {'hero_skill_definitions','worker_skill_definitions','research_lab_abilities',
    'technology_definitions','rogue_reward_cards','rogue_reward_rules','challenge_definitions',
    'rebirth_challenges','weapon_definitions','item_definitions','content_catalog','tooltip_definitions'}

def rows(path):
    text=path.read_text(encoding='utf-8-sig')
    reader=csv.DictReader(io.StringIO(text))
    return reader.fieldnames, list(reader)

def item_for(identity):
    if identity in ITEMS:return ITEMS[identity]
    identity=re.sub(r'^item_survival_', '', identity)
    identity=re.sub(r'^(weapon_|equipment_)', '', identity)
    identity=identity.removesuffix('_shell')
    match=re.fullmatch(r'(growth_sword|frost_blade|ice_blade|epic_icefire|legend_abyss|attack_gloves|burning_blade|iron_armor|infernal_armor)_(\d+|max)',identity)
    if match:
        family,tier=match.groups()
        if family=='growth_sword':return ['broadsword','claymore','demon_edge','lesser_crit','greater_crit'][4 if tier=='max' else min(4,max(0,int(tier)-1))]
        return {'frost_blade':'sange_and_yasha','ice_blade':'skadi','epic_icefire':'bloodthorn',
            'legend_abyss':'abyssal_blade','attack_gloves':'gloves','burning_blade':'radiance',
            'iron_armor':'chainmail','infernal_armor':'crimson_guard'}[family]
    if re.search(r'(molten|ember|lava)_core',identity):return 'bloodstone'
    return {'attack_gloves':'gloves','burning_blade':'radiance','iron_armor':'chainmail',
        'infernal_armor':'crimson_guard','death_mask':'lifesteal','small_polar_crystal':'point_booster',
        'large_polar_crystal':'ultimate_orb','synthesis_gem':'gem','ice_soul_ember':'shivas_guard'}.get(identity)

def native_paths():
    vpk=ROOT.parents[1]/'dota/pak01_dir.vpk'
    with vpk.open('rb') as f:
        sig,version,size=struct.unpack('<III',f.read(12));assert sig==0x55aa1234
        f.seek(28 if version==2 else 12);data=f.read(size)
    i=0; paths=set()
    def string():
        nonlocal i
        end=data.index(0,i);value=data[i:end].decode();i=end+1;return value
    while (ext:=string()):
        while (folder:=string()):
            while (name:=string()):
                _,preload,_,_,_,_=struct.unpack_from('<IHHIIH',data,i);i+=18+preload
                paths.add((folder+'/' if folder!=' ' else '')+name+'.'+ext)
    return paths

def resource(kind,name):return f"panorama/images/{'items' if kind=='item' else 'spellicons'}/{name}_png.vtex_c"
def write(path,text):
    path.parent.mkdir(parents=True,exist_ok=True)
    if not path.exists() or path.read_text(encoding='utf-8-sig')!=text:path.write_text(text,encoding='utf-8',newline='')

def seed():
    entries={k:('ability',v,'按技能描述匹配原生技能图标') for k,v in ALIASES.items()}
    entries.update({'ability:'+k:('ability',v,'按具体技能效果匹配，覆盖通用图标') for k,v in SPECIAL_ABILITIES.items()})
    entries.update({'skill:'+k:('ability',v,'同一塔技能的全部等级共用原生图标') for k,v in FAMILIES.items()})
    entries['content:advanced_researcher_unlock']=('ability','rubick_spell_steal','高级研究服务')
    for file in ('weapon_definitions','item_definitions'):
        for row in rows(next(DATA.rglob(file+'.csv')))[1]:
            identity=row.get('content_id','')
            if identity.startswith('#'):continue
            icon=item_for(identity)
            if icon:entries['content:'+identity]=('item',icon,'按物品名称与攻击、护甲、吸血、寒冰或合成效果匹配')
    return entries

def kv_blocks(text):
    return re.compile(r'("([^"\n]+)"\s*\{)([^{}]*)(\})',re.S)

def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--seed',action='store_true');parser.add_argument('--check',action='store_true')
    args=parser.parse_args()
    if args.seed:
        mapping=seed()
    else:
        mapping={r['icon_id']:(r['icon_type'],r['icon_name'],r['match_reason']) for r in rows(MAPPING)[1]
            if r.get('enabled')=='1' and not r['icon_id'].startswith('#')}
    paths=native_paths()
    missing=[(key,resource(kind,name)) for key,(kind,name,_) in mapping.items() if resource(kind,name) not in paths]
    if missing:raise RuntimeError('Native icons missing: '+json.dumps(missing,ensure_ascii=False))
    if args.check:print('NATIVE_ICON_MAPPING_PASS '+str(len(mapping)));return
    if args.seed:
        out=io.StringIO(newline='');writer=csv.writer(out,lineterminator='\n')
        writer.writerow(['icon_id','icon_type','icon_name','match_reason','enabled'])
        writer.writerow(['#中文名:图标映射ID','原生图标类型','原生图标名称','匹配依据','是否启用'])
        writer.writerow(['#types:string','enum','string','string','boolean'])
        for key,(kind,name,reason) in sorted(mapping.items()):writer.writerow([key,kind,name,reason,1])
        write(MAPPING,out.getvalue())
    aliases={k:v[1] for k,v in mapping.items() if ':' not in k}
    def replace_alias(match):
        name=match.group(1)
        if name not in aliases:raise RuntimeError('Unmapped native alias '+name)
        return aliases[name]
    def convert_alias(text):return re.sub(r'survival/native/([A-Za-z0-9_]+)',replace_alias,text)
    content={k[8:]:{'type':v[0],'name':v[1]} for k,v in mapping.items() if k.startswith('content:')}
    ability_icons={};native_item_ids=set()
    for relative in ('scripts/npc/npc_abilities_custom.txt','scripts/npc/npc_items_custom.txt'):
        path=ROOT/relative;item='items' in path.name;text=path.read_text(encoding='utf-8')
        def block(match):
            start,identity,body,end=match.groups();old=re.search(r'"AbilityTextureName"\s*"([^\"]*)"',body)
            if not old:return match.group(0)
            icon=old.group(1)
            if item:
                specific=mapping.get('content:'+identity)
                native=specific[1] if specific else item_for(identity)
                if not native:
                    leaf=icon.split('/')[-1]
                    native={'skill_destroy':'recipe','gold_stack':'hand_of_midas'}.get(leaf,leaf)
                if resource('item',native) not in paths:raise RuntimeError('Unknown item '+identity+' '+native)
                content[identity]={'type':'item','name':native}
                native_item_ids.add(identity)
            else:
                special=mapping.get('skill:'+re.sub(r'_lv\d+$','',identity)) or mapping.get('ability:'+identity)
                native=special[1] if special else convert_alias(icon)
                if resource('ability',native) not in paths:raise RuntimeError('Unknown ability '+identity+' '+native)
                ability_icons[identity]=native
            body=body[:old.start(1)]+native+body[old.end(1):]
            return start+body+end
        write(path,kv_blocks(text).sub(block,text))
    changed=[]
    for path in DATA.rglob('*.csv'):
        if path.stem not in SOURCE_NAMES:continue
        headers,records=rows(path);dirty=False
        for row in records:
            identity=next(iter(row.values()),'')
            if identity.startswith('#'):continue
            if path.stem=='tooltip_definitions':identity=row.get('id',identity)
            ability=row.get('ability_name') or (identity if identity.startswith('ability_') else None)
            specific=mapping.get('content:'+identity) or (mapping.get('ability:'+ability) if ability else None)
            if ability in ability_icons and not specific:specific=('ability',ability_icons[ability],'')
            for field,value in list(row.items()):
                if field not in ('icon','icon_name','tooltip_icon','ability_icon') or not isinstance(value,str):continue
                replacement=(('item_' if specific[0]=='item' else '')+specific[1]) if specific else convert_alias(value)
                if replacement!=value:row[field]=replacement;dirty=True
        if dirty:
            out=io.StringIO(newline='');writer=csv.DictWriter(out,headers,lineterminator='\n');writer.writeheader();writer.writerows(records)
            write(path,out.getvalue());changed.append(path)
    tooltip=ROOT/'scripts/vscripts/config/ability_tooltip_config.lua'
    tooltip_text=convert_alias(tooltip.read_text(encoding='utf-8'))
    def align_tooltip(match):
        identity,body=match.groups()
        if identity in ability_icons:
            body=re.sub(r'(abilityicon\s*=\s*)"[^"]+"',lambda m:m[1]+'"'+ability_icons[identity]+'"',body)
        return identity+' = {'+body+'}'
    tooltip_text=re.sub(r'([A-Za-z0-9_]+)\s*=\s*\{([^{}]*)\}',align_tooltip,tooltip_text)
    write(tooltip,tooltip_text)
    for relative in ('scripts/vscripts/abilities/ability_survival_rogue_reward.lua',):
        path=ROOT/relative;write(path,convert_alias(path.read_text(encoding='utf-8')))
    training=ROOT/'scripts/vscripts/abilities/ability_train_lumberjack.lua'
    text=training.read_text(encoding='utf-8')
    text=re.sub(r'(function M:GetAbilityTextureName\(\)\n)[\s\S]*?(\nend)',
        lambda m:m[1]+'    return "'+ability_icons['ability_train_lumberjack']+'"'+m[2],text)
    write(training,text)
    for path in changed:build_configs.build(path,ROOT/'scripts/vscripts/config/generated'/f'{path.stem}.lua')
    build_configs.build(MAPPING,ROOT/'scripts/vscripts/config/generated/native_ui_icon_mapping.lua')
    subprocess.run([sys.executable,str(ROOT/'tools/build_tooltip_definitions.py'),'--from-csv'],cwd=ROOT,check=True)
    textures={identity:entry['name'] for identity,entry in content.items() if entry['type']=='item'}
    lua='-- Generated by tools/restore_native_ui_icons.py from native_ui_icon_mapping.csv.\nreturn {\n'
    lua+=''.join(f'    ["{key}"] = "{value}",\n' for key,value in sorted(textures.items()))+'}\n'
    write(ROOT/'scripts/vscripts/config/inventory_original_icons.lua',lua)
    for path in DATA.rglob('*.csv'):
        if path.stem not in ('challenge_definitions','rebirth_challenges','technology_definitions','rogue_reward_cards'):continue
        for row in rows(path)[1]:
            identity=next(iter(row.values()),'');icon=row.get('icon_name')
            if identity.startswith('#') or not icon:continue
            kind='item' if icon.startswith('item_') else 'ability';name=icon.removeprefix('item_') if kind=='item' else icon
            if resource(kind,name) not in paths:raise RuntimeError('Unknown shop resource '+identity+' '+icon)
            content[identity]={'type':kind,'name':name}
    for entry in content.values():entry['uri']='file://{images}/'+('items/' if entry['type']=='item' else 'spellicons/')+entry['name']+'.png'
    mapping.update({'ability:'+key:('ability',value,'技能栏、技能提示使用一致的原生图标') for key,value in ability_icons.items()})
    mapping.update({'content:'+key:(value['type'],value['name'],'商店、背包与物品提示使用一致的原生图标') for key,value in content.items()})
    out=io.StringIO(newline='');writer=csv.writer(out,lineterminator='\n')
    writer.writerow(['icon_id','icon_type','icon_name','match_reason','enabled'])
    writer.writerow(['#中文名:图标映射ID','原生图标类型','原生图标名称','匹配依据','是否启用'])
    writer.writerow(['#types:string','enum','string','string','boolean'])
    for key,(kind,name,reason) in sorted(mapping.items()):writer.writerow([key,kind,name,reason,1])
    write(MAPPING,out.getvalue())
    build_configs.build(MAPPING,ROOT/'scripts/vscripts/config/generated/native_ui_icon_mapping.lua')
    js='(function(){\n    "use strict";\n    var icons='+json.dumps(content,ensure_ascii=False,sort_keys=True,separators=(',',':'))+';\n'
    js+='''    function resolve(value){
        if(!value)return null;
        var id=String(value), found=icons[id]||icons[id.replace(/^shop_/, "")];
        if(found)return found;
        return null;
    }
    function create(parent,entry,className){
        var keys=entry?[entry.content_id,entry.contentid,entry.item_id,entry.id,entry.entry_id,entry.entryid,entry.shop_entry_id,entry.icon]:[];
        var found=null;
        for(var i=0;i<keys.length&&!found;i++)found=resolve(keys[i]);
        if(!found&&entry&&entry.icon){
            var value=String(entry.icon);
            if(/^item_[a-z0-9_]+$/.test(value))found={uri:"file://{images}/items/"+value.slice(5)+".png"};
            else if(/^[a-z0-9_]+$/.test(value)&&entry.icon_type==="ability")found={uri:"file://{images}/spellicons/"+value+".png"};
        }
        if(!found)return null;
        var panel=$.CreatePanel("Image",parent,"");
        if(className)panel.AddClass(className);
        panel.SetImage(found.uri);panel.SetScaling("stretch-to-fit-preserve-aspect");
        panel.hittest=false;panel.hittestchildren=false;
        return panel;
    }
    GameUI.CustomUIConfig().SurvivalNativeIcons={Resolve:resolve,Create:create};
})();
'''
    write(ROOT/'panorama/src/scripts/custom_game/native_ui_icons.js',js)
    inventory={'mode':'dota_native','nativeItems':len(native_item_ids),
        'mappings':textures,'icons':content,'ability_icons':ability_icons,'images':[]}
    write(MANIFEST,json.dumps(inventory,ensure_ascii=False,sort_keys=True,indent=2)+'\n')
    print(f'NATIVE_UI_ICONS_RESTORED abilities={len(ability_icons)} inventory={len(textures)} shop_identities={len(content)} CSVs={len(changed)}')

if __name__=='__main__':main()
