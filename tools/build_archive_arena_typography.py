"""Build static arena popup glyph assets from the project's licensed Source Han font.
Requires Pillow. Dynamic numbers/data remain native labels. Activate with switch_archive_popup_ui.py.
"""
from pathlib import Path
import re,sys
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'output/ui_review_python'))
from PIL import Image,ImageDraw,ImageFont,ImageFilter
FONT=ROOT/'panorama/fonts/Radiance-Survival-SourceHanSansSC-Medium.otf'
OUT=ROOT/'output/popup_iterations_20261009/assets'
OUT.mkdir(parents=True,exist_ok=True)
rows=re.findall(r'category_id = "([^"]+)", display_name = "([^"]+)"',(ROOT/'scripts/vscripts/config/generated/archive_categories.lua').read_text(encoding='utf8'))
for key,text in rows+[('archive','存档')]:
 for role,w,h,size in [('heading',680,110,64),('nav',280,64,36)]:
  font=ImageFont.truetype(str(FONT),size);im=Image.new('RGBA',(w,h));draw=ImageDraw.Draw(im);bounds=draw.textbbox((0,0),text,font=font)
  x=(w-(bounds[2]-bounds[0]))/2-bounds[0] if role=='heading' else 0;y=(h-(bounds[3]-bounds[1]))/2-bounds[1]
  if role=='heading':
   glow=Image.new('RGBA',(w,h));ImageDraw.Draw(glow).text((x,y),text,font=font,fill=(172,125,220,160),stroke_width=2);im.alpha_composite(glow.filter(ImageFilter.GaussianBlur(5)))
  ImageDraw.Draw(im).text((x,y),text,font=font,fill=(237,225,255,255) if role=='heading' else (210,194,239,255))
  im.save(OUT/f'arena_{role}_{key}.png')
for key,text in [('unlocked','已解锁'),('locked','未解锁'),('detail','查看详情')]:
 font=ImageFont.truetype(str(FONT),32);im=Image.new('RGBA',(280,64));draw=ImageDraw.Draw(im);bounds=draw.textbbox((0,0),text,font=font)
 draw.text(((280-(bounds[2]-bounds[0]))/2-bounds[0],(64-(bounds[3]-bounds[1]))/2-bounds[1]),text,font=font,fill=(226,209,248,255));im.save(OUT/f'arena_state_{key}.png')
print('Static glyph assets:',OUT)
