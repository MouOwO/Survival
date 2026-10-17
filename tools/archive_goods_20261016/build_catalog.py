"""Read-only collection metadata from active formal definitions; no grants."""
from pathlib import Path
import hashlib,importlib.util,json,re,subprocess
ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'design_refs/archive_goods_20261016'
GENERATED=ROOT/'scripts/vscripts/config/generated/archive_commerce_goods.lua'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def icon_uri(name,root=ROOT):
    """Validate the shared visual resolver's URI without guessing an item from its name."""
    assert isinstance(name,str),'unsafe_icon:'+str(name)
    asset=r'(custom_game|items|spellicons)/(?:[A-Za-z0-9_-]+/)*[A-Za-z0-9_-]+'
    if re.fullmatch(r's2r://panorama/images/'+asset+r'\.vtex',name):
        relative=name[len('s2r://'):]
        compiled=root/(relative+'_c')
        recipe=root/'panorama/src'/relative[len('panorama/'):]
        assert compiled.is_file() or (recipe.is_file() and recipe.with_suffix('.png').is_file()),'missing_icon:'+name
        return name
    relative=name[len('file://{images}/'):] if name.startswith('file://{images}/') else name
    assert re.fullmatch(asset+r'\.(?:png|svg)',relative),'unsafe_icon:'+name
    if relative.startswith('custom_game/'):
        assert (root/'panorama/src/images'/relative).is_file(),'missing_icon:'+name
    return 'file://{images}/'+relative
def lua(v):
    if isinstance(v,bool):return 'true' if v else 'false'
    if isinstance(v,str):return json.dumps(v,ensure_ascii=False)
    if isinstance(v,(int,float)):return str(v)
    if isinstance(v,list):return '{'+','.join(lua(x) for x in v)+'}'
    if isinstance(v,dict):return '{'+','.join('['+lua(k)+']='+lua(x) for k,x in v.items())+'}'
    raise TypeError(type(v).__name__)
def main():
    OUT.mkdir(parents=True,exist_ok=True)
    resource_spec=importlib.util.spec_from_file_location('shared_item_resources',ROOT/'tools/build_item_resources.py')
    resource_module=importlib.util.module_from_spec(resource_spec);resource_spec.loader.exec_module(resource_module)
    _,resource_rows,resource_aliases=resource_module.load(ROOT)
    def resource(item):
        keys=[item] if isinstance(item,str) else [item.get(k) for k in ('sku','id','item_id','ownership_id','source_id')]
        return next((resource_rows[resource_aliases[k]] for k in keys if k in resource_aliases),None)
    h=json.loads((ROOT/'server/bundles/current.json').read_bytes())['hash']
    source=ROOT/'server/bundles'/h/'bundle.json';assert sha(source)==h
    cfg=json.loads(source.read_bytes())['configs'];products=cfg['commerce_catalog']['rows']
    cash_path=ROOT/'design_refs/shop_functional_20261016/release_v2/payment_catalog.json'
    cash=json.loads(cash_path.read_bytes())['products']
    resolved=json.loads(subprocess.run(['node',str(Path(__file__).with_name('resolve_icons.cjs')),str(source),str(cash_path)],
      cwd=ROOT,capture_output=True,check=True,timeout=15).stdout)
    lottery={r['item_id']:r for r in cfg['lottery_item_definitions']['rows']}
    order=json.loads((ROOT/'data/ui/shop_catalog_presentation_20261016.json').read_bytes())['groups']['all']
    ranks={sku:i for i,sku in enumerate(order)}
    rows=[];markers=set();omitted=[];aliases=[];icons=set();icon_substitutions=[]
    def icon(name):
        uri=icon_uri(name);icons.add(uri);return uri
    def text(v):return str(v).replace('；','\n').replace(';','\n')
    def add(row):
        asset=resource(row)
        assert asset,'unregistered_collection_resource:'+row['id']
        row.update(icon=icon(asset['uri']),resource_id=asset['id'])
        row.update(sort_order=len(rows)+1,enabled=True,icon_type='image');rows.append(row)
    def product(p,legacy=False):
        marker=p['item_id'];sku=p['sku']
        if marker in markers:
            aliases.append(dict(sku=sku,ownership_id=marker,reason='same_permanent_item'));return
        markers.add(marker);name=p['title'];description=p['description'];paused=not p['enabled']
        if marker=='lottery_ember_of_legacy':
            name=lottery[marker]['display_name'];description=lottery[marker]['description']
        condition='购买或获得该永久权益后解锁'
        if paused:
            assert sku in {'video_p037','video_p038'} and p['currency']=='shop_gold'
            condition='商城金币暂未开放；保留历史持有记录，当前不可购买'
        if p.get('product_type')=='bundle':
            condition='购买该礼包后解锁；子道具按实际持有记录分别点亮'
        artwork=resolved['icons'].get(sku) or p['icon']
        add(dict(id=marker,kind='product',source_id=p.get('source_id') or sku,sku=sku,ownership_id=marker,
          name=name,description=text(description),icon=icon(artwork),quality=lottery.get(marker,{}).get('quality',''),
          unlock_condition=condition,catalog_paused=paused,source='cash_legacy' if legacy else 'commerce'))
    for p in sorted(products,key=lambda p:ranks.get(p['sku'],10000+p['sort_order'])):
        sku=p['sku']
        if not p['enabled'] and sku not in {'video_p037','video_p038'}:
            omitted.append(dict(sku=sku,reason='unimplemented_or_disabled'));continue
        if sku=='video_p001':
            omitted.append(dict(sku=sku,reason='consumable_ticket'));continue
        if sku.startswith('video_bundle_vip_'):
            package=[c for c in p['grants']['vip_claims'] if c.startswith('vip_package_')]
            assert len(package)==1
            aliases.append(dict(sku=sku,ownership_id=package[0],reason='canonical_VIP_package_card'));continue
        product(p)
    commerce_skus={p['sku'] for p in products}
    for p in cash:
        if p['sku'] in commerce_skus:continue
        if p['enabled'] and p['purchase_limit']==1:product(p,True)
        else:omitted.append(dict(sku=p['sku'],reason='disabled_sample_consumable_or_expiring'))
    for t in sorted(cfg['archive_starjoy_levels']['rows'],key=lambda t:t['level']):
        if not t.get('enabled'):continue
        add(dict(id=t['tier_id'],kind='starjoy',source_id=t['tier_id'],ownership_id=t['tier_id'],
          name=t['display_name'],description=text(t['description']),icon=icon(resource(t['tier_id'])['uri']),quality='',
          level=t['level'],required_points=t['required_points'],source='starjoy_settled_level',
          unlock_condition='累计获得星悦积分达到'+str(t['required_points'])+'，以实际已结算等级点亮'))
    for v in cfg['archive_vip_rewards']['rows']:
        if not v.get('enabled'):continue
        art=resource(v['reward_id'])['uri']
        add(dict(id=v['reward_id'],kind='vip',source_id=v['reward_id'],ownership_id=v['reward_id'],
          name=v['display_name'],description=text(v['description']),icon=icon(art),quality='',level=v['level'],
          unlock_condition=v['condition']+'；以实际领取或购买发放记录为准',source='vip_'+v['group_id']))
    assert len(rows)==178,len(rows)
    assert len({r['id'] for r in rows})==178
    assert sum(r['kind']=='starjoy' for r in rows)==24
    assert sum(r['kind']=='vip' for r in rows)==33
    assert sum(r['source']=='cash_legacy' for r in rows)==5
    assert sum(r.get('catalog_paused',False) for r in rows)==2
    assert all('max_owned' not in r for r in rows),'Do not infer holdings caps from purchase limits'
    assert {r['ownership_id'] for r in rows}>={'commerce_p016','commerce_p028','commerce_p032','lottery_monkey_king','commerce_p147'}
    paths=['data/csv/存档系统/archive_categories.csv','scripts/vscripts/config/generated/archive_categories.lua',
           'scripts/vscripts/config/generated/archive_commerce_goods.lua']
    for name in paths:
        p=ROOT/name;b=OUT/'baseline'/name
        if p.exists() and not b.exists():b.parent.mkdir(parents=True,exist_ok=True);b.write_bytes(p.read_bytes())
    payload=dict(source_bundle=h,rows=rows,aliases=aliases,omitted=omitted)
    (OUT/'catalog.json').write_text(json.dumps(payload,ensure_ascii=False,indent=2)+'\n',encoding='utf8')
    raw='-- AUTO-GENERATED read-only collection metadata by tools/archive_goods_20261016/build_catalog.py\n'
    raw+='local M = { source_bundle = '+lua(h)+', rows = {\n'+''.join('    '+lua(r)+',\n' for r in rows)+'} }\n'
    raw+='M.by_id = {}\nfor _, row in ipairs(M.rows) do M.by_id[row.id] = row end\nreturn M\n'
    GENERATED.write_text(raw,encoding='utf8',newline='\n')
    category=ROOT/paths[0];original=category.read_bytes()
    spec=importlib.util.spec_from_file_location('csv_builder',ROOT/'tools/build_configs.py')
    builder=importlib.util.module_from_spec(spec);spec.loader.exec_module(builder)
    if b'commerce_goods,' not in original:
        category.write_bytes(original+(b'' if original.endswith(b'\n') else b'\n')+b'commerce_goods,'+'商城道具'.encode()+b',commerce_goods,99,1\n')
    builder.build(category,ROOT/'scripts/vscripts/config/generated/archive_categories.lua')
    report=dict(status='PASS',count=len(rows),source_bundle=h,
      kinds={k:sum(r['kind']==k for r in rows) for k in ['product','starjoy','vip']},
      aliases=aliases,omitted=omitted,icons=sorted(icons),paused_known_permanent_items=['video_p037','video_p038'],
      icon_substitutions=icon_substitutions,
      paused_currency_stays_closed=True,server_or_player_mutations=False,
      icon_resolver=resolved['resolver'],icon_resolver_sha256=resolved['resolver_sha256'],
      category_source_sha256=sha(category),generated_catalog_sha256=sha(GENERATED))
    (OUT/'catalog_build.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf8')
    print(json.dumps({k:report[k] for k in ['status','count','kinds','source_bundle','server_or_player_mutations']},ensure_ascii=False))
if __name__=='__main__':main()
