"""Build a lightweight artist-facing library without renaming engine resource IDs."""
from pathlib import Path
from collections import Counter
import csv, hashlib, html, json, re
from PIL import Image

ROOT=Path(__file__).resolve().parents[2]
CONTENT=ROOT.parents[2]/'content/dota_addons/Survival'
SOURCE=ROOT/'art/ui/sources'
OUT=ROOT/'art'
IMAGE_EXT={'.png','.svg','.jpg','.jpeg','.tga','.webp'}
CATEGORY={'clear':'通关存档','endless':'无尽存档','map_level':'地图等级','work':'上班福利','fishing':'钓鱼存档','building':'存档建筑','friend':'我的好基友','friends':'我的好基友','ex':'我的前女友','beast':'瑞兽赐福','blessing':'瑞兽赐福','shadow':'积分道具','weapon':'神兵碎片','spell':'秘法牢笼','void':'虚空之影'}
NAMES={}
CATEGORY.update({'points':'积分道具','fragment':'神兵碎片','shop':'商城道具','pet':'秘法牢笼','boss':'BOSS存档'})
def csv_rows(rel):
    with (ROOT/rel).open(encoding='utf-8-sig',newline='') as f:return list(csv.DictReader(f))
for r in csv_rows('data/csv/存档系统/archive_item_icons.csv'):
    NAMES.setdefault(r['icon_path'],[]).append(('02_存档/'+CATEGORY.get(r['category_id'],r['category_id']),r['item_id'],r['display_name']))
for r in csv_rows('data/csv/存档系统/archive_navigation_icons.csv'):
    NAMES.setdefault(r['image_path'],[]).append(('02_存档/导航图标',r['category_id'],r['display_name']))
for r in csv_rows('data/csv/肉鸽奖励系统/rogue_reward_art.csv'):
    NAMES.setdefault(r['image_path'],[]).append(('07_肉鸽/卡牌插画',r['card_id'],r['display_name']))

def classification(rel):
    if rel in NAMES:return NAMES[rel][0][0]
    s=rel.lower()
    if any(t in s for t in ['archive_gothic/','archive_moon/','lottery_celestial/','st2_']):return '90_历史兼容素材/待核对'
    if '/shared/' in s:
        sub=s.split('/shared/')[1].split('/')[0]
        return '00_公共组件/'+{'button':'按钮','card':'卡片','checkbox':'勾选框','icon':'通用图标','nav':'导航','overlay':'遮罩','texture':'纹理','badge':'状态徽标'}.get(sub,'其他')
    if 'remaining_handoff_ready/' in s and any(t in p for p in [Path(s).stem] for t in ['button_','window_','tab_','action_','reward_card']):return '00_公共组件/当前窗口与按钮'
    if 'boss_warning' in s:return '01_主界面/BOSS提示'
    if 'daily' in s:return '05_每日福利/页面素材'
    if 'rogue' in s or 'roguelike' in s:return '07_肉鸽/卡面与纹理'
    if 'shop' in s or 'commerce' in s or 'purchase' in s:return '06_商城/商品与支付窗口'
    if 'lottery' in s or 'pool_' in s or 'history_' in s:return '03_抽奖/页面素材'
    if 'archive' in s:return '02_存档/通用素材与纹理'
    if any(t in s for t in ['hud','handoff_v1/','survival_native/']):return '01_主界面/框体与图标'
    if '/page_assets/' in s:return '08_页面通用资源/待核对用途'
    if 'remaining_handoff' in s:return '08_页面通用资源/已打包素材'
    return '99_待分类/需要确认用途'

def role(stem):
    for key,label in [('close','关闭叉号'),('button','按钮'),('tab','页签'),('checkbox','勾选框'),('tooltip','提示框'),('frame','边框'),('border','边框'),('panel','面板'),('background','背景'),('card','卡牌'),('icon','图标'),('gold','金币'),('wood','木材'),('ticket','抽奖券'),('blank','空白底板')]:
        if key in stem:return label
    return '素材'
def state(stem):
    for key,label in [('disabled','禁用'),('selected','选中'),('pressed','按下'),('hover','悬停'),('normal','常态')]:
        if key in stem:return label
    return ''
def safe(s):return re.sub(r'[<>:"/\\|?*\x00-\x1f]','_',s)[:95]
def hash_file(p):return hashlib.sha256(p.read_bytes()).hexdigest()

def build():
    OUT.mkdir(exist_ok=True)
    rows=[]; shortcuts=[]
    for p in sorted(SOURCE.rglob('*')):
        if not p.is_file() or p.suffix.lower() not in IMAGE_EXT:continue
        rel=p.relative_to(SOURCE).as_posix();group=classification(rel)
        names=NAMES.get(rel,[]);key=names[0][1] if names else p.stem
        display='、'.join(dict.fromkeys(x[2] for x in names)) if names else role(p.stem)
        ident=hashlib.sha256(rel.encode()).hexdigest()[:8]
        artist_name=safe(f'{display[:32]}__{key}__{state(p.stem)}__{ident}'.replace('____','__'))
        content=CONTENT/'panorama/images'/rel
        runtime=ROOT/'panorama/images'/Path(rel).with_name(p.stem+'_'+p.suffix[1:]+'.vtex_c')
        width=height='';mode=''
        try:
            if p.suffix.lower()=='.svg':
                import xml.etree.ElementTree as ET
                a=ET.parse(p).getroot().attrib;width=a.get('width','');height=a.get('height','');mode='SVG'
            else:
                with Image.open(p) as im:width,height=im.size;mode=im.mode
        except Exception:mode='需检查'
        sha=hash_file(p)
        same=content.is_file() and hash_file(content)==sha
        row={'asset_id':ident,'category':group,'display_name':display,'business_ids':';'.join(x[1] for x in names),'artist_name':artist_name,'role':role(p.stem),'state':state(p.stem),'width':width,'height':height,'mode':mode,'source':str(p),'content':str(content) if content.is_file() else '', 'runtime':str(runtime) if runtime.is_file() else '', 'content_status':'一致' if same else ('不同，请核对后同步' if content.is_file() else '无同名文件'),'reference_status':'配置表映射' if names else '按路径分类，是否活动需结合发布清单','sha256':sha}
        rows.append(row)
        shortcuts.append({'link':str(OUT/'ui'/group/(artist_name+'.lnk')),'target':str(p)})
        if content.is_file():shortcuts.append({'link':str(CONTENT/'美术索引/UI'/group/(artist_name+'.lnk')),'target':str(content)})
    with (OUT/'UI素材总表.csv').open('w',encoding='utf-8-sig',newline='') as f:
        w=csv.DictWriter(f,fieldnames=list(rows[0]));w.writeheader();w.writerows(rows)
    (OUT/'catalog.json').write_text(json.dumps(rows,ensure_ascii=False,indent=2),encoding='utf-8')
    (OUT/'shortcuts.json').write_text(json.dumps(shortcuts,ensure_ascii=False),encoding='utf-8')
    inventory=[]
    for p in sorted(CONTENT.rglob('*')):
        if not p.is_file() or '美术索引' in p.parts:continue
        rel=p.relative_to(CONTENT).as_posix();top=rel.split('/')[0]
        kind={'panorama':'UI源文件','materials':'材质','particles':'粒子特效','maps':'地图','resource':'资源与本地化'}.get(top,'其他')
        inventory.append({'category':kind,'path':rel,'extension':p.suffix,'bytes':p.stat().st_size})
        if top != 'panorama':
            shortcuts.append({'link':str(CONTENT/'美术索引/非UI资源'/kind/(safe(p.stem)+'__'+hashlib.sha256(rel.encode()).hexdigest()[:8]+'.lnk')),'target':str(p)})
    with (OUT/'Content文件总表.csv').open('w',encoding='utf-8-sig',newline='') as f:
        w=csv.DictWriter(f,fieldnames=['category','path','extension','bytes']);w.writeheader();w.writerows(inventory)
    # No fetch/server needed: works by double-clicking the local HTML file.
    cards=[]
    for r in rows:
        esc=lambda x:html.escape(str(x),quote=True)
        tags=' '.join(str(r[k]) for k in ['category','display_name','business_ids','artist_name','source'])
        cards.append(f'<article data-search="{esc(tags.lower())}" data-category="{esc(r["category"])}"><img loading="lazy" src="{esc(Path(r["source"]).as_uri())}"><b>{esc(r["display_name"])}</b><small>{esc(r["business_ids"] or Path(r["source"]).stem)}</small><small>{esc(r["category"])} · {r["width"]} × {r["height"]}</small><a href="{esc(Path(r["source"]).as_uri())}">打开原图</a>'+ (f'<a href="{esc(Path(r["content"]).as_uri())}">content 源文件</a>' if r['content'] else '')+f'<small>{esc(r["content_status"])}</small></article>')
    options=''.join(f'<option>{html.escape(c)}</option>' for c in sorted({r['category'] for r in rows}))
    page='''<!doctype html><html lang="zh-CN"><meta charset="utf-8"><title>Survival 美术素材索引</title><style>body{margin:0;background:#162d35;color:#f0e8d8;font:16px system-ui}header{position:sticky;top:0;background:#10232b;padding:20px;z-index:2}input,select{padding:10px;width:300px;margin-right:10px}main{display:grid;grid-template-columns:repeat(auto-fill,minmax(200px,1fr));gap:12px;padding:20px}article{background:#24404a;padding:12px;overflow-wrap:anywhere}img{display:block;width:100%;height:150px;object-fit:contain;background:repeating-conic-gradient(#bbb 0% 25%,#eee 0% 50%) 0/16px 16px}b,small,a{display:block;margin-top:6px}small{font-size:12px;color:#c5caca}a{color:#edcb83}[hidden]{display:none}</style><header><b>Survival 美术素材索引</b><p>这是美术查找入口，不是游戏预览。源文件保留引擎路径；content 不一致时先核对，不要直接覆盖。</p><input id="q" placeholder="中文名称、物品编号或文件名"><select id="category"><option value="">全部分类</option>'''+options+'''</select><span id="count"></span></header><main>'''+''.join(cards)+'''</main><script>const cards=[...document.querySelectorAll('article')],q=document.querySelector('#q'),category=document.querySelector('#category');function filter(){let n=0;for(const c of cards){c.hidden=!(c.dataset.search.includes(q.value.toLowerCase())&&(!category.value||category.value===c.dataset.category));if(!c.hidden)n++}document.querySelector('#count').textContent=n+' 项'}q.oninput=filter;category.onchange=filter;filter();</script></html>'''
    (OUT/'index.html').write_text(page,encoding='utf-8')
    result={'images':len(rows),'content_inventory':len(inventory),'shortcuts':len(shortcuts),'content_status':dict(Counter(r['content_status'] for r in rows)),'categories':dict(Counter(r['category'] for r in rows))}
    (OUT/'verification.json').write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8')
    (OUT/'shortcuts.json').write_text(json.dumps(shortcuts,ensure_ascii=False),encoding='utf-8')
    print(json.dumps(result,ensure_ascii=False))
if __name__=='__main__':build()
