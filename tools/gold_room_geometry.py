"""Original modular stone courtyard kit, Source units, Z up, fronts toward -Y."""
import math
from mathutils import Vector, Matrix
from reference_building_geometry import Kit

PALETTE={
    'stone':(.66,.65,.59),'stone_light':(.72,.70,.63),'stone_cool':(.62,.64,.61),
    'mortar':(.39,.395,.33),'rock':(.61,.625,.55),'bronze':(.62,.48,.25),
    'gold':(.86,.68,.32),'teal':(.22,.40,.385),'wood':(.34,.24,.12),
    'earth':(.36,.29,.18),'moss':(.28,.34,.12),'leaf':(.27,.41,.16),
    'leaf_light':(.43,.51,.19),'leaf_dark':(.16,.29,.16),'flower':(.85,.79,.58),
}

class GoldKit(Kit):
    def __init__(self,seed=1):
        super().__init__(seed);self.keys=list(PALETTE)
    def beam(self,a,b,w=2,mat='wood',round=False,top=None):
        # Subpixel stems / coin reeds gain no visible benefit from 32-vertex
        # bevelled boxes. Keep those thin pieces to twelve triangles.
        if w<=3 and not round:
            a,b=Vector(a),Vector(b);delta=b-a
            self.box((a+b)/2,(w,w,delta.length),mat,0,delta.to_track_quat('Z','Y').to_matrix())
        else:super().beam(a,b,w,mat,round,top)
    def stone(self,c,s,light=False):
        key=self.rng.choice(['stone','stone','stone_light','stone_cool']) if not light else 'stone_light'
        self.box(c,s,key,3.2)
    def rock(self,c,s,mat='rock',seed=None):
        n=7;v=[]
        for z,r in [(-.5,.85),(-.2,1),(.28,.86),(.5,.62)]:
            for i in range(n):
                a=i*math.tau/n;w=r*self.rng.uniform(.87,1.1)
                v.append((c[0]+math.cos(a)*w*s[0]/2,c[1]+math.sin(a)*w*s[1]/2,c[2]+(z+self.rng.uniform(-.055,.055))*s[2]))
        f=[tuple(reversed(range(n))),tuple(range(3*n,4*n))]
        for row in range(3):
            for i in range(n):
                a=row*n+i;b=row*n+(i+1)%n;d=(row+1)*n+i;e=(row+1)*n+(i+1)%n
                f.extend([(a,b,e),(a,e,d)])
        start=len(self.m);self.mesh(v,f,mat)
        if mat=='rock':
            for i in range(start,len(self.m)):
                if self.rng.random()<.22:self.m[i]=self.keys.index(self.rng.choice(['stone','stone_cool']))
    def sector(self,inner,outer,a0,a1,z,h,mat='stone',steps=3):
        n=steps+1
        v=[(r*math.cos(a0+(a1-a0)*i/steps),r*math.sin(a0+(a1-a0)*i/steps),zz)
           for zz in (z,z+h) for r in (inner,outer) for i in range(n)]
        f=[]
        for i in range(steps):
            f.extend([(i,i+1,n+i+1,n+i),(2*n+i,3*n+i,3*n+i+1,2*n+i+1),
                      (i,2*n+i,2*n+i+1,i+1),(n+i,n+i+1,3*n+i+1,3*n+i)])
        f += [(0,n,3*n,2*n),(n-1,3*n-1,4*n-1,2*n-1)]
        self.mesh(v,f,mat)
    def lathe(self,c,profile,mat='bronze',n=32):
        v=[(c[0]+r*math.cos(i*math.tau/n),c[1]+r*math.sin(i*math.tau/n),c[2]+z)
           for r,z in profile for i in range(n)]
        f=[tuple(reversed(range(n))),tuple(range((len(profile)-1)*n,len(profile)*n))]
        for row in range(len(profile)-1):
            f.extend((row*n+i,row*n+(i+1)%n,(row+1)*n+(i+1)%n,(row+1)*n+i)for i in range(n))
        self.mesh(v,f,mat)
    def polygon(self,points,z,thickness,mat):
        n=len(points);v=[(x,y,zz)for zz in (z,z+thickness)for x,y in points]
        self.mesh(v,[tuple(reversed(range(n))),tuple(range(n,2*n))]+
                  [(i,(i+1)%n,(i+1)%n+n,i+n)for i in range(n)],mat)
    def transform_since(self,start,angle=0,offset=(0,0,0)):
        rot=Matrix.Rotation(angle,3,'Z');off=Vector(offset)
        self.v[start:]=[tuple(rot@Vector(p)+off) for p in self.v[start:]]
    def wall(self,length=256):
        self.box((0,0,77),(length,42,154),'mortar',.4)
        for row in range(3):
            offset=32 if row%2 else 0
            edges=sorted(set([-length/2,length/2]+[x+offset for x in range(-256,320,64) if -length/2<x+offset<length/2]))
            # Unequal joint widths and stone tones, with straight module ends.
            for a,b in zip(edges,edges[1:]):
                self.stone(((a+b)/2,0,39+row*46.5),(b-a-1.2,46,45))
        for i in range(round(length/64)):
            x=-length/2+(i+.5)*64
            self.stone((x,0,8),(63,52,16))
            self.stone((x,0,166),(63.4,56,20),True)
        for i in range(max(2,round(length/25))):
            x=self.rng.uniform(-length/2+4,length/2-4);side=self.rng.choice([-1,1])
            self.rock((x,side*24,5),(self.rng.uniform(5,12),3,self.rng.uniform(5,15)),'moss')
    def paving(self,broken=False,seed=1):
        self.box((0,0,-9),(256,256,12),'mortar',0)
        for row in range(2):
            for col in range(2):
                x=-64+col*128;y=-64+row*128
                if broken and (col,row)==(1,1):
                    # Sunken chips stay below the walking plane.
                    for side in (-1,1):
                        self.polygon([(x-62,y+side*1),(x+61,y+side*3),(x+62,y+side*62),(x-61,y+side*62)],-12,11.6,'stone')
                    self.beam((x-57,y,-.1),(x+54,y+2,-.1),1.6,'mortar')
                else:self.stone((x,y,-7),(125.8,125.8,14))
        for i in range(8 if broken else 3):
            x=self.rng.choice([-127,0,127]);y=self.rng.uniform(-117,117)
            self.box((x,y,-.35),(2.2,self.rng.uniform(5,14),.3),'moss',0)
    def pillar(self,badge=False):
        self.stone((0,0,10),(84,84,20),True)
        self.box((0,0,99),(65,65,166),'mortar',2)
        for row in range(4):self.stone((0,0,40+row*40),(69,69,39))
        self.stone((0,0,193),(84,84,23),True)
        self.stone((0,0,216),(52,52,24),True)
        if badge:
            self.box((0,-36,109),(40,5,123),'bronze',2)
            self.box((0,-40,109),(31,3,112),'teal',1)
            for z in (85,133):
                rot=Matrix.Rotation(math.pi/2,3,'X')
                self.cone((0,-45,z),14,14,4,'gold',24,rot)
                self.ring((0,-48,z),10,1,'bronze',rot,n=24)
    def curved_wall(self):
        for row in range(3):
            for i in range(5):
                a=math.radians(60+i*12+.18);b=math.radians(72+i*12-.18)
                self.sector(234,278,a,b,17+row*44,42,self.rng.choice(['stone','stone_light','stone_cool']))
        for z,h,ri,ro in ((0,16,230,282),(150,23,228,284)):
            for i in range(5):self.sector(ri,ro,math.radians(60+i*12+.12),math.radians(72+i*12-.12),z,h,'stone_light' if z else 'stone')
    def crest(self,r=260,z=.4,teal=False):
        for radius,t in ((r,4),(r-15,1.7),(r-36,1.7)):
            self.ring((0,0,z),radius,t,'bronze' if teal else 'gold',n=96)
        pts=[]
        for i in range(8):
            a=math.pi/2+i*math.tau/8;rr=r*.77 if i%2==0 else r*.25
            pts.append((rr*math.cos(a),rr*math.sin(a)))
        for a,b in zip(pts,pts[1:]+pts[:1]):self.beam((*a,z+1),(*b,z+1),6.5,'gold')
        inner=[(0,r*.3),(r*.20,0),(0,-r*.3),(-r*.2,0)]
        self.polygon(inner,z+.4,.6,'teal' if teal else 'gold')
        for a,b in zip(inner,inner[1:]+inner[:1]):self.beam((*a,z+1),(*b,z+1),2,'bronze')
        for i in range(12):
            a=i*math.tau/12
            self.beam((math.cos(a)*(r-31),math.sin(a)*(r-31),z),
                      (math.cos(a)*(r-17),math.sin(a)*(r-17),z),1.6,'gold')
    def portal(self):
        self.cone((0,0,5),184,184,10,'mortar',64)
        self.cone((0,0,11),141,141,8,'teal',64)
        for i in range(20):
            self.sector(143,185,i*math.tau/20+.006,(i+1)*math.tau/20-.006,0,17,
                        'stone_light' if i%3 else 'stone')
        self.crest(132,15,True)
    def coins(self):
        for x,count in ((-24,4),(22,6)):
            for i in range(count):
                z=45+i*10
                self.cone((x,-37,z),22,22,8,'gold',24)
                self.ring((x,-37,z+4),19,1,'bronze',n=24)
                for j in range(12):
                    a=j*math.tau/12;self.beam((x+21*math.cos(a),-37+21*math.sin(a),z-2),
                                            (x+21*math.cos(a),-37+21*math.sin(a),z+2),.7,'bronze')
    def stele(self):
        self.stone((0,0,97),(154,44,194))
        self.box((0,-24,96),(119,5,157),'mortar',5)
        for x in (-68,68):self.stone((x,-29,97),(23,20,183),True)
        for z in (14,179):self.stone((0,-29,z),(153,20,24),True)
    def brazier(self,base=True,bowl=True):
        if base:
            self.stone((0,0,6),(78,78,12),True)
            self.stone((0,0,35),(66,66,48))
            self.stone((0,0,61),(74,74,9),True)
        if bowl:
            self.lathe((0,0,0),[(15,0),(20,5),(24,13),(39,23),(49,39),(49,44),
                                (45,44),(42,36),(32,22),(18,14),(6,14)],'bronze')
            self.ring((0,0,44),47,2.2,'gold',n=40)
            self.ring((0,0,20),33,1.1,'gold',n=40)
    def leaf(self,a,b,width,mat='leaf'):
        a,b=Vector(a),Vector(b);d=b-a
        side=d.cross(Vector((0,0,1))).normalized()*width/2
        mid=a+d*.43;ridge=mid+Vector((0,0,width*.12))
        self.mesh([a,mid-side,b,mid+side,ridge],[(0,1,4),(1,2,4),(2,3,4),(3,0,4)],mat)
    def grass(self,large=False):
        for i in range(36 if large else 18):
            a=self.rng.random()*math.tau;r=self.rng.uniform(0,20 if large else 10)
            p=Vector((r*math.cos(a),r*math.sin(a),0));h=self.rng.uniform(23,63 if large else 38)
            bend=Vector((math.cos(a)*h*.46,math.sin(a)*h*.46,h))
            self.leaf(p,p+bend,self.rng.uniform(3,7),self.rng.choice(['leaf','leaf_light','leaf_dark']))
    def fern(self):
        for j in range(9):
            a=j*math.tau/9;length=self.rng.uniform(48,76);rad=Vector((math.cos(a),math.sin(a),0));side=Vector((-rad.y,rad.x,0))
            points=[rad*(length*t*.85)+Vector((0,0,length*math.sin(t*math.pi*.63)*.65))for t in (0,.2,.4,.6,.8,1)]
            for p,q in zip(points,points[1:]):self.beam(p,q,1.1,'leaf_light')
            for i in range(1,10):
                t=i/11;p=rad*(length*t*.85)+Vector((0,0,length*math.sin(t*math.pi*.63)*.65))
                for s in (-1,1):self.leaf(p,p+side*s*length*.20*(1-t*.75)+rad*length*.08,7*(1-t*.6),'leaf' if j%2 else 'leaf_light')
    def shrub(self,flowers=False):
        for j in range(12):
            a=j*2.399;h=self.rng.uniform(25,64);r=self.rng.uniform(12,48)
            tip=Vector((math.cos(a)*r,math.sin(a)*r,h));self.beam((0,0,0),tip,1.3,'wood')
            for i in range(4):
                p=tip*(.38+i*.16);side=Vector((-math.sin(a),math.cos(a),.30))
                for s in (-1,1):self.leaf(p,p+side*s*15+Vector((math.cos(a)*9,math.sin(a)*9,8)),10,
                                       self.rng.choice(['leaf','leaf_light','leaf_dark']))
            if flowers and j%2==0:
                self.cone(tip,2.2,2.2,2,'gold',7)
                for f in range(5):
                    ang=f*math.tau/5;self.leaf(tip,tip+Vector((math.cos(ang)*8,math.sin(ang)*8,2)),5,'flower')
    def flag(self):
        self.beam((-37,0,152),(37,0,152),4.2,'bronze',True)
        self.beam((0,0,136),(0,18,153),4,'bronze',True)
        for x in (-37,37):self.cone((x,0,152),6,6,5,'gold',12,Matrix.Rotation(math.pi/2,3,'Y'))
        verts=[]
        for row in range(9):
            t=row/8
            for col in range(7):
                u=col/6
                z=145-t*124-(12*abs(u-.5)*2 if row==8 else 0)
                verts.append(((u-.5)*58,-4+math.sin(u*math.tau*1.4+t*2)*2.2,z))
        self.mesh(verts,[(r*7+c,r*7+c+1,(r+1)*7+c+1,(r+1)*7+c)for r in range(8)for c in range(6)],'teal')
        for side in (-1,1):self.beam((side*28,-5,144),(side*28,-5,12),1.6,'gold')
        self.beam((0,-9,70),(0,-9,119),2,'gold')
        for side in (-1,1):
            self.beam((0,-9,85),(side*13,-9,97),2,'gold')
            self.beam((side*13,-9,97),(side*13,-9,105),2,'gold')
        self.polygon([(-3,-3),(0,5),(3,-3),(0,-1)],0,1,'gold')
    def moss_patch(self):
        for i in range(30):
            x=self.rng.gauss(0,21);y=self.rng.gauss(0,32);r=self.rng.uniform(3,11)
            p=[(x+math.cos(a)*r,y+math.sin(a)*r*.65)for a in [j*math.tau/6 for j in range(6)]]
            self.polygon(p,0,.25,self.rng.choice(['moss','moss','leaf_dark']))

def build_modules():
    jobs=[]
    def add(name,label,kit,category,collision=None):jobs.append(dict(name=name,label=label,kit=kit,category=category,collision=collision or []))
    box=lambda c,s:dict(center=c,size=s)
    for variant in range(3):
        k=GoldKit(300+variant);k.paving(variant==2)
        add(['b01_floor_a','b01_floor_b','b02_floor_worn'][variant],['标准石板 A','标准石板 B','破损石板'][variant],k,'floor')
    # Clip the rear paving to the semicircle; no square corners protrude through
    # the curved enclosure into the planted border.
    k=GoldKit(304)
    boundary=[(-254,0),(254,0)]+[(254*math.cos(i*math.pi/24),254*math.sin(i*math.pi/24))for i in range(1,24)]
    def clip(poly,a,b):
        out=[]
        def side(p):return (b[0]-a[0])*(p[1]-a[1])-(b[1]-a[1])*(p[0]-a[0])
        for p,q in zip(poly,poly[1:]+poly[:1]):
            sp,sq=side(p),side(q)
            if sp>=0:out.append(p)
            if (sp>=0)!=(sq>=0):
                t=sp/(sp-sq);out.append((p[0]+t*(q[0]-p[0]),p[1]+t*(q[1]-p[1])))
        return out
    for x in (-256,-128,0,128):
        for y in (0,128):
            poly=[(x+1,y+1),(x+127,y+1),(x+127,y+127),(x+1,y+127)]
            for a,b in zip(boundary,boundary[1:]+boundary[:1]):
                if poly:poly=clip(poly,a,b)
            if len(poly)>2:k.polygon(poly,-14,14,k.rng.choice(['stone','stone_light','stone_cool']))
    add('b01_niche_floor','弧墙内侧半圆石板',k,'floor')
    for length,name in ((256,'b03_wall_256'),(128,'b03_wall_128')):
        k=GoldKit(32+length);k.wall(length);add(name,'直线墙段 '+str(length),k,'wall',[box((0,0,88),(length,48,176))])
    for badge in (False,True):
        k=GoldKit(43);k.pillar(badge);add('b04_pillar'+('_coin' if badge else ''),'金币墙柱' if badge else '独立墙柱',k,'wall',[box((0,0,114),(78,78,228))])
    k=GoldKit(55)
    for a in (0,math.pi/2):
        start=len(k.v);k.wall(128);k.transform_since(start,a,(math.cos(a)*64,math.sin(a)*64,0))
    add('b05_corner','90 度转角墙',k,'wall',[box((64,0,88),(128,48,176)),box((0,64,88),(48,128,176))])
    k=GoldKit(66);k.curved_wall();hulls=[]
    for i in range(5):
        a0=math.radians(60+i*12);a1=a0+math.radians(12)
        hulls.append(dict(vertices=[(r*math.cos(a),r*math.sin(a),z)for z in (0,173) for r,a in [(232,a0),(280,a0),(280,a1),(232,a1)]]))
    add('b06_arc_60','60 度弧形墙段',k,'wall',hulls)
    k=GoldKit(77);k.portal();add('b07_teleport_base','传送石台与金属嵌件（无光）',k,'feature')
    k=GoldKit(88);k.crest(308,.3);add('b08_spawn_inlay','中央刷怪金属地纹（无光）',k,'feature')
    k=GoldKit(99);k.stele();add('b09_coin_stele','金币标识碑框',k,'feature',[box((0,0,98),(152,54,196))])
    k=GoldKit(99);k.coins();add('b09_coin_relief','金币浮雕嵌件',k,'feature')
    k=GoldKit(100);k.brazier(True,False);add('b10_brazier_plinth','青铜灯具石基',k,'feature')
    k=GoldKit(100);k.brazier(False,True);add('b10_bronze_bowl','青铜火盆（无火焰）',k,'feature')
    for i,s in enumerate([(245,200,286),(167,156,152),(90,83,72)]):
        k=GoldKit(110+i);k.rock((0,0,s[2]/2),s,'rock');
        for j in range(6):k.rock((k.rng.uniform(-s[0]*.4,s[0]*.4),-s[1]*.35,k.rng.uniform(3,s[2]*.25)),(20,13,15),'moss')
        add('b11_rock_'+str(i+1),['大岩石','中岩石','小岩石'][i],k,'nature')
    k=GoldKit(120)
    for i in range(15):
        s=k.rng.uniform(8,29);k.rock((k.rng.uniform(-85,85),k.rng.uniform(-54,54),s*.2),(s,s*.85,s*.6),'rock')
    add('b12_rubble','碎石散落组',k,'nature')
    k=GoldKit(121)
    points=[(math.cos(i*math.tau/20)*k.rng.uniform(78,100),math.sin(i*math.tau/20)*k.rng.uniform(54,80))for i in range(20)]
    k.polygon(points,-.3,.5,'earth');add('b12_ground_patch','不规则泥土接地片',k,'nature')
    for large in (False,True):
        k=GoldKit(130+large);k.grass(large);add('b13_grass_'+('large' if large else 'small'),'大草丛' if large else '小草丛',k,'nature')
    k=GoldKit(132);k.fern();add('b13_fern','蕨类',k,'nature')
    for flowers in (False,True):
        k=GoldKit(140+flowers);k.shrub(flowers);add('b14_shrub'+('_flowers' if flowers else ''),'低灌木与小花' if flowers else '低灌木',k,'nature')
    k=GoldKit(160);k.flag();add('b16_banner','青铜支架与青绿挂旗',k,'feature')
    k=GoldKit(161);k.moss_patch();add('b16_moss_patch','独立苔痕薄片',k,'nature')
    k=GoldKit(200);points=[]
    for i in range(48):
        a=i*math.tau/48;ca=math.cos(a);sa=math.sin(a)
        points.append((math.copysign(abs(ca)**.55,ca)*k.rng.uniform(1250,1340),
                       80+math.copysign(abs(sa)**.55,sa)*k.rng.uniform(1450,1540)))
    k.polygon(points,-27,13,'earth');add('room_earth_base','房间外沿土层',k,'terrain')
    return jobs
