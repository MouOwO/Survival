"""Native hero shader: moving pearlescent color, separate height-mask UVs.

The alpha channel never scrolls during construction. Only color coordinates
animate; reveal material groups move the soft height mask down the building.
"""
import math
import struct
import zlib
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'output/building_presentation/source/materials/survival_buildings'
REVEAL_STEPS=48
REVEAL_SECONDS=1.5

def png(path,width,height,pixels):
    def chunk(kind,data):
        return struct.pack('>I',len(data))+kind+data+struct.pack('>I',zlib.crc32(kind+data)&0xffffffff)
    rows=b''.join(b'\0'+bytes(pixels[y*width*4:(y+1)*width*4]) for y in range(height))
    path.write_bytes(b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('>IIBBBBB',width,height,8,6,0,0,0))+chunk(b'IDAT',zlib.compress(rows))+chunk(b'IEND',b''))

def material(step):
    # Native hero.vfx makes F_DO_NOT_CAST_SHADOWS mutually exclusive with
    # F_TRANSLUCENT. Disable prop shadows in Lua; setting both shader flags
    # silently compiles an opaque DXT1 color texture without the height mask.
    return '''"Layer0"
{
    "shader" "hero.vfx"
    "F_TRANSLUCENT" "1"
    "F_SEPARATE_ALPHA_TRANSFORM" "1"
    "TextureColor" "materials/survival_buildings/build_flow_color.png"
    "TextureNormal" "materials/survival_buildings/build_flow_normal.png"
    "TextureTranslucency" "materials/survival_buildings/build_flow_mask.png"
    "g_flAmbientScale" "1.25"
    "g_flDiffuseModulationAmount" "1.0"
    "g_flSelfIllumBlendToFull" "0.22"
    "g_flSpecularBlendToFull" "1.0"
    "g_flSpecularScale" "2.5"
    "g_flSpecularExponent" "96.0"
    "g_vSpecularColor" "[0.85 0.95 1.0 0.0]"
    "g_flRimLightScale" "2.5"
    "g_vRimLightColor" "[0.35 0.72 1.0 0.0]"
    "g_flBloomScale" "0.3"
    "g_flBloomShift" "0.0"
    "g_vBloomColor" "[0.7 0.9 1.0 0.0]"
    "g_vTexCoordScale" "[1.0 3.0 1.0 1.0]"
    "g_vAlphaTexCoordScale" "[1.0 1.0 1.0 1.0]"
    "g_vAlphaTexCoordOffset" "[0.0 OFFSET 0.0 0.0]"
    "DynamicParams"
    {
        "g_vTexCoordOffset" "return float2(time()*0.085, -time()*0.19);"
    }
}
'''.replace('OFFSET',f'{step/REVEAL_STEPS*.48:.6f}')

def main():
    OUT.mkdir(parents=True,exist_ok=True)
    size=512;pixels=bytearray();normals=bytearray();mask=bytearray()
    palette=((.28,.55,.72),(.78,.87,.91),(.95,.82,.52),(.6,.5,.76),(.8,.93,.95))
    for y in range(size):
        v=(y+.5)/size
        a=max(0,min(1,(.47-v)/.05));a=a*a*(3-2*a)
        for x in range(size):
            u=(x+.5)/size
            # Broad, continuous ribbons; no animated opacity or random pulses.
            wave=(u*2+v*2+.16*math.sin(math.tau*(v*2-u)))%1
            p=wave*len(palette);i=int(p);t=p-i;t=t*t*(3-2*t)
            rgb=[palette[i][k]*(1-t)+palette[(i+1)%len(palette)][k]*t for k in range(3)]
            ribbon=math.exp(-((wave-.24)/.035)**2)*.22
            pixels.extend([round(255*min(1,c+ribbon)) for c in rgb]+[255])
            mask.extend([round(a*255)]*4)
            nx=.10*math.sin(math.tau*(u*2+v*2));ny=.10*math.cos(math.tau*(u*2-v*2));nz=math.sqrt(1-nx*nx-ny*ny)
            normals.extend([round((nx*.5+.5)*255),round((ny*.5+.5)*255),round((nz*.5+.5)*255),255])
    png(OUT/'build_flow_color.png',size,size,pixels)
    png(OUT/'build_flow_normal.png',size,size,normals)
    png(OUT/'build_flow_mask.png',size,size,mask)
    for step in range(REVEAL_STEPS+1):
        (OUT/f'build_flow_{step:02d}.vmat').write_text(material(step),encoding='utf-8')
    print(f'BUILDING_FLOW_MATERIALS materials={REVEAL_STEPS+1} reveal_seconds={REVEAL_SECONDS}')

if __name__=='__main__':main()
