"""Check that every corner/edge is an exact crop of official decoded pixels."""
from pathlib import Path
import json, hashlib, os
from PIL import Image, ImageChops

ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'design_refs/collection_gold_refine_20261019'
manifest=json.loads((OUT/'manifest.json').read_text('utf-8'))
records=[]
for spec in manifest['slices']:
    original=OUT/spec['localSourcePng']
    if not original.exists():
        original=Path(os.environ.get('COLLECTION_UI_CATALOG', ROOT/'design_refs/official_ui_catalog_20261019'))/spec['sourcePng']
    assert hashlib.sha256(original.read_bytes()).hexdigest()==spec['sourceSha256']
    im=Image.open(original).convert('RGBA');w,h=im.size
    left,top,right,bottom=spec['cutLTRB'];xs=[0,left,w-right,w];ys=[0,top,h-bottom,h]
    assert len(spec['parts'])==9
    for part in spec['parts']:
        row,col=part['row'],part['column'];crop=im.crop((xs[col],ys[row],xs[col+1],ys[row+1]))
        actual=Image.open(OUT/part['file']).convert('RGBA')
        assert crop.size==actual.size
        assert ImageChops.difference(crop,actual).getbbox() is None
        assert part['paint']==(spec['fillCenter'] or row!=1 or col!=1)
    records.append({'key':spec['key'],'parts':9,'exactPixels':True,'fillCenter':spec['fillCenter'],'fixedCornerLTRB':spec['targetLTRB']})
assert manifest['search'] is False and manifest['persistentItemSelection'] is False
assert [r['id'] for r in manifest['rounds']]==[1,2,3,4,5]
report={'result':'PASS','source':'official decoded textures','cropAudit':records,'finalSize':manifest['finalSize'],'rounds':5}
(ROOT/'output/collection_gold_refine_20261019/qa_preview/native_slice_audit.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
print('COLLECTION_GOLD_REFINE_NATIVE_AUDIT_PASS: 27 exact crops, fill policy, fixed corner geometry')
