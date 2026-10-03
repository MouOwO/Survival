"""Blender authoring: fantasy castle town hall, composed after the user's reference.

Original geometry and an original eight-point star sigil (no Warcraft/Alliance
emblems). Composition follows the reference: sandstone ashlar curtain walls with
battlements, round towers under royal-blue conical roofs with gold bands and
flags, a clustered central keep with a tall spire, a square clock tower at the
rear right, a round-arched gatehouse, braziers and a grand stone staircase.
Run: blender -b --factory-startup --python tools/build_townhall_homage.py [-- --preview-only]
"""
import bpy, math, random, sys, json
from pathlib import Path
from mathutils import Vector
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tools'))
import unique_building_bake as baking
from unique_building_detail import project_uv
OUT=ROOT/'output/townhall_castle_20260930'
MODELS=OUT/'source/models/survival_buildings';MATS=OUT/'source/materials/survival_buildings'
for p in [MODELS,MATS,OUT/'previews']:p.mkdir(parents=True,exist_ok=True)
NAME='main_base_townhall_v1'
random.seed(20260930)
bpy.ops.wm.read_factory_settings(use_empty=True)
scene=bpy.context.scene
objects=[]
Z=Vector((0,0,1))

def material(name,colors,rough=.8,metal=0,scale=.4,bump=.08,emit=0):
 m=bpy.data.materials.new(name);m.use_nodes=True;n=m.node_tree.nodes;l=m.node_tree.links;bs=n.get('Principled BSDF')
 bs.inputs['Roughness'].default_value=rough;bs.inputs['Metallic'].default_value=metal
 geo=n.new('ShaderNodeNewGeometry');noise=n.new('ShaderNodeTexNoise');noise.inputs['Scale'].default_value=scale;noise.inputs['Detail'].default_value=5;l.new(geo.outputs['Position'],noise.inputs['Vector'])
 ramp=n.new('ShaderNodeValToRGB');ramp.color_ramp.elements.remove(ramp.color_ramp.elements[1])
 for i,c in enumerate(colors):
  e=ramp.color_ramp.elements[0] if i==0 else ramp.color_ramp.elements.new(i/(len(colors)-1));e.position=i/(len(colors)-1);e.color=(*c,1)
 l.new(noise.outputs['Fac'],ramp.inputs['Fac']);l.new(ramp.outputs['Color'],bs.inputs['Base Color'])
 fine=n.new('ShaderNodeTexNoise');fine.inputs['Scale'].default_value=6;fine.inputs['Detail'].default_value=3;l.new(geo.outputs['Position'],fine.inputs['Vector'])
 b=n.new('ShaderNodeBump');b.inputs['Strength'].default_value=.45;b.inputs['Distance'].default_value=bump;l.new(fine.outputs['Fac'],b.inputs['Height']);l.new(b.outputs['Normal'],bs.inputs['Normal'])
 if emit:
  bs.inputs['Emission Color'].default_value=(*colors[-1],1);bs.inputs['Emission Strength'].default_value=emit
 return m
def brick(name,c1,c2,mortar,bw,rh,rough=.85,metal=0,msize=.1,bump=.12):
 """Block-coursed masonry or shingles. Horizontal coord = x+y so every wall face gets courses."""
 m=bpy.data.materials.new(name);m.use_nodes=True;n=m.node_tree.nodes;l=m.node_tree.links;bs=n.get('Principled BSDF')
 bs.inputs['Roughness'].default_value=rough;bs.inputs['Metallic'].default_value=metal
 geo=n.new('ShaderNodeNewGeometry');sep=n.new('ShaderNodeSeparateXYZ');l.new(geo.outputs['Position'],sep.inputs[0])
 add=n.new('ShaderNodeMath');add.operation='ADD';l.new(sep.outputs['X'],add.inputs[0]);l.new(sep.outputs['Y'],add.inputs[1])
 comb=n.new('ShaderNodeCombineXYZ');l.new(add.outputs[0],comb.inputs['X']);l.new(sep.outputs['Z'],comb.inputs['Y'])
 br=n.new('ShaderNodeTexBrick');br.offset=.5
 br.inputs['Scale'].default_value=1;br.inputs['Brick Width'].default_value=bw;br.inputs['Row Height'].default_value=rh
 br.inputs['Mortar Size'].default_value=msize;br.inputs['Color1'].default_value=(*c1,1);br.inputs['Color2'].default_value=(*c2,1);br.inputs['Mortar'].default_value=(*mortar,1)
 l.new(comb.outputs[0],br.inputs['Vector'])
 noise=n.new('ShaderNodeTexNoise');noise.inputs['Scale'].default_value=.35;noise.inputs['Detail'].default_value=6;l.new(geo.outputs['Position'],noise.inputs['Vector'])
 ramp=n.new('ShaderNodeValToRGB');ramp.color_ramp.elements[0].color=(.72,.72,.72,1);ramp.color_ramp.elements[1].color=(1,1,1,1)
 l.new(noise.outputs['Fac'],ramp.inputs['Fac'])
 mix=n.new('ShaderNodeMixRGB');mix.blend_type='MULTIPLY';mix.inputs['Fac'].default_value=1
 l.new(br.outputs['Color'],mix.inputs['Color1']);l.new(ramp.outputs['Color'],mix.inputs['Color2']);l.new(mix.outputs['Color'],bs.inputs['Base Color'])
 b=n.new('ShaderNodeBump');b.invert=True;b.inputs['Strength'].default_value=.6;b.inputs['Distance'].default_value=bump
 l.new(br.outputs['Fac'],b.inputs['Height']);l.new(b.outputs['Normal'],bs.inputs['Normal'])
 return m
mats={
 'stone':brick('sandstone ashlar',(.36,.31,.23),(.52,.46,.35),(.15,.13,.1),2.6,1.3),
 'plinth':brick('grey foundation blocks',(.2,.19,.17),(.31,.29,.26),(.09,.085,.08),3.4,1.7),
 'roof':brick('royal blue slate shingles',(.025,.05,.26),(.06,.12,.44),(.008,.015,.07),1.4,.8,.5,.05,.07,.1),
 'trim':material('pale dressed limestone',[(.4,.36,.28),(.56,.51,.41),(.66,.61,.5)],.85,0,.5,.06),
 'gold':material('polished gold',[(.32,.2,.05),(.62,.45,.15),(.86,.7,.35)],.28,.9,.6,.02),
 'iron':material('blackened iron',[(.018,.018,.02),(.055,.055,.06),(.12,.12,.13)],.5,.75,.5,.02),
 'wood':material('dark oak',[(.04,.022,.012),(.1,.06,.03),(.17,.105,.055)],.8,0,.9,.05),
 'dark':material('shadowed openings',[(.008,.01,.012),(.03,.032,.036)],.95),
 'ivory':material('clock dial',[(.62,.56,.42),(.8,.74,.6)],.55,0,.4,.01),
 'cloth':material('royal blue cloth',[(.02,.045,.22),(.05,.1,.38)],.9,0,.8,.03),
 'fire':material('brazier flame',[(.9,.35,.05),(1,.72,.25)],.4,0,.9,.01,emit=6),
}
def finish(o,key,bevel=0,smooth=False):
 o.data.materials.append(mats[key]);objects.append(o)
 if smooth:
  for f in o.data.polygons:f.use_smooth=True
 if bevel:
  mod=o.modifiers.new('bevel','BEVEL');mod.width=bevel;mod.segments=2
  bpy.context.view_layer.objects.active=o;bpy.ops.object.modifier_apply(modifier=mod.name)
 return o
def mesh(name,verts,faces,key,bevel=0):
 me=bpy.data.meshes.new(name);me.from_pydata(verts,[],faces);me.update();o=bpy.data.objects.new(name,me);scene.collection.objects.link(o);return finish(o,key,bevel)
def box(name,loc,size,key='stone',bevel=.35,rz=0):
 bpy.ops.mesh.primitive_cube_add(size=1,location=loc);o=bpy.context.object;o.name=name;o.dimensions=size;o.rotation_euler.z=rz
 bpy.ops.object.transform_apply(location=False,rotation=True,scale=True);return finish(o,key,bevel)
def taper(name,loc,bottom,top,height,key='stone',bevel=.4):
 x,y,z=loc;v=[]
 for d,dz in [(bottom,0),(top,height)]:
  for a,b in [(-1,-1),(1,-1),(1,1),(-1,1)]:v.append((x+a*d[0]/2,y+b*d[1]/2,z+dz))
 return mesh(name,v,[(3,2,1,0),(4,5,6,7),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7)],key,bevel)
def gable(name,loc,length,width,height,key='roof',bevel=.3):
 """Gabled roof prism, ridge along Y."""
 x,y,z=loc;L,W=length/2,width/2
 v=[(x-W,y-L,z),(x-W,y+L,z),(x+W,y+L,z),(x+W,y-L,z),(x,y-L,z+height),(x,y+L,z+height)]
 return mesh(name,v,[(3,2,1,0),(0,1,5,4),(2,3,4,5),(0,4,3),(1,2,5)],key,bevel)
def gable_wall(name,y0,y1,half,z0,apex,key='stone'):
 v=[(-half,y0,z0),(half,y0,z0),(0,y0,apex),(-half,y1,z0),(half,y1,z0),(0,y1,apex)]
 return mesh(name,v,[(0,1,2),(5,4,3),(0,3,4,1),(1,4,5,2),(2,5,3,0)],key,.3)
def cyl(name,loc,r,depth,key='stone',verts=24,r2=None,rot=None):
 bpy.ops.mesh.primitive_cone_add(vertices=verts,radius1=r,radius2=r if r2 is None else r2,depth=depth,location=loc);o=bpy.context.object;o.name=name
 if rot:o.rotation_euler=rot;bpy.ops.object.transform_apply(location=False,rotation=True,scale=False)
 return finish(o,key,smooth=verts>=12)
def ring(name,loc,major,minor,rot=(0,0,0),key='gold'):
 bpy.ops.mesh.primitive_torus_add(major_radius=major,minor_radius=minor,major_segments=32,minor_segments=6,location=loc,rotation=rot)
 o=bpy.context.object;o.name=name;return finish(o,key,smooth=True)
def beam(name,a,b,t,key='trim'):
 a,b=Vector(a),Vector(b);d=b-a
 bpy.ops.mesh.primitive_cube_add(size=1,location=(a+b)/2);o=bpy.context.object;o.name=name;o.scale=(t,t,d.length)
 o.rotation_euler=d.to_track_quat('Z','Y').to_euler();bpy.ops.object.transform_apply(location=False,rotation=True,scale=True);return finish(o,key)
def arch(name,x,y,z,w,h,key='dark',depth=.8,axis='y'):
 """Round-headed opening: rectangle plus a half-disc crown."""
 rh=max(.1,h-w/2)
 box(name,(x,y,z+rh/2),(w,depth,rh) if axis=='y' else (depth,w,rh),key,0)
 cyl(name+' crown',(x,y,z+rh),w/2,depth,key,16,rot=(math.pi/2,0,0) if axis=='y' else (0,math.pi/2,0))
def star(c,R,r,n,depth,key='gold'):
 """Original n-point star sigil facing -Y."""
 x,y,z=c;pts=[(math.cos(math.pi/2+i*math.pi/n)*(R if i%2==0 else r),math.sin(math.pi/2+i*math.pi/n)*(R if i%2==0 else r)) for i in range(2*n)]
 v=[(x,y-depth,z),(x,y,z)]+[(x+u,y-depth,z+w) for u,w in pts]+[(x+u,y,z+w) for u,w in pts];m=len(pts);f=[]
 for i in range(m):
  j=(i+1)%m;f+=[(0,2+i,2+j),(1,2+m+j,2+m+i),(2+i,2+m+i,2+m+j,2+j)]
 return mesh('star sigil',v,f,key)
def finial(loc,h=9):
 x,y,z=loc
 cyl('gold finial stem',(x,y,z+h*.35),.7,h*.7,'gold',8)
 bpy.ops.mesh.primitive_uv_sphere_add(segments=12,ring_count=6,radius=1.5,location=(x,y,z+h*.62));finish(bpy.context.object,'gold',smooth=True)
 cyl('gold finial spike',(x,y,z+h*.9),.85,h*.5,'gold',8,r2=.05)
def flag(x,y,z,size=1):
 beam('flag pole',(x,y,z-2),(x,y,z+8*size),.4,'gold')
 box('flag cloth',(x+3.6*size,y,z+6*size),(6.6*size,.25,3.8*size),'cloth',.05)
 star((x+3.6*size,y-.15,z+6*size),1.2*size,.5*size,5,.2)
def banner(x,y,ztop,h,w):
 box('hanging banner',(x,y,ztop-h/2),(w,.35,h),'cloth',.05)
 beam('banner rod',(x-w/2-.6,y,ztop),(x+w/2+.6,y,ztop),.5,'gold')
 box('banner hem',(x,y-.05,ztop-h+.5),(w,.4,1),'gold',.05)
 star((x,y-.2,ztop-h*.42),w*.34,w*.14,8,.25)
def brazier(x,y,z):
 cyl('brazier bowl',(x,y,z+.8),1.0,1.6,'iron',14,r2=2.1)
 ring('brazier rim',(x,y,z+1.6),2.1,.25)
 cyl('brazier flame',(x,y,z+3.2),1.6,3.2,'fire',10,r2=.12)
 cyl('brazier flame tip',(x+.5,y-.3,z+4.2),.8,2.4,'fire',8,r2=.05)
def crenels(x0,y0,x1,y1,z,step=3.2):
 L=math.hypot(x1-x0,y1-y0);n=max(1,int(L/step));along_x=abs(x1-x0)>=abs(y1-y0)
 for i in range(n+1):
  t=i/n;box('merlon',(x0+(x1-x0)*t,y0+(y1-y0)*t,z),(1.9,1.3,2.4) if along_x else (1.3,1.9,2.4),'trim',.1)
def round_tower(x,y,r,z0,top,roof_h,merl=12,has_flag=False,banner_at=None,windows=(),corbel=False):
 if corbel:cyl('turret corbel',(x,y,z0-2.5),.6,5,'trim',20,r2=r)
 cyl('round tower',(x,y,(z0+top)/2),r,top-z0,'stone',28)
 if not corbel:cyl('tower base course',(x,y,z0+1),r+.6,2,'trim',28)
 cyl('tower string course',(x,y,z0+(top-z0)*.55),r+.35,1.1,'trim',28)
 cyl('machicolation corbel',(x,y,top+.9),r,1.8,'trim',28,r2=r+1.3)
 cyl('machicolation ring',(x,y,top+2.8),r+1.3,2,'trim',28)
 for i in range(merl):
  a=math.tau*i/merl;box('merlon',(x+(r+.6)*math.cos(a),y+(r+.6)*math.sin(a),top+5),(1.3,1.9,2.4),'trim',.1,a)
 cyl('roof drum',(x,y,top+5),r-.3,4,'stone',28)
 zr=top+7
 cyl('conical blue roof',(x,y,zr+roof_h/2),r+2.2,roof_h,'roof',28,r2=.35)
 ring('roof gold band',(x,y,zr+.3),r+2.1,.45)
 finial((x,y,zr+roof_h-.5),max(6,r))
 if has_flag:flag(x,y,zr+roof_h+max(6,r)*.9)
 for wz in windows:arch('tower window',x,y-r-.05,wz,2.4,5,'dark',1.2)
 if banner_at:banner(x,y-r-.35,*banner_at)

# ---- Foundation terrace and grand stone staircase (front faces -Y) ----
taper('foundation terrace',(0,4,0),(112,84),(108,80),8,'plinth',.8)
box('terrace coping',(0,4,7.6),(109,81,.8),'trim',.2)
for i in range(6):
 z0=i*8/6;yf=-58+i*20/6;depth=-38-yf;yc=(yf-38)/2;x=-11.0
 while x<10.9:
  w=min(random.uniform(4.5,7.5),11-x)
  box('worn stone stair slab',(x+w/2,yc+random.uniform(-.1,.1),z0+.67+random.uniform(-.06,.06)),(w-.25,depth-.2,1.34),'trim',.22,random.uniform(-.008,.008))
  x+=w
for s in [-1,1]:
 x0,x1=s*11.2,s*14.6;pts=[(-58,0),(-38,0),(-38,11),(-58,3.4)]
 v=[(x0,y,z) for y,z in pts]+[(x1,y,z) for y,z in pts]
 mesh('stair cheek wall',v,[(0,1,2,3),(7,6,5,4),(0,4,5,1),(1,5,6,2),(2,6,7,3),(3,7,4,0)],'stone',.3)
 box('stair newel post',(s*12.9,-56.6,2.6),(4.4,4.4,5.2),'trim',.3)
 box('newel cap',(s*12.9,-56.6,5.6),(5.2,5.2,.8),'trim',.2)
 brazier(s*12.9,-56.6,6)
 cyl('gate brazier pedestal',(s*15.8,-37.4,10),1.4,4,'trim',14)
 brazier(s*15.8,-37.4,12)

# ---- Battlemented curtain walls ----
W0,WT=8,32
for s in [-1,1]:
 box('front curtain wall',(s*23.75,-30,20),(23.5,4,24))
 box('front wall coping',(s*23.75,-30,32.5),(24,4.6,1),'trim',.15)
 crenels(s*13,-31.7,s*35,-31.7,34.2)
box('left curtain wall',(-44,5.75,20),(4,54.5,24));box('left wall coping',(-44,5.75,32.5),(4.6,55,1),'trim',.15);crenels(-45.7,-21,-45.7,32.5,34.2)
box('right curtain wall',(44,1.25,20),(4,45.5,24));box('right wall coping',(44,1.25,32.5),(4.6,46,1),'trim',.15);crenels(45.7,-21,45.7,23.5,34.2)
box('rear curtain wall',(-4.5,40,20),(65,4,24));box('rear wall coping',(-4.5,40,32.5),(65.5,4.6,1),'trim',.15);crenels(-36.5,41.7,27.5,41.7,34.2)

# ---- Round corner towers ----
for s in [-1,1]:round_tower(s*44,-30,8.5,8,46,22,12,True,(42,16,5.5),(24,36))
round_tower(-44,40,7,8,42,18,12,True,None,(30,))

# ---- Gatehouse with round-arched gate and sigil ----
box('gatehouse',(0,-30,25),(24,10,34))
box('gatehouse coping',(0,-30,42.5),(24.6,10.6,1),'trim',.15)
crenels(-11,-35.7,11,-35.7,44.2);crenels(-11,-24.3,11,-24.3,44.2)
arch('gate stone frame',0,-35.2,8,15.5,21.5,'trim',.8)
arch('gate opening',0,-35.5,8,12,18,'dark',.8)
for s in [-1,1]:
 box('oak gate leaf',(s*2.95,-36.05,14),(5.7,.6,12),'wood',.12)
 for z in [10.5,14,17.5]:box('iron gate strap',(s*2.95,-36.4,z),(5.2,.3,.7),'iron',.05)
 round_tower(s*12,-35,3.6,8,48,12,8,True,(44,11,3.6),(30,))
cyl('gate sigil roundel',(0,-35.3,32),4.2,.8,'trim',28,rot=(math.pi/2,0,0))
ring('gate sigil ring',(0,-35.75,32),4.2,.35,(math.pi/2,0,0))
star((0,-35.75,32),3.3,1.4,8,.35)

# ---- Central keep: gabled hall, clustered turrets and a tall spire ----
box('keep hall',(0,10,31),(38,34,46))
box('keep base course',(0,10,9),(39.4,35.4,2),'trim',.2)
box('keep string course',(0,10,44),(38.8,34.8,1),'trim',.15)
for x in [-10,10]:arch('keep window',x,-7.1,24,4,9,'dark',.8)
for y in [3,17]:arch('keep side window',19.1,y,26,4,9,'dark',.8,'x')
gable('keep blue roof',(0,10,54),36,41,17,'roof')
beam('keep gold ridge',(0,-8,71.2),(0,28,71.2),1,'gold')
gable_wall('keep facade gable',-8.6,-7,20,54,72)
for sgn in [-1,1]:beam('gable coping',(sgn*20.2,-8.9,54.4),(0,-8.9,72.4),1.4)
cyl('keep sigil roundel',(0,-8.9,61),4,.8,'trim',28,rot=(math.pi/2,0,0))
star((0,-9.3,61),3.1,1.3,8,.35)
for s in [-1,1]:banner(s*6,-7.3,52,12,4)
for s in [-1,1]:
 round_tower(s*19,-7,3.4,36,66,13,8,False,None,(),True)
 round_tower(s*19,27,3.2,38,62,12,8,False,None,(),True)
 round_tower(s*9.8,4.6,2.6,60,84,11,6,False,None,(),True)
box('central tower',(0,12,72),(15,15,36))
box('central tower band',(0,12,76),(15.8,15.8,1),'trim',.15)
arch('central tower window',0,4.4,78,3,7,'dark',.8)
arch('central tower side window',7.6,12,78,3,7,'dark',.8,'x')
box('central machicolation',(0,12,91.5),(17,17,3),'trim',.25)
for e in [-8.3,8.3]:crenels(-8.3,12+e,8.3,12+e,94.2,3.3);crenels(e,3.7,e,20.3,94.2,3.3)
cyl('central spire drum',(0,12,95),7,4,'stone',8,rot=(0,0,math.pi/8))
cyl('central gold band',(0,12,97.4),10.4,.8,'gold',8,rot=(0,0,math.pi/8))
cyl('central blue spire',(0,12,111),10.2,28,'roof',8,r2=.3,rot=(0,0,math.pi/8))
finial((0,12,124.5),12);flag(0,12,137,1.3)

# ---- Square clock tower, rear right ----
box('clock tower',(36,32,50),(16,16,84))
for z in [30,50,66]:box('clock tower band',(36,32,z),(16.8,16.8,1.1),'trim',.15)
for z in [34,54]:
 arch('clock tower window',36,23.9,z,3,7,'dark',.8)
 arch('clock tower side window',44.1,32,z,3,7,'dark',.8,'x')
def clock(c,n,r=6.2):
 c,n=Vector(c),Vector(n).normalized();u=(-n).cross(Z).normalized();rot=n.to_track_quat('Z','Y').to_euler()
 cyl('clock dial',c+n*.4,r,.8,'ivory',32,rot=rot)
 ring('clock gold rim',c+n*.85,r+.35,.7,rot)
 ring('clock inner ring',c+n*.85,r*.62,.2,rot,'iron')
 for i in range(12):
  a=math.tau*i/12;d=u*math.cos(a)+Z*math.sin(a);length=1.5 if i%3==0 else .9
  beam('clock hour marker',c+n*.95+d*(r-.9-length),c+n*.95+d*(r-.9),.5 if i%3==0 else .34,'iron')
 for ang,length,t in [(150,.52,.7),(30,.8,.45)]:
  a=math.radians(ang);d=u*math.cos(a)+Z*math.sin(a)
  beam('clock hand',c+n*1.15-d*.9,c+n*1.15+d*r*length,t,'iron')
 cyl('clock hub',c+n*1.2,.8,.6,'gold',12,rot=rot)
box('clock frame front',(36,23.8,79),(14.6,.6,14.6),'trim',.2);clock((36,23.5,79),(0,-1,0))
box('clock frame side',(44.2,32,79),(.6,14.6,14.6),'trim',.2);clock((44.5,32,79),(1,0,0))
banner(36,23.6,70,14,6)
box('clock machicolation',(36,32,93.5),(18.4,18.4,3),'trim',.25)
for e in [-8.9,8.9]:crenels(27.1,32+e,44.9,32+e,96.2,3.4);crenels(36+e,23.1,36+e,40.9,96.2,3.4)
box('clock roof drum',(36,32,97),(15,15,4),'stone',.3)
taper('clock tower blue roof',(36,32,99),(18.6,18.6),(.4,.4),24,'roof',.2)
box('clock roof gold band',(36,32,99.4),(18.8,18.8,.7),'gold',.1)
finial((36,32,122.6),10);flag(36,32,133)

print('GEOMETRY',len(objects),'parts',flush=True)
bpy.ops.object.select_all(action='DESELECT')
for o in objects:o.select_set(True)
bpy.context.view_layer.objects.active=objects[0];bpy.ops.object.join();o=bpy.context.object;o.name=NAME
bpy.ops.object.transform_apply(location=False,rotation=True,scale=True)
bpy.context.scene.cursor.location=(0,0,0);bpy.ops.object.origin_set(type='ORIGIN_CURSOR')
# Same 236-unit footprint as the existing five main-city models; gameplay grid unchanged.
bounds=[v.co for v in o.data.vertices]
width=max(max(v.x for v in bounds)-min(v.x for v in bounds),max(v.y for v in bounds)-min(v.y for v in bounds));scale=236/width
cy=(max(v.y for v in bounds)+min(v.y for v in bounds))/2
for v in o.data.vertices:v.co=Vector((v.co.x*scale,(v.co.y-cy)*scale,v.co.z*scale))
bpy.ops.object.mode_set(mode='EDIT');bpy.ops.mesh.select_all(action='SELECT');bpy.ops.mesh.normals_make_consistent(inside=False);bpy.ops.object.mode_set(mode='OBJECT')
project_uv(o)
mod=o.modifiers.new('Runtime triangles','TRIANGULATE');bpy.ops.object.modifier_apply(modifier=mod.name)
coords=[v.co for v in o.data.vertices];height=max(v.z for v in coords)

scene.world=bpy.data.worlds.new('Soft daylight');scene.world.use_nodes=True
scene.world.node_tree.nodes['Background'].inputs[0].default_value=(.7,.75,.8,1);scene.world.node_tree.nodes['Background'].inputs[1].default_value=.6
bpy.ops.object.camera_add(location=(365,-520,420));camera=bpy.context.object
camera.rotation_euler=(Vector((0,0,height*.4))-camera.location).to_track_quat('-Z','Y').to_euler();camera.data.type='ORTHO';camera.data.ortho_scale=max(height,236)*1.25;scene.camera=camera
for loc,power,size in [((-260,-330,500),4800000,300),((330,-50,250),2300000,250),((20,350,400),3000000,220)]:
 bpy.ops.object.light_add(type='AREA',location=loc);light=bpy.context.object;light.data.energy=power;light.data.shape='DISK';light.data.size=size;light.rotation_euler=(-light.location).to_track_quat('-Z','Y').to_euler()
bpy.ops.mesh.primitive_plane_add(size=2000,location=(0,0,-.3));floor=bpy.context.object;floor.name='preview_floor'
fm=bpy.data.materials.new('preview_grass');fm.diffuse_color=(.09,.16,.05,1);floor.data.materials.append(fm)
scene.render.engine='CYCLES';scene.cycles.samples=32;scene.render.resolution_x=1200;scene.render.resolution_y=1100;scene.render.resolution_percentage=100
scene.render.image_settings.file_format='PNG';scene.view_settings.view_transform='AgX'
scene.render.filepath=str(OUT/'previews/geometry.png');bpy.ops.render.render(write_still=True)
camera.location=(0,-620,height*.45);camera.rotation_euler=(math.pi/2,0,0)
scene.render.filepath=str(OUT/'previews/front.png');bpy.ops.render.render(write_still=True)
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'authoring.blend'))
(OUT/'preview_stats.json').write_text(json.dumps({'triangles':len(o.data.polygons),'vertices':len(o.data.vertices),'dimensions':list(o.dimensions),'min_z':min(v.z for v in coords)},indent=2))
print('PREVIEW_COMPLETE',len(o.data.polygons),'triangles',list(o.dimensions),flush=True)
if '--preview-only' in sys.argv:raise SystemExit(0)

camera.location=(365,-520,420);camera.rotation_euler=(Vector((0,0,height*.4))-camera.location).to_track_quat('-Z','Y').to_euler()
floor.hide_render=True;bpy.ops.object.select_all(action='DESELECT');o.select_set(True);bpy.context.view_layer.objects.active=o
baking.bake(o,NAME,MATS,resolution=2048,color_gain=1.0,cavity_strength=.35,atlas_margin=.003)
arm=baking.rig(o);arm.name=NAME+'_rig';scene.frame_start=1;scene.frame_end=30
pb=arm.pose.bones['root'];pb.rotation_mode='XYZ';pb.keyframe_insert('rotation_euler',frame=1);pb.keyframe_insert('rotation_euler',frame=30);arm.animation_data.action.name=NAME+'_idle'
bpy.ops.export_scene.fbx(filepath=str(MODELS/(NAME+'.fbx')),use_selection=True,object_types={'MESH','ARMATURE'},axis_forward='-Y',axis_up='Z',bake_anim=True,bake_anim_use_all_actions=False,bake_anim_use_nla_strips=False,add_leaf_bones=False)
uv=o.data.uv_layers.active;saved=[tuple(p.uv) for p in uv.data]
for loop in o.data.loops:
 v=o.data.vertices[loop.vertex_index].co;uv.data[loop.index].uv=((v.x+v.y*.32)/236+.5,1-(.05+.35*v.z/height))
bpy.ops.export_scene.fbx(filepath=str(MODELS/(NAME+'_flow.fbx')),use_selection=True,object_types={'MESH','ARMATURE'},axis_forward='-Y',axis_up='Z',bake_anim=False,add_leaf_bones=False)
for p,v in zip(uv.data,saved):p.uv=v
floor.hide_render=False;arm.hide_render=True;scene.cycles.samples=32;scene.render.filepath=str(OUT/'previews/final.png');bpy.ops.render.render(write_still=True)
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/(NAME+'.blend')))
(OUT/'manifest.json').write_text(json.dumps({'name':NAME,'triangles':len(o.data.polygons),'vertices':len(o.data.vertices),'dimensions':list(o.dimensions),'min_z':min(v.co.z for v in o.data.vertices),'front':'authoring -Y; engine east at yaw 0; southwest at entity yaw 225','runtime_yaw':225,'import_scale':.01,'texture_resolution':2048,'root_bone':'root','levels':[1,2,3,4,5]},indent=2))
print('TOWNHALL_COMPLETE',len(o.data.polygons),'triangles',flush=True)
