"""Reference-led Radiant village kit. Geometry is batched before Blender import.

Z up, entrances face -Y. No display plinths: foundations follow each building.
The silhouettes, roof tiles, stone courses and equipment are actual geometry.
"""
import math
import random
from mathutils import Vector

TAU = math.tau
PALETTE = {
    'stone': (.58,.59,.53), 'limestone': (.73,.71,.61),
    'ivory': (.84,.80,.65), 'basalt': (.20,.24,.23),
    'shadow': (.035,.046,.041), 'wood': (.28,.16,.071),
    'wood_light': (.48,.32,.15), 'slate': (.14,.32,.34),
    'teal': (.19,.39,.40), 'brass': (.65,.44,.18),
    'gold': (.98,.68,.19), 'blue': (.20,.80,.72),
    'green': (.31,.43,.14), 'leaf': (.43,.55,.22),
    'earth': (.24,.19,.10), 'wheat': (.82,.61,.26),
    'window': (1.0,.61,.17), 'red': (.34,.10,.055),
}

class Kit:
    def __init__(self, seed=1):
        self.v=[]; self.f=[]; self.m=[]; self.rng=random.Random(seed)
        self.keys=list(PALETTE)

    def mesh(self, verts, faces, mat='stone'):
        # Bakes and Source 2 need a real thin solid, not coincident front/back
        # triangles (which otherwise bake black on flags and canvas sails).
        if len(faces)==2 and tuple(faces[0])==tuple(reversed(faces[1])):
            verts=[Vector(v) for v in verts]
            normal=(verts[1]-verts[0]).cross(verts[2]-verts[0]).normalized()*.18
            n=len(verts);verts=verts+[v-normal for v in verts]
            faces=[tuple(range(n)),tuple(reversed(range(n,n*2)))]+[(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)]
        off=len(self.v); self.v.extend(tuple(v) for v in verts)
        self.f.extend(tuple(off+i for i in f) for f in faces)
        self.m.extend([self.keys.index(mat)]*len(faces))

    def box(self,c,s,mat='stone', bevel=.35, rotation=None):
        x,y,z=[a/2 for a in s]; b=min(bevel,x*.3,y*.3,z*.3)
        if b:
            octagon=[(-x+b,-y), (x-b,-y), (x,-y+b),(x,y-b),
                     (x-b,y),(-x+b,y),(-x,y-b),(-x,-y+b)]
            vs=[]
            for zz,inset in [(-z,b),(-z+b,0),(z-b,0),(z,b)]:
                vs.extend((xx*(1-inset/x),yy*(1-inset/y),zz) for xx,yy in octagon)
            fs=[tuple(reversed(range(8))),tuple(range(24,32))]
            for row in range(3):
                fs.extend((row*8+i,row*8+(i+1)%8,(row+1)*8+(i+1)%8,(row+1)*8+i) for i in range(8))
        else:
            vs=[(a*x,b*y,d*z) for d in (-1,1) for b in (-1,1) for a in (-1,1)]
            fs=[(0,2,3,1),(4,5,7,6),(0,1,5,4),(2,6,7,3),(0,4,6,2),(1,3,7,5)]
        if rotation is not None: vs=[rotation@Vector(v) for v in vs]
        self.mesh([Vector(v)+Vector(c) for v in vs],fs,mat)

    def cone(self,c,r,top,h,mat='stone',n=12,rotation=None):
        vs=[(radius*math.cos(i*TAU/n),radius*math.sin(i*TAU/n),z)
            for z,radius in [(-h/2,r),(h/2,top)] for i in range(n)]
        if rotation is not None: vs=[rotation@Vector(v) for v in vs]
        fs=[tuple(reversed(range(n))),tuple(range(n,n*2))]
        fs.extend((i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n))
        self.mesh([Vector(v)+Vector(c) for v in vs],fs,mat)

    def beam(self,a,b,w=2,mat='wood_light',round=False,top=None):
        a,b=Vector(a),Vector(b); delta=b-a
        rot=delta.to_track_quat('Z','Y').to_matrix()
        if round:self.cone((a+b)/2,w,top if top is not None else w,delta.length,mat,8,rot)
        else:self.box((a+b)/2,(w,w,delta.length),mat,.18,rot)

    def claw(self,angle):
        # A continuous tapered stone arch, with a carved bevel and brass inlay.
        vs=[];n=10;centers=[]
        for i in range(n+1):
            t=i/n
            rr=(1-t)**3*30+3*(1-t)**2*t*45+3*(1-t)*t*t*26+t**3*12
            z=(1-t)**3*35+3*(1-t)**2*t*62+3*(1-t)*t*t*96+t**3*110
            width=7*(1-t)+.35;depth=5.5*(1-t)+.5
            c=Vector((math.cos(angle)*rr,8+math.sin(angle)*rr,z));centers.append(c)
            radial=Vector((math.cos(angle),math.sin(angle),0));across=Vector((-math.sin(angle),math.cos(angle),0))
            for u,v in [(-.35,-.5),(.35,-.5),(.5,-.35),(.5,.35),(.35,.5),(-.35,.5),(-.5,.35),(-.5,-.35)]:
                vs.append(c+across*u*width+radial*v*depth)
        fs=[tuple(reversed(range(8))),tuple(range(n*8,n*8+8))]
        fs += [(j*8+i,j*8+(i+1)%8,(j+1)*8+(i+1)%8,(j+1)*8+i) for j in range(n) for i in range(8)]
        self.mesh(vs,fs,'ivory')
        for i in range(n):
            offset=Vector((math.cos(angle),math.sin(angle),0))*(3.2*(1-i/n)+.3)
            self.beam(centers[i]+offset,centers[i+1]+offset,.8,'brass')
        for i in (0,3,6):
            self.cone(centers[i],5*(1-i/n),5*(1-i/n),1.5,'brass',8)

    def ring(self,c,r,t=.8,mat='brass',rotation=None,start=0,end=TAU,n=32):
        vs=[]
        for i in range(n+1):
            a=start+(end-start)*i/n
            for j in range(5):
                b=j*TAU/5; p=Vector(((r+t*math.cos(b))*math.cos(a),(r+t*math.cos(b))*math.sin(a),t*math.sin(b)))
                if rotation is not None:p=rotation@p
                vs.append(p+Vector(c))
        self.mesh(vs,[(i*5+j,i*5+(j+1)%5,(i+1)*5+(j+1)%5,(i+1)*5+j) for i in range(n) for j in range(5)],mat)

    def rock(self,c,s,mat='stone',seed=None):
        rng=self.rng if seed is None else random.Random(seed)
        n=7;vs=[]
        for z,r in [(-.5,.72),(-.20,1),(.28,.72),(.5,.20)]:
            for i in range(n):
                a=i*TAU/n;w=r*rng.uniform(.82,1.16)
                vs.append((c[0]+math.cos(a)*w*s[0]/2,c[1]+math.sin(a)*w*s[1]/2,c[2]+(z+rng.uniform(-.045,.045))*s[2]))
        fs=[tuple(reversed(range(n))),tuple(range(3*n,4*n))]
        for row in range(3):
            for i in range(n):
                a=row*n+i;b=row*n+(i+1)%n;d=(row+1)*n+i;e=(row+1)*n+(i+1)%n
                fs.extend([(a,b,e),(a,e,d)])
        self.mesh(vs,fs,mat)

    def crystal(self,c,r,h,mat='blue'):
        self.cone((c[0],c[1],c[2]+h*.18),r*.4,r,h*.36,mat,6)
        self.cone((c[0],c[1],c[2]+h*.63),r,0,h*.54,mat,6)

    def wall(self,c,w,d,h):
        x,y,z=c
        self.box((x,y,z+h/2),(w,d,h),'basalt',.5)
        rows=max(1,round(h/7)); course=h/rows
        for row in range(rows):
            zz=z+(row+.5)*course
            for side in (-1,1):
                for axis,length in [(0,w),(1,d)]:
                    count=max(1,round(length/10)); size=length/count
                    offset=size*.5 if row%2 else 0
                    edges=[-length/2]+[-length/2+offset+i*size for i in range(count+1) if -length/2< -length/2+offset+i*size <length/2]+[length/2]
                    for a,b in zip(edges,edges[1:]):
                        mat='limestone' if self.rng.random()<.25 else 'stone'
                        cc=(x+(a+b)/2,y+side*d/2,zz) if axis==0 else (x+side*w/2,y+(a+b)/2,zz)
                        ss=(b-a-.35,1.5,course-.4) if axis==0 else (1.5,b-a-.35,course-.4)
                        self.box(cc,ss,mat,.3)

    def roundwall(self,c,r,h,n=16):
        x,y,z=c
        self.cone((x,y,z+h/2),r,r*.96,h,'basalt',n)
        rows=max(1,round(h/7))
        for row in range(rows):
            for i in range(n):
                a=(i+(row%2)*.5)*TAU/n; width=2*r*math.sin(math.pi/n)*.94
                rot=Vector((math.cos(a),math.sin(a),0)).to_track_quat('Y','Z').to_matrix()
                self.box((x+math.cos(a)*r,y+math.sin(a)*r,z+(row+.5)*h/rows),(width,1.6,h/rows-.4),
                         'limestone' if (i+row)%5==0 else 'stone',.25,rot)
        self.cone((x,y,z+h),r+1.7,r+1.7,2.5,'limestone',n)

    def roof(self,x,y,w,d,z,h,mat='slate'):
        self.mesh([(x-w/2,y-d/2,z-3.5),(x+w/2,y-d/2,z-3.5),(x,y-d/2,z+h-3.5),
                   (x-w/2,y+d/2,z-3.5),(x+w/2,y+d/2,z-3.5),(x,y+d/2,z+h-3.5)],
                  [(0,2,1),(3,4,5),(0,3,5,2),(1,2,5,4),(0,1,4,3)],'wood')
        # Individual slightly curved overlapping shingles, with a scalloped eave.
        rows=max(4,round(math.hypot(w/2,h)/6));cols=max(3,round(d/6))
        def pos(side,u,v,extra=0):
            return (x+side*w/2*(1-u),y+v,z+h*u-2.5*math.sin(math.pi*u)+extra)
        for side in (-1,1):
            for row in range(rows):
                u0=max(0,row/rows-.025);u1=(row+1)/rows
                for col in range(cols):
                    v0=-d/2+col*d/cols+.13;v1=v0+d/cols-.26
                    e=self.rng.uniform(.3,.65)
                    p=[pos(side,u0,v0,e),pos(side,u0,v1,e),pos(side,u1,v1,e),pos(side,u1,v0,e)]
                    self.mesh(p+[(a,b,c-.75) for a,b,c in p],[(0,1,2,3),(7,6,5,4),(0,4,5,1),(1,5,6,2),(2,6,7,3),(3,7,4,0)],
                              'teal' if self.rng.random()<.23 and mat=='slate' else mat)
            for yy in (-d/2-.6,d/2+.6):
                for row in range(4):
                    self.beam(pos(side,row/4,yy-y,1.2),pos(side,(row+1)/4,yy-y,1.2),2.2,'wood_light')
                self.box((x+side*w/2,yy,z+1),(3.4,4,4.5),'brass')
        self.beam((x,y-d/2-2,z+h+1),(x,y+d/2+2,z+h+1),3,'wood_light')
        for yy in (-d/2,d/2):self.box((x,y+yy,z+h+2),(4.2,3.2,5),'brass')

    def hip(self,c,r,h,mat='slate',n=12,opening=False):
        x,y,z=c;rows=5
        def pos(a,u,extra=0):
            rr=r*(1-.82*u);zz=z+h*u-2.5*math.sin(math.pi*u)
            return (x+rr*math.cos(a),y+rr*math.sin(a),zz+extra)
        for i in range(n):
            if opening and i in (7,8,9,10):continue
            for row in range(rows):
                for col in range(2):
                    a0=(i+col/2+.018)*TAU/n;a1=(i+(col+1)/2-.018)*TAU/n
                    u0=max(0,row/rows-.025);u1=(row+1)/rows
                    p=[pos(a0,u0),pos(a1,u0),pos(a1,u1),pos(a0,u1)]
                    self.mesh(p+[(a,b,c-.8) for a,b,c in p],[(0,1,2,3),(7,6,5,4),(0,4,5,1),(1,5,6,2),(2,6,7,3),(3,7,4,0)],'teal' if (i+row)%4==0 and mat=='slate' else mat)
            for row in range(4):self.beam(pos(i*TAU/n,row/4,1),pos(i*TAU/n,(row+1)/4,1),1.4,'wood_light')
        if not opening:
            self.cone((x,y,z+h+3),r*.2,0,9,'brass',n)
        self.ring((x,y,z-1),r,.9,'wood_light',n=n)

    def window(self,x,y,z,w=6,h=10):
        self.box((x,y,z),(w+2.5,2,h+2.5),'wood',.35)
        self.box((x,y-1.3,z),(w,.5,h),'window',.1)
        self.beam((x,y-1.8,z-h/2),(x,y-1.8,z+h/2),.8,'wood')
        for zz in (z-1,z+2.5):self.beam((x-w/2,y-1.8,zz),(x+w/2,y-1.8,zz),.7,'wood')
        self.box((x,y-1.5,z-h/2-1.3),(w+4,3,1.5),'limestone')

    def door(self,x,y,z,w=13,h=22):
        self.box((x,y,z+h*.42),(w,1.8,h*.84),'shadow')
        self.mesh([(x-w/2,y-1,z+h*.7),(x+w/2,y-1,z+h*.7),(x,y-1,z+h)],[(0,1,2)],'wood')
        for i in range(6):
            dx=(i-2.5)*w/6;hh=h*(1-.3*abs(dx)/(w/2))
            self.box((x+dx,y-1.5,z+hh/2),(w/6-.18,1,hh),'wood_light',.12)
        for side in (-1,1):
            for j in range(3):self.box((x+side*(w/2+1.7),y-1,z+(j+.5)*h*.22),(3.4,4,h*.21),'limestone',.3)
            self.beam((x+side*(w/2+1.7),y-1,z+h*.66),(x,y-1,z+h+2),3.2,'limestone')
        for zz in (.25,.58):self.box((x,y-2.2,z+h*zz),(w*.88,.8,1.1),'basalt',.1)
        self.ring((x+2,y-2.8,z+8),1.15,.28,'brass',Vector((0,-1,0)).to_track_quat('Z','Y').to_matrix(),n=12)

    def steps(self,x,y,w=22,z=0,count=4):
        for i in range(count):self.box((x,y+3.5*i,z+1+i),(w-i*.5,5,2),'stone',.3)

    def flag(self,x,y,z,w=9,h=24,emblem='leaf'):
        self.beam((x-w/2-2,y,z+1),(x+w/2+2,y,z+1),1.1,'brass')
        p=[(x-w/2,y,z),(x+w/2,y,z),(x+w/2,y-.6,z-h+4),(x,y-.7,z-h),(x-w/2,y-.6,z-h+4)]
        self.mesh(p+[ (a,b+.45,c) for a,b,c in p],[(4,3,2,1,0),(5,6,7,8,9)]+[(i,(i+1)%5,(i+1)%5+5,i+5) for i in range(5)],'teal')
        self.beam((x-w/2,y-1,z-h+4),(x,y-1,z-h),.6,'brass');self.beam((x,y-1,z-h),(x+w/2,y-1,z-h+4),.6,'brass')
        zz=z-h*.43
        if emblem=='leaf':
            self.beam((x,y-1.1,zz-5),(x,y-1.1,zz+5),.65,'ivory')
            for side in (-1,1):
                for j in range(2):
                    self.mesh([(x,y-1.2,zz-3+j*3),(x+side*w*.32,y-1.2,zz+j*3),(x+side*w*.23,y-1.2,zz+2+j*3)],[(0,1,2),(2,1,0)],'ivory')
        else:
            rot=Vector((0,-1,0)).to_track_quat('Z','Y').to_matrix()
            self.ring((x,y-1.2,zz),2.1,.55,'ivory',rot,n=16)
            for i in range(8):
                a=i*TAU/8;self.beam((x+3*math.cos(a),y-1.2,zz+3*math.sin(a)),(x+4.6*math.cos(a),y-1.2,zz+4.6*math.sin(a)),.5,'ivory')

    def lantern(self,x,y,z):
        self.box((x,y,z),(2.8,2.8,4.7),'window',.1)
        for dx in (-1.6,1.6):
            for dy in (-1.6,1.6):self.beam((x+dx,y+dy,z-2.5),(x+dx,y+dy,z+2.5),.45,'basalt')
        self.cone((x,y,z+3.3),2.7,.8,2,'brass',4)
        self.beam((x,y,z+4.3),(x,y+4,z+6.3),.55,'basalt')

    def barrel(self,x,y,z=0,r=3.8):
        self.cone((x,y,z+4),r*.85,r,8,'wood_light',10)
        for zz in (1.3,6.6):self.ring((x,y,z+zz),r,.45,'basalt',n=16)
        self.cone((x,y,z+8.2),r*.9,r*.9,.6,'wood',10)

    def cottage(self,x,y,w,d,h=28,roofh=23,entrance=True):
        self.wall((x,y,2),w,d,h)
        for xx in (x-w/2,x+w/2):
            for yy in (y-d/2,y+d/2):self.box((xx,yy,h/2+3),(3.5,3.5,h+4),'wood',.3)
        self.box((x,y-d/2-1,h),(w+3,2.5,3),'wood_light')
        self.roof(x,y,w+10,d+9,h+4,roofh)
        if entrance:self.door(x,y-d/2-2,3,min(13,w*.32),min(23,h*.84))
        for side in (-1,1):
            if w>35:self.window(x+side*w*.31,y-d/2-2,h*.61,5,9)
        self.window(x,y-d/2-5.5,h+roofh*.47,5,7)
        for dx in range(-int(w/2)+4,int(w/2),4):
            peak=roofh*(1-abs(dx)/(w/2))
            if peak>3:self.beam((x+dx,y-d/2-5,h+1),(x+dx,y-d/2-5,h+peak),.6,'wood_light')
        self.beam((x-w/2,y-d/2-5,h+3),(x,y-d/2-5,h+roofh),2.5,'wood_light')
        self.beam((x+w/2,y-d/2-5,h+3),(x,y-d/2-5,h+roofh),2.5,'wood_light')
        self.lantern(x-w*.27,y-d/2-4,h*.57)
        if entrance:self.steps(x,y-d/2-14,min(22,w*.55),count=3)

    def chimney(self,x,y,z=0,h=58):
        self.wall((x,y,z),9,9,h)
        self.box((x,y,z+h+1),(12,12,3),'limestone')
        self.box((x,y,z+h+2.8),(7,7,1.2),'shadow',0)

    def foliage(self,x,y,z,r=5):
        if r>8:
            for i in range(12):
                a=i*TAU/12;rr=r*(.25 if i%3==0 else .64)
                self.rock((x+math.cos(a)*rr,y+math.sin(a)*rr,z+r*(.15+.12*(i%3))),
                          (r*.78,r*.64,r*.46),'green' if i%3==0 else 'leaf')
            # Small overlapping leaf sprays break the crown into leafy edges.
            for i in range(36):
                a=i*2.39996;rr=r*math.sqrt((i+1)/36)
                xx=x+math.cos(a)*rr;yy=y+math.sin(a)*rr;zz=z+r*(.56-.18*rr/r)
                self.mesh([(xx-2,yy,zz),(xx,yy-1.4,zz+.4),(xx+2.7,yy,zz+.9),(xx,yy+1.4,zz+.4)],
                          [(0,1,2,3),(3,2,1,0)],'leaf' if i%3 else 'green')
            return
        for i in range(4):
            a=i*TAU/4;self.rock((x+math.cos(a)*r*.35,y+math.sin(a)*r*.35,z+r*.35),(r*1.2,r,r*.8),'green' if i%2 else 'leaf')

    def ivy(self,x,y,z,h=25):
        for i in range(max(2,int(h/4))):
            xx=x+math.sin(i*1.8)*1.5;zz=z+i*4
            self.beam((xx,y,zz),(x+math.sin((i+1)*1.8)*1.5,y,zz+4),.4,'wood')
            for side in (-1,1):self.rock((xx+side*1.4,y-.6,zz),(3,1.8,2.2),'green')

    def ground(self,r=52,count=24):
        for i in range(count):
            a=i*TAU/count;rr=r+self.rng.uniform(-2,2)
            x,y=rr*math.cos(a),rr*math.sin(a)
            if y< -r*.76 and abs(x)<14:continue
            self.rock((x,y,1.8),(self.rng.uniform(3,7),self.rng.uniform(3,6),4),'stone')
            if i%3==0:self.foliage(x,y,0,3.2)

    def tree(self,x,y,z=0,h=85):
        trunk=[(x,y,z),(x-3,y+1,z+h*.25),(x+2,y,z+h*.48),(x-2,y+1,z+h*.72)]
        for i in range(3):self.beam(trunk[i],trunk[i+1],5.8-i,'wood',True,4.8-i)
        for i in range(5):
            a=i*TAU/5;self.beam((x,y,z+14),(x+math.cos(a)*18,y+math.sin(a)*18,z+1),3.5,'wood',True,1)
        for i in range(7):
            a=i*TAU/7;end=(x+math.cos(a)*19,y+math.sin(a)*16,z+h*(.83+.11*(i%2)))
            self.beam(trunk[2],end,2.8,'wood',True,.9)
            self.foliage(*end,13)

    def tower(self,x,y,z=0,h=35,r=9,roof=True):
        self.roundwall((x,y,z),r,h,10)
        self.window(x,y-r-1,z+h*.61,4,9)
        if roof:self.hip((x,y,z+h+2),r+4,16,n=8)
        else:
            for i in range(5):
                a=i*TAU/5;self.box((x+math.cos(a)*r,y+math.sin(a)*r,z+h+4),(4,4,6),'limestone')

    def city(self,level):
        if level<=2:
            self.cottage(0,4,48,40,33,28)
            for side in (-1,1):self.cottage(side*34,7,24,30,23,15,False)
            self.chimney(-23,18,0,70)
            if level==2:
                self.roundwall((0,11,54),16,22,12);self.hip((0,11,77),23,24,n=8)
                self.flag(0,-6,75,8,17)
            for x in (-23,23):self.flag(x,-19,40,8,25)
        elif level<=4:
            r=32 if level==3 else 38
            self.roundwall((0,3,1),r,34,20)
            self.roundwall((0,5,34),24,25,16);self.hip((0,5,61),33,24,n=12)
            self.roundwall((0,7,79),12,15,12);self.hip((0,7,95),18,15,n=8)
            self.door(0,3-r-3,3,16,27);self.steps(0,-r-16,26,count=5)
            for x in (-31,31):
                self.tower(x,-15,h=40,r=8,roof=False);self.flag(x,-24,39,8,26)
            self.tree(-28,24,h=95)
            if level==4:
                self.tree(25,27,h=103)
                for x in (-42,42):
                    self.tower(x,17,h=47,r=7,roof=False)
                    self.flag(x,9,46,7,25)
                for side in (-1,1):
                    for i in range(5):self.box((side*(39-i*1.1),-17+i*8,15),(6,9,28),'stone')
            for x in (-16,16):self.flag(x,-r,32,8,21)
        else:
            self.roundwall((0,5,1),36,34,20)
            for x in (-32,32):self.cottage(x,8,24,30,32,18,False)
            self.door(0,-32,2,17,28);self.steps(0,-50,29,count=5)
            self.cone((0,8,38),26,26,7,'limestone',16)
            self.cone((0,8,43),16,18,6,'brass',12)
            self.crystal((0,8,47),13,52)
            for i in range(4):
                self.claw(math.pi/4+i*TAU/4)
            for i in range(12):
                a=i*TAU/12;self.cone((19*math.cos(a),8+19*math.sin(a),46),2.4,1,10,'brass',6)
            for x in (-40,40):self.tower(x,-20,h=42,r=7,roof=False);self.flag(x,-28,42,7,25,'sun')
            self.flag(0,-34,51,10,20,'sun')
        for x in (-17,17):
            self.cone((x,-41,8),3,2,15,'limestone',8);self.cone((x,-41,17),3,5,3,'brass',8)
            self.crystal((x,-41,19),2.5,6,'window')
        self.ivy(-26,-19,3,26);self.ground(55)

    def farm(self,level):
        if level==1:
            self.cottage(-24,-3,29,30,26,19)
            self.roundwall((15,13,1),23,32,14);self.hip((15,13,35),28,31,'wheat',14)
            for a in range(8):
                aa=a*TAU/8;self.beam((15+23*math.cos(aa),13+23*math.sin(aa),3),(15+23*math.cos(aa),13+23*math.sin(aa),34),2.5,'wood')
            self.box((15,-12,12),(15,8,17),'wood');self.box((15,-17,18),(13,3,5),'wheat')
            self.flag(15,-12,56,8,19)
        else:
            self.cottage(-9,9,46,42,31,27)
            self.chimney(-27,22,0,66)
            if level>=3:self.cottage(28,16,24,30,26,18)
            if level==2:self.cottage(-26,-17,23,20,18,14)
            if level>=3:
                self.roundwall((30,34,0),12,37,12);self.hip((30,34,39),16,16,'wheat',12)
            if level==4:
                self.roundwall((-26,2,0),15,62,14);self.hip((-26,2,64),20,17,n=10)
                center=Vector((-26,-15,53))
                rot=Vector((0,-1,0)).to_track_quat('Z','Y').to_matrix()
                self.cone(center,4,4,5,'brass',12,rot)
                for i in range(4):
                    a=math.pi/4+i*TAU/4;direction=Vector((math.cos(a),0,math.sin(a)));across=Vector((-math.sin(a),0,math.cos(a)))
                    self.beam(center+direction*4,center+direction*39,1.8,'wood_light')
                    p=[center+direction*r+across*q for r,q in [(10,-1),(37,-1),(37,8),(10,5)]]
                    self.mesh(p,[(0,1,2,3),(3,2,1,0)],'ivory')
                    for r in (10,22,37):self.beam(center+direction*r-across,center+direction*r+across*8,.8,'wood')
            if level==5:
                self.cottage(-35,8,23,32,28,23);self.roundwall((2,22,46),12,20,12);self.hip((2,22,68),17,21,n=10)
                self.flag(3,8,83,7,18)
        for side in (-1,1):
            bx=side*31;by=-32
            self.box((bx,by,2),(22,20,4),'earth',0)
            for yy in (-42,-22):self.beam((bx-12,yy,5),(bx+12,yy,5),1.5,'wood_light')
            for i in range(3):
                for j in range(3):self.foliage(bx-7+i*7,by-6+j*6,4,2.7)
            if level==5:
                for yy in (-40,-24):
                    self.beam((bx-11,yy,4),(bx-11,yy,16),.9,'brass');self.beam((bx+11,yy,4),(bx+11,yy,16),.9,'brass')
                    self.beam((bx-11,yy,16),(bx,yy,24),1,'brass');self.beam((bx+11,yy,16),(bx,yy,24),1,'brass')
                self.beam((bx,-41,24),(bx,-23,24),1,'brass')
                self.mesh([(bx-10,-40,16),(bx,-40,23),(bx,-24,23),(bx-10,-24,16)],[(0,1,2,3),(3,2,1,0)],'blue')
        for x in (-46,46):
            for y in (-43,-21,1):self.box((x,y,7),(3,3,14),'wood_light')
            for z in (6,11):self.beam((x,-43,z),(x,4,z),1.6,'wood')
        self.barrel(-13,-31);self.barrel(18,-18)
        self.ivy(-29,-13,2,27);self.ground(53,20)

    def portal(self,x,y,z=0,w=17,h=22,stone=False):
        self.box((x,y,z+h/2),(w,2,h),'shadow',0)
        if stone:
            for i in range(9):
                a=i*math.pi/8;radius=w*.56
                rot=Vector((math.cos(a),0,math.sin(a))).to_track_quat('Y','Z').to_matrix()
                self.box((x+math.cos(a)*radius,y-3,z+h-6+math.sin(a)*radius),(4,4.5,4.5),'limestone',.35,rot)
        for side in (-1,1):
            self.box((x+side*(w/2+1.7),y-2,z+h/2),(3.5,5,h+2),'limestone' if stone else 'wood_light')
            self.beam((x+side*w/2,y-4,z+h-7),(x+side*(w/2-5),y-4,z+h),2,'wood')
        self.box((x,y-3,z+h+1),(w+9,6,4),'limestone' if stone else 'wood_light')
        self.lantern(x+w/2+4,y-6,z+h-5)

    def tracks(self,x,y,z=0,length=28):
        for j in range(int(length/4)+1):self.box((x,y-j*4,z+1),(14,2,1.6),'wood',.15)
        for dx in (-4.5,4.5):self.beam((x+dx,y+2,z+2),(x+dx,y-length,z+2),.9,'basalt')

    def cart(self,x,y,z=0):
        self.box((x,y,z+5),(11,12,6),'wood',.3)
        for dx in (-5.6,5.6):
            self.box((x+dx,y,z+6),(1,13,7),'basalt',.15)
            for yy in (-4,4):self.cone((x+dx,y+yy,z+2),1.9,1.9,1.2,'basalt',10,Vector((1,0,0)).to_track_quat('Z','Y').to_matrix())
        for i in range(5):self.rock((x+self.rng.uniform(-4,4),y+self.rng.uniform(-4,4),z+9),(4,4,4),'gold')

    def platform(self,x,y,z,w=26,d=20):
        for i in range(int(w/3)):self.box((x-w/2+(i+.5)*3,y,z),(2.8,d,2),'wood_light',.1)
        for dx in (-w*.4,w*.4):
            self.beam((x+dx,y-d*.36,0),(x+dx,y-d*.36,z),2.5,'wood')
            self.beam((x+dx,y-d*.36,z-12),(x,y-d*.36,z),1.8,'wood_light')

    def winch(self,x,y,z,h=21):
        for dx in (-9,9):self.beam((x+dx,y,z),(x+dx,y,z+h),2.4,'wood_light')
        self.beam((x-11,y,z+h),(x+11,y,z+h),2.5,'wood')
        rot=Vector((1,0,0)).to_track_quat('Z','Y').to_matrix()
        self.cone((x,y,z+h),4,4,15,'wood',12,rot)
        for dx in (-7.7,7.7):
            self.ring((x+dx,y,z+h),7,.85,'brass',rot,n=20)
            for i in range(6):
                a=i*TAU/6;self.beam((x+dx,y,z+h),(x+dx,y+6*math.cos(a),z+h+6*math.sin(a)),.6,'brass')
        self.beam((x,y-4,z+h),(x,y-4,max(4,z-12)),.65,'wheat')
        self.box((x,y-4,max(4,z-12)),(8,8,7),'wood_light')

    def mountain(self,x,y,h,rx=25,ry=22):
        self.rock((x,y,h*.46),(rx*2,ry*2,h),'stone')
        for i in range(36):
            a=i*2.39996;zz=h*(.12+.19*(i%4));rr=1-zz/h*.58
            xx=x+math.cos(a)*rx*rr;yy=y+math.sin(a)*ry*rr
            self.rock((xx,yy,zz),(rx*.57,ry*.53,h*(.19+.07*(i%2))),'stone' if i%4 else 'limestone')
            if i%4==0:self.foliage(xx,yy,zz+h*.10,2.6)
        # Thin exposed mineral seams and smaller chipped ledges interrupt the
        # large rock facets, instead of a single smooth dark mountain core.
        for j in range(14):
            zz=5+j*h*.056;xx=x+math.sin(j*1.8)*3;yy=y-ry*(1-zz/h*.57)-4
            self.rock((xx,yy,zz),(3.8,3.5,h*.085),'gold')
            if j%2==0:
                for side in (-1,1):self.rock((xx+side*5.5,yy+1,zz-1),(7,6,6),'limestone' if j%4 else 'stone')

    def mine(self,level):
        if level==1:
            self.mountain(0,7,43,42,32);self.cart(-8,-33)
            self.beam((-29,-25,1),(-22,-23,23),1.4,'wood_light');self.beam((-29,-23,23),(-16,-23,23),1.4,'basalt')
        elif level in (2,3,5,6,9,10):
            self.mountain(-22,17,65+level*2,23,25);self.mountain(24,22,54+level*4,22,25)
            self.mountain(0,31,48+level*2,24,17)
            self.portal(-8,-20,0,stone=level>=9);self.tracks(-8,-23);self.cart(-8,-36)
            if level>=3:
                self.platform(25,-6,27);self.portal(25,1,28,14,20,level>=9)
                for i in range(8):self.box((35,-29+i*3,2+i*3.4),(9,4,3),'stone')
            if level>=5:
                self.platform(0,6,59,28,18);self.winch(0,7,60)
            if level==6:
                for xx in (-26,28):self.platform(xx,10,64,18,15);self.winch(xx,13,65,16)
                self.beam((-27,9,81),(28,9,81),.65,'wheat');self.beam((0,9,81),(0,9,65),.55,'wheat');self.box((0,9,61),(9,8,8),'wood')
            if level>=9:
                self.portal(25,-18,0,14,20,True);self.tracks(25,-20,0,24)
                self.flag(-29,-16,38,8,22,'sun');self.flag(28,-14,67,8,25,'sun')
            if level==10:
                self.portal(-24,-3,28,14,20,True);self.platform(-24,-9,26,24,16)
                self.portal(0,-5,54,15,22,True)
                for xx in (-22,22):self.tower(xx,-24,0,32,6,False)
        elif level==4:
            for i in range(3):
                self.mountain(-i*8,14+i*5,32+i*17,40-i*8,30-i*6)
                for j in range(6):self.box((25-i*17,-36+j*8,3+i*15+j*1.5),(12,8,3),'limestone')
            self.platform(27,-2,29);self.winch(27,-2,30,16);self.cart(-16,-34)
        elif level==7:
            self.mountain(0,10,74,34,29);self.portal(0,-24,0,20,23,True);self.tracks(0,-25)
            for i in range(40):
                a=i*TAU/40;xx=42*math.cos(a);yy=8+36*math.sin(a)
                rot=Vector((-math.sin(a),math.cos(a),0)).to_track_quat('Y','Z').to_matrix()
                self.box((xx,yy,34),(13,5.7,2),'wood_light',.15,rot)
                if i%5==0:self.beam((xx,yy,0),(xx,yy,34),2.5,'wood')
            for rr in (37,45):
                for i in range(48):
                    a=i*TAU/48;b=(i+1)*TAU/48
                    self.beam((rr*math.cos(a),8+rr*.86*math.sin(a),36),(rr*math.cos(b),8+rr*.86*math.sin(b),36),.7,'basalt')
            self.cart(0,-27,36);self.flag(35,-7,34,8,22,'sun')
        elif level==8:
            self.mountain(-26,15,94,21,28);self.mountain(27,20,86,21,26)
            self.box((0,18,20),(22,26,38),'shadow');self.platform(0,20,75,29,18);self.winch(0,19,76,17)
            self.portal(24,-24,0);self.tracks(24,-25,0,22)
            for i in range(12):self.box((-9,-35+i*4,i*3),(7,5,3),'stone')
            for xx in (-11,11):self.beam((xx,7,3),(xx,7,88),2.2,'wood_light')
        if level>1:self.flag(-27,-11,39,8,23,'sun')
        self.barrel(28,-32,0,3);self.ground(53,24)

    def laboratory(self,advanced=False):
        if not advanced:
            self.cottage(-14,5,49,43,38,40)
            self.flag(-14,-28,70,12,30)
            self.wall((34,15,0),22,26,34);self.portal(34,0,1,11,20,stone=True)
            self.box((34,-2,10),(9,1,15),'window');self.hip((34,15,36),19,12,n=4)
            self.chimney(35,19,40,16)
            self.cone((23,26,65),12,11,27,'teal',12)
            for zz in (52,76):self.ring((23,26,zz),12,1.5,'brass',n=24)
            self.cone((23,26,81),13,5,7,'brass',12)
            for dx in (-8,8):self.beam((23+dx,26,24),(23+dx,26,52),3,'wood')
            for a,b in [((34,26,69),(43,26,69)),((43,26,69),(47,26,64)),((47,26,64),(47,26,40))]:self.beam(a,b,2.2,'basalt',True)
            self.flag(24,12,74,8,18)
            self.box((26,-23,13),(35,18,3),'wood_light')
            for x in (11,40):
                for y in (-30,-17):self.beam((x,y,0),(x,y,14),2.5,'wood')
                self.beam((x,-16,1),(x,-16,36),2,'wood_light')
            self.mesh([(7,-14,39),(44,-14,39),(44,-32,30),(7,-32,30)],[(0,1,2,3),(3,2,1,0)],'teal')
            for x in (7,44):self.beam((x,-14,39),(x,-32,30),1.7,'wood_light')
            for i,mat in enumerate(('gold','green','blue')):
                xx=15+i*10;self.rock((xx,-24,19),(8,8,9),mat);self.cone((xx,-24,24),3,1.4,4,mat,10);self.cone((xx,-24,28),1.4,1.3,5,mat,8);self.ring((xx,-24,30),1.6,.4,'brass',n=12)
        else:
            self.roundwall((-13,6,1),23,68,16)
            for x in (-30,4):self.box((x,-11,30),(5,7,58),'limestone')
            for x in (-25,-1):self.window(x,-14,44,4,17)
            self.door(-13,-19,3,14,25);self.steps(-13,-35,24,count=4)
            self.cone((-13,6,72),29,29,6,'wood_light',16)
            for i in range(8):
                a=i*TAU/8
                if i not in (5,6):self.beam((-13+24*math.cos(a),6+24*math.sin(a),73),(-13+24*math.cos(a),6+24*math.sin(a),95),2.5,'wood')
            self.hip((-13,6,95),30,30,n=12,opening=True)
            self.cone((-13,6,82),7,4,15,'brass',12)
            center=(-13,6,101)
            for axis in ((0,-1,0),(.5,-.7,.6),(-.6,-.2,.8)):
                self.ring(center,17,1,'brass',Vector(axis).to_track_quat('Z','Y').to_matrix(),n=32)
            self.rock(center,(12,12,12),'gold')
            self.flag(-13,-23,70,10,31,'sun')
            self.cottage(28,4,30,38,29,21)
            self.chimney(39,18,0,59)
            self.beam((30,2,49),(30,2,58),2,'wood');self.beam((23,-6,61),(38,7,66),3.5,'brass',True)
            self.cone((22,-7,61),4,4,2,'blue',12,Vector((-1,-1,0)).to_track_quat('Z','Y').to_matrix())
            self.box((30,-28,14),(20,13,2),'wood_light');self.box((30,-28,16),(16,11,.6),'ivory',0)
            for xx in (23,37):self.beam((xx,-27,0),(xx,-27,14),1.8,'wood')
            self.flag(39,-18,33,7,20,'sun')
        self.ivy(-29 if advanced else -36,-12 if advanced else -17,3,34)
        self.barrel(2,-30);self.ground(53)

    def altar(self):
        for z,r in ((2,32),(6,27),(10,22)):self.cone((0,4,z),r,r,4,'limestone',12)
        self.cone((0,4,20),10,7,16,'stone',8)
        self.beam((0,4,26),(0,4,76),5,'ivory');self.beam((0,1,30),(0,1,74),.9,'brass')
        self.beam((-15,4,77),(15,4,77),4,'brass');self.beam((0,4,77),(0,4,92),3,'wood')
        self.crystal((0,4,92),4,9)
        for side in (-1,1):
            self.tower(side*34,18,0,43,7,True);self.flag(side*34,10,40,7,24)
            for i in range(5):self.beam((side*(6+i*3),14,38),(side*(23+i*5),14,77-i*8),3.5,'ivory')
            self.lantern(side*21,-18,15)
        self.steps(0,-31,27,count=4);self.ground(51)

    def challenge(self):
        for i in range(18):
            a=-.1+i*(math.pi+0.2)/17;x=43*math.cos(a);y=43*math.sin(a)
            self.wall((x,y,0),10,7,22)
            self.box((x,y,25),(6,8,6),'limestone')
        for x in (-31,31):
            self.tower(x,-26,0,40,10,False);self.flag(x,-38,40,10,25,'sun')
            self.cone((x,-26,48),11,11,2,'brass',10)
            self.crystal((x,-26,49),3,9,'window')
        self.wall((0,34,0),24,12,44)
        for side in (-1,1):
            self.beam((-side*16,26,40),(side*13,26,66),2.7,'ivory')
            self.beam((-side*19,26,37),(-side*14,26,42),2.2,'wood')
            self.beam((-side*19,26,45),(-side*11,26,37),2.2,'brass')
        for i in range(12):
            a=i*TAU/12;self.box((math.cos(a)*25,math.sin(a)*24,1),(8,5,2),'stone')
        self.ground(55)
