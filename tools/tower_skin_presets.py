"""Three tower outfit presets. CSVs remain runtime authority; only art fields change.
Run --preset A/B/C, then reload the map. --check validates all presets without edits.
"""
from __future__ import annotations
import argparse, csv, hashlib, io, json, sys, subprocess, shutil
from pathlib import Path
from urllib.parse import quote
from build_wave_monster_cosmetics import Vpk, parse_kv, modifiers
from build_configs import build
import build_tower_native_wearable_units as carrier

ROOT = Path(__file__).resolve().parents[1]
RES = ROOT / 'data/csv/资源系统'
TOWERS = ROOT / 'data/csv/建筑与工人系统/防御塔'
GEN = ROOT / 'scripts/vscripts/config/generated'
PRESETS = ROOT / 'data/tower_visual_presets'
# R uses the free native outfit; SR introduces Immortals. Alternate full sets
# enter at SSR alongside premium pieces, avoiding an expensive R set followed
# by a cheaper single Immortal. Milestone cosmetics take priority over set slots.
ROUTES = {
 'death': ('nevermore', ('', '21217', '21752'), ('8259',), ('8259','6996')),
 'mystery': ('tinker', ('', '20940', '21110'), ('13777',), ('13777','6224','7143')),
 'lightning': ('zuus', ('', '22024', '24196'), ('12323',), ('12323','6914','5412')),
 'machine_gun': ('sniper', ('', '20264', '20321'), ('21777','9197'), ('21654',)),
 'multi': ('clinkz', ('', '20053', '20207'), ('13009',), ('13009','9162')),
 'frost': ('lich', ('', '20155', '21273'), ('9756',), ('9756','7576','14998')),
 'anti_air': ('techies', ('', '', ''), ('21424',), ('20610',)),
}
NAMES = {'A':'原生清晰', 'B':'暗色猎手', 'C':'华丽典礼'}
ANTI_AIR_PROJECTILES = (
 'particles/units/heroes/hero_clinkz/clinkz_searing_arrow.vpcf',
 'particles/econ/items/clinkz/clinkz_maraxiform/clinkz_maraxiform_searing_arrow.vpcf',
 'particles/econ/items/clinkz/clinkz_maraxiform/clinkz_maraxiform_searing_arrow_deso.vpcf',
)
BASES = ['io_amber_portal','leshrac_edict','kinetic_markers','bulldoze_ring','clinkz_embers','io_blue_portal','psionic_trap']
DEATH_BASE_COLORS = {'color_r':'255|150|55', 'color_sr':'255|150|55', 'color_ssr':'255|150|55'}
COLORS = {'A':['165|100|245','155|165|255','105|195|255','255|185|95','255|130|65','145|220|255','145|215|250'],
          'B':['135|80|210','145|115|235','95|155|240','215|145|70','220|85|50','110|175|235','135|175|235'],
          'C':['200|125|255','200|180|255','155|220|255','255|205|120','255|170|75','190|240|255','180|230|255']}

def table(path):
    rows = list(csv.reader(io.StringIO(path.read_text(encoding='utf-8-sig'))))
    return rows[0], [r for r in rows[1:] if r and r[0].startswith('#')], [dict(zip(rows[0],r)) for r in rows[1:] if r and not r[0].startswith('#')]

def save(path, rows, extra=()):
    head, comments, _ = table(path)
    for name, typ, label in extra:
        if name not in head:
            head.append(name)
            for c in comments:
                c.extend(['']*(len(head)-1-len(c)))
                c.append(typ if c[0].startswith('#types:') else label)
    out=io.StringIO(newline=''); w=csv.writer(out,lineterminator='\n');w.writerow(head);w.writerows(comments)
    for r in rows:w.writerow([r.get(k,'') for k in head])
    path.write_text(out.getvalue(),encoding='utf-8',newline='')

def verify(vpk, resource):
    if resource and not (ROOT/(resource+'_c')).exists():vpk.verify(resource)

def skill_path(hero, name):return f'particles/units/heroes/hero_{hero}/{name}.vpcf'

def projections(vpk, schema, loc, preset):
    items=schema['items']; byname={v.get('name'):k for k,v in items.items()}
    def expand(key):
        x=items[key]
        if 'bundle' in x:
            return [i for n in x['bundle'] for i in expand(byname[n])]
        return [key]
    stages=[]; wears=[]; report=[]; attacks={}; activities=[]; ambients=[]
    for route,(hero,backdrops,sr,ssr) in ROUTES.items():
        unit='npc_dota_hero_'+hero
        h=parse_kv(vpk.read('scripts/npc/heroes/'+unit+'.txt').decode('utf-8-sig'))['DOTAHeroes'][unit]
        route_rows=table(TOWERS/f'tower_class_{route}.csv')[2]
        assets=list(dict.fromkeys(r['model_asset_id'] for r in route_rows));assert len(assets)==3
        backdrop=backdrops['ABC'.index(preset)]
        for tier,aid in enumerate(assets):
            selected={}
            for k,x in items.items():
                if x.get('prefab')=='default_item' and unit in x.get('used_by_heroes',{}):selected[x.get('item_slot','weapon')]=k
            outfit=([backdrop] if backdrop and tier==2 else [])+([] if tier==0 else list(sr if tier==1 else ssr))
            # Keep the Rime Lord crown in the C mix instead of replacing the
            # selected full-set crown with the inexpensive TI10 head.
            if hero=='lich' and tier==2 and preset=='C':outfit.remove('14998')
            for k in outfit:
                for item_id in expand(k):
                    x=items[item_id]
                    if unit not in x.get('used_by_heroes',{}):continue # cursor packs etc.
                    if x.get('model_player') or x.get('item_slot')=='hero_base':selected[x.get('item_slot','weapon')]=item_id
            body=h['Model']; active=list(selected.values()); body_mods={}
            for k in active:
                for m in modifiers(items[k]):
                    if m.get('type')=='entity_model' and m.get('asset')==unit:body=m['modifier']
                    if m.get('type')=='model':body_mods[m.get('asset')]=m['modifier']
            # Hero-code cosmetics are not all represented by generic asset modifiers.
            if hero=='nevermore' and tier==2:
                body='models/heroes/shadow_fiend/shadow_fiend_arcana.vmdl'
                body_mods.update({f'models/heroes/shadow_fiend/shadow_fiend_{p}.vmdl':f'models/heroes/shadow_fiend/shadow_fiend_arcana_{p}.vmdl' for p in ('head','shoulders','arms')})
            if hero=='skywrath_mage' and tier==2:body='models/items/skywrath_mage/skywrath_arcana/skywrath_arcana.vmdl'
            verify(vpk,body)
            labels=[loc.get(items[k].get('item_name','').lstrip('#').lower(),items[k]['name']) for k in outfit]
            title=' / '.join(labels) if labels else '原生默认装束'
            stages.append(dict(asset_id=aid,hero_unit_name=unit,body_model=body,model_skin=('1' if hero=='skywrath_mage' and tier==2 and preset=='C' else '0'),display_name=f'{NAMES[preset]} {hero} '+['R','SR','SSR'][tier]+' · '+title,enabled='1',notes=f'皮肤方案{preset}；同英雄升阶；'+title))
            stages[-1]['model_scale']=h.get('ModelScale','0.6') if hero=='techies' else '1'
            count=0
            for slot,k in sorted(selected.items()):
                x=items[k];model=body_mods.get(x.get('model_player'),x.get('model_player'))
                if not model or model=='models/development/invisiblebox.vmdl':continue
                verify(vpk,model);count+=1;key=aid+'_'+slot
                skin=str(x.get('visuals',{}).get('skin','0'))
                if hero=='skywrath_mage' and tier==2:skin='1' if preset=='C' else '0'
                wears.append(dict(wearable_key=key,asset_id=aid,item_def=k,hero_unit_name=unit,slot=slot,model_path=model,sort_order=str(count),enabled='1',entity_class='prop_dynamic',attach_mode='bone_merge',model_skin=skin,notes=x['name']))
                for m in modifiers(x):
                    if m.get('type')=='activity' and m.get('asset')=='ALL':
                        activities.append(dict(modifier_key=aid+':'+m['modifier'],asset_id=aid,modifier_name=m['modifier'],sort_order=str(count),enabled='1',notes='所选饰品原生活动修饰'))
            attack=h.get('ProjectileModel','');mode='native_hero'
            # Explicit hero-code mappings + schema particle replacement chains.
            if hero=='nevermore':
                if tier==1:attack='particles/econ/items/shadow_fiend/sf_desolation/sf_base_attack_desolation.vpcf';mode='native_cosmetic'
                if tier==2:attack='particles/econ/items/shadow_fiend/sf_desolation/sf_base_attack_desolation_fire_arcana.vpcf';mode='native_cosmetic_combination'
            elif hero=='sniper' and tier:
                attack=('particles/econ/items/sniper/sniper_witch_hunter/sniper_witch_hunter_base_attack.vpcf' if tier==1 else 'particles/econ/items/sniper/sniper_fall20_immortal/sniper_fall20_immortal_base_attack.vpcf');mode='native_cosmetic'
            elif hero=='clinkz' and tier:
                attack=(skill_path('clinkz','clinkz_searing_arrow') if tier==1 else 'particles/econ/items/clinkz/clinkz_maraxiform/clinkz_maraxiform_searing_arrow.vpcf');mode='fallback_native_skill' if tier==1 else 'native_cosmetic_skill_as_attack'
            elif hero=='lich':
                attack=[skill_path('lich','lich_chain_frost'),'particles/econ/items/lich/lich_ti8_immortal_arms/lich_ti8_chain_frost.vpcf',{'A':'particles/survival/towers/trial/frost_ssr_comet.vpcf','B':'particles/survival/towers/trial/frost_ssr_chain.vpcf','C':'particles/survival/towers/trial/frost_ssr_chain.vpcf'}[preset]][tier];mode='fallback_native_skill' if tier==0 else 'native_cosmetic_skill_as_attack' if tier==1 else 'fallback_custom'
            elif hero=='techies':
                # Match multi SR's searing arrow, then distinguish higher tiers
                # with Maraxiform's Ire and its native red Desolator variant.
                attack=ANTI_AIR_PROJECTILES[tier];mode='native_searing_arrow' if tier==0 else 'native_cosmetic_searing_arrow' if tier==1 else 'native_cosmetic_searing_arrow_deso'
            if hero in ('tinker','zuus'):mode='suppressed_by_continuous_laser' if hero=='tinker' else 'replaced_by_ranked_lightning'
            verify(vpk,attack);attacks[aid]=attack
            if hero=='nevermore' and tier==2:
                ambients.append((aid,'particles/econ/items/shadow_fiend/sf_fire_arcana/sf_fire_arcana_ambient.vpcf',''))
            if hero=='zuus' and tier==2:
                ambients.append((aid,'particles/econ/items/zeus/arcana_chariot/zeus_arcana_chariot.vpcf',''))
            if hero=='techies' and tier==2:
                ambients.append((aid,'particles/econ/items/techies/techies_arcana/techies_bigshot_fuse.vpcf',''))
            report.append(dict(preset=preset,route=route,tier=['R','SR','SSR'][tier],asset_id=aid,hero=unit,body_model=body,outfit=title,purchased_item_defs=outfit,wearable_item_defs=active,projectile=attack,projectile_policy=mode,market_links=['https://steamcommunity.com/market/listings/570/'+quote(items[k]['name']) for k in outfit],price_policy='逐阶普通装束→不朽→至宝/成套不朽；不读取游戏外市场价格参与玩法'))
    for _,p,_ in ambients:verify(vpk,p)
    return dict(stages=stages,wearables=wears,attacks=attacks,activities=activities,ambients=ambients,report=report)

def combat_digest():
    values=[]
    for p in sorted(TOWERS.glob('tower_class_*.csv')):
        values.append([{k:v for k,v in r.items() if k not in ('model_name','projectile_model')} for r in table(p)[2]])
    return hashlib.sha256(json.dumps(values,ensure_ascii=False,sort_keys=True).encode()).hexdigest()

def write_base_profiles(preset):
    profiles=table(RES/'tower_visual_profiles.csv')[2]
    for r in profiles:
        if not r['profile_id'].startswith('class_'):continue
        n=int(r['profile_id'].split('_')[1])-1
        for key in ('core','detail','detail_ssr','crown'):r[key]=''
        r.update(native_base=BASES[n],color=COLORS[preset][n],radius_r='96',radius_sr='108',radius_ssr='120',alpha={'A':'0.9','B':'0.95','C':'0.95'}[preset],enabled='1',native_base_r='',color_r='',color_sr='',color_ssr='')
        if r['profile_id'] in {'class_1', 'class_6'}:
            # Retain the requested 75% portal size across outfit switches.
            r.update(radius_r='72', radius_sr='81', radius_ssr='90', radius_ur='96')
        if r['profile_id']=='class_1':
            # Outfit switches must preserve the requested orange portal and
            # the transfer of the old sigil to the initial machine-gun tower.
            r.update(DEATH_BASE_COLORS,color=DEATH_BASE_COLORS['color_r'],alpha='0.95')
        elif r['profile_id']=='class_4':
            r.update(native_base_r='willow_shadow_realm',color_r='25|219|241',color='180|95|255',alpha='0.95')
        elif r['profile_id']=='class_6':
            r.update(color='110|175|235',alpha='0.95')
    save(RES/'tower_visual_profiles.csv',profiles,[('color_r','list','R底座颜色'),('color_sr','list','SR底座颜色'),('color_ssr','list','SSR底座颜色'),('native_base_r','string','R阶段底座样式')])

def write_preset(preset,data):
    aids={s['asset_id'] for s in data['stages']};models={s['asset_id']:s['body_model'] for s in data['stages']}
    save(RES/'asset_native_wearable_stages.csv',data['stages'],[('model_skin','number','主体皮肤编号'),('model_scale','number','主体显示缩放')])
    save(RES/'asset_native_wearables.csv',data['wearables'],[('model_skin','number','饰品皮肤编号')])
    # Remove stale bindings/animations from the old unrelated-hero outfits.
    for name,add in [('asset_activity_modifiers',data['activities']),('asset_bodygroups',[])]:
        p=RES/(name+'.csv')
        if p.exists():save(p,[r for r in table(p)[2] if r['asset_id'] not in aids]+add)
    for route in ROUTES:
        p=TOWERS/f'tower_class_{route}.csv';rows=table(p)[2]
        for r in rows:
            r['model_name']=models[r['model_asset_id']];r['projectile_model']=data['attacks'][r['model_asset_id']]
        save(p,rows)
    effects=[];have=set()
    for r in table(RES/'asset_effects.csv')[2]:
        aid=r['asset_id']
        if aid in aids:
            if r['effect_role'] in ('ambient','attack_launch','attack_hit') or r['effect_key'].startswith('skin_preset:'):continue
            if r['effect_role']=='attack_projectile':r['particle_path']=data['attacks'][aid];r['notes']='按当前皮肤选择原生普攻；缺少专属普攻才使用适配弹道';have.add(aid)
            if r['skill_id'].startswith('death_grenade_'):r['particle_path']='particles/econ/items/shadow_fiend/sf_fire_arcana/sf_fire_arcana_shadowraze.vpcf';r['notes']='SSR影魔至宝影压命中，仅替换视觉'
        effects.append(r)
    for aid,p in data['attacks'].items():
        if aid not in have:effects.append(dict(effect_key='skin_preset:'+aid+':attack',asset_id=aid,effect_group_id='default_attack',effect_id='attack_projectile',effect_role='attack_projectile',phase='travel',particle_path=p,attach_type='projectile',sort_order='1',enabled='1',notes='当前皮肤弹道'))
    for i,(aid,p,owner) in enumerate(data['ambients']):
        techies_fuse=p.endswith('/techies_bigshot_fuse.vpcf')
        effects.append(dict(effect_key='skin_preset:'+aid+':ambient',asset_id=aid,effect_group_id='ambient',effect_id='skin_ambient',effect_role='ambient',phase='persistent',particle_path=p,owner_component_id=owner,attach_type='PATTACH_CUSTOMORIGIN' if techies_fuse else 'PATTACH_ABSORIGIN_FOLLOW',attachment_point='attach_fxhand' if techies_fuse else '',sort_order=str(i+1),enabled='1',notes='至宝原生饰品特效；工程师引信按官方挂点绑定' if techies_fuse else '至宝原生周身特效，模型配套'))
    # Frost attack is inherited by upper tiers. Bind its impact to the outfit
    # actually worn by that tier, while the existing radius/damage code owns AoE.
    frost_assets=[r['asset_id'] for r in data['report'] if r['route']=='frost']
    base_impacts=[r for r in effects if r['asset_id']==frost_assets[0] and r.get('effect_role')=='skill_impact' and r.get('skill_id','').startswith('frost_attack_')]
    effects=[r for r in effects if not (r['asset_id'] in frost_assets[1:] and r.get('effect_role')=='skill_impact' and r.get('skill_id','').startswith('frost_attack_'))]
    for tier,path in [(1,'particles/econ/items/lich/lich_ti8_immortal_arms/lich_ti8_chain_frost_explode.vpcf'),(2,'particles/econ/items/lich/frozen_chains_ti6/lich_frozenchains_frostnova.vpcf')]:
        for original in base_impacts:
            r=dict(original);r.update(asset_id=frost_assets[tier],effect_key='skin_preset:'+frost_assets[tier]+':'+r['skill_id'],particle_path=path,notes='当前阶装备对应的巫妖不朽命中；伤害范围仍由技能配置决定')
            effects.append(r)
    save(RES/'asset_effects.csv',effects)
    write_base_profiles(preset)
    carrier.sync_csv_sources(False)
    carrier.NPC_UNITS.write_text(carrier.expected_text(),encoding='utf-8',newline='')
    names=['asset_catalog','asset_native_wearable_stages','asset_native_wearables','asset_components','asset_activity_modifiers','asset_bodygroups','asset_effects','tower_visual_profiles']
    for name in names:
        p=RES/(name+'.csv')
        if p.exists():build(p,GEN/(name+'.lua'))
    for route in ROUTES:
        p=TOWERS/f'tower_class_{route}.csv';build(p,GEN/(p.stem+'.lua'))

def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--preset',choices=list(NAMES),default='A');parser.add_argument('--check',action='store_true');args=parser.parse_args()
    vpk=Vpk(ROOT/'../../dota/pak01_dir.vpk');schema=parse_kv(vpk.read('scripts/items/items_game.txt').decode('utf-8-sig'))['items_game'];loc=parse_kv(vpk.read('resource/localization/items_schinese.txt').decode('utf-8-sig'))['lang']['Tokens'];loc={k.lower():v for k,v in loc.items()}
    all_data={p:projections(vpk,schema,loc,p) for p in NAMES}
    if args.check:
        print('TOWER_SKIN_PRESETS_VALID presets=3 stages=63 resources=verified');return
    # Roll back all generated files if a build fails, preserving existing gameplay edits.
    files=list(RES.glob('*.csv'))+list(TOWERS.glob('tower_class_*.csv'))+list(GEN.glob('*.lua'))+[carrier.NPC_UNITS]
    old={p:p.read_bytes() for p in files};digest=combat_digest()
    try:
        write_preset(args.preset,all_data[args.preset]);assert digest==combat_digest(),'combat columns changed'
        lua=shutil.which('lua5.1') or shutil.which('lua')
        if not lua and Path('C:/Program Files/lua/bin/lua5.1.exe').exists():lua='C:/Program Files/lua/bin/lua5.1.exe'
        if not lua:raise RuntimeError('Lua 5.1 is required to validate the generated catalog before activation')
        subprocess.run([lua,'-e',"package.path='scripts/vscripts/?.lua;'..package.path; require('config/asset_catalog'); require('config/tower_route_config')"],cwd=ROOT,check=True)
    except BaseException:
        for p,b in old.items():p.write_bytes(b)
        raise
    PRESETS.mkdir(parents=True,exist_ok=True)
    (PRESETS/'active.json').write_text(json.dumps(dict(preset=args.preset,name=NAMES[args.preset],map_reload_required=True),ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    for p,data in all_data.items():
        (PRESETS/(p+'.json')).write_text(json.dumps(dict(preset=p,name=NAMES[p],stages=data['report']),ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print('TOWER_SKIN_PRESET_APPLIED '+args.preset+' stages=21 combat_unchanged=true; reload map to view')

if __name__=='__main__':main()
