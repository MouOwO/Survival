"""Combine the five real browser renders for review."""
from pathlib import Path
import json
from PIL import Image, ImageDraw, ImageFont

ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'design_refs/collection_gold_refine_20261019'
report=json.loads((ROOT/'output/collection_gold_refine_20261019/qa_preview/browser_report.json').read_text('utf-8'))
manifest=json.loads((OUT/'manifest.json').read_text('utf-8'))
assert report['result']=='PASS'
canvas=Image.new('RGB',(1640,1720),'#101311')
draw=ImageDraw.Draw(canvas)
font='C:/Windows/Fonts/msyh.ttc'
title=ImageFont.truetype(font,30)
heading=ImageFont.truetype(font,23)
body=ImageFont.truetype(font,16)
small=ImageFont.truetype(font,14)
draw.text((35,25),'05 黑金典藏 · 五轮连续优化',font=title,fill='#e9cf90')
draw.text((37,72),'官方 Dota 2 素材 · 九宫格固定边角 · 激战 2 分类与网格布局',font=body,fill='#afa68e')
for i,(meta,screen) in enumerate(zip(manifest['rounds'],report['rounds'])):
    x,y=30+i%2*805,120+i//2*520
    draw.rectangle((x,y,x+775,y+494),fill='#1a1e19',outline='#61543a')
    draw.text((x+18,y+13),f"R{meta['id']}  {meta['name']}"+(' · 最终方案' if i==4 else ''),font=heading,fill='#e5c77f')
    desc=[
        '窗体固定角 / 官方黑金底图完整保留',
        '分类、筛选、关闭、抽取按钮原生组装',
        '头像满铺 / 官方细框 / 品质清晰区分',
        '去除重复计数 / 提示框统一黑金九宫格',
        '960 × 548 / 78 像素头像 / 无常驻动画',
    ][i]
    draw.text((x+19,y+50),desc,font=small,fill='#a8a28f')
    im=Image.open(OUT/screen['file']).convert('RGB');b=screen['bounds']
    im=im.crop((int(b['x'])-8,int(b['y'])-8,int(b['x']+b['width'])+8,int(b['bottom'])+8))
    im.thumbnail((748,399),Image.Resampling.LANCZOS)
    canvas.paste(im,(x+(775-im.width)//2,y+83+(399-im.height)//2))
x,y=835,1160
draw.text((x+22,y+22),'最终定稿',font=heading,fill='#e9cf90')
for i,line in enumerate(['九个独立裁片，四角固定尺寸','官方原生金色按钮与空心装备框','四类各 40 项，10 列 × 4 行','只保留一次收集数量、票券与抽取','无搜索栏，无单格持久选中效果','全尺寸截图与交互预览位于同目录']):
    draw.text((x+22,y+77+i*42),'· '+line,font=body,fill='#b5ad98')
draw.text((x+22,y+368),'悬停详情 / 分类切换 / 拥有筛选均可操作',font=small,fill='#d0bb86')
draw.text((35,1686),'离线浏览器组合预览 · 采用现有正式目录与角色头像 · 拥有数量为展示样例',font=small,fill='#7e806e')
canvas.save(OUT/'overview.jpg',quality=95,subsampling=0)
print('COLLECTION_GOLD_REFINE_OVERVIEW_PASS')
