"""Four-sided reference battlements, authored directly within a 256-unit tile."""
import math
from mathutils import Vector, Matrix
from reference_building_geometry import Kit, PALETTE

from wall_asset_spec import NAMES
PALETTE.update({
    'iron':(.22,.24,.25),'bronze':(.32,.44,.40),'copper':(.65,.31,.12),
    'azure':(.085,.24,.44),'jade':(.10,.37,.32),'purple':(.35,.11,.59),
    'silver':(.65,.70,.74),'crystal':(.16,.85,.77),'ruby':(.35,.085,.055),
    'wall_stone':(.48,.51,.51),'wall_pale':(.72,.72,.65),
    'wall_ivory':(.86,.83,.71),'wall_dark':(.28,.31,.36),
    'wood_end':(.43,.29,.15),
})

class WallKit(Kit):
    def __init__(self,seed=1):
        super().__init__(seed)
        self.surface_parts=[]

    def mesh(self,verts,faces,mat='stone'):
        start_v,start_f=len(self.v),len(self.f)
        super().mesh(verts,faces,mat)
        self.surface_parts.append((start_v,len(self.v),start_f,len(self.f),mat))

    def box(self,c,s,mat='stone',bevel=.35,rotation=None):
        start=len(self.v)
        super().box(c,s,mat,bevel,rotation)
        if mat.startswith('wall_') or mat in ('wood','wood_light'):
            # Consistent coordinate-based edge chipping keeps coincident bevel
            # vertices together, while breaking the machine-cut silhouette.
            self.v[start:]=[(x+.23*math.sin(y*1.3+z*.8),y+.23*math.sin(x*.9+z*1.7),z+.18*math.sin(x*1.8+y*.8)) for x,y,z in self.v[start:]]

    def diamond(self,x,y,z,w,h,mat,depth=2.4):
        self.mesh([(x-w/2,y,z),(x,y,z+h/2),(x+w/2,y,z),(x,y,z-h/2),
                   (x,y-depth,z),(x,y+1,z)],
                  [(0,1,4),(1,2,4),(2,3,4),(3,0,4),(1,0,5),(2,1,5),(3,2,5),(0,3,5)],mat)

    def pointed_panel(self,x,y,z,w,h,mat,frame):
        pts=[(x,y,z+h/2),(x+w/2,y,z+h*.1),(x+w*.30,y,z-h*.32),
             (x,y,z-h/2),(x-w*.30,y,z-h*.32),(x-w/2,y,z+h*.1)]
        self.mesh(pts+[ (a,b+2,c) for a,b,c in pts],
                  [(5,4,3,2,1,0),(6,7,8,9,10,11)]+[(i,(i+1)%6,(i+1)%6+6,i+6) for i in range(6)],mat)
        for a,b in zip(pts,pts[1:]+pts[:1]):self.beam(a,b,2.3,frame)

    def leaf(self,x,y,z,w,h,mat):
        self.beam((x,y,z-h/2),(x,y,z+h/2),1.5,mat)
        for side in (-1,1):
            for i in range(2):
                zz=z-h*.3+i*h*.28
                self.mesh([(x,y,zz),(x+side*w*.34,y-.5,zz+h*.07),
                           (x+side*w*.5,y,zz+h*.4),(x+side*w*.12,y-.5,zz+h*.24)],
                          [(0,1,2,3),(3,2,1,0)],mat)
        self.diamond(x,y,z+h*.42,w*.25,h*.3,mat,1.1)

    def rivet(self,x,y,z,mat='iron',r=1.5):
        self.cone((x,y,z),r,r*.8,1.6,mat,8,Matrix.Rotation(math.pi/2,3,'X'))

    def gem(self,x,y,z,r,h,mat):
        self.cone((x,y,z+h*.22),r*.65,r,h*.44,mat,5)
        self.cone((x,y,z+h*.70),r,0,h*.52,mat,5)

    def crown(self,x,y,z):
        for i in range(6):
            a=i*math.tau/6
            points=[]
            for r,h,w in ((13,1,5.5),(19,12,4.8),(18,25,2.8),(13,35,.25)):
                for t,d in ((-1,-1),(1,-1),(1,1),(-1,1)):
                    points.append((x+math.cos(a)*(r+d*1.4)-math.sin(a)*t*w/2,
                                   y+math.sin(a)*(r+d*1.4)+math.cos(a)*t*w/2,z+h))
            faces=[(3,2,1,0),(12,13,14,15)]+[(j*4+k,j*4+(k+1)%4,(j+1)*4+(k+1)%4,(j+1)*4+k) for j in range(3) for k in range(4)]
            self.mesh(points,faces,'gold')

    def wall(self,stage):
        stone='wall_stone' if stage<=3 else 'wall_pale'
        if stage in (7,8):stone='wall_dark'
        if stage>=9:stone='wall_ivory'
        accent={1:'wood',2:'wood',3:stone,4:'bronze',5:'azure',6:'jade',7:'ruby',8:'purple',9:'azure',10:'jade'}[stage]
        trim='iron' if stage==1 else 'brass' if stage<=6 else 'copper' if stage==7 else 'silver' if stage==8 else 'gold'
        floor_z=104 if stage<=3 else 110 if stage<=7 else 116
        self.box((0,0,floor_z/2),(211,211,floor_z),'shadow',1)
        # The square footprint includes the foundation, not a separate display slab.
        for side in range(4):
            start=len(self.v)
            for i in range(7):
                x=(i-3)*33.7
                self.box((x,-111,11),(33,25,22),stone,1.5)
            if stage==1:
                for i in range(13):
                    x=(i-6)*15
                    self.box((x,-107,62),(14.5,19,82),'wood_light' if i%4==0 else 'wood',.9)
                    # Large, irregular longitudinal split survives RTS distance.
                    if i%3==0:self.beam((x+2,-117,30),(x+1,-117,76),.45,'shadow')
                for z in (33,93):self.box((0,-119,z),(211,7,9),'wood_light',.8)
            else:
                rows=5;rh=(floor_z-23)/rows
                for row in range(rows):
                    for i in range(7):
                        x=-112+i*34+(17 if row%2 else 0)
                        l=max(-112,x);r=min(112,x+33)
                        if r-l<3:continue
                        color=stone if (i+row)%5 else ('wall_stone' if stage<9 else 'wall_pale')
                        self.box(((l+r)/2,-109,24+(row+.5)*rh),(r-l,21,rh-.7),color,1.05)
                if stage==2:
                    for row in range(2):self.box((0,-113,82+row*14),(202,8,13),'wood',.85)
            # Coping ring and three squared merlons per side match the references.
            self.box((0,-108,floor_z+1),(214,25,7),accent if stage>=4 else stone if stage>=3 else 'wood_light',.8)
            for x in (-59,0,59):
                self.box((x,-105,floor_z+21),(28,24,34),stone if stage>=3 else 'wood',1.2)
                if stage>=4:
                    self.box((x,-105,floor_z+40),(30,26,6),trim,1)
                    self.box((x,-105,floor_z+43),(25,21,2.2),accent,.6)
                if stage>=8:self.diamond(x,-119,floor_z+22,6,16,accent,1.9)
            if stage>=4:
                for z in (29,floor_z-8):
                    self.box((0,-121,z),(191,3.5,7),trim,.5)
                    self.box((0,-123,z),(182,1.5,3.5),accent,.3)
                for x in (-68,68):
                    self.box((x,-120,floor_z-11),(11,5,15),trim,.5)
                    self.rivet(x,-124,floor_z-11,trim,2)
                if stage in (4,5):
                    self.pointed_panel(0,-122,63,45,57,accent,trim)
                    self.leaf(0,-126,64,23,35,trim)
                elif stage in (6,8,10):
                    self.pointed_panel(0,-123,65,53,69,accent,stone if stage<10 else trim)
                    self.diamond(0,-127,65,17,36,'purple' if stage in (8,10) else 'gold',4)
                elif stage in (7,9):
                    rot=Matrix.Rotation(math.pi/2,3,'X')
                    self.cone((0,-123,64),17,17,3,trim,20,rot)
                    self.ring((0,-126,64),18,1.7,trim,rot,n=24)
                    for j in range(12):
                        a=j*math.tau/12
                        self.mesh([(math.cos(a-.11)*19,-126,64+math.sin(a-.11)*19),
                                   (math.cos(a)*34,-126,64+math.sin(a)*34),
                                   (math.cos(a+.11)*19,-126,64+math.sin(a+.11)*19)],[(0,1,2),(2,1,0)],trim)
                    if stage==9:self.diamond(0,-128,64,14,21,'azure',4)
            elif stage==3:
                self.box((0,-121,64),(34,3,44),'wall_pale',1)
                self.leaf(0,-124,64,21,31,'jade')
            # Repeat the same face, without introducing a directional front.
            rot=Matrix.Rotation(side*math.pi/2,3,'Z')
            self.v[start:]=[tuple(rot@Vector(p)) for p in self.v[start:]]
        # Walkable-looking inset wooden/stone deck; no through-hole.
        if stage==1:
            for i in range(13):self.box(((i-6)*14,0,floor_z),(13.5,187,6),'wood_light' if i%3 else 'wood',.4)
        else:
            for ix in range(6):
                for iy in range(6):
                    self.box(((ix-2.5)*30.5,(iy-2.5)*30.5,floor_z),(29.8,29.8,6),stone,.7)
        for x in (-101,101):
            for y in (-101,101):
                self.box((x,y,13),(46,46,26),stone,2)
                if stage>=3:
                    # Broad sloping stone feet and tall chamfered piers.
                    pts=[(x+dx*r,y+dy*r,z) for z,r in ((15,23),(43,18)) for dx,dy in ((-1,-1),(1,-1),(1,1),(-1,1))]
                    self.mesh(pts,[(3,2,1,0),(4,5,6,7),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7)],stone)
                if stage<=2:self.box((x,y,87),(35,35,130),'wood_light' if stage==1 else 'wood',1.4)
                else:
                    for row in range(6):
                        self.box((x,y,34+row*21),(35,35,20.3),stone,1.4)
                top=floor_z+50
                self.box((x,y,top),(40,40,21),accent if stage>=4 else 'wood_light' if stage<=2 else stone,1.5)
                if stage!=3:
                    for z in ((30,top-8) if stage<=2 else (30,top-8,top+10)):
                        self.box((x,y,z),(42,42,9 if stage<=2 else 5),trim,.7)
                        # Interior stays wood / stone; band is a true forged collar.
                    if stage>=6:
                        self.box((x,y,top+14),(29,29,4),accent,.8)
                        self.cone((x,y,top+18),8,0,7,trim,4,Matrix.Rotation(math.pi/4,3,'Z'))
                for face in range(2):
                    # Decorate the two outward corner faces.
                    dx=math.copysign(20,x) if face==0 else 0
                    dy=math.copysign(20,y) if face==1 else 0
                    start=len(self.v)
                    if stage<=2:
                        for z in (30,top-8):
                            for xx in (-10,10):self.rivet(xx,-22,z,trim,2.3)
                    elif stage>=4:
                        self.box((0,-19,84),(21,3,101),trim,.65)
                        self.box((0,-21,84),(16,1.8,92),accent,.6)
                        if stage<=5:
                            for z in (43,82,123):self.rivet(0,-23,z,trim,2)
                        else:
                            self.pointed_panel(0,-23,83,18,84,accent,trim if stage!=8 else stone)
                            self.diamond(0,-26,84,9,27,'purple' if stage in (8,10) else trim if stage<=7 else 'azure',3)
                    ang=(math.pi/2 if x>0 else -math.pi/2) if face==0 else (math.pi if y>0 else 0)
                    rot=Matrix.Rotation(ang,3,'Z')
                    self.v[start:]=[tuple(rot@Vector(p)+Vector((x,y,0))) for p in self.v[start:]]
                if stage>=8:
                    self.gem(x,y,top+14,12,19 if stage<10 else 32,'purple' if stage==8 else 'azure' if stage==9 else 'crystal')
                if stage>=9:
                    for a in range(4):
                        angle=a*math.tau/4+math.pi/4
                        xx=x+math.cos(angle)*22;yy=y+math.sin(angle)*22
                        self.cone((xx,yy,top+20),5,0,31,trim,4)
                    if stage==10:
                        self.ring((x,y,top+19),12,1.7,'gold',n=16)
                        self.crown(x,y,top+12)
        return self
