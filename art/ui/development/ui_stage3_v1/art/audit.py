import csv,json,hashlib,html
from pathlib import Path
from PIL import Image
root=Path(__file__).resolve().parents[5]
prompts=json.loads((root/'art/ui/development/ui_stage3_v1/art/prompts.json').read_text(encoding='utf-8'))
audit=[]
for row in prompts:
    rel='custom_game/rogue_cards_v1/'+row['id']+'.png'
    f=root/'panorama/src/images'/rel
    if not f.exists(): continue
    with Image.open(f) as im:
        alpha=im.getchannel('A') if im.mode=='RGBA' else None
        if alpha is None or alpha.getextrema()[0]!=0: raise ValueError('No real alpha: '+row['id'])
        audit.append(dict(card_id=row['id'],display_name=row['name'],image_path=rel,width=im.width,height=im.height,alpha_min=alpha.getextrema()[0],alpha_max=alpha.getextrema()[1],enabled=row['enabled'],sha256=hashlib.sha256(f.read_bytes()).hexdigest()))
here=Path(__file__).resolve().parent
(here/'audit.json').write_text(json.dumps(audit,ensure_ascii=False,indent=2),encoding='utf-8')
page='<!doctype html><meta charset="utf-8"><title>肉鸽大图 · 离线素材审阅</title><style>body{background:#183c46;color:#f3ead6;font:16px sans-serif}main{display:grid;grid-template-columns:repeat(auto-fill,minmax(210px,1fr));gap:16px}article{background:#ece7da;padding:14px;color:#203d47}img{width:100%;height:300px;object-fit:contain}small{display:block;overflow-wrap:anywhere}</style><h1>肉鸽大图 · 离线素材审阅（不是游戏验收图）</h1><main>'
for row in audit:
    page+='<article><img loading="lazy" src="../../../../panorama/src/images/'+row['image_path']+'"><b>'+html.escape(row['display_name'])+'</b><small>'+row['card_id']+'</small><small>'+('启用' if row['enabled'] else '原配置停用，仅保留素材')+'</small></article>'
(here/'index.html').write_text(page+'</main>',encoding='utf-8')
print(f'Alpha inspected: {len(audit)}/{len(prompts)}')
if len(audit)==len(prompts):
    target=root/'data/csv/肉鸽奖励系统/rogue_reward_art.csv'
    with target.open('w',encoding='utf-8-sig',newline='') as stream:
        writer=csv.writer(stream)
        writer.writerow(['card_id','display_name','image_path','design_width','design_height','notes'])
        writer.writerows([r['card_id'],r['display_name'],r['image_path'],232,348,'仅美术映射；停用卡不启用'] for r in audit)
    print('Complete art-only CSV mapping written; gameplay configuration unchanged')
