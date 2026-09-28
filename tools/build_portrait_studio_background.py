"""Build a static opaque studio backdrop for every native 3D unit portrait."""
from pathlib import Path
import math,struct,zlib
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'output/portrait_live_20260927/source/materials/survival_ui'
OUT.mkdir(parents=True,exist_ok=True)
size=512;raw=bytearray()
for y in range(size):
 raw.append(0)
 for x in range(size):
  # Solid blue-black slate inset with softly lit bevels, not a fog/spotlight.
  u=x/(size-1);v=y/(size-1)
  light=(1-v)*0.30+(1-u)*0.22
  grain=(((x*73+y*151)%29)/29-.5)*1.7+math.sin(y*.79+x*.012)*.65
  inset=min(u,1-u,v,1-v)
  bevel=6 if .023<inset<.029 else -5 if .029<=inset<.036 else 0
  facet=3.5*max(0,1-abs(u-.16)/.11)-2.5*max(0,1-abs(u-.86)/.10)
  # All seams are at the perimeter; nothing runs across a unit's face.
  color=[round(a+b*light+grain+bevel+facet) for a,b in [(10,29),(23,40),(31,46)]]
  raw.extend([max(0,min(255,c)) for c in color]+[255])

def chunk(tag,data):return struct.pack('>I',len(data))+tag+data+struct.pack('>I',zlib.crc32(tag+data)&0xffffffff)
png=b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('>IIBBBBB',size,size,8,6,0,0,0))+chunk(b'IDAT',zlib.compress(raw,9))+chunk(b'IEND',b'')
(OUT/'portrait_slate_backdrop.png').write_bytes(png)
panorama_image=ROOT/'panorama/src/images/custom_game/portraits/portrait_slate_backdrop.png'
panorama_image.parent.mkdir(parents=True,exist_ok=True)
panorama_image.write_bytes(png)
(OUT/'portrait_slate_backdrop.vmat').write_text('''"Layer0"
{
 "shader" "ui.vfx"
 "F_STENCIL_MASKING" "1"
 "F_TRANSLUCENT" "1"
 "Texture" "materials/survival_ui/portrait_slate_backdrop.png"
}
''',encoding='utf-8')
for legacy in ('portrait_studio','portrait_hud_backdrop'):
 (OUT/(legacy+'.vmat')).write_text((OUT/'portrait_slate_backdrop.vmat').read_text(encoding='utf-8'),encoding='utf-8')
print('PORTRAIT_SLATE_SOURCE_READY 512x512 opaque; legacy profile aliases retained')
