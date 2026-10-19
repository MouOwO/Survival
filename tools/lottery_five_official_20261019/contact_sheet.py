"""Review only: arrange exact official exports into a labeled contact sheet."""
from pathlib import Path
import json
import sys
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[2]
CATALOG = ROOT / 'design_refs/official_ui_catalog_20261019'
OUT = ROOT / 'output/lottery_five_official_20261019'

def main():
    data = json.loads((CATALOG / 'catalog.json').read_text(encoding='utf-8'))
    treasures = '--treasures' in sys.argv
    source_base = ROOT / 'design_refs/lottery_five_official_20261019' if treasures else CATALOG
    records = json.loads((OUT / 'extra_native.json').read_text(encoding='utf-8'))['records'] if treasures else data['assets']
    ids = [row['id'] for row in records] if treasures else sys.argv[1:] or ['UI01775', 'UI01781', 'UI02011', 'UI04949', 'UI04018', 'UI04019', 'UI02164', 'UI04026', 'UI04022', 'UI01671']
    lookup = {row['id']: row for row in records}
    columns, w, h = (4, 360, 310) if treasures else (2, 580, 370)
    image = Image.new('RGB', (columns*w, ((len(ids)+columns-1)//columns)*h), '#161c22')
    draw = ImageDraw.Draw(image)
    font = ImageFont.truetype('C:/Windows/Fonts/arial.ttf', 17)
    for index, key in enumerate(ids):
        row = lookup[key]
        src = Image.open(source_base / row['original']).convert('RGBA')
        src.thumbnail((w-24, h-66), Image.Resampling.LANCZOS)
        x, y = index%columns*w, index//columns*h
        image.paste(src, (x+(w-src.width)//2, y+(h-66-src.height)//2), src)
        draw.text((x+12, y+h-56), key+' '+row['name'], font=font, fill='#e8d8aa')
        draw.text((x+12, y+h-30), row.get('family', 'Official treasure')+'  '+str(row['width'])+' x '+str(row['height']), font=font, fill='#adbdc7')
    OUT.mkdir(parents=True, exist_ok=True)
    image.save(OUT/'asset_contact_sheet.jpg', quality=94)
    print(OUT/'asset_contact_sheet.jpg')

if __name__ == '__main__':
    main()
