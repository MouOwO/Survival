"""Produce an offline review gallery from existing art; never alter master images."""
import html
import json
from collections import Counter
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

ROOT=Path(__file__).resolve().parents[1]
BULK=ROOT/'art/ui/development/remaining_ui_handoff_v1/bulk_art'
NAMES={'shadow':'虚空之影','points':'积分道具','fragment':'神兵碎片','pet':'秘法牢笼','friend':'我的好基友','ex':'我的前女友','beast':'瑞兽赐福','fishing':'钓鱼存档','building':'存档建筑','shop':'商店道具'}

def main():
    work=json.loads((BULK/'prompts.json').read_text(encoding='utf-8'))
    available=[]
    for row in work:
        file=ROOT/'panorama/src/images'/row['icon_path']
        if file.exists():
            with Image.open(file) as im:
                alpha=im.getchannel('A') if im.mode=='RGBA' else None
                row['valid_alpha']=bool(alpha and alpha.getextrema()==(0,255))
                row['source_size']=list(im.size)
            available.append(row)
    data=json.dumps(available,ensure_ascii=False).replace('<','\\u003c')
    names=json.dumps(NAMES,ensure_ascii=False)
    page='''<!doctype html><html lang="zh-CN"><meta charset="utf-8"><title>存档图标批量审阅</title>
<style>*{box-sizing:border-box}body{margin:0;padding:28px;background:#173744;color:#efeadf;font:15px "Microsoft YaHei",sans-serif}h1{font-size:25px}p{color:#c6d8db}nav{display:flex;flex-wrap:wrap;gap:8px;margin:18px 0}button,select{padding:8px 14px;background:#274c5a;color:#fff1c7;border:1px solid #b79e69;border-radius:4px;cursor:pointer}button[aria-pressed=true]{background:#e5d6b9;color:#193b49}.grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(238px,1fr));gap:16px}.card{background:#ebebe4;color:#234451;border:1px solid #bca880;padding:12px;border-radius:6px}.large{height:180px;display:flex;justify-content:center}.large img{max-width:100%;height:100%;object-fit:contain}.small{display:flex;gap:8px;justify-content:center;margin-top:8px}.sample{width:93px;height:74px;display:flex;align-items:center;justify-content:center;background:#183e4e;border:1px solid #af9a70}.sample.light{background:#f4efdf}.sample img{width:93px;height:74px;object-fit:contain}h2{font-size:16px;margin:10px 0 4px}code{font-size:11px;overflow-wrap:anywhere}.description{font-size:12px;line-height:1.6;max-height:76px;overflow:auto;color:#3e5c65}.badge{font-size:12px;color:#436658}.bad{color:#b31c26}footer{margin:25px 0}</style>
<h1>存档与商店图标 · 批量审阅</h1><p>以下为资源审阅页，不是游戏内截图。大图核对角色与造型，下方按 93×74 设计区域对照浅底、深底；原图保留真实 Alpha。</p><p id="summary"></p><nav id="categories"></nav><main class="grid" id="grid"></main><footer><button id="prev">上一页</button> <span id="page"></span> <button id="next">下一页</button> · <a style="color:#e8d29d" href="prompts.json">提示词及真实条目映射</a></footer>
<script>const data=__DATA__,names=__NAMES__;let selected='all',page=0;const size=24,grid=document.querySelector('#grid');function render(){const rows=data.filter(x=>selected==='all'||x.category_id===selected),pages=Math.max(1,Math.ceil(rows.length/size));page=Math.max(0,Math.min(page,pages-1));grid.replaceChildren();for(const row of rows.slice(page*size,page*size+size)){const card=document.createElement('article');card.className='card';const url='../../../panorama/src/images/'+row.icon_path;for(const cls of ['large','small']){const host=document.createElement('div');host.className=cls;if(cls==='large'){const a=document.createElement('a');a.href=url;a.target='_blank';const img=new Image();img.src=url;img.loading='lazy';a.append(img);host.append(a)}else for(const theme of ['light','dark']){const sample=document.createElement('div');sample.className='sample '+theme;const img=new Image();img.src=url;img.loading='lazy';sample.append(img);host.append(sample)}card.append(host)}const title=document.createElement('h2');title.textContent=row.display_name;card.append(title);const id=document.createElement('code');id.textContent=row.item_id;card.append(id);const badge=document.createElement('p');badge.className='badge'+(row.valid_alpha?'':' bad');badge.textContent=names[row.category_id]+' · '+row.source_size.join('×')+' · '+(row.valid_alpha?'Alpha 通过':'Alpha 待修复');card.append(badge);const desc=document.createElement('div');desc.className='description';desc.textContent=row.description;card.append(desc);grid.append(card)}document.querySelector('#page').textContent=(page+1)+' / '+pages;document.querySelectorAll('nav button').forEach(b=>b.setAttribute('aria-pressed',b.dataset.id===selected))}for(const id of ['all',...new Set(data.map(x=>x.category_id))]){const b=document.createElement('button');b.dataset.id=id;b.textContent=id==='all'?'全部':names[id];b.onclick=()=>{selected=id;page=0;render()};document.querySelector('nav').append(b)}document.querySelector('#prev').onclick=()=>{page--;render()};document.querySelector('#next').onclick=()=>{page++;render()};document.querySelector('#summary').textContent='已生成 '+data.length+' / __TOTAL__ 张；未完成条目保留原图，不用重复占位图冒充完成。';render();</script></html>'''
    (BULK/'index.html').write_text(page.replace('__DATA__',data).replace('__NAMES__',names).replace('__TOTAL__',str(len(work))),encoding='utf-8')
    # Contact sheets are review evidence only. Production originals are untouched.
    font=ImageFont.truetype('C:/Windows/Fonts/msyh.ttc',18)
    for category in NAMES:
        items=[r for r in available if r['category_id']==category]
        for start in range(0,len(items),24):
            subset=items[start:start+24];cols=6;cellw,cellh=180,210
            sheet=Image.new('RGB',(cols*cellw,50+((len(subset)+cols-1)//cols)*cellh),'#ebebe4')
            draw=ImageDraw.Draw(sheet);draw.text((15,10),NAMES[category]+' · 资源审阅（非游戏截图）',fill='#234451',font=font)
            for i,row in enumerate(subset):
                x=(i%cols)*cellw;y=50+(i//cols)*cellh
                with Image.open(ROOT/'panorama/src/images'/row['icon_path']) as im:
                    im.thumbnail((154,154),Image.Resampling.LANCZOS);sheet.paste(im,(x+(cellw-im.width)//2,y),im)
                draw.text((x+5,y+160),row['display_name'][:10],fill='#234451',font=font)
            sheet.save(BULK/(category+'_'+str(start//24+1)+'_review.jpg'),quality=94)
    print(json.dumps(dict(total=len(work),generated=len(available),counts=dict(Counter(r['category_id'] for r in available)),alpha_invalid=[r['item_id'] for r in available if not r['valid_alpha']])))

if __name__=='__main__':main()
