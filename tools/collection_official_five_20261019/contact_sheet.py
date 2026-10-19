"""Arrange browser captures for side-by-side design review; no game art edits."""
from pathlib import Path
import json
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[2]
DELIVERY = ROOT / 'design_refs/collection_official_five_20261019'
report = json.loads((ROOT / 'output/collection_official_five_20261019/browser_report.json').read_text('utf-8'))
manifest = json.loads((DELIVERY / 'manifest.json').read_text('utf-8'))
assert report['result'] == 'PASS'
canvas = Image.new('RGB', (1640, 1710), '#10161c')
draw = ImageDraw.Draw(canvas)
font = 'C:/Windows/Fonts/msyh.ttc'
title = ImageFont.truetype(font, 30)
heading = ImageFont.truetype(font, 22)
body = ImageFont.truetype(font, 17)
small = ImageFont.truetype(font, 14)
draw.text((36, 23), '收藏 · 五套官方 UI 方案', font=title, fill='#e9e4d8')
draw.text((38, 69), '激战 2 布局：竖向分类 / 10 × 4 连续网格 / 底部货币与抽取', font=body, fill='#9daab4')
for index, (theme, screen) in enumerate(zip(manifest['themes'], report['themes'])):
    left, top = 30 + index % 2 * 805, 120 + index // 2 * 525
    draw.rounded_rectangle((left, top, left + 775, top + 502), radius=3, fill='#1b242c', outline='#39454d')
    draw.text((left + 19, top + 13), theme['number'] + '  ' + theme['name'], font=heading, fill=theme['accent'])
    draw.text((left + 20, top + 49), theme['subtitle'], font=small, fill='#a8b4bb')
    source = Image.open(DELIVERY / screen['file']).convert('RGB')
    bounds = screen['bounds']
    crop = source.crop((int(bounds['x'])-10, int(bounds['y'])-10,
                        int(bounds['x']+bounds['width'])+10, int(bounds['bottom'])+10))
    crop.thumbnail((747, 411), Image.Resampling.LANCZOS)
    canvas.paste(crop, (left + (775-crop.width)//2, top + 83 + (411-crop.height)//2))
left, top = 835, 1170
draw.text((left + 22, top + 27), '共同保留', font=heading, fill='#e7dcc0')
for index, text in enumerate(['官方背景、边框、按钮与导航图标', '现有角色头像，四类收藏均可切换', '无搜索栏，无单格常驻选中效果', '悬停详情、拥有筛选与本地抽取演示']):
    draw.text((left + 22, top + 80 + index * 43), '· ' + text, font=body, fill='#aebac1')
draw.text((left + 22, top + 290), '完整尺寸图片：01 ～ 05 单独打开查看', font=body, fill='#d1bc8f')
draw.text((left + 22, top + 334), 'index.html 可点击切换全部方案', font=body, fill='#d1bc8f')
draw.text((36, 1680), '离线浏览器组合预览 · 数量为展示样例', font=small, fill='#7d8b94')
canvas.save(DELIVERY / 'overview.jpg', quality=95, subsampling=0)
print('COLLECTION_FIVE_OVERVIEW_SAVED ' + str(DELIVERY / 'overview.jpg'))
