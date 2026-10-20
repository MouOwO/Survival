"""Refresh only the reviewed permanent ember row; preserve concurrent generated rows."""
from pathlib import Path
import csv
import importlib.util
import json
import re

ROOT=Path(__file__).resolve().parents[2]
spec=importlib.util.spec_from_file_location('points_config_generator',ROOT/'tools/build_configs.py')
generator=importlib.util.module_from_spec(spec);spec.loader.exec_module(generator)
identity='lottery_ember_of_legacy'
out=ROOT/'design_refs/points_goods_unique_20261018/generated'
out.mkdir(parents=True,exist_ok=True)
sources=['抽奖系统/lottery_item_definitions.csv','物品系统/content_catalog.csv','通用/tooltip_definitions.csv']
# Locate the formal tooltip table without assuming its categorized folder.
sources[-1]=next(p.relative_to(ROOT/'data/csv').as_posix() for p in (ROOT/'data/csv').rglob('tooltip_definitions.csv'))
changed=[]
for relative in sources:
    source=ROOT/'data/csv'/relative
    generated=ROOT/'scripts/vscripts/config/generated'/(source.stem+'.lua')
    temporary=out/(source.stem+'.lua')
    generator.build(source,temporary)
    before=generated.read_text('utf-8-sig')
    row=[line for line in temporary.read_text('utf-8-sig').splitlines() if '"'+identity+'"' in line]
    original=[line for line in before.splitlines() if '"'+identity+'"' in line]
    assert len(row)==len(original)==1,(relative,len(row),len(original))
    after=before.replace(original[0],row[0])
    if after!=before:
        (out/(source.stem+'.before.lua')).write_bytes(generated.read_bytes())
        generated.write_text(after,encoding='utf-8',newline='\n')
        changed.append(generated.relative_to(ROOT).as_posix())

lottery=ROOT/'data/csv/抽奖系统/lottery_item_definitions.csv'
rows=csv.DictReader(line for line in lottery.read_text('utf-8-sig').splitlines() if not line.startswith('#'))
description=next(row['description'] for row in rows if row['item_id']==identity).replace('；','\n').replace(';','\n')
catalog=ROOT/'scripts/vscripts/config/generated/archive_commerce_goods.lua'
before=catalog.read_text('utf-8-sig')
rows=[line for line in before.splitlines() if '["id"]="'+identity+'"' in line]
assert len(rows)==1
line=rows[0]
after_line=re.sub(r'\["description"\]="(?:\\.|[^"\\])*"',lambda _: '["description"]='+json.dumps(description,ensure_ascii=False),line)
after_line=after_line.replace('["source_id"]="P089"','["source_id"]="P103"').replace('["sku"]="video_p089"','["sku"]="video_p103"')
after=before.replace(line,after_line)
if after!=before:
    (out/'archive_commerce_goods.before.lua').write_bytes(catalog.read_bytes())
    catalog.write_text(after,encoding='utf-8',newline='\n')
    changed.append(catalog.relative_to(ROOT).as_posix())
print(json.dumps({'status':'POINTS_CONFIG_ROWS_REFRESHED','id':identity,'changed':changed},ensure_ascii=False))
