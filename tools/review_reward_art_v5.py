"""Validate all reward masters and render labelled review sheets (masters stay untouched)."""
import csv, hashlib, json, math
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
ROOT=Path(__file__).resolve().parents[1]
manifest=json.loads((ROOT/'data/ui/reward_art_v5.json').read_text(encoding='utf-8'))
spec=json.loads((ROOT/'data/ui/reward_art_v5_prompts.json').read_text(encoding='utf-8'))
assert set(manifest)=={r['id'] for r in spec}
assert len({r['sha256'] for r in manifest.values()})==len(manifest),'Duplicated masters'
assert len({r['runtime_uri'] for r in manifest.values()})==len(manifest),'Duplicated runtime icons'
checks=[]
for identity,row in manifest.items():
    source=ROOT/'panorama/src/images'/row['icon_path'];blob=source.read_bytes()
    assert hashlib.sha256(blob).hexdigest()==row['sha256'],identity
    if Path(row['original_file']).is_file():
        assert blob==Path(row['original_file']).read_bytes(),'Master altered: '+identity
    with Image.open(source) as im:
        assert im.width==im.height and im.mode=='RGBA',identity
        alpha=im.getchannel('A');lo,hi=alpha.getextrema()
        assert lo==0 and hi>=250,(identity,lo,hi)
        bounds=alpha.point(lambda a:255 if a>32 else 0).getbbox()
        assert bounds,('Empty art',identity)
        edge_touch=bounds[0]==0 or bounds[1]==0 or bounds[2]==im.width or bounds[3]==im.height
        checks.append({'id':identity,'size':im.size,'bounds':bounds,'alpha':[lo,hi],'edge_touch':edge_touch})
for script in ['item_art_remaining_5d5c1152eb.js','icons_remaining_5d5c1152eb.js']:
    s=(ROOT/'panorama/src/scripts/custom_game'/script).read_text(encoding='utf-8');start=s.index('entries=')+len('entries=')
    entries,_=json.JSONDecoder().raw_decode(s[start:]);lookup={r['item_id']:r for r in entries}
    expected=[r for r in spec if r['kind']!='pool' and (script.startswith('item_art') or r['id'] in lookup)]
    for item in expected:
        row=lookup[item['id']];assert row['runtime_uri']==manifest[item['id']]['runtime_uri'],item['id']
        assert not row.get('portrait') and not row.get('tint_icon'),item['id']
font=ImageFont.truetype('C:/Windows/Fonts/msyh.ttc',17)
out=ROOT/'output/reward_art_v5_review';out.mkdir(parents=True,exist_ok=True)
for page in range(math.ceil(len(spec)/35)):
    part=spec[page*35:(page+1)*35]
    sheet=Image.new('RGB',(7*170,5*190),'#132d38');draw=ImageDraw.Draw(sheet)
    for i,item in enumerate(part):
        x=(i%7)*170;y=(i//7)*190
        with Image.open(ROOT/'panorama/src/images'/manifest[item['id']]['icon_path']) as im:
            art=im.copy();art.thumbnail((148,148),Image.Resampling.LANCZOS)
            sheet.paste(art,(x+(170-art.width)//2,y+8+(148-art.height)//2),art)
        draw.text((x+85,y+160),item['name'],font=font,fill='#e8eef0',anchor='mt')
    sheet.save(out/('sheet_'+str(page+1)+'.jpg'),quality=94)
(out/'audit.json').write_text(json.dumps({'count':len(checks),'checks':checks},ensure_ascii=False,indent=2),encoding='utf-8')
print('REWARD_ART_V5_PASS:',len(checks),'distinct, transparent, byte-identical masters and consistent runtime mappings')
print('EDGE_REVIEW:',[c['id'] for c in checks if c['edge_touch']])
