"""Self-contained dynamic Tooltip renderer; call render_tooltip(package, package, data)."""
from pathlib import Path
import io, json, os
from PIL import Image, ImageDraw, ImageFont

def save_png(im,path):
    path.parent.mkdir(parents=True,exist_ok=True)
    b=io.BytesIO();im.save(b,format='PNG');p=path.with_suffix(path.suffix+'.writing')
    p.write_bytes(b.getvalue());os.replace(p,path)
    with Image.open(path) as test:test.load()

def nine_slice(im,size,border):
    if im.size==size:return im.copy()
    l,t,r,b=border;sw,sh=im.size;dw,dh=size
    if dw<l+r or dh<t+b:raise ValueError('Target is smaller than fixed corners')
    sx=[0,l,sw-r,sw];sy=[0,t,sh-b,sh];dx=[0,l,dw-r,dw];dy=[0,t,dh-b,dh]
    out=Image.new('RGBA',size)
    for yi in range(3):
        for xi in range(3):
            p=im.crop((sx[xi],sy[yi],sx[xi+1],sy[yi+1]))
            p=p.resize((dx[xi+1]-dx[xi],dy[yi+1]-dy[yi]),Image.Resampling.LANCZOS)
            out.paste(p,(dx[xi],dy[yi]))
    return out

def wrap_text(text,font,width):
    lines=[]
    for para in str(text).split('\n'):
        line=''
        for c in para:
            if line and font.getlength(line+c)>width:lines.append(line);line=c
            else:line+=c
        lines.append(line)
    return lines or ['']

def render_tooltip(package,base,data):
    m=json.loads((package/'tooltip_layout.json').read_text());cfg=m['layout'];pad=cfg['padding'];w=cfg['width']
    font_path=base/'fonts/SourceHanSansSC-Regular.otf'
    fonts={k:ImageFont.truetype(str(font_path),v) for k,v in {'title':22,'body':17,'small':15}.items()}
    title_lines=wrap_text(data.get('title','—'),fonts['title'],w-2*pad)
    extra_header=(len(title_lines)-1)*28
    state='—' if data.get('current') is None else '已拥有' if data['current']>0 else '未解锁'
    effect_lines=[]
    for effect in data.get('effects') or ['—']:effect_lines.extend(wrap_text(effect,fonts['body'],w-2*pad))
    h=cfg['minimum_height']+extra_header+max(0,len(effect_lines)-1)*cfg['line_height']
    shadow_pad=cfg['shadow_padding'];out=Image.new('RGBA',(w+shadow_pad*2,h+shadow_pad*2))
    for key,pos,size in [('shadow',(0,0),out.size),('background',(shadow_pad,shadow_pad),(w,h)),('frame',(shadow_pad,shadow_pad),(w,h))]:
        a=m['assets'][key];im=Image.open(package/a['file']).convert('RGBA')
        im=nine_slice(im,size,a['nine_slice_ltrb']);out.alpha_composite(im,pos)
    a=m['assets']['separator'];im=Image.open(package/a['file']).convert('RGBA').resize((w-2*pad,4),Image.Resampling.LANCZOS)
    out.alpha_composite(im,(shadow_pad+pad,shadow_pad+79+extra_header))
    d=ImageDraw.Draw(out);fits=[]
    def put(id,text,x,y,font,color,align='left',allowed_width=w-2*pad):
        ink=d.textbbox((0,0),text,font=font);tw=ink[2]-ink[0];th=ink[3]-ink[1]
        if align=='right':x-=tw
        d.text((round(shadow_pad+x-ink[0]),round(shadow_pad+y-ink[1])),text,font=font,fill=color)
        fits.append({'id':id,'text':text,'ink_size':[tw,th],'fits':tw<=allowed_width,'panel_position':[x,y]})
    for i,line in enumerate(title_lines):put('title_'+str(i),line,pad,19+i*28,fonts['title'],'#e1cc83')
    put('state',data.get('category','虚空之影')+' · '+state,pad,52+extra_header,fonts['small'],'#bab9b5')
    put('effect_caption','道具效果',pad,95+extra_header,fonts['small'],'#aaa9a4')
    for i,line in enumerate(effect_lines):put('effect_'+str(i),line,pad,121+extra_header+i*26,fonts['body'],'#e9e7e1')
    current='—' if data.get('current') is None else str(data['current'])
    quantity=current if data.get('cap') is None else current+' / '+str(data['cap'])
    put('quantity_label','持有数量',pad,h-44,fonts['small'],'#aaa9a4',allowed_width=112)
    put('quantity',quantity,w-pad,h-44,fonts['body'],'#dac98e','right',allowed_width=w-2*pad-112)
    return out,{'width':w,'height':h,'state':state,'text_fit':fits,'all_text_fits':all(f['fits'] for f in fits)}

def clamp_position(anchor,size,bounds,gap=13):
    x0,y0,x1,y1=anchor;w,h=size;bx0,by0,bx1,by1=bounds
    x=x1+gap
    if x+w>bx1:x=x0-gap-w
    x=max(bx0,min(x,bx1-w));y=max(by0,min(y0+21,by1-h))
    return int(x),int(y)

