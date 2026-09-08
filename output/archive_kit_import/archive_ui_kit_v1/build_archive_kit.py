from PIL import Image,ImageDraw,ImageFont
import numpy as np,json,shutil,zipfile
from pathlib import Path
from scipy.ndimage import binary_fill_holes,binary_closing
root=Path('/workspace/scratch/48deb03ca350'); out=root/'archive_ui_kit_v1'
for d in ['reference','exact_crops','icons_rgba','reusable','art_tiles','background_tiles']: (out/d).mkdir(exist_ok=True)
src=Image.open(root/'upload/image-edit-target-2563773781af9fa2.png').convert('RGB')
mock=root/'generated_images/exec-c54554e4-6979-47d4-a964-fdc84d20b3eb.png'
atlas=Image.open(root/'generated_images/exec-dc7aaed9-6b4e-4d11-9e24-c84562330fad.png').convert('RGB')
src.save(out/'reference/original.png');shutil.copy(mock,out/'reference/progress_mockup.png');atlas.save(out/'reference/components_generated.png')
manifest=[]
def save(im,folder,name,box=None,kind='exact_crop'):
 p=out/folder/(name+'.png');im.save(p);manifest.append(dict(file=str(p.relative_to(out)),size=list(im.size),source_rect=box,type=kind));return im
def crop(name,box,folder='exact_crops'):return save(src.crop(box),folder,name,box)
nav=['clear','void','points','weapon','spell','endless','friends','ex','blessing'];ys=[218,292,364,437,510,583,657,730,803]
for i,(n,y) in enumerate(zip(nav,ys)):
 crop('nav_'+n,[335,y-34,577,y+34]); icon=crop('icon_'+n,[367,y-24,411,y+24])
 a=np.asarray(icon).astype(float);r,g,b=a[:,:,0],a[:,:,1],a[:,:,2]
 if i==0: alpha=np.clip((190-(r+g+b)/3)/95,0,1)
 else: alpha=np.clip((np.minimum(r,g)-b*.6-48)/90,0,1)
 for state,color in [('normal',(230,209,158)),('hover',(255,235,185)),('selected',(35,65,80)),('disabled',(136,148,150))]:
  rgba=np.zeros((64,64,4),dtype=np.uint8);rgba[8:56,10:54,:3]=color;rgba[8:56,10:54,3]=(alpha*(130 if state=='disabled' else 255)).astype('uint8');save(Image.fromarray(rgba),'icons_rgba',n+'_'+state,kind='extracted_recolored_alpha')
for name,box in [('close',[1265,108,1304,148]),('hint',[1162,235,1184,259]),('book',[816,52,859,82])]:
 im=crop('icon_'+name,box);a=np.array(im).astype(float);alpha=np.clip((190-a.mean(2))/95,0,1) if name=='hint' else np.clip((np.minimum(a[:,:,0],a[:,:,1])-.6*a[:,:,2]-48)/90,0,1)
 for state,col in [('normal',(230,209,158)),('hover',(255,238,196)),('selected',(35,65,80)),('disabled',(136,148,150))]:
  z=np.zeros((*alpha.shape,4),dtype=np.uint8);z[:,:,:3]=col;z[:,:,3]=(alpha*255).astype('uint8');can=Image.new('RGBA',(64,64));part=Image.fromarray(z);can.paste(part,((64-part.width)//2,(64-part.height)//2));save(can,'icons_rgba',name+'_'+state,kind='extracted_recolored_alpha')
for row,y in enumerate([320,486,648]):
 for col,x in enumerate([605,779,953,1127]):
  num=row*4+col+1;crop(f'card_{num:02}',[x,y,x+162,y+154]);crop(f'art_{num:02}',[x+15,[330,494,653][row],x+145,[425,590,749][row]],'art_tiles')
for n,b in [('header',[335,36,1337,165]),('sidebar',[335,165,577,846]),('panel',[575,165,1337,846]),('filter_selected',[610,271,757,309]),('filter_normal',[769,272,896,307]),('scrollbar',[1294,315,1315,802]),('status_unlocked',[623,446,751,473]),('status_locked',[1144,446,1273,473])]:crop(n,b)
crop('ivory_texture',[990,181,1140,231],'background_tiles');crop('teal_texture',[436,263,481,281],'background_tiles')
# Source-derived 9 border pieces, preserving exact unmodified texels.
b=(605,320,767,474);xs=[605,617,755,767];yy=[320,332,462,474]
for j in range(3):
 for i in range(3):crop(f'card_slice_{j}{i}',[xs[i],yy[j],xs[i+1],yy[j+1]],'background_tiles')
# Generated blank assets. Chroma masking keeps teal/gold/ivory, fills enclosed interiors.
rows=[(60,211),(254,402),(414,786),(801,936)];names=[['toggle_normal','toggle_hover','toggle_selected'],['button_normal','button_hover','button_pressed'],['card_normal','card_hover','card_selected'],['badge_progress','badge_unlocked','badge_locked']]
for j,(y0,y1) in enumerate(rows):
 for i in range(3):
  box=[i*512+20,y0,(i+1)*512-20,y1];im=atlas.crop(box);a=np.array(im).astype(float);ch=a.max(2)-a.min(2);mask=binary_fill_holes(binary_closing(ch>22,iterations=2));rgba=np.dstack([a.astype('uint8'),(mask*255).astype('uint8')]);part=Image.fromarray(rgba)
  bounds=part.getbbox();part=part.crop(bounds);target=(256,76) if j<2 else ((176,176) if j==2 else (140,44));part.thumbnail((target[0]-8,target[1]-8),Image.Resampling.LANCZOS);can=Image.new('RGBA',target);can.paste(part,((target[0]-part.width)//2,(target[1]-part.height)//2));save(can,'reusable',names[j][i],box,'generated_blank_background_removed')
# Contact sheet uses actual deliverable PNGs on contrasting background.
files=list((out/'reusable').glob('*.png'))+list((out/'icons_rgba').glob('*_normal.png'))+list((out/'art_tiles').glob('*.png'))
preview=Image.new('RGB',(1040,((len(files)+3)//4)*205),(57,68,75));draw=ImageDraw.Draw(preview)
for k,p in enumerate(files):
 x=(k%4)*260;y=(k//4)*205;im=Image.open(p).convert('RGBA');im.thumbnail((240,170));preview.paste(im,(x+(260-im.width)//2,y+5),im);draw.text((x+10,y+183),p.stem,fill='white')
preview.save(out/'asset_preview.png')
(out/'manifest.json').write_text(json.dumps({'reference_size':list(src.size),'assets':manifest},ensure_ascii=False,indent=2))
print(json.dumps({'assets':len(manifest),'preview':str(out/'asset_preview.png')}))
