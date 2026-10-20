"""Build a versioned Source Han bitmap glyph atlas for the archive popup only.
Native labels retain live data/events; atlas rendering avoids client font fallback.
Uses the project's unmodified, OFL-licensed Source Han Sans SC Medium font.
"""
from pathlib import Path
import sys,json,hashlib,unicodedata
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'output/ui_review_python'))
from PIL import Image,ImageDraw,ImageFont
FONT=ROOT/'panorama/fonts/Radiance-Survival-SourceHanSansSC-Medium.otf'
OUT=ROOT/'output/popup_iterations_20261009/assets'
RECORD=ROOT/'output/popup_refinement_v12_20261010'
chars=set(chr(i) for i in range(32,127))|set('…×·−：，。！？（）【】「」“”‘’％＋☆★')
for directory,extensions in [('panorama/src/scripts/custom_game',{'.js'}),('panorama/src/layout/custom_game',{'.xml'}),('scripts/vscripts/config',{'.lua'}),('data/csv',{'.csv'})]:
 for source in (ROOT/directory).rglob('*'):
  if source.is_file() and source.suffix in extensions:
   try:text=source.read_text(encoding='utf-8-sig')
   except UnicodeError:continue
   chars.update(c for c in text if ord(c)>=32 and not unicodedata.category(c).startswith('C'))
font=ImageFont.truetype(str(FONT),32)
cell=64;side=2048;cols=side//cell;per=cols*cols
ordered=sorted(chars);metrics={};pages=[]
for start in range(0,len(ordered),per):
 page=Image.new('RGBA',(side,side));draw=ImageDraw.Draw(page);number=len(pages)
 for index,c in enumerate(ordered[start:start+per]):
  x=(index%cols)*cell;y=(index//cols)*cell
  draw.text((x+8,y+8+font.getmetrics()[0]),c,font=font,anchor='ls',fill=(255,255,255,255))
  metrics[c]=[number,x,y,round(font.getlength(c),3)]
 filename=f'arena_font_v12_{number}.png';page.save(OUT/filename);pages.append(filename)
data={'font':'Source Han Sans SC Medium','font_sha256':hashlib.sha256(FONT.read_bytes()).hexdigest(),'size':32,'cell':64,'side':side,'padding':8,'logical_height':sum(font.getmetrics()),'pages':pages,'glyphs':metrics}
(RECORD/'font_atlas.json').write_text(json.dumps(data,ensure_ascii=False,separators=(',',':')),encoding='utf8')
# Keep recorded V12 source and its atlas coordinates in sync when text changes.
script=RECORD/'v12.js'
if script.exists():
 source=script.read_text(encoding='utf8');begin=source.index('var atlas=')+len('var atlas=');end=source.index(',missingGlyphs=',begin)
 payload={k:v for k,v in data.items() if k not in ('font','font_sha256')}
 source=source[:begin]+json.dumps(payload,ensure_ascii=False,separators=(',',':'))+source[end:]
 script.write_text(source,encoding='utf8');(ROOT/'output/popup_iterations_20261009/v12.js').write_text(source,encoding='utf8')
print('Archive glyphs:' ,len(metrics),'pages:',len(pages),'logical height:',data['logical_height'])
