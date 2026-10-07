"""Stone, teal slate and brass village geometry from the approved 20260926 concept."""
import math
from mathutils import Vector, Matrix
from reference_building_geometry import Kit, PALETTE
PALETTE.update(stone=(.34,.37,.36),limestone=(.52,.52,.46),ivory=(.65,.61,.49),basalt=(.13,.17,.18),wood=(.17,.09,.04),wood_light=(.32,.20,.09),slate=(.045,.17,.21),teal=(.075,.25,.28),brass=(.47,.30,.10),gold=(.78,.53,.19),blue=(.13,.43,.49),green=(.17,.25,.11),leaf=(.28,.36,.16),window=(1,.49,.12))
PALETTE.update(wood_bark=(.34,.15,.055),wood_cut=(.55,.32,.12),
    bronze=(.34,.28,.13),azure=(.07,.25,.43),jade=(.06,.31,.18),jade_light=(.24,.60,.33),
    copper=(.40,.115,.055),copper_light=(.70,.29,.12),amethyst=(.22,.08,.34),
    amethyst_light=(.56,.24,.73),platinum=(.64,.68,.66),radiant_crystal=(.38,.78,.64))
# Gold-bearing rock has its own palette; village stone and timber keep their colors.
PALETTE.update(ore_gold=(.64,.40,.065),ore_gold_light=(.80,.57,.16))
TAU=math.tau
class ConceptKit(Kit):
    def cornice(self,x,y,z,w,d):
        self.box((x,y,z),(w+3,d+3,2.5),'limestone',.55)
        self.box((x,y,z+1.8),(w+4,d+4,1.1),'brass',.2)
    def buttress(self,x,y,h):
        for z,w in [(h*.22,7),(h*.55,5.4),(h*.83,4.2)]:
            self.box((x,y,z),(w,w,h*.33),'limestone',.5)
            self.box((x,y,z+h*.165),(w+1.7,w+1.7,1.7),'ivory',.3)
    def spire(self,x,y,z,r,h):
        self.hip((x,y,z),r,h,n=8)
        for i in range(8):
            a=i*TAU/8
            self.beam((x+r*math.cos(a),y+r*math.sin(a),z+1),(x+r*.18*math.cos(a),y+r*.18*math.sin(a),z+h+1),.65,'brass')
        self.cone((x,y,z+h+6),1.3,0,12,'gold',8)
    def keep_tower(self,x,y,h,r=9,roof=True):
        self.wall((x,y,1),r*2,r*2,h)
        self.cornice(x,y,h,r*2,r*2)
        self.window(x,y-r-1,h*.62,4,11)
        for xx in [-1,1]:
            for yy in [-1,1]:self.buttress(x+xx*r,y+yy*r,h*.9)
        if roof:self.spire(x,y,h+3,r*1.6,h*.46)
        else:
            for xx,yy in [(-1,-1),(-1,1),(1,-1),(1,1)]:self.box((x+xx*r,y+yy*r,h+6),(5,5,7),'limestone')
    def brazier(self,x,y,z=0):
        self.box((x,y,z+2),(10,10,4),'basalt',.8)
        self.cone((x,y,z+7),3.2,2.4,9,'limestone',8)
        self.cone((x,y,z+12),3,5,3,'brass',12)
        self.cone((x,y,z+13.8),4.4,4.4,.7,'shadow',12)
        self.crystal((x,y,z+14),2,7,'window')
    def dome(self,x,y,z,r,h):
        # Closed segmented hemisphere with actual curved ribs, not a painted roof.
        rows=8;segments=24
        def pt(a,t):return (x+r*math.cos(t)*math.cos(a),y+r*math.cos(t)*math.sin(a),z+h*math.sin(t))
        for row in range(rows):
            t0=row*math.pi/2/rows;t1=(row+1)*math.pi/2/rows
            for i in range(segments):
                a=i*TAU/segments;b=(i+1)*TAU/segments
                self.mesh([pt(a,t0),pt(b,t0),pt(b,t1),pt(a,t1)],[(0,1,2,3)],'teal' if i%5==0 else 'slate')
        self.ring((x,y,z),r,1.1,'brass',n=48)
        for i in range(12):
            a=i*TAU/12
            for j in range(rows):self.beam(pt(a,j*math.pi/2/rows),pt(a,(j+1)*math.pi/2/rows),.75,'gold')
        self.cone((x,y,z+h+3),3,2.5,6,'limestone',8)
        for i in range(6):
            a=i*TAU/6;self.beam((x+3*math.cos(a),y+3*math.sin(a),z+h+4),(x+3*math.cos(a),y+3*math.sin(a),z+h+12),.65,'brass')
        self.cone((x,y,z+h+13),4.2,0,5,'gold',8)
        self.beam((x,y,z+h+14),(x,y,z+h+22),.7,'gold')
    def city(self,level):
        h=35+level*4
        self.wall((0,4,1),48,42,h)
        self.cornice(0,4,h,48,42);self.roof(0,4,56,51,h+3,23)
        self.door(0,-20,2,17,27);self.steps(0,-39,29,count=5)
        self.keep_tower(0,12,h+30,12,True)
        for x in [-35,35]:
            self.keep_tower(x,-14,h*.77,8,level>=2)
            self.wall((x/2,-14,1),22,7,h*.55)
            self.flag(x,-24,h*.69,8,20)
        if level>=3:
            for x in [-34,34]:self.keep_tower(x,28,h*.87,8,True)
            for x in [-31,31]:self.wall((x,6,1),6,37,h*.49)
        if level>=4:
            for x in [-17,17]:self.keep_tower(x,3,h+10,6,True)
            self.flag(0,-20,h+11,11,26,'sun')
        if level==5:
            for x in [-42,42]:self.buttress(x,-15,h*.8)
            self.dome(0,-8,h+2,10,12)
        for x in [-16,16]:self.window(x,-19,h*.63,5,13);self.brazier(x,-30)
        self.flag(0,8,h+75,8,15)
        self.ground(52,18)
    def farm(self,level):
        self.cottage(-8,9,43,37,28+level*1.4,25)
        self.chimney(-26,18,0,62+level*2)
        self.cottage(27,-1,25,27,20+level,16)
        if level>=3:self.cottage(-30,18,20,24,23,19)
        if level>=4:
            self.roundwall((29,27,1),10,32+level*2,12);self.spire(29,27,33+level*2,13,14)
        for x in [-29,27]:
            self.box((x,-30,2),(25,19,4),'earth',.5)
            for side in [-1,1]:
                self.beam((x-13,-30+side*10,5),(x+13,-30+side*10,5),1.4,'wood_light')
            for i in range(4):
                for j in range(3):
                    xx=x-9+i*6;yy=-36+j*6
                    if level>=2 and x>0:
                        self.beam((xx,yy,4),(xx,yy,10),.4,'wheat');self.rock((xx,yy,10),(1.5,1.5,4),'wheat')
                    else:self.foliage(xx,yy,4,2.4)
        for x in [-47,47]:
            for y in [-41,-20,1]:self.box((x,y,7),(2.5,2.5,14),'wood_light',.2)
            for z in [5,10]:self.beam((x,-41,z),(x,2,z),1.3,'wood')
        for x,y in [(-12,-22),(12,-18),(38,15)]:self.barrel(x,y)
        self.flag(-7,-14,34,7,14);self.ground(53,14)
    def mine(self,level):
        ore_start=len(self.m)
        self.mountain(-20,15,53+level*2.4,22,23)
        self.mountain(21,20,44+level*2.8,22,25)
        self.mountain(0,33,61+level*1.5,20,17)
        ore_colors={'stone':'ore_gold','limestone':'ore_gold_light'}
        for face in range(ore_start,len(self.m)):
            key=self.keys[self.m[face]]
            if key in ore_colors:self.m[face]=self.keys.index(ore_colors[key])
        self.portal(0,-20,0,22,27,stone=level>=7);self.tracks(0,-23,0,29);self.cart(0,-41)
        self.platform(-30,-4,31+level,21,23);self.winch(-30,-4,32+level,20)
        self.beam((-29,-4,51+level),(-1,-4,46+level),2.5,'wood_light')
        self.beam((-2,-4,46+level),(-2,-4,18),.6,'wheat')
        for j in range(8):self.beam((-38,-19,j*4),(-30,-19,j*4),.65,'wood_light')
        for x in [-39,-29]:self.beam((x,-19,0),(x,-19,34),1.1,'wood')
        if level>=4:self.platform(25,5,35,20,20);self.portal(25,11,36,12,18,level>=8)
        if level>=6:self.platform(0,19,66,23,16);self.winch(0,20,67,15)
        if level>=9:self.flag(-29,-16,42,8,20,'sun');self.flag(27,-9,64,7,20,'sun')
        for x,y in [(-19,-28),(27,-28),(35,-11)]:self.rock((x,y,5),(9,8,7),'gold');self.barrel(x-5,y+5)
        self.ground(53,18)
    def laboratory(self,advanced=False):
        r=26 if advanced else 23;h=48 if advanced else 36
        self.roundwall((0,9,1),r,h,24)
        self.ring((0,9,h),r+1,1.2,'brass',n=48)
        self.dome(0,9,h+2,r+3,25 if advanced else 22)
        self.cottage(0,-20,27,27,25,22)
        self.door(0,-35,2,12,21);self.steps(0,-47,22,count=4)
        for x in [-21,21]:
            self.window(x,-10,h*.52,4,17)
            self.buttress(x,-6,h*.88)
        if advanced:
            for x in [-34,34]:
                self.roundwall((x,4,0),11,34,12);self.dome(x,4,36,13,16)
                self.window(x,-8,21,5,14)
                self.flag(x,-10,32,6,17,'sun')
            for x in [-38,38]:self.keep_tower(x,27,46,5,True)
        else:
            self.keep_tower(-34,6,33,7,False)
            center=(-34,6,51)
            for axis in [(0,0,1),(.5,-.8,.4),(-.5,-.8,.4)]:
                self.ring(center,9,.65,'brass',Vector(axis).to_track_quat('Z','Y').to_matrix(),n=32)
            self.rock(center,(4,4,4),'gold')
            self.cottage(32,12,18,27,22,17)
        for x in [-15,15]:self.lantern(x,-32,18)
        self.ground(54,18)
    def dais(self,r=40):
        for z,rr in [(2,r+4),(5,r+2),(8,r)]:self.cone((0,0,z),rr,rr,3,'stone',32)
        for rr in [r-1,r-6,r*.55]:self.ring((0,0,10),rr,.55,'brass',n=64)
        for i in range(24):
            a=i*TAU/24;self.beam(((r-6)*math.cos(a),(r-6)*math.sin(a),10),(r*math.cos(a),r*math.sin(a),10),.35,'basalt')
        for i in range(8):
            a=i*TAU/8;b=(i+3)*TAU/8
            self.beam((16*math.cos(a),16*math.sin(a),10),(16*math.cos(b),16*math.sin(b),10),.6,'limestone')
        self.steps(0,-54,36,0,8)
    def statue(self,x,y,h=45):
        self.box((x,y,13),(15,14,7),'basalt',1)
        self.box((x,y,17),(16,15,2),'limestone',.4)
        # Cloaked sentinel, faceted head, two arms and an upright sword.
        self.cone((x,y,29),6.8,3.8,23,'stone',8)
        self.rock((x,y,43),(10,8,13),'limestone')
        self.cone((x,y+1,48),5,1,7,'stone',8)
        self.beam((x-4,y,37),(x-8,y-3,30),2.4,'limestone')
        self.beam((x+4,y,37),(x+7,y-4,31),2.4,'limestone')
        self.beam((x+7,y-4,20),(x+7,y-4,53),1.5,'ivory')
        self.beam((x+3,y-4,34),(x+11,y-4,34),1,'brass')
        self.box((x,y+4,31),(11,2.5,24),'stone',.6)
    def altar(self):
        self.dais(39)
        for x,y in [(-28,16),(28,16),(0,32)]:self.statue(x,y)
        for x in [-39,39]:
            self.beam((x,10,0),(x,10,70),1.2,'brass');self.flag(x,9,65,9,31,'sun')
        for x,y in [(-25,-24),(25,-24),(-29,29),(29,29)]:self.brazier(x,y,10)
        self.ground(50,14)
    def challenge(self):
        self.dais(42)
        for i in range(9):
            a=i*math.pi/8;x=43*math.cos(a);y=43*math.sin(a)
            self.wall((x,y,10),9,9,15+i%3*3)
            self.box((x,y,27+i%3*3),(11,11,2),'limestone',.6)
        for x in [-36,36]:
            for y,h in [(3,48),(27,54)]:self.wall((x,y,9),9,9,h)
            self.wall((x,15,59),11,33,8)
            self.ivy(x-5,1,10,42)
        for x in [-28,28]:self.brazier(x,-25,10)
        self.wall((0,42,9),15,10,33);self.box((0,35,29),(7,2,15),'brass')
        self.ground(54,15)
    def archive_challenge(self,variant):
        # Three permanent archive hubs: common masonry, unmistakable silhouettes.
        self.dais(41)
        accent={1:'amethyst_light',2:'blue',3:'gold'}[variant]
        for x in [-28,28]:
            self.box((x,-24,13),(10,10,6),'basalt',.8)
            self.cone((x,-24,20),3.8,3.3,10,'brass',8)
            self.crystal((x,-24,28),3.6,9,accent)
        for x in [-1,1]:
            for y in [8,29]:
                self.box((x*35,y,14),(12,12,8),'basalt',.8)
        if variant==1:
            # Open ceremonial arch, with a small inset crystal rather than a bright screen.
            for x in [-29,29]:
                self.wall((x,12,12),12,15,37)
                self.cornice(x,12,48,12,15)
                self.box((x,3.8,34),(2.4,1,24),'brass',.2)
            for i in range(12):
                a=i*math.pi/12;b=(i+1)*math.pi/12
                self.beam((29*math.cos(a),12,49+29*math.sin(a)),
                    (29*math.cos(b),12,49+29*math.sin(b)),9,'limestone')
                self.beam((24*math.cos(a),6,49+24*math.sin(a)),
                    (24*math.cos(b),6,49+24*math.sin(b)),1.5,'brass')
            self.box((0,7,77),(11,11,13),'slate',1)
            self.crystal((0,1,78),3.5,9,accent)
            self.cone((0,12,19),13,10,16,'basalt',8)
            self.ring((0,12,27),10,1.4,'brass',n=24)
            self.crystal((0,12,41),8,28,'amethyst')
            for x in [-40,40]:self.flag(x,18,51,7,20,'sun')
        elif variant==2:
            # Three carved obelisks frame an open summoning basin.
            for x,y,h in [(-28,8,57),(28,8,57),(0,33,73)]:
                self.box((x,y,16),(17,17,10),'basalt',1)
                self.cone((x,y,18+h*.5),7,4,h,'stone',6)
                self.cone((x,y,22+h),7,3,6,'slate',6)
                self.crystal((x,y,31+h),4.5,16,accent)
                self.beam((x,y-6,25),(x,y-4,12+h),1.4,'brass')
            self.cone((0,-2,17),17,18,12,'basalt',12)
            self.cone((0,-2,24),18,14,4,'brass',12)
            self.cone((0,-2,26),13,13,1.5,'teal',12)
            for a in [0,TAU/3,TAU*2/3]:
                self.beam((15*math.cos(a),-2+15*math.sin(a),26),
                    (24*math.cos(a),-2+24*math.sin(a),36),2,'brass')
        else:
            # Roofed archive shrine with an enclosed rear wall and broad entrance.
            self.wall((0,29,12),60,10,42)
            for x in [-28,28]:
                self.wall((x,9,12),10,35,40)
                self.cornice(x,9,53,10,35)
                self.box((x,-10,34),(3,2,28),'brass',.3)
            self.box((0,10,55),(70,53,5),'limestone',.8)
            self.spire(0,10,58,44,29)
            self.box((0,21,33),(21,4,22),'slate',.5)
            self.ring((0,17,34),8,1.6,'gold',rotation=Matrix.Rotation(math.pi/2,3,'X'))
            self.cone((0,2,16),13,11,11,'basalt',8)
            self.cone((0,2,24),9,9,4,'brass',8)
            self.cone((0,2,34),3,9,13,'gold',10)
            for x in [-8,8]:
                self.beam((x,2,35),(x*1.5,2,42),1.7,'brass')
        self.ground(49,10)

    def stone_defensive_wall(self,level):
        h=24+level*1.8;r=45
        # A square perimeter follows the existing square build footprint in every yaw.
        for side in [-1,1]:
            self.wall((0,side*r,0),r*2,9,h)
            self.wall((side*r,0,0),9,r*2,h)
            for q in range(-3,4):
                self.box((q*12,side*r,h+4),(6.5,10,8),'limestone',.6)
                self.box((side*r,q*12,h+4),(10,6.5,8),'limestone',.6)
            if level>=4:
                self.box((0,side*(r+4.7),h-4),(r*2,1,1.5),'brass',.2)
                self.box((side*(r+4.7),0,h-4),(1,r*2,1.5),'brass',.2)
            for q in [-26,26]:
                self.buttress(q,side*(r+3),h*.9);self.buttress(side*(r+3),q,h*.9)
        for x in [-r,r]:
            for y in [-r,r]:
                self.wall((x,y,0),15,15,h+9)
                self.cornice(x,y,h+9,15,15)
                for xx in [-5,5]:
                    for yy in [-5,5]:self.box((x+xx,y+yy,h+14),(5,5,7),'limestone')
                if level>=3:self.brazier(x,y,h+10)
        self.flag(0,-r-5,h-1,12,21,'sun')
        if level>=6:
            for x in [-r,r]:self.flag(x,-r-9,h+5,7,22,'sun')
        if level>=8:
            for x in [-r,r]:self.spire(x,r,h+15,9,13+level)
        # Paving grounds the enclosure and avoids an apparent floating hollow shell.
        for x in range(-32,33,16):
            for y in range(-32,33,16):self.box((x,y,1),(15.5,15.5,2),'stone',.3)
        for x,y in [(-52,-27),(52,31),(-29,52),(23,-53)]:self.foliage(x,y,0,3)
        self.ivy(-24,-r-5,1,22)

    def defensive_wall(self, level):
        # Material progression follows the ten named wall stages, three gameplay
        # levels per model. The established square footprint/collision stays intact.
        if level <= 2:
            radius=45; floor_height=0 if level==1 else 9
            for x in range(-32,33,16):
                for y in range(-32,33,16):self.box((x,y,.5),(15.5,15.5,1),'earth',.2)
            for side in [-1,1]:
                if level==2:
                    self.wall((0,side*radius,0),90,10,10)
                    self.wall((side*radius,0,0),10,90,10)
                for q in range(-39,40,6):
                    for x,y in [(q,side*radius),(side*radius,q)]:
                        height=31+self.rng.uniform(-2,2)
                        self.cone((x,y,floor_height+height/2),3.0,2.8,height,'wood_bark',10)
                        self.cone((x,y,floor_height+height+2.8),2.8,.4,5.6,'wood_cut',10)
                        # Broad bark seams and lighter freshly cut tips remain
                        # legible from the actual strategy camera distance.
                        for k in range(3):
                            a=(k/3)*TAU
                            self.beam((x+3*math.cos(a),y+3*math.sin(a),floor_height+3),
                                (x+2.85*math.cos(a),y+2.85*math.sin(a),floor_height+height-2),.24,'wood')
                for z in [floor_height+8,floor_height+22]:
                    self.beam((-42,side*(radius-3.5),z),(42,side*(radius-3.5),z),2.1,'wood_cut')
                    self.beam((side*(radius-3.5),-42,z),(side*(radius-3.5),42,z),2.1,'wood_cut')
                for q in [-27,0,27]:
                    self.beam((q-10,side*(radius+3),floor_height+4),(q+10,side*(radius+3),floor_height+25),1.25,'wood_light')
                    self.beam((side*(radius+3),q-10,floor_height+4),(side*(radius+3),q+10,floor_height+25),1.25,'wood_light')
            for x in [-45,45]:
                for y in [-45,45]:
                    self.cone((x,y,floor_height+20),4.3,4,40,'wood_bark',12)
                    self.cone((x,y,floor_height+41),4,4,2,'wood_cut',12)
                    for z in [floor_height+9,floor_height+28]:self.ring((x,y,z),4.4,.7,'basalt',n=12)
            return
        self.stone_defensive_wall(level)
        if level==3:return # Existing dressed-stone silhouette already matches.
        bodies={4:'bronze',5:'azure',6:'jade',7:'copper',8:'amethyst',9:'platinum',10:'ivory'}
        trims={4:'brass',5:'blue',6:'jade_light',7:'copper_light',8:'amethyst_light',9:'gold',10:'gold'}
        mapping={'stone':bodies[level],'limestone':bodies[level],'ivory':trims[level],
                 'brass':trims[level],'slate':bodies[level],'teal':bodies[level]}
        self.m=[self.keys.index(mapping.get(self.keys[m],self.keys[m])) for m in self.m]
        h=24+level*1.8
        if level in (5,6,8,10):
            gem={5:'blue',6:'jade_light',8:'amethyst_light',10:'radiant_crystal'}[level]
            for x in [-45,45]:
                for y in [-45,45]:
                    self.cone((x,y,h+16),7,5,4,trims[level],12)
                    self.crystal((x,y,h+22),4.5,13 if level<10 else 23,gem)
                    if level==10:
                        for a in [0,math.pi/2,math.pi,3*math.pi/2]:
                            self.crystal((x+8*math.cos(a),y+8*math.sin(a),h+19),2.4,12,gem)
        if level in (4,7,9):
            for side in [-1,1]:
                for q in [-24,0,24]:
                    self.box((q,side*50,h*.6),(10,2,13),trims[level],.6)
                    self.box((side*50,q,h*.6),(2,10,13),trims[level],.6)
