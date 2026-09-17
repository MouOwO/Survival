"""Grounded fantasy/industrial silhouettes, with no presentation plinths."""
import bpy
import math
from mathutils import Vector

def redesign(name,g):
    box,cone,beam,ring,mesh=[g[k] for k in ('box','cone','beam','ring','mesh')]
    parts=g['parts']
    def remove(o):parts.remove(o);bpy.data.objects.remove(o,do_unlink=True)
    def rock(c,s,seed=1):
        bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=2,radius=1,location=c)
        o=g['finish'](bpy.context.object,'Weathered footing','stone');o.scale=s
        for v in o.data.vertices:v.co*=1+.12*math.sin(v.co.x*21+v.co.y*17+seed)
        return o
    def pipe(points,r=2,mat='brass'):
        for a,b in zip(points,points[1:]):
            d=Vector(b)-Vector(a);o=cone('Forged conduit',(Vector(a)+Vector(b))/2,r,r,d.length,mat,10)
            o.rotation_euler=d.to_track_quat('Z','Y').to_euler()
    if 'research_lab' in name:
        for o in list(parts):remove(o)
        if name=='research_lab':
            # Broad asymmetrical workshop: squat roof, furnace stack, side retort.
            box('Workshop stone body',(-9,2,24),(76,64,45),'stone',3)
            for x,y in ((-40,-24),(22,-24),(-40,25),(22,25)):
                rock((x,y,5),(12,11,7),int(x+y))
                beam('Iron corner brace',(x,y,7),(x,y,41),5,'basalt')
            g['roof'](-9,2,86,74,43,16,'slate')
            for side in (-1,1):
                for i in range(6):
                    yy=-30+i*12
                    beam('Roof standing seam',(-9+side*43,yy,44),(-9,yy,60),1.7,'basalt')
            box('Recessed workshop door',(-11,-31,18),(24,2,32),'shadow',1)
            for i in range(5):box('Door iron slat',(-21+i*5,-33,18),(4.4,2,29),'wood',.25)
            for z in (9,27):box('Forged hinge bar',(-11,-35,z),(27,2,3),'basalt')
            for x in (-31,9):
                box('Inset amber window',(x,-31,31),(12,3,10),'basalt')
                box('Workshop amber glass',(x,-33,31),(9,1,7),'gold',.2)
                for zz in (29,32):beam('Window grate',(x-5,-34,zz),(x+5,-34,zz),.7,'basalt')
            # Retort and exhaust are larger silhouette cues, not roof trinkets.
            cone('Alchemical retort',(39,8,23),17,15,39,'brass',16)
            cone('Retort shoulder',(39,8,46),15,7,9,'basalt',16)
            for z in (9,23,38):ring('Retort riveted band',(39,8,z),16,1.4,'basalt')
            for i in range(8):
                a=i*math.tau/8;beam('Retort plate rib',(39+15*math.cos(a),8+15*math.sin(a),10),(39+14*math.cos(a),8+14*math.sin(a),39),1,'brass')
            pipe([(39,8,50),(39,8,62),(15,8,62),(15,8,47)],3)
            box('Forge chimney',(-33,17,64),(14,16,37),'basalt',1)
            for z in (49,60,72,82):box('Chimney collar',(-33,17,z),(17,19,3),'stone',.7)
            box('Soot dark opening',(-33,17,84),(11,13,1),'shadow',.3)
            box('Front workbench',(23,-30,13),(27,18,5),'wood',1)
            for x in (14,32):beam('Workbench leg',(x,-30,1),(x,-30,12),3,'basalt')
            g['crystal']((21,-30,16),4,10,'blue')
            for y in (-37,-24):cone('Reagent vessel',(33,y,19),3,2,8,'brass',10)
            for i in range(5):beam('Rear ventilation slat',(-25+i*9,35,24),(-25+i*9,35,36),2,'basalt')
            for i in range(3):box('Threshold stone',(-11,-37-i*5,2),(29-i*2,7,4),'stone',1)
        else:
            # Three radial buttresses embracing an exposed energy core.
            cone('Core housing',(0,0,14),29,25,26,'basalt',12)
            cone('Core upper socket',(0,0,30),27,15,9,'brass',12)
            g['crystal']((0,0,34),13,48,'blue')
            ring('Reactor collar',(0,0,31),22,2,'basalt')
            for i in range(3):
                a=-math.pi/2+i*math.tau/3
                def p(r,z,t=0):return (r*math.cos(a)-t*math.sin(a),r*math.sin(a)+t*math.cos(a),z)
                rock(p(38,6),(15,15,8),i)
                # Tapered curved pylon carved from massive stone plates.
                levels=[(43,3,12),(40,24,11),(34,49,8),(25,75,5),(17,96,1)]
                v=[]
                for r,z,w in levels:
                    for dr,t in ((-5,-w),(5,-w),(5,w),(-5,w)):v.append(p(r+dr,z,t))
                faces=[(3,2,1,0),(16,17,18,19)]
                for k in range(4):
                    for j in range(4):faces.append((k*4+j,k*4+(j+1)%4,(k+1)*4+(j+1)%4,(k+1)*4+j))
                mesh('Arched reactor pylon',v,faces,'stone')
                pipe([p(36,14),p(30,44),p(21,70),p(16,88)],1.8,'brass')
                pipe([p(34,22,-5),p(28,45,-4),p(22,66,-2)],1.1,'blue')
                for z,r in ((14,41),(33,38),(54,32)):
                    beam('Pylon engraved cuff',p(r-6,z,-10 if z<40 else -6),p(r-6,z,10 if z<40 else 6),2,'basalt')
                box('Core vent',p(20,16),(8,8,14),'shadow',.7)
            ring('Floating containment hoop',(0,0,64),19,1.5,'brass')
            for i in range(8):
                a=i*math.tau/8
                beam('Socket ribs',(26*math.cos(a),26*math.sin(a),8),(23*math.cos(a),23*math.sin(a),27),2,'stone')
    else:
        # Delete all exhibition/platform surfaces, retaining functional altar steps.
        prefixes=('Foundation','Paving','Entrance step','Cut foundation paver','Arena floor','Arena boundary','Arena inlay','Radial stone joint')
        for o in list(parts):
            if o.name.startswith(prefixes):remove(o)
        # Remove colorful toy-like decoration while retaining functional identities.
        if name=='gold_mine':
            for o in list(parts):
                if o.name.startswith('Crystal'):
                    for v in o.data.vertices:v.co.z*=.55
        if name=='population_farm':
            for o in parts:
                if o.name.startswith('Overlapping roof shingle'):
                    o.rotation_euler.z+=.008*math.sin(o.location.y)
            for x,y in ((-40,-12),(5,-12),(-40,43),(5,43)):
                rock((x,y,8),(9,8,5),int(x+y))
        if name=='hero_altar':
            # Compact sacred dais belongs to the altar itself, not a full footprint disc.
            for o in parts:
                if o.name.startswith('Altar step'):o.scale.x*=.85;o.scale.y*=.85
            for x in (-37,37):rock((x,24,10),(11,12,8),int(x))
        if name=='challenge_arena':
            for x in (-33,33):rock((x,-33,10),(14,13,8),int(x))
        # Settle the architecture onto natural ground after removing its 8-unit plinth.
        for o in parts:o.location.z-=8
    # Flatten only ground-contact vertices. Raising the whole mesh to its lowest
    # decorative rock would leave the walls, sacks and posts floating above terrain.
    bpy.context.view_layer.update()
    for o in parts:
        inv=o.matrix_world.inverted()
        for v in o.data.vertices:
            world=o.matrix_world@v.co
            if world.z<=1.5:
                world.z=0
                v.co=inv@world
