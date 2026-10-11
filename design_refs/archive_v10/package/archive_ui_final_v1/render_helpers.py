"""Local Pillow helpers used by the approved V10 composition."""
from pathlib import Path
import io, os
from PIL import Image, ImageDraw, ImageFont, ImageFilter

def save_png(im,path):
    path.parent.mkdir(parents=True,exist_ok=True)
    b=io.BytesIO();im.save(b,format='PNG');p=path.with_suffix(path.suffix+'.writing')
    p.write_bytes(b.getvalue());os.replace(p,path)
    with Image.open(path) as test:test.load()

def nine_slice(im,size,border):
    if im.size==size:return im
    l,t,r,b=border;sw,sh=im.size;dw,dh=size
    sx=[0,l,sw-r,sw];sy=[0,t,sh-b,sh];dx=[0,l,dw-r,dw];dy=[0,t,dh-b,dh]
    out=Image.new('RGBA',size)
    for yi in range(3):
        for xi in range(3):
            p=im.crop((sx[xi],sy[yi],sx[xi+1],sy[yi+1])).resize((dx[xi+1]-dx[xi],dy[yi+1]-dy[yi]),Image.Resampling.LANCZOS)
            out.paste(p,(dx[xi],dy[yi]))
    return out

def draw_text(out,text,bb,font,color,align='center',shadow=False):
    d=ImageDraw.Draw(out);stroke=(2 if text.startswith('—') else 1) if shadow and align=='right' else 0;ink=d.textbbox((0,0),text,font=font,stroke_width=stroke);tw=ink[2]-ink[0];th=ink[3]-ink[1]
    x=bb[0]-ink[0] if align=='left' else bb[2]-tw-ink[0] if align=='right' else (bb[0]+bb[2]-tw)/2-ink[0]
    y=(bb[1]+bb[3]-th)/2-ink[1]
    if shadow:
        # Glyph shadow only: no rectangle or gradient plate underneath the quantity.
        shadow_layer=Image.new('RGBA',out.size);sd=ImageDraw.Draw(shadow_layer)
        sd.text((round(x),round(y+1)),text,font=font,fill=(0,0,0,210),stroke_width=1,stroke_fill=(0,0,0,145))
        out.alpha_composite(shadow_layer.filter(ImageFilter.GaussianBlur(.45)))
        d=ImageDraw.Draw(out)
    d.text((round(x),round(y)),text,font=font,fill=color,stroke_width=stroke,stroke_fill='#070710')
    return {'text':text,'bbox':bb,'ink_size':[tw,th],'fits':tw<=bb[2]-bb[0] and th<=bb[3]-bb[1]}

