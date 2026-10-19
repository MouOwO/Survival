"""Lossless native UI slices. Corners stay fixed in the browser compositor."""
from pathlib import Path
import json, hashlib, os, shutil
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
CAT = Path(os.environ.get('COLLECTION_UI_CATALOG', ROOT / 'design_refs/official_ui_catalog_20261019'))
OUT = ROOT / 'design_refs/collection_gold_refine_20261019/assets/slices'
OUT.mkdir(parents=True, exist_ok=True)
SOURCES = OUT.parent / 'native_sources'
SOURCES.mkdir(parents=True, exist_ok=True)
specs = [
    ('window', 'panorama/images/events/dark_carnival/overworld/inner_panel_border_png', [20,20,20,20], [10,10,10,10], False),
    ('button', 'panorama/images/dota_plus/relic_rare_button_psd', [16,12,16,12], [8,6,8,6], True),
    ('slot', 'panorama/images/hud/passive_ability_border_png', [8,8,8,8], [2,2,2,2], False),
]
records = []
for key, resource, cuts, target, fill in specs:
    original = SOURCES / (key + '.png')
    if not original.exists():
        shutil.copyfile(CAT / 'assets' / (resource + '.png'), original)
    im = Image.open(original).convert('RGBA')
    w,h = im.size
    left,top,right,bottom = cuts
    xs,ys=[0,left,w-right,w],[0,top,h-bottom,h]
    parts=[]
    for row in range(3):
        for col in range(3):
            part=im.crop((xs[col],ys[row],xs[col+1],ys[row+1]))
            name=f'{key}_{row}{col}.png'
            part.save(OUT/name, optimize=True)
            parts.append({'row':row,'column':col,'file':'assets/slices/'+name,'size':list(part.size),'paint':fill or row!=1 or col!=1})
    records.append({'key':key,'source':resource+'.vtex_c','sourcePng':'assets/'+resource+'.png','localSourcePng':'assets/native_sources/'+key+'.png','dimensions':[w,h], 'sourceSha256':hashlib.sha256(original.read_bytes()).hexdigest(),'cutLTRB':cuts,'targetLTRB':target,'fillCenter':fill,'parts':parts})
(OUT.parent/'nine_slice_manifest.json').write_text(json.dumps(records,ensure_ascii=False,indent=2),encoding='utf-8')
print('NATIVE_NINE_SLICE_EXPORT_PASS: 27 lossless PNG crops; window and icon centers omitted at composition')
