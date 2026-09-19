"""Original periodic material fields, not cropped reference-board images.
Run inside Blender's Python (NumPy); all scalar data maps are generated separately.
"""
import os, json, math, zlib, struct
import numpy as np
ROOT=r'D:\steam\steamapps\common\dota 2 beta\game\dota_addons\survival'
OUT=os.path.join(ROOT,'output','xianxia_kit'); MAT=os.path.join(OUT,'materials')
os.makedirs(MAT,exist_ok=True)
N=1024
y,x=np.meshgrid(np.arange(N)/N,np.arange(N)/N,indexing='ij')
def png(path,a):
    a=np.asarray(np.clip(a,0,1)*255+.5,dtype=np.uint8)
    if a.ndim==2:a=np.repeat(a[:,:,None],3,axis=2)
    h,w,c=a.shape
    def chunk(t,d):return struct.pack('!I',len(d))+t+d+struct.pack('!I',zlib.crc32(t+d)&0xffffffff)
    with open(path,'wb')as f:f.write(b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('!2I5B',w,h,8,6 if c==4 else 2,0,0,0))+chunk(b'IDAT',zlib.compress(b''.join(b'\x00'+row.tobytes()for row in a),6))+chunk(b'IEND',b''))
def smooth(a):a=np.clip(a,0,1);return a*a*(3-2*a)
def noise(seed,octaves=5):
    rng=np.random.default_rng(seed);v=np.zeros_like(x)
    for k in range(octaves):
        freq=2**k
        for j in range(4):
            a,b=rng.integers(-freq,freq+1,2);v+=np.sin(2*np.pi*(a*x+b*y)+rng.random()*6.28)/(2**k*4)
    return v
fine=noise(74,8); broad=noise(32,4); grain=noise(123,10)
micro=np.zeros_like(x);rng=np.random.default_rng(442)
for i in range(35):
    a,b=rng.integers(35,440,2);micro+=np.sin(math.tau*(a*x+b*y)+rng.random()*math.tau)/9
records=[]
def save(name,c,h,r,strength=1,mask=None):
    c=np.clip(c,0,1);h=np.clip(h,0,1);r=np.clip(r+np.zeros_like(h),0,1)
    dx=(np.roll(h,-1,1)-np.roll(h,1,1))*strength*12
    dy=(np.roll(h,-1,0)-np.roll(h,1,0))*strength*12
    n=np.stack([-dx,dy,np.ones_like(h)],2);n/=np.linalg.norm(n,axis=2)[:,:,None]
    maps={'color':c,'height':h,'normal':n*.5+.5,'roughness':r,'reflectance':(1-r)**2}
    if mask is not None:maps['mask']=mask
    rec={'name':name,'size':[N,N],'maps':{},'normalConvention':'tangent +Y (OpenGL), generated from periodic height, not color','colorSpace':{'color':'sRGB','normal':'Non-Color','height':'Non-Color','roughness':'Non-Color','reflectance':'Non-Color','mask':'Non-Color'}}
    for suffix,a in maps.items():
        png(os.path.join(MAT,name+'_'+suffix+'.png'),a)
        # Compare wrap transitions with the ordinary neighboring-pixel gradient.
        seam=float(max(np.mean(np.abs(a[:,0]-a[:,-1])),np.mean(np.abs(a[0]-a[-1]))))
        normal=float((np.mean(np.abs(np.diff(a,axis=0)))+np.mean(np.abs(np.diff(a,axis=1))))/2)
        rec['maps'][suffix]={'wrapMean':seam,'interiorMean':normal,'file':name+'_'+suffix+'.png'}
    small=c[::2,::2];png(os.path.join(OUT,'previews',name+'_repeat_2x2.png'),np.tile(small,(2,2,1)))
    records.append(rec)
# Periodic jittered stone cells: narrow chipped joints, mineral inclusions,
# sparse fractures. Torus distances ensure exact repeat continuity.
rng=np.random.default_rng(504);d1=np.full_like(x,9);d2=d1.copy();cell=np.zeros_like(x)
wx=x+.004*noise(55,6);wy=y+.004*noise(90,6)
for j in range(4):
    for i in range(4):
        cx=(i+.5+rng.uniform(-.24,.24))/4;cy=(j+.5+rng.uniform(-.24,.24))/4
        dx=(wx-cx+.5)%1-.5;dy=(wy-cy+.5)%1-.5;d=np.sqrt(dx*dx+dy*dy)
        nearer=d<d1;cell=np.where(nearer,rng.uniform(.1,1),cell);d2=np.where(nearer,d1,np.minimum(d2,d));d1=np.minimum(d1,d)
edge=(d2-d1);mortar=smooth((edge-.0025-.0018*micro)/.009)
fracture=(1-smooth((np.abs(noise(78,5))-.001)/.005))*smooth((noise(98,4)-.16)*8)
h=.24+.54*mortar+.035*fine+.014*micro-.035*fracture
mineral=.034*noise(962,7)+.018*micro-.028*fracture
c=np.stack([.66+.08*cell+.035*fine+mineral,.65+.072*cell+.03*fine+mineral,.59+.065*cell+.025*fine+mineral],2)
c*= (.69+.31*mortar)[:,:,None]
save('xx_stone',c,h,.86+.03*fine,.8)
# Layered rock has mineral facets and moss in cracks, with periodic fields.
strata=np.sin(2*np.pi*(y*7+.09*np.sin(x*6*np.pi)))
h=.5+.23*noise(19,6)+.055*strata+.02*micro
moss=smooth((noise(87,5)-.15)*2)*smooth((.58-h)*8)
c=np.stack([.51+.13*fine-.12*moss+.045*micro,.54+.12*fine-.05*moss+.04*micro,.50+.12*fine-.18*moss+.035*micro],2)
save('xx_rock',c,h,.89,1.4,moss)
# Teal ceramic, wood grain, soft grass/earth and aged bronze are separate materials.
save('xx_roof',np.stack([.13+.04*fine,.29+.04*fine,.29+.05*fine],2),.5+.12*grain,.47+.12*fine,.3)
woodgrain=np.sin(2*np.pi*(x*28+.14*np.sin(y*4*np.pi)+.035*np.sin(y*18*np.pi)))
save('xx_wood',np.stack([.27+.035*fine+.02*woodgrain,.19+.025*fine+.012*woodgrain,.12+.02*fine+.008*woodgrain],2),.5+.16*woodgrain+.1*grain,.88,.55)
blades=np.sin(2*np.pi*(x*72+y*21+.12*np.sin(y*8*np.pi)))*np.sin(2*np.pi*(x*29-y*83))
save('xx_grass',np.stack([.30+.055*fine,.40+.07*fine,.23+.045*fine],2),.5+.08*blades+.06*grain,.95,.6)
save('xx_earth',np.stack([.44+.06*fine,.38+.05*fine,.27+.035*fine],2),.5+.10*grain+.07*fine,.97,.8)
# A separate periodic scalar transition mask plus a ready-to-use mixed surface.
blend=smooth((noise(331,6)+.05)*3)
grass=np.stack([.30+.055*fine,.40+.07*fine,.23+.045*fine],2)
earth=np.stack([.44+.06*fine,.38+.05*fine,.27+.035*fine],2)
save('xx_ground_blend',earth*(1-blend[:,:,None])+grass*blend[:,:,None],.5+.06*grain+.05*blades*blend,.95,.6,blend)
save('xx_bronze',np.stack([.48+.08*fine,.36+.06*fine,.15+.035*fine],2),.5+.08*grain,.53+.1*fine,.4)
# Standalone ornament field (no typography); used as normal/height for optional floor inlays.
rx=x-.5;ry=y-.5;radius=np.hypot(rx,ry);angle=np.arctan2(ry,rx)
rings=np.zeros_like(x)
for r in [.20,.29,.36,.41]:rings=np.maximum(rings,1-smooth((np.abs(radius-r)-.002)/.003))
rings*=smooth((.47-radius)/.025)
save('xx_array',c*0+np.array([.65,.64,.57]),.55-.18*rings,.87,1.5,rings)
# Water height and normals are data, not a baked blue photo with highlights.
waterh=.5+.14*noise(321,6)+.035*np.sin(2*np.pi*(x*9+y*13))
save('xx_water',np.stack([x*0+.09,x*0+.32,x*0+.36],2),waterh,.19,.5)
# Leaf cutout independently authored on a fully transparent canvas.
for name,col in [('xx_leaf',(0.29,.40,.20)),('xx_blossom',(.78,.48,.53))]:
    u=(x-.5)/.4;v=(y-.5)/.42;r=np.sqrt(u*u+v*v)
    a=smooth((1-r)/.035);rgba=np.zeros((N,N,4));rgba[:,:,:3]=col;rgba[:,:,3]=a
    png(os.path.join(MAT,name+'_color.png'),rgba)
with open(os.path.join(OUT,'material_manifest.json'),'w')as f:json.dump(records,f,indent=2)
print('Independent periodic materials:',len(records))
