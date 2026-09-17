"""Read-only PNG audit. Never rewrites alpha or image pixels."""
import json,struct,zlib,pathlib
root=pathlib.Path(__file__).resolve().parent.parent
registry=json.loads((root/'art/ui/development/ui_reuse_import/runtime_registry.json').read_text(encoding='utf-8'))
results=[]
for asset_id,a in registry['assets'].items():
    if not a['runtime'].startswith('ui/'): continue
    data=(root/'panorama/src/images'/a['runtime']).read_bytes(); offset=8; chunks=[]; palette_alpha=None
    while offset<len(data):
        size=struct.unpack('>I',data[offset:offset+4])[0];kind=data[offset+4:offset+8];chunk=data[offset+8:offset+8+size];offset+=12+size
        if kind==b'IHDR': w,h,depth,kind_color,_,_,interlace=struct.unpack('>IIBBBBB',chunk)
        if kind==b'IDAT':chunks.append(chunk)
        if kind==b'tRNS':palette_alpha=chunk
    assert [w,h]==a['size'],asset_id
    has_alpha=kind_color in (4,6) or palette_alpha is not None
    if a['transparent']:assert has_alpha,asset_id+' lacks real alpha'
    record={'id':asset_id,'size':[w,h],'color_type':kind_color,'has_alpha':has_alpha,'quality':a['quality']}
    # Decode only small state assets to audit transparent corners efficiently.
    if w*h<300000 and depth==8 and interlace==0 and kind_color in (4,6):
        bpp=4 if kind_color==6 else 2;stride=w*bpp;raw=zlib.decompress(b''.join(chunks));prev=bytearray(stride);corners=[];minimum=255;maximum=0
        for y in range(h):
            f=raw[y*(stride+1)];row=bytearray(raw[y*(stride+1)+1:(y+1)*(stride+1)])
            for i in range(stride):
                left=row[i-bpp] if i>=bpp else 0;up=prev[i];ul=prev[i-bpp] if i>=bpp else 0
                if f==1: p=left
                elif f==2:p=up
                elif f==3:p=(left+up)//2
                elif f==4:
                    base=left+up-ul;dist=[abs(base-left),abs(base-up),abs(base-ul)];p=[left,up,ul][dist.index(min(dist))]
                else:p=0
                row[i]=(row[i]+p)%256
            alpha=row[bpp-1::bpp];minimum=min(minimum,min(alpha));maximum=max(maximum,max(alpha))
            if y in (0,h-1):corners.extend([alpha[0],alpha[-1]])
            prev=row
        record.update(alpha_range=[minimum,maximum],corner_alpha=corners)
    results.append(record)
(root/'art/ui/development/ui_reuse_import/alpha_audit.json').write_text(json.dumps(results,ensure_ascii=False,indent=2),encoding='utf-8')
print('SHARED_ALPHA_PASS:',len(results),'original PNGs; dimensions and real alpha match registry; no pixels modified')
