"""Native mesh construction for the approved 700-square biome arenas.

Only the closed wall body occupies 700 x 700. The coast has its own bounds.
All surfaces are real geometry; no concept picture is projected onto a plane.
"""
import math
from mathutils import Vector, Matrix
from wood_training_geometry import WoodKit
from ten_realm_spec import PALETTE, realm, CLEAR_HALF, WATER_Z


class RealmKit(WoodKit):
    def __init__(self, rank):
        super().__init__(7900 + rank * 91)
        self.keys = list(PALETTE)
        self.spec = realm(rank)
        self.smooth_faces = []
        self.parts = []
        self.shore_rings = []

    def mesh(self, verts, faces, mat='stone'):
        first = len(self.f)
        super().mesh(verts, faces, mat)
        self.smooth_faces.extend([False] * (len(self.f)-first))

    def section(self, name, function):
        start_v, start_f = len(self.v), len(self.f)
        function()
        self.parts.append(dict(name=name, vertices=[start_v,len(self.v)], faces=[start_f,len(self.f)]))

    def place(self, function, center, scale=1.0, angle=0.0):
        first = len(self.v)
        function()
        if isinstance(scale, (int,float)):
            scale = (scale,)*3
        self.v[first:] = [(x*scale[0], y*scale[1], z*scale[2]) for x,y,z in self.v[first:]]
        self.transform_since(first, angle, center)

    def shore_height(self, x, y):
        # Interpolate the actual generated ring strips, not a nominal square:
        # decorative roots and pebbles follow the sloping island substrate.
        a = math.atan2(y,x) % math.tau
        t = a/math.tau*96
        index, fraction = int(t)%96, t-int(t)
        distance = math.hypot(x,y)
        previous = None
        for ring in self.shore_rings:
            p, q = ring[index], ring[(index+1)%96]
            radius = math.hypot(p[0],p[1])*(1-fraction)+math.hypot(q[0],q[1])*fraction
            z = p[2]*(1-fraction)+q[2]*fraction
            if previous and distance <= radius:
                r0,z0=previous
                f=max(0,min(1,(distance-r0)/max(.01,radius-r0)))
                return z0+(z-z0)*f
            previous=(radius,z)
        return previous[1] if previous else -8

    def rock(self, center, size, mat='rock', seed=None):
        # Deliberate large facets with a few smaller broken planes.
        n=8; vertices=[]
        for row,(h,radius) in enumerate(((-.5,.80),(-.27,1.0),(.21,.91),(.5,.61))):
            for i in range(n):
                a=i*math.tau/n
                r=radius*self.rng.uniform(.87,1.10)
                vertices.append((center[0]+math.cos(a)*size[0]*r/2,
                                 center[1]+math.sin(a)*size[1]*r/2,
                                 center[2]+(h+self.rng.uniform(-.036,.036))*size[2]))
        faces=[tuple(reversed(range(n))),tuple(range(3*n,4*n))]
        for row in range(3):
            for i in range(n):
                a=row*n+i;b=row*n+(i+1)%n;c=(row+1)*n+(i+1)%n;d=(row+1)*n+i
                if (i+row)%3:faces.extend([(a,b,c),(a,c,d)])
                else:faces.append((a,b,c,d))
        self.mesh(vertices,faces,mat)

    def inlay_line(self,a,b,z,width=1.1,mat='gold'):
        a,b=Vector((a[0],a[1],z)),Vector((b[0],b[1],z));d=b-a
        self.box((a+b)/2,(d.length,width,.18),mat,.03,Matrix.Rotation(math.atan2(d.y,d.x),3,'Z'))

    def inlay_ring(self,center,radius,z,mat='gold',thickness=1,steps=64):
        for i in range(steps):
            a=i*math.tau/steps;b=(i+1)*math.tau/steps
            self.inlay_line((center[0]+math.cos(a)*radius,center[1]+math.sin(a)*radius),
                            (center[0]+math.cos(b)*radius,center[1]+math.sin(b)*radius),z,thickness,mat)

    def crystal_gem(self,center,radius,height,mat='amethyst'):
        n=6;x,y,z=center
        v=[(x+math.cos(i*math.tau/n)*r,y+math.sin(i*math.tau/n)*r,z+h)
           for r,h in ((radius*.70,0),(radius,height*.65)) for i in range(n)]
        v.append((x+radius*.1,y-radius*.08,z+height))
        self.mesh(v,[tuple(reversed(range(n)))]+
                  [(i,(i+1)%n,(i+1)%n+n,i+n)for i in range(n)]+
                  [(i+n,(i+1)%n+n,2*n)for i in range(n)],mat)


def clip_halfplane(poly, nx, ny, limit):
    out=[]
    for p,q in zip(poly,poly[1:]+poly[:1]):
        a=nx*p[0]+ny*p[1]-limit;b=nx*q[0]+ny*q[1]-limit
        if a<=1e-7:out.append(p)
        if (a<=0)!=(b<=0):
            t=a/(a-b);out.append((p[0]+(q[0]-p[0])*t,p[1]+(q[1]-p[1])*t))
    return out


def floor(kit):
    rank=kit.spec['rank'];mat=kit.spec['roles']['ground']
    # Mortar in the joints remains within one unit of the walkable deck.
    kit.box((0,0,-12),(700,700,22.8),'mortar',0)
    if rank in (1,2,3):
        # One flush ground sheet. Noise is in material normal maps, not walkable bumps.
        kit.box((0,0,-2),(698,698,4),mat,0)
        for i in range(32 if rank>1 else 14):
            side=i%4;x=kit.rng.uniform(-292,292);y=kit.rng.uniform(278,310)
            start=len(kit.v)
            if rank>1:
                kit.rock((x,y,-1.7),(kit.rng.uniform(15,35),kit.rng.uniform(10,27),4),
                         'stone' if i%3 else 'moss')
            else:
                # Scattered slabs may overlap in plan. Slightly different
                # burial depths prevent coincident top faces and black flicker.
                kit.box((x,y,-1+i*.02),(kit.rng.uniform(18,36),kit.rng.uniform(18,33),2.2),'sandstone_light',.6)
            kit.transform_since(start,side*math.pi/2)
        if rank>1:
            for i in range(100):
                a=kit.rng.random()*math.tau;r=kit.rng.uniform(260,300)
                x,y=math.cos(a)*r,math.sin(a)*r
                # A handful of fallen leaves at edges, thin enough to stay flush.
                kit.leaf((x,y,.08),(x+kit.rng.uniform(3,7),y+kit.rng.uniform(3,7),.15),3,
                         'leaf_dark' if rank==3 else kit.rng.choice(['leaf_light','wood_light']))
    else:
        # Non-periodic Voronoi cells create a genuine broken-stone silhouette.
        # Dressed Radiant paving keeps a more orderly joint pattern.
        count=13 if rank==9 else 11
        step=700/count;seeds=[]
        for row in range(count):
            for col in range(count):
                jitter=.06 if rank==9 else .27
                seeds.append((-350+(col+.5)*step+kit.rng.uniform(-jitter,jitter)*step,
                              -350+(row+.5)*step+kit.rng.uniform(-jitter,jitter)*step))
        for i,(sx,sy) in enumerate(seeds):
            poly=[(-350,-350),(350,-350),(350,350),(-350,350)]
            near=sorted((j for j in range(len(seeds)) if j!=i),key=lambda j:(sx-seeds[j][0])**2+(sy-seeds[j][1])**2)[:18]
            for j in near:
                ox,oy=seeds[j]
                poly=clip_halfplane(poly,ox-sx,oy-sy,(ox*ox+oy*oy-sx*sx-sy*sy)/2)
                if not poly:break
            if len(poly)<3:continue
            cx=sum(p[0]for p in poly)/len(poly);cy=sum(p[1]for p in poly)/len(poly)
            inset=.989 if rank==9 else .985
            ring=[(cx+(x-cx)*inset,cy+(y-cy)*inset)for x,y in poly]
            top=[(cx+(x-cx)*.97,cy+(y-cy)*.97)for x,y in ring]
            n=len(poly)
            verts=[(x,y,z)for points,z in ((ring,-5),(ring,-.6),(top,0)) for x,y in points]
            faces=[tuple(reversed(range(n))),tuple(range(2*n,3*n))]
            faces +=[(r*n+j,r*n+(j+1)%n,(r+1)*n+(j+1)%n,(r+1)*n+j)for r in range(2)for j in range(n)]
            chosen=mat
            if rank==5 and i%8==0:chosen='ice'
            if rank==8 and i%19==0:chosen='quartz'
            if rank==9 and i%17==0:chosen='ivory_light'
            kit.mesh(verts,faces,chosen)
    # Small arrival discs are inlaid into the walking plane, not raised steps.
    for y in (-234,234):
        stone=kit.spec['roles']['cap'];accent=kit.spec['roles']['accent']
        kit.cone((0,y,-.75),37,37,1.8,stone,48)
        kit.inlay_ring((0,y),33,.26,accent,1.3,48)
        kit.inlay_ring((0,y),27,.27,accent,.65,48)
        for a in range(4):
            angle=a*math.pi/2
            p=(math.cos(angle)*19,y+math.sin(angle)*19)
            q=(math.cos(angle+math.pi/4)*6,y+math.sin(angle+math.pi/4)*6)
            r=(math.cos(angle+math.pi/2)*19,y+math.sin(angle+math.pi/2)*19)
            kit.inlay_line(p,q,.29,1,accent);kit.inlay_line(q,r,.29,1,accent)
    if rank==9:
        for r in (68,73):kit.inlay_ring((0,0),r,.22,'gold',1.0,80)
        for i in range(8):
            a=i*math.tau/8
            kit.inlay_line((math.cos(a)*17,math.sin(a)*17),(math.cos(a)*58,math.sin(a)*58),.25,1.4,'gold')
        for i in range(4):
            a=i*math.pi/2
            kit.inlay_line((math.cos(a)*74,math.sin(a)*74),(math.cos(a)*182,math.sin(a)*182),.24,1.1,'gold')
        # Ivory, teal and brass form a readable, flush ceremonial compass.
        for i in range(4):
            first=len(kit.v)
            kit.polygon([(-10,90),(-6,164),(0,183),(6,164),(10,90),(0,104)],.16,.045,'teal')
            for x in(-1,1):
                kit.inlay_line((x*11,90),(x*7,164),.23,1.5,'gold')
                kit.inlay_line((x*7,164),(0,183),.23,1.5,'gold')
            kit.polygon([(-12,31),(0,65),(12,31),(0,42)],.15,.04,'teal')
            kit.transform_since(first,i*math.pi/2)
        for r in(16,21,63,79):kit.inlay_ring((0,0),r,.23,'gold',1.0,64)


def coast(kit):
    roles=kit.spec['roles'];rank=kit.spec['rank'];rings=[]
    # Nested near-square rings keep dry ledges beneath corner trees.  The
    # old rounded first ring could actually cross the square at its corners.
    for row,(half,z,variation)in enumerate(((350,-3,0),(431,-10,23),(480,-47,25),(520,-84,21),(554,-119,13))):
        ring=[]
        for i in range(96):
            a=i*math.tau/96;c,s=math.cos(a),math.sin(a)
            if row==0:r=half/max(abs(c),abs(s))
            else:
                extent=half+variation*(.56*math.sin(a*5+rank*.8)+.32*math.cos(a*9-rank)+.12*math.sin(a*17))
                r=extent/(abs(c)**12+abs(s)**12)**(1/12)
            h=z+(0 if row==0 else 3.5*math.sin(a*7+rank*.4)+2*math.cos(a*3))
            ring.append((c*r,s*r,h))
        rings.append(ring)
    kit.shore_rings=rings
    v=[p for ring in rings for p in ring]
    for row in range(4):
        for i in range(96):
            j=(i+1)%96
            mat=roles['shore'] if row==0 else roles['rock']
            if row==1 and rank in(1,2,3,6):
                # A per-sector dry/wet material swap reads as rectangular
                # reflective stripes. Keep continuous sediment above water;
                # the next, submerged strip carries the darker wet response.
                mat=roles['shore']
            if row>=2:mat=roles['wet']
            # Smooth normals only on soft sediment; exposed rock shelves are faceted.
            before=len(kit.f)
            kit.mesh([v[row*96+i],v[row*96+j],v[(row+1)*96+j],v[(row+1)*96+i]],[(0,2,1),(0,3,2)],mat)
            if rank in (1,2,3,6):
                kit.smooth_faces[before:]=[True]*(len(kit.f)-before)
    # Exposed rock masses break the edge into coves and headlands; sediment
    # themes keep flatter, half-buried stones and longer sandy stretches.
    for i in range(48):
        a=i*math.tau/48+kit.rng.uniform(-.038,.038)
        half=kit.rng.uniform(416,476)
        r=half/(abs(math.cos(a))**12+abs(math.sin(a))**12)**(1/12)
        x,y=r*math.cos(a),r*math.sin(a);z=kit.shore_height(x,y)
        width=kit.rng.uniform(34,64)
        height=kit.rng.uniform(27,48) if rank in(1,2,3,6)else kit.rng.uniform(48,88)
        if rank==1 and i%3:continue
        kit.rock((x,y,z+height*.12),(width,width*kit.rng.uniform(.7,1.1),height),roles['rock'])
        if rank in(2,3,9) and i%3!=0:
            kit.rock((x-4,y+3,z+height*.52),(width*.64,width*.48,5),'moss')
    for i in range(160):
        a=kit.rng.random()*math.tau
        half=kit.rng.uniform(367,517)
        r=half/(abs(math.cos(a))**12+abs(math.sin(a))**12)**(1/12)
        x,y=r*math.cos(a),r*math.sin(a);z=kit.shore_height(x,y)
        radius=kit.rng.uniform(4,14) if rank in(1,2,3,6) else kit.rng.uniform(6,24)
        mat=roles['wet'] if z<WATER_Z+12 else roles['rock']
        kit.rock((x,y,z+radius*.12),(radius*2,radius*1.6,radius*1.1),mat)
    # Small broken foam arcs only at selected exposed stones, never a rigid border.
    for i in range(16):
        a=kit.rng.random()*math.tau
        r=474/(abs(math.cos(a))**12+abs(math.sin(a))**12)**(1/12)
        x,y=math.cos(a)*r,math.sin(a)*r
        points=[(x+t*3,y+math.sin(t*.8+a)*2)for t in range(5)]
        kit.polygon(points+[(px,py+kit.rng.uniform(.35,1.1))for px,py in points][::-1],WATER_Z+.17,.04,'foam')


def wall_details(k, rank, h):
    """Theme-specific solid carving on a local +Y wall, all inside 700 square."""
    def diamond(x,y,z,w,hh,mat):
        k.mesh([(x-w/2,y,z),(x,y,z-hh/2),(x+w/2,y,z),(x,y,z+hh/2),(x,y-2,z)],
               [(0,1,4),(1,2,4),(2,3,4),(3,0,4),(3,2,1,0)],mat)
    if rank==1:
        for x in(-220,0,220):
            k.box((x,321.8,40),(30,1.6,31),'sandstone_light',1.8)
            for z in(31,39,47):
                k.box((x,320.7,z),(17 if z==39 else 10,.7,1),'sandstone',.1)
        for x in(-328,-110,110):
            k.box((x,328,104),(27,27,5),'sandstone',1.4)
    elif rank in(2,3):
        for x in(-220,0,220):
            k.timber((x,347,22),(143,5,7),'wood',.8,axis=(1,0,0))
            k.timber((x,347,53),(143,5,7),'wood',.8,axis=(1,0,0))
            for dx in(-58,58):
                k.beam((x+dx,347.5,19),(x-dx*.22,347.5,58),4,'wood_light',False)
        # Thicker root braids read as grown-over masonry at combat distance.
        for x in(-273,-173,34,224):
            for j in range(5):
                a=(x+math.sin(j*.8)*5,319+j*.3,4+j*10)
                b=(x+math.sin((j+1)*.8)*5,319+(j+1)*.3,14+j*10)
                k.beam(a,b,3.4 if rank==2 else 4.5,'bark',True,.3)
        if rank==3:
            for x in(-270,-55,190):
                k.timber((x,335,h+3),(82,21,6),'wood',1.2,axis=(1,0,0))
    elif rank==4:
        for x in(-268,-220,-56,0,220,264):
            k.rock((x,336,h+4),(39,23,16),'redstone_light')
        for x in(-328,-110,110):
            k.box((x,328,91),(33,33,5),'bronze',.8)
    elif rank==5:
        for x in range(-289,300,37):
            k.rock((x,336,h+2),(41,24,10),'snow')
        for x in(-328,-110,110):
            k.rock((x,328,102),(27,27,10),'snow')
        for x in(-280,-180,-29,68,256):
            k.cone((x,347,h-11),.3,2.8,19,'ice',6)
    elif rank==6:
        for x in(-220,0,220):
            # Shallow shell fan carved into the landward wall face.
            for i in range(7):
                a=math.radians(28+i*20)
                k.beam((x,320,30),(x+math.cos(a)*18,320,30+math.sin(a)*18),1.7,'coral_light',True,.2)
        for x in(-328,-110,110):
            k.ring((x,328,105),10,2,'coral_light',n=12)
    elif rank==7:
        for x in(-328,-110,110):
            for z in(15,80,96):
                k.box((x,328,z),(35,35,4),'bronze',.6)
            for zz in(19,75):
                for dx in(-8,8):diamond(x+dx,309,zz,3,3,'bronze')
        for x in(-220,0,220):
            k.box((x,321,17),(171,2,4),'bronze',.6)
            k.box((x,321,60),(171,2,3),'iron',.6)
    elif rank==8:
        for x in(-220,0,220):
            diamond(x,321,36,20,42,'quartz')
            diamond(x,318,36,11,30,'amethyst')
        for x in(-328,-110,110):
            diamond(x,308,52,12,51,'amethyst')
            k.crystal_gem((x,328,102),7,21,'amethyst')
    elif rank==9:
        for x in(-220,0,220):
            k.box((x,321,41),(159,1.8,44),'ivory_light',1)
            for z in(19,63):k.box((x,319.5,z),(165,1.5,1.5),'gold',.3)
            for dx in(-81,81):k.box((x+dx,319.5,41),(1.5,1.5,44),'gold',.3)
            diamond(x,318,41,11,26,'teal')
        for x in(-328,-110,110):
            k.box((x,328,93),(31,31,2),'gold',.3)
            # Faceted gilded pyramid, not a light source.
            k.mesh([(x-12,316,102),(x+12,316,102),(x+12,340,102),(x-12,340,102),(x,328,116)],
                   [(0,1,4),(1,2,4),(2,3,4),(3,0,4),(3,2,1,0)],'gold')
            diamond(x,309,56,9,24,'gold')
            for dx in(-13,13):k.box((x+dx,307.8,50),(1.5,1.2,59),'gold',.2)
    elif rank==10:
        for x in(-220,0,220):
            diamond(x,321,42,20,36,'iron')
            diamond(x,318,42,9,27,'red_cloth')
        for x in(-328,-110,110):
            for dx in(-9,9):
                k.beam((x+dx,328,98),(x+dx*1.2,328,118),4,'slate',True,.5)
                k.cone((x+dx*1.2,328,120),3,0,8,'bone',5)
            for z in(16,80):k.box((x,328,z),(35,35,4),'iron',.6)


def walls(kit):
    rank=kit.spec['rank'];h=kit.spec['wall_height'];roles=kit.spec['roles']
    for side in range(4):
        start=len(kit.v)
        kit.box((0,336,(h-5)/2),(654,25,h-5),'mortar',0)
        for row in range(3):
            pitch=61 if rank not in(6,9)else 54
            edges=sorted(set([-328,328]+[x+(pitch*.5 if row%2 else 0)for x in range(-360,390,pitch) if -328<x+(pitch*.5 if row%2 else 0)<328]))
            for a,b in zip(edges,edges[1:]):
                mat=roles['cap'] if (row+round(a))%13==0 else roles['wall']
                kit.box(((a+b)/2,336,5+(row+.5)*(h-14)/3),(b-a-.7,28,(h-14)/3-.5),mat,1.5)
        for i in range(12):
            kit.box((-302+i*55,336,h-3),(54.3,28,6),roles['cap'],1.5)
        for x in (-328,-110,110):
            width=44 if abs(x)>300 else 32
            # Both corner bases and caps remain inside [-350,350].
            kit.box((x,328,5),(width,width,10),roles['wall'],1.5)
            for row in range(3):
                kit.box((x,328,19+row*24),(width-7,width-7,23.6),roles['wall'],2)
            kit.box((x,328,91),(width,width,8),roles['cap'],1.8)
            kit.box((x,328,98),(width-13,width-13,7),roles['cap'],1.7)
            if rank in(7,9):
                kit.box((x,309,55),(width-15,1.8,58),'bronze'if rank==7 else'teal',.35)
                for zz in (31,77):
                    kit.box((x,307,zz),(width-11,2.5,4),roles['accent'],.4)
            if rank==10:
                for offset in(-8,8):
                    kit.beam((x+offset,346,31),(x+offset*1.3,344,91),3,'bone',True,.5)
        if rank in(2,3):
            for x in (-270,-162,0,162,270):
                kit.log((x,343,0),(x+2,343,78),4,'bark')
                for z in(19,57):kit.ring((x+1,343,z),4.8,.6,'wood_light',n=12)
        if rank==8:
            for x in(-328,328):kit.crystal_gem((x,328,100),8,22,'amethyst')
        wall_details(kit,rank,h)
        kit.transform_since(start,side*math.pi/2)
    # Visible lower courses have dry crevices and moss, not a single uniform tint.
    if rank in(2,3,9):
        for side in range(4):
            start=len(kit.v)
            for i in range(18):
                x=kit.rng.uniform(-295,295)
                kit.rock((x,321,kit.rng.uniform(2,12)),(kit.rng.uniform(4,14),2,kit.rng.uniform(3,17)),'moss')
            kit.transform_since(start,side*math.pi/2)


def build_realms():
    from ten_realm_dressing import decorate
    jobs=[]
    for rank in range(1,11):
        k=RealmKit(rank)
        k.section('combat_floor',lambda:floor(k))
        k.section('shore',lambda:coast(k))
        k.section('closed_walls',lambda:walls(k))
        k.section('biome_dressing',lambda:decorate(k,rank))
        meta=k.spec.copy()
        meta.update(wall_bounds=[[-350,-350,0],[350,350,124]],
                    interior_bounds=[[-CLEAR_HALF,-CLEAR_HALF,-.1],[CLEAR_HALF,CLEAR_HALF,.5]],
                    shore_rings=[[[round(x,3),round(y,3),round(z,3)]for x,y,z in ring]for ring in k.shore_rings],
                    parts=k.parts,wall_closed=True)
        collision=[dict(center=[0,0,-8],size=[700,700,16],role='floor')]
        for axis in(0,1):
            for sign in(-1,1):
                c=[0,0,55];s=[700,700,110];c[axis]=sign*328;s[axis]=44
                collision.append(dict(center=c,size=s,role='enclosing_wall'))
        jobs.append(dict(name=meta['name'],label=meta['label'],kit=k,meta=meta,collision=collision))
    return jobs
