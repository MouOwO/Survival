"""Display original official images on a labeled contact sheet; do not edit source images."""
from pathlib import Path
import json
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
BASE = ROOT / 'design_refs/daily_stargold_polish_20261019'
manifest = json.loads((BASE / 'provenance.json').read_text('utf-8'))
font = ImageFont.truetype('C:/Windows/Fonts/arial.ttf', 17)
small = ImageFont.truetype('C:/Windows/Fonts/arial.ttf', 14)
cols, cw, ch = 3, 460, 210
rows = (len(manifest['records']) + cols - 1) // cols
sheet = Image.new('RGB', (cols * cw, rows * ch), '#0c111a')
draw = ImageDraw.Draw(sheet)
for index, row in enumerate(manifest['records']):
    image = Image.open(BASE / row['local']).convert('RGBA')
    alpha = image.getchannel('A')
    bounds = alpha.point(lambda a: 255 if a > 32 else 0).getbbox()
    row['alpha32'] = None if bounds is None else dict(x=bounds[0], y=bounds[1], width=bounds[2]-bounds[0], height=bounds[3]-bounds[1])
    x, y = index % cols * cw, index // cols * ch
    draw.rectangle((x+6,y+6,x+cw-6,y+ch-6),fill='#1c2029',outline='#5a503b')
    draw.text((x+17,y+15),row['key'],font=font,fill='#edcf85')
    draw.text((x+17,y+41),f"{image.width} x {image.height}    alpha32 {bounds}",font=small,fill='#a0a6b0')
    image.thumbnail((cw-36,ch-82),Image.Resampling.LANCZOS)
    sheet.paste(image,(x+(cw-image.width)//2,y+70+(ch-82-image.height)//2),image)
(BASE / 'button_shortlist.png').parent.mkdir(parents=True,exist_ok=True)
sheet.save(BASE / 'button_shortlist.png')
(BASE / 'provenance.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps({'status':'PASS','count':len(manifest['records']),'contactSheet':str(BASE/'button_shortlist.png')}))
