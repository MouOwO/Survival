"""Compose the five actual browser captures for quick visual comparison."""
from pathlib import Path
import json
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'design_refs/lottery_five_official_20261019'
SHOTS = ROOT / 'output/lottery_five_official_20261019/qa/browser'

def main():
    themes = json.loads((Path(__file__).with_name('schemes.json')).read_text(encoding='utf-8'))['themes']
    width, height = 840, 510
    image = Image.new('RGB', (width*2, height*3), '#11171e')
    draw = ImageDraw.Draw(image)
    font = ImageFont.truetype('C:/Windows/Fonts/msyh.ttc', 22)
    for index, theme in enumerate(themes):
        screenshot = Image.open(SHOTS / f'1920x1080_{theme["id"]}_map_stage.png').convert('RGB')
        screenshot.thumbnail((width-24, height-56), Image.Resampling.LANCZOS)
        x, y = index%2*width, index//2*height
        draw.text((x+20, y+12), f'方案 {index+1:02d} · {theme["title"]}', font=font, fill='#e5d3ad')
        image.paste(screenshot, (x+(width-screenshot.width)//2, y+50))
    draw.text((width+28, height*2+90), '同一布局 · 五套官方素材组合', font=font, fill='#cfc2a4')
    draw.text((width+28, height*2+135), '完整效果与交互请打开 HTML 预览', font=font, fill='#9daab4')
    image.save(OUT / '五套方案对比.jpg', quality=95)
    print(OUT / '五套方案对比.jpg')

if __name__ == '__main__':
    main()
