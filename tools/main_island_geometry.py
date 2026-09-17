"""Reference-led cross island. Source units, floor origin Z=0, north quadrant +Y."""
import math
from mathutils import Vector, Matrix
from gold_room_geometry import GoldKit, PALETTE as GOLD_PALETTE

PALETTE={**GOLD_PALETTE,
 'stone':(.73,.70,.62),'stone_light':(.77,.735,.65),'stone_cool':(.68,.68,.625),
 'rock':(.53,.56,.52),'rock_wet':(.29,.37,.33),'mortar':(.39,.39,.33),
 'blue_cloth':(.28,.38,.48),'ochre_cloth':(.60,.40,.17),'rose_cloth':(.46,.25,.32),
 'pink':(.94,.53,.62),'pink_light':(1,.73,.75),'pink_dark':(.65,.28,.39),
 'water':(.025,.18,.26),'foam':(.38,.59,.57),'water_dark':(.015,.085,.12),
}
PLATFORM=[(-1536,2816),(1536,2816),(1536,4352),(1152,4864),(-1152,4864),(-1536,4352)]
OUTER_EDGE=[(1536,1536),(1536,4352),(1152,4864),(-1152,4864),(-1536,4352),(-1536,1536)]
INNER_EDGE=[(640,640),(448,1792),(320,2304)]
FLOOR_Z=640;WATER_Z=400

def clip(poly,boundary):
    for a,b in zip(boundary,boundary[1:]+boundary[:1]):
        result=[]
        def side(p):return (b[0]-a[0])*(p[1]-a[1])-(b[1]-a[1])*(p[0]-a[0])
        for p,q in zip(poly,poly[1:]+poly[:1]):
            u,v=side(p),side(q)
            if u>=-1e-6:result.append(p)
            if (u>=0)!=(v>=0):
                t=u/(u-v);result.append((p[0]+t*(q[0]-p[0]),p[1]+t*(q[1]-p[1])))
        poly=result
        if not poly:break
    return poly

def inner(y):
    return 640-(y-640)/6 if y<=1792 else 448-(y-1792)/4 if y<=2304 else 320

def arm_parts(side=1):
    result=[]
    for a,b in zip([640,1536,1792,2304],[1536,1792,2304,2816]):
        p=[(inner(a),a),(min(a,1536),a),(min(b,1536),b),(inner(b),b)]
        # The first strip starts at a shared diagonal point.
        p=[v for i,v in enumerate(p)if i==0 or v!=p[i-1]]
        if side<0:p=[(-x,y)for x,y in p][::-1]
        result.append(p)
    return result

class IslandKit(GoldKit):
    def __init__(self,seed=1):super().__init__(seed);self.keys=list(PALETTE)
    def stone(self,c,s,light=False):
        self.box(c,s,'stone_light' if light else self.rng.choices(['stone','stone_light','stone_cool'],[8,1,1])[0],3.0)
    def slab(self,p,z=0):
        if len(p)<3:return
        area=abs(sum(a[0]*b[1]-a[1]*b[0]for a,b in zip(p,p[1:]+p[:1])))/2
        if area<5:return
        cx=sum(x for x,y in p)/len(p);cy=sum(y for x,y in p)/len(p)
        edge=[(cx+(x-cx)*.985,cy+(y-cy)*.985)for x,y in p]
        top=[(cx+(x-cx)*.982,cy+(y-cy)*.982)for x,y in edge]
        n=len(p);v=[(x,y,zz)for points,zz in [(edge,z-18),(edge,z-2),(top,z)]for x,y in points]
        f=[tuple(reversed(range(n))),tuple(range(2*n,3*n))]
        f +=[(j*n+i,j*n+(i+1)%n,(j+1)*n+(i+1)%n,(j+1)*n+i)for j in range(2)for i in range(n)]
        self.mesh(v,f,self.rng.choices(['stone','stone_light','stone_cool'],[14,1,1])[0])
    def paved(self,polys,origin=(0,0)):
        for p in polys:
            self.polygon(p,-480,463,'mortar')
            for y in range(math.floor(min(v[1]for v in p)/128)*128,math.ceil(max(v[1]for v in p)/128)*128,128):
                for x in range(math.floor(min(v[0]for v in p)/128)*128,math.ceil(max(v[0]for v in p)/128)*128,128):
                    self.slab(clip([(x,y),(x+128,y),(x+128,y+128),(x,y+128)],p))
        self.v=[(x-origin[0],y-origin[1],z)for x,y,z in self.v]
    def bank(self,length=256):
        self.box((0,12,-186),(length,82,372),'mortar',0)
        for row in range(5):
            edges=sorted(set([-length/2,length/2]+[i*64+(32 if row%2 else 0)for i in range(-5,6)if -length/2<i*64+(32 if row%2 else 0)<length/2]))
            for a,b in zip(edges,edges[1:]):
                self.box(((a+b)/2,-4,-341+row*70),(b-a-1.2,94,68),'rock_wet' if row<2 else 'stone',3)
        self.cap(length)
    def cap(self,length=256):
        for i in range(round(length/64)):
            self.stone((-length/2+(i+.5)*64,0,0),(63,116,30),True)
    def cliff(self,kind=0):
        # Seam endpoints are fixed; silhouette variation stays inside the module.
        n=8;v=[]
        for row,z in enumerate([-480,-300,-150,-20]):
            for i in range(n+1):
                t=i/n;x=-128+t*256
                outward=(40+kind*35)*math.sin(math.pi*t)
                y=-40-outward-(self.rng.uniform(0,45)if i not in (0,n) else 0)
                v.append((x,y,z+(self.rng.uniform(-12,12)if i not in(0,n)else 0)))
        # Each column has a real irregular outward face, then a buried backing.
        v += [(x,90,z)for x,y,z in v]
        off=4*(n+1);faces=[];mats=[]
        for row in range(3):
            for i in range(n):
                a=row*(n+1)+i;b=a+1;c=b+n+1;d=a+n+1
                faces.extend([(a,b,c),(a,c,d)]);mats.extend(['rock_wet' if row==0 else 'rock']*2)
                faces.append((a+off,d+off,c+off,b+off));mats.append('rock')
        for i in range(n):
            faces.extend([(i,i+off,i+1+off,i+1),(3*(n+1)+i,3*(n+1)+i+1,3*(n+1)+i+1+off,3*(n+1)+i+off)]);mats.extend(['rock_wet','rock'])
        for end in (0,n):
            for row in range(3):
                a=row*(n+1)+end;b=a+n+1;faces.append((a,b,b+off,a+off));mats.append('rock')
        for f,m in zip(faces,mats):self.mesh([v[i]for i in f],[tuple(range(len(f)))],m)
        for i in range(5):
            x=-98+i*48;z=self.rng.uniform(-215,-35)
            self.rock((x,-50-20*kind,z),(self.rng.uniform(55,95),self.rng.uniform(35,70),self.rng.uniform(90,210)),'rock')
        for i in range(8):
            x=self.rng.uniform(-110,110);self.rock((x,-67,-215+self.rng.uniform(-60,60)),(16,3,32),'moss')
    def lowwall(self):
        self.box((0,0,41),(256,55,82),'mortar',0)
        for row in range(2):
            for i in range(4):self.stone((-96+i*64,0,20+row*39),(63,63,38))
        start=len(self.v);self.cap();self.transform_since(start,offset=(0,0,90))
    def post(self):
        self.stone((0,0,9),(105,105,18),True)
        for z in (38,82,126):self.stone((0,0,z),(80,80,43))
        self.stone((0,0,155),(105,105,18),True);self.stone((0,0,171),(64,64,16),True)
    def banner(self,color='teal'):
        start=len(self.v);self.flag()
        self.v[start:]=[(x*2.15,y*2.15,z*2.15+128)for x,y,z in self.v[start:]]
        teal=self.keys.index('teal');target=self.keys.index(color)
        self.m=[target if m==teal else m for m in self.m]
    def standard_post(self):
        for z,s in [(15,112),(45,88)]:self.stone((0,18,z),(s,s,30),True)
        self.beam((0,18,55),(0,18,465),10,'bronze',True)
        self.stone((0,18,122),(55,55,110))
        self.cone((0,18,454),24,17,20,'gold',10)
        self.cone((0,18,481),16,0,35,'gold',10)
    def cherry(self,variant=0):
        trunk=[(0,0,0),(-15,9,85),(12,-8,180),(-3,10,270),(25,3,360)]
        if variant:trunk=[(-x,y,z)for x,y,z in trunk]
        for i,(a,b)in enumerate(zip(trunk,trunk[1:])):self.beam(a,b,20-i*3,'wood',True,17-i*3)
        for j in range(10):
            a=j*2.399+variant;h=230+(j%4)*40;end=Vector((math.cos(a)*(135+(j%3)*24),math.sin(a)*(100+(j%3)*16),h+70))
            self.beam((0,0,h*.65),end,7,'wood',True,2)
            # Airy, discrete leaf / blossom clusters instead of solid pink spheres.
            for n in range(32):
                p=end+Vector((self.rng.uniform(-65,65),self.rng.uniform(-48,48),self.rng.uniform(-27,42)))
                c=self.rng.choice(['pink','pink_light','pink_light','pink_dark'])
                for k in range(5):
                    ang=k*math.tau/5
                    self.leaf(p,p+Vector((math.cos(ang)*self.rng.uniform(8,16),math.sin(ang)*self.rng.uniform(8,16),self.rng.uniform(-3,7))),self.rng.uniform(6,10),c)
        for a in range(6):self.beam((0,0,10),(math.cos(a)*40,math.sin(a)*40,0),7,'wood',True,2)
    def foam(self):
        for j in range(2):
            for i in range(6):
                x=-126+i*43;y=-4-j*22+math.sin(i*1.7+j)*7
                if self.rng.random()<.2:continue
                top=[(x+t*7,y+math.sin(t*.9+i)*6+self.rng.uniform(-2,2))for t in range(7)]
                bottom=[(xx,yy+self.rng.uniform(1,4))for xx,yy in top][::-1]
                self.polygon(top+bottom,0,.10,'foam')

def build_modules():
    jobs=[]
    def add(name,label,k,category='structure',collision=None,**extra):jobs.append(dict(name=name,label=label,kit=k,category=category,collision=collision or [],**extra))
    box=lambda c,s:dict(center=c,size=s)
    k=IslandKit(100);k.paved([PLATFORM],(0,3584));add('m01_player_platform','M01 玩家平台基体',k,polygons=PLATFORM)
    for side in (-1,1):
        k=IslandKit(110+side);k.paved(arm_parts(side),(0,0));add('m02_arm_'+('left'if side<0 else'right'),'M02 连接通道 '+('左'if side<0 else'右'),k)
    k=IslandKit(120)
    for i in range(16):
        top=(i+1)*244/16
        for j in range(4):k.stone((-216+j*144,(i+.5)*32,top-10),(143,31.5,20))
        k.box((0,(i+.5)*32,(top-20)/2),(576,32,top-20),'mortar',0) if top>20 else None
    add('m03_stair_treads','M03 迎敌阶梯 · 16 级',k)
    for side in (-1,1):
        k=IslandKit(130+side)
        for i in range(16):
            z=(i+1)*244/16
            k.box((0,(i+.5)*32,z/2+12),(64,32,z+24),'stone',1)
            k.stone((0,(i+.5)*32,z+30),(74,33,20),True)
        for y,z in [(0,16),(512,244)]:k.stone((0,y,z+57),(86,86,106),True)
        add('m03_stair_cheek_'+('left'if side<0 else'right'),'M03 阶梯侧帮 '+str(side),k,collision=[box((0,256,145),(76,576,290))])
    k=IslandKit(140);k.bank();add('m04_inner_bank_256','M04 内岸直墙',k,collision=[box((0,0,-186),(256,94,372))])
    for side in(-1,1):
        k=IslandKit(150+side);k.bank(128);start=len(k.v);k.bank(128);k.transform_since(start,side*math.pi/2,(side*64,64,0))
        add('m05_bank_'+('convex'if side>0 else'concave'),'M05 内岸折角 '+str(side),k)
    k=IslandKit(160);k.paved([[(-128,-128),(128,-128),(128,128),(-128,128)]])
    for x,y in [(-120,-100),(100,-100)]:k.rock((x,y,-150),(210,170,440),'rock')
    add('m06_outer_corner','M06 外岸转角基体',k)
    for i,style in enumerate(['clean','worn','moss']):
        k=IslandKit(170+i);k.paving(i==1)
        if i==2:
            for xy in [(-90,-90),(100,90),(0,120)]:start=len(k.v);k.moss_patch();k.transform_since(start,offset=(*xy,.3))
        add('m07_paving_'+style,['M07 干净地坪','M07 轻磨损地坪','M07 边缘苔痕地坪'][i],k,'floor')
    for typ in ['straight','corner','end']:
        k=IslandKit(180);k.cap(64 if typ=='end' else 128 if typ=='corner' else 256)
        if typ=='corner':s=len(k.v);k.cap(128);k.transform_since(s,math.pi/2,(64,64,0))
        add('m08_coping_'+typ,'M08 岸沿压顶 '+typ,k)
    for i,typ in enumerate(['straight','bulge','recess']):
        k=IslandKit(190+i);k.cliff([0,1,-1][i]);add('m09_cliff_'+typ,'M09 外岸岩壁 '+typ,k)
    for i,typ in enumerate(['dry','wet']):
        k=IslandKit(200+i)
        for j in range(30):
            x=k.rng.uniform(-125,125);y=k.rng.uniform(-70,70)
            k.rock((x,y,k.rng.uniform(-2,2)),(k.rng.uniform(10,35),k.rng.uniform(8,24),5),'earth' if i==0 else 'rock_wet')
        for j in range(8):k.rock((k.rng.uniform(-120,120),k.rng.uniform(-60,60),2),(10,9,6),'stone')
        add('m10_transition_'+typ,'M10 石土草过渡 '+typ,k,'nature')
    k=IslandKit(210);k.foam();add('m11_shore_foam','M11 岸线碎沫',k,'water')
    k=IslandKit(220);k.mesh([(-512,-512,0),(512,-512,0),(512,512,0),(-512,512,0)],[(0,1,2,3)],'water');add('m12_water_tile','M12 深蓝水面模块',k,'water')
    k=IslandKit(221);v=[(0,0,0)];n=128
    for r in range(80,1601,80):v.extend((r*math.cos(i*math.tau/n),r*math.sin(i*math.tau/n),0)for i in range(n))
    f=[(0,1+i,1+(i+1)%n)for i in range(n)]
    f +=[(1+j*n+i,1+j*n+(i+1)%n,1+(j+1)*n+(i+1)%n,1+(j+1)*n+i)for j in range(19)for i in range(n)]
    k.mesh(v,f,'water');add('m12_vortex_surface','M12 中央缓涡水面',k,'water')
    k=IslandKit(230);k.lowwall();add('m13_lowwall_256','M13 外边界矮墙',k,collision=[box((0,0,52),(256,90,104))])
    k=IslandKit(231);k.post();add('m13_short_post','M13 边界短柱',k,collision=[box((0,0,89),(105,105,178))])
    k=IslandKit(240);k.standard_post();add('m14_banner_post','M14 独立旗杆',k,'feature')
    for col in ['teal','blue_cloth','ochre_cloth','rose_cloth']:
        k=IslandKit(241);k.banner(col);add('m14_flag_'+col,'M14 玩家旗帜 '+col,k,'feature')
    for i,size in enumerate([(310,250,360),(200,170,230),(115,100,140)]):
        k=IslandKit(250+i);k.rock((0,0,size[2]*.46),size);add('m15_rock_'+str(i+1),'M15 岩石 '+str(i+1),k,'nature')
    for i in range(2):
        k=IslandKit(260+i);k.cherry(i);add('m16_cherry_'+str(i+1),'M16 疏朗樱树 '+str(i+1),k,'nature')
    for name,method in [('grass',lambda k:k.grass(True)),('fern',lambda k:k.fern()),('shrub',lambda k:k.shrub()),('flowers',lambda k:k.shrub(True)),('moss',lambda k:k.moss_patch())]:
        k=IslandKit(270+len(jobs));method(k);add('m17_'+name,'M17 边缘地被 '+name,k,'nature')
    return jobs
