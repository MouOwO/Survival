from pathlib import Path
import json,io,os
from PIL import Image, ImageDraw, ImageFont

def render(package):
    m=json.loads((package/'layout.json').read_text());out=Image.new('RGBA',tuple(m['canvas']),(0,0,0,255))
    def nine_resize(im,size,border):
        if im.size==size:return im
        l,t,r,b=border;sw,sh=im.size;dw,dh=size
        sx=[0,l,sw-r,sw];sy=[0,t,sh-b,sh];dx=[0,l,dw-r,dw];dy=[0,t,dh-b,dh]
        dest=Image.new('RGBA',size)
        for yi in range(3):
            for xi in range(3):
                p=im.crop((sx[xi],sy[yi],sx[xi+1],sy[yi+1])).resize((dx[xi+1]-dx[xi],dy[yi+1]-dy[yi]),Image.Resampling.BICUBIC)
                dest.paste(p,(dx[xi],dy[yi]))
        return dest
    fits=[]
    for l in m['layers']:
        if l['kind']=='image':
            a=m['assets'][l['asset']];im=Image.open(package/a['file']).convert('RGBA')
            size=(l.get('width',im.width),l.get('height',im.height))
            im=nine_resize(im,size,a['nine_slice']) if 'nine_slice' in a else im.resize(size,Image.Resampling.LANCZOS)
            out.alpha_composite(im,(l['x'],l['y']))
        else:
            p='/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf' if l['font']=='latin' else str(package/m['fonts']['cjk'])
            font=ImageFont.truetype(p,l['size']); d=ImageDraw.Draw(out); bb=l['bbox'];stroke=l.get('stroke',0)
            ink=d.textbbox((0,0),l['text'],font=font,stroke_width=stroke);tw=ink[2]-ink[0];th=ink[3]-ink[1]
            x=bb[0]-ink[0] if l['align']=='left' else bb[2]-tw-ink[0] if l['align']=='right' else (bb[0]+bb[2]-tw)/2-ink[0]
            y=(bb[1]+bb[3]-th)/2-ink[1]
            d.text((round(x),round(y)),l['text'],font=font,fill=l['color'],stroke_width=stroke,stroke_fill=l['color'])
            fits.append({'id':l['id'],'text':l['text'],'fits':tw<=bb[2]-bb[0] and th<=bb[3]-bb[1],'ink_size':[tw,th],'box_size':[bb[2]-bb[0],bb[3]-bb[1]]})
    target=package/'previews/reassembled_dynamic.png';b=io.BytesIO();out.save(b,format='PNG')
    staging=target.with_suffix('.writing');staging.write_bytes(b.getvalue());os.replace(staging,target)
    (package/'previews/text_fit.json').write_text(json.dumps(fits,ensure_ascii=False,indent=2))
    return out

if __name__=='__build__':render(PACKAGE)
elif __name__=='__main__':render(Path(__file__).resolve().parent)
