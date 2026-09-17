"""Molten Core modular arena. Source units, Z up; no emissive geometry/materials."""
import math
from mathutils import Vector,Matrix
from gold_room_geometry import GoldKit

PALETTE={
 'stone':(.365,.38,.385),'stone_light':(.42,.43,.425),'stone_cool':(.32,.35,.365),
 'stone_edge':(.49,.465,.42),'stone_scorched':(.30,.265,.245),'charred':(.185,.195,.20),
 'rock':(.29,.305,.32),'mortar':(.135,.145,.15),'bronze':(.48,.32,.205),
 'copper':(.70,.46,.29),'iron':(.205,.24,.245),'patina':(.16,.29,.275),
 'teal':(.16,.39,.405),'ash':(.23,.215,.205),'lava':(.57,.22,.09),'earth':(.265,.245,.22),
}

class MoltenKit(GoldKit):
    def __init__(self,seed=1):super().__init__(seed);self.keys=list(PALETTE)
    def stone(self,c,s,light=False,mat=None):
        m=mat or ('stone_light' if light else self.rng.choice(['stone']*6+['stone_light','stone_cool']))
        start=len(self.m);self.box(c,s,m,2.8)
        # A slim pale chipped bevel, not a bright painted face.
        for i in range(start+18,min(start+26,len(self.m))):
            if self.rng.random()<.65:self.m[i]=self.keys.index('stone_edge')
    def rivet(self,x,y,z):
        self.cone((x,y,z),3.6,2.8,2.5,'copper',8,Matrix.Rotation(math.pi/2,3,'X'))
    def paving(self,scorched=False):
        self.box((0,0,-11),(256,256,12),'mortar',0)
        step=256/3
        for row in range(3):
            for col in range(3):
                x=-128+(col+.5)*step;y=-128+(row+.5)*step
                self.stone((x,y,-8),(step-1.8,step-1.8,16),mat='stone_scorched' if scorched and (row==0 or col==2) else None)
        if scorched:
            for i in range(14):
                x=self.rng.uniform(-120,120);y=self.rng.uniform(-126,-92)
                self.rock((x,y,-.7),(self.rng.uniform(3,9),self.rng.uniform(3,8),1),'charred')
    def wall(self,length=256):
        self.box((0,0,86),(length,59,172),'mortar',0)
        for row in range(3):
            cuts=sorted(set([-length/2,length/2]+[x+(32 if row%2 else 0)for x in range(-256,300,64)if -length/2<x+(32 if row%2 else 0)<length/2]))
            for a,b in zip(cuts,cuts[1:]):self.stone(((a+b)/2,0,39+row*46),(b-a-1.2,66,44.5))
        for i in range(round(length/64)):
            x=-length/2+(i+.5)*64
            self.stone((x,0,9),(63,79,18));self.stone((x,0,174),(63.2,80,24),True)
        for side in(-1,1):
            for z in(28,155):self.box((0,side*34,z),(length,5,6),'bronze',1)
            self.box((0,side*34.2,99),(length-3,1.5,12),'iron',.3)
    def pillar(self):
        self.stone((0,0,12),(96,96,24))
        for z in(52,105,158):self.stone((0,0,z),(78,78,52))
        for a in range(4):
            start=len(self.v)
            self.box((0,-42,108),(30,7,160),'bronze',1.5)
            self.box((0,-46,108),(23,2.8,148),'patina',.6)
            for z in(28,186):
                self.box((0,-43,z),(87,9,25),'bronze',2)
                for x in(-32,32):self.rivet(x,-49,z)
            for z in(55,161):self.rivet(0,-48,z)
            self.transform_since(start,a*math.pi/2)
        self.stone((0,0,204),(100,100,20),True)
    def pillar_cap(self):
        self.stone((0,0,12),(66,66,24),True)
        self.box((0,0,1),(73,73,4),'bronze',2)
        self.cone((0,0,29),30,18,15,'stone_light',4,Matrix.Rotation(math.pi/4,3,'Z'))
    def curved_wall(self):
        for row in range(3):
            for i in range(5):self.sector(228,290,math.radians(60+i*12+.12),math.radians(72+i*12-.12),17+row*47,45,self.rng.choice(['stone','stone','stone_cool']))
        for z,h,ri,ro in((0,18,224,294),(161,25,222,296)):
            for i in range(5):self.sector(ri,ro,math.radians(60+i*12+.1),math.radians(72+i*12-.1),z,h,'stone_light')
        for z in(29,155):
            for ri in(226,289):self.sector(ri,ri+3,math.pi/3,math.pi*2/3,z,6,'bronze',16)
    def flat_ring(self,r,width,z,mat='copper'):
        self.sector(r-width/2,r+width/2,0,math.tau,z,.20,mat,96)
    def ribbon(self,points,width=3,z=.25,mat='copper',closed=True):
        for a,b in zip(points,points[1:]+points[:1] if closed else points[1:]):
            d=Vector((b[0]-a[0],b[1]-a[1],0)).normalized();n=Vector((-d.y,d.x,0))*width/2
            p=[(a[0]+n.x,a[1]+n.y),(a[0]-n.x,a[1]-n.y),(b[0]-n.x,b[1]-n.y),(b[0]+n.x,b[1]+n.y)]
            self.polygon(p,z,.2,mat)
    def crest(self,r=300,z=.30,portal=False):
        mat='teal'if portal else'copper'
        for radius,t in((r,5),(r-15,2.7),(r-36,1.8)):self.flat_ring(radius,t,z,mat if portal else'copper')
        pts=[]
        for i in range(16 if not portal else 8):
            a=math.pi/2+i*math.tau/(16 if not portal else 8)
            rr=(.8 if i%4==0 else .61 if i%2==0 else .29)*r if not portal else (.75 if i%2==0 else .23)*r
            pts.append((rr*math.cos(a),rr*math.sin(a)))
        self.ribbon(pts,5.5,z,mat)
        diamond=[(0,r*.40),(r*.21,0),(0,-r*.40),(-r*.21,0)]
        self.ribbon(diamond,3.3,z,mat)
        self.polygon([(0,r*.12),(r*.08,0),(0,-r*.12),(-r*.08,0)],z,.25,mat)
        for i in range(12):
            a=i*math.tau/12;self.ribbon([(math.cos(a)*(r-33),math.sin(a)*(r-33)),(math.cos(a)*(r-17),math.sin(a)*(r-17))],1.5,z,'bronze',False)
    def portal_ring(self):
        for i in range(24):self.sector(146,191,i*math.tau/24+.005,(i+1)*math.tau/24-.005,0,18,'stone_light' if i%5==0 else 'stone')
        self.flat_ring(148,3,17,'bronze');self.flat_ring(188,2,18,'bronze')
        for i in range(8):
            a=i*math.tau/8;start=len(self.v)
            self.box((0,170,20),(16,42,4),'bronze',1)
            for y in(154,184):self.cone((0,y,23),3,2,2,'copper',8)
            self.transform_since(start,a)
    def portal_inlay(self):
        self.cone((0,0,4),145,145,8,'iron',64)
        self.cone((0,0,8.2),137,137,1,'patina',64)
        self.crest(129,8.9,True)
    def trough(self,end=False):
        self.box((0,0,-8),(256,90,12),'charred',0)
        for side in(-1,1):
            for i in range(4):self.stone((-96+i*64,side*40,3),(63,17,30),mat='charred')
            self.box((0,side*49,8),(256,3,3),'bronze',.5)
        if end:self.stone((120,0,3),(16,72,30),mat='charred')
    def lava_surface(self,corner=False):
        p=[(-126,-30),(126,-30),(126,30),(-126,30)]if not corner else[(-80,-29),(29,-29),(29,80),(-29,80),(-29,29),(-80,29)]
        self.polygon(p,-2,.5,'lava')
    def trough_corner(self):
        self.polygon([(-80,-49),(49,-49),(49,80),(-49,80),(-49,49),(-80,49)],-14,12,'charred')
        for c,s in[((-16,-40,3),(128,17,30)),((40,16,3),(17,128,30)),((-64,40,3),(32,17,30)),((-40,64,3),(17,32,30))]:self.stone(c,s,mat='charred')
    def bracket(self):
        self.box((0,0,14),(93,90,28),'stone',3)
        self.box((0,-35,-18),(47,37,66),'iron',2)
        self.box((0,-57,-14),(51,8,58),'bronze',2)
        for x in(-17,17):
            for z in(-32,5):self.rivet(x,-63,z)
        self.box((0,0,33),(77,77,10),'bronze',2)
    def brazier(self):
        self.lathe((0,0,0),[(22,0),(30,7),(27,11),(35,20),(52,33),(61,48),(61,55),(56,55),(53,46),(44,32),(25,19),(3,19)],'iron',32)
        for z,r,w in((7,29,2),(34,51,1.5),(55,59,2.2)):self.ring((0,0,z),r,w,'copper',n=40)
        for i in range(5):self.rock((self.rng.uniform(-20,20),self.rng.uniform(-20,20),23),(20,18,12),'charred')
    def stele(self):
        self.stone((0,0,97),(158,46,194))
        self.box((0,-25,98),(124,5,157),'iron',3)
        self.box((0,-28,98),(114,2,149),'patina',2)
        for x in(-70,70):self.box((x,-31,98),(15,9,180),'bronze',1)
        for z in(13,183):self.box((0,-31,z),(149,9,15),'bronze',1)
        for x in(-64,64):
            for z in(19,176):
                self.box((x,-36,z),(26,8,26),'bronze',2);self.rivet(x,-42,z)
    def flame_emblem(self):
        # Flat copper flame silhouette with a recessed central cutout, not fire.
        pts=[(0,72),(-16,40),(-14,18),(-35,40),(-44,5),(-39,-19),(-24,-40),(-9,-46),(-12,-58),(0,-68),(12,-58),(9,-46),(29,-32),(42,-9),(38,14),(23,38),(21,13),(9,27)]
        start=len(self.v);self.polygon(pts,0,2.3,'copper')
        inner=[(0,20),(-7,7),(-6,-3),(-13,6),(-19,-11),(-12,-27),(0,-34),(14,-24),(19,-10),(10,7),(6,-3)]
        self.polygon(inner,2.35,.4,'iron')
        rot=Matrix.Rotation(math.pi/2,3,'X');self.v[start:]=[tuple(rot@Vector(v)+Vector((0,-33,100)))for v in self.v[start:]]
    def ash_patch(self):
        for i in range(25):
            x=self.rng.gauss(0,31);y=self.rng.gauss(0,22);r=self.rng.uniform(7,22)
            p=[(x+math.cos(a)*r,y+math.sin(a)*r*.7)for a in[j*math.tau/7 for j in range(7)]]
            self.polygon(p,-.5,self.rng.uniform(.2,.5),self.rng.choice(['ash','charred','earth']))

def build_modules():
    jobs=[]
    def add(n,label,k,category='feature',hulls=None):jobs.append(dict(name=n,label=label,kit=k,category=category,collision=hulls or []))
    box=lambda c,s:dict(center=c,size=s)
    for i,n in enumerate(('f01_floor_a','f01_floor_b','f02_floor_scorched')):
        k=MoltenKit(700+i);k.paving(i==2);add(n,['F01 标准玄武岩石板 A','F01 标准玄武岩石板 B','F02 焦痕石板'][i],k,'floor')
    # Reuse only the proven clipped footprint, rebuilding it in this material family.
    from gold_room_geometry import build_modules as gold_modules
    g=next(j['kit']for j in gold_modules()if j['name']=='b01_niche_floor')
    k=MoltenKit(704);k.v=g.v;k.f=g.f;k.m=[k.keys.index(g.keys[m])for m in g.m];add('f01_niche_floor','F01 传送龛半圆铺地',k,'floor')
    for length in(256,128):
        k=MoltenKit(710+length);k.wall(length);add('f03_wall_'+str(length),'F03 直线墙段 '+str(length),k,'wall',[box((0,0,93),(length,70,186))])
    k=MoltenKit(720);k.pillar();add('f04_pillar_body','F04 包铜墙柱',k,'wall',[box((0,0,107),(94,94,214))])
    k=MoltenKit(721);k.pillar_cap();add('f04_pillar_cap','F04 可拆柱顶',k,'wall')
    k=MoltenKit(730)
    for a in(0,math.pi/2):
        start=len(k.v);k.wall(128);k.transform_since(start,a,(64*math.cos(a),64*math.sin(a),0))
    add('f05_corner','F05 直角墙段',k,'wall',[box((64,0,93),(128,70,186)),box((0,64,93),(70,128,186))])
    k=MoltenKit(740);k.curved_wall();h=[]
    for i in range(5):
        a=math.radians(60+i*12);b=a+math.radians(12);h.append(dict(vertices=[(r*math.cos(t),r*math.sin(t),z)for z in(0,186)for r,t in[(226,a),(292,a),(292,b),(226,b)]]))
    add('f06_arc_60','F06 弧形背墙 · 60 度',k,'wall',h)
    k=MoltenKit(750);k.portal_ring();add('f07_portal_ring','F07 传送底座石环',k)
    k=MoltenKit(751);k.portal_inlay();add('f07_portal_inlay','F07 铜质青色嵌片 · 无光',k)
    k=MoltenKit(760);k.crest(320);add('f08_spawn_inlay','F08 中央平铺铜纹 · 无光',k)
    for end in(False,True):
        k=MoltenKit(770);k.trough(end);add('f09_trough_'+('end'if end else'straight'),'F09 熔岩槽'+('封闭端头'if end else'直线外壳'),k,'exterior')
    k=MoltenKit(772);k.trough_corner();add('f09_trough_corner','F09 熔岩槽直角外壳',k,'exterior')
    for corner in(False,True):
        k=MoltenKit(774);k.lava_surface(corner);add('f09_lava_'+('corner'if corner else'straight'),'F09 独立熔岩表面 · 无光'+('转角'if corner else''),k,'exterior')
    k=MoltenKit(780);k.bracket();add('f10_brazier_bracket','F10 炉火灯具支架',k)
    k=MoltenKit(781);k.brazier();add('f10_brazier_bowl','F10 暗铁铜边火盆 · 无火焰',k)
    k=MoltenKit(790);k.stele();add('f11_fire_stele','F11 火焰标识碑主体',k,'feature',[box((0,0,97),(158,46,194))])
    k=MoltenKit(791);k.flame_emblem();add('f11_flame_emblem','F11 独立铜质火焰徽记',k)
    for i,s in enumerate([(270,220,320),(175,150,180),(90,85,94),(210,180,75)]):
        k=MoltenKit(800+i);k.rock((0,0,s[2]/2),s,'rock');add('f12_rock_'+str(i+1),['F12 大火山岩','F12 中火山岩','F12 小火山岩','F12 扁平火山岩'][i],k,'exterior')
    k=MoltenKit(810)
    for i in range(19):
        s=k.rng.uniform(7,30);k.rock((k.rng.uniform(-95,95),k.rng.uniform(-45,45),s*.24),(s,s*.8,s*.6),'charred'if i%4 else'rock')
    add('f14_rubble','F14 火山碎石组',k,'exterior')
    k=MoltenKit(811);k.ash_patch();add('f14_ash_patch','F14 不规则焦灰接地片',k,'exterior')
    k=MoltenKit(820)
    # Small restrained banner; emblem is geometric copper, no emissive decal.
    k.mesh([(-23,0,161),(23,0,161),(23,-2,47),(0,-3,30),(-23,-2,47)],[(0,1,2,3,4),(4,3,2,1,0)],'teal')
    for x in(-23,23):k.beam((x,-3,158),(x,-4,47),1.4,'copper')
    k.beam((-31,0,168),(31,0,168),3,'bronze',True)
    k.beam((0,-6,82),(0,-6,130),1.7,'copper')
    for s in(-1,1):k.beam((0,-6,99),(s*12,-6,112),1.7,'copper')
    add('f16_banner','F16 入口青铜挂旗',k)
    k=MoltenKit(830);points=[]
    for i in range(48):
        a=i*math.tau/48;ca=math.cos(a);sa=math.sin(a)
        points.append((math.copysign(abs(ca)**.55,ca)*k.rng.uniform(1280,1380),65+math.copysign(abs(sa)**.55,sa)*k.rng.uniform(1440,1540)))
    k.polygon(points,-27,12,'earth');add('room_ash_base','房间外围焦灰基底',k,'terrain')
    return jobs
