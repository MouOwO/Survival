"""Blender authoring: concrete/rusted-steel radar bunker from user's single image."""
import bpy, math, random, sys, json
from pathlib import Path
from mathutils import Vector
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tools'))
import unique_building_bake as baking
from unique_building_detail import project_uv
OUT=ROOT/'output/main_base_bunker_20260930'
MODELS=OUT/'source/models/survival_buildings';MATS=OUT/'source/materials/survival_buildings'
for p in [MODELS,MATS,OUT/'previews']:p.mkdir(parents=True,exist_ok=True)
NAME='main_base_bunker_v1'
random.seed(93024)
bpy.ops.wm.read_factory_settings(use_empty=True)
scene=bpy.context.scene
objects=[]

def material(name, colors, rough=.8, metal=0, scale=.32, bump=.1):
 m=bpy.data.materials.new(name);m.use_nodes=True;n=m.node_tree.nodes;l=m.node_tree.links;bs=n.get('Principled BSDF');bs.inputs['Roughness'].default_value=rough;bs.inputs['Metallic'].default_value=metal
 geo=n.new('ShaderNodeNewGeometry');noise=n.new('ShaderNodeTexNoise');noise.inputs['Scale'].default_value=scale;noise.inputs['Detail'].default_value=5;noise.inputs['Roughness'].default_value=.78;l.new(geo.outputs['Position'],noise.inputs['Vector'])
 ramp=n.new('ShaderNodeValToRGB');ramp.color_ramp.elements.remove(ramp.color_ramp.elements[1])
 for i,c in enumerate(colors):
  e=ramp.color_ramp.elements[0] if i==0 else ramp.color_ramp.elements.new(i/(len(colors)-1));e.position=i/(len(colors)-1);e.color=(*c,1)
 if name=='oxidized iron armor':
  for e,pos in zip(ramp.color_ramp.elements,[.27,.42,.53,.64]):e.position=pos
 if name=='weathered warm concrete':
  for e,pos in zip(ramp.color_ramp.elements,[.22,.52,.78]):e.position=pos
 l.new(noise.outputs['Fac'],ramp.inputs['Fac']);l.new(ramp.outputs['Color'],bs.inputs['Base Color'])
 fine=n.new('ShaderNodeTexNoise');fine.inputs['Scale'].default_value=7;fine.inputs['Detail'].default_value=3;l.new(geo.outputs['Position'],fine.inputs['Vector'])
 b=n.new('ShaderNodeBump');b.inputs['Strength'].default_value=.5;b.inputs['Distance'].default_value=bump;l.new(fine.outputs['Fac'],b.inputs['Height']);l.new(b.outputs['Normal'],bs.inputs['Normal'])
 return m
mats={
 'concrete':material('weathered warm concrete',[(.045,.043,.037),(.155,.15,.132),(.285,.275,.245)],.94,0,.62,.13),
 'rust':material('oxidized iron armor',[(.025,.038,.04),(.085,.055,.031),(.24,.105,.038),(.09,.115,.12)],.74,.48,.58,.085),
 'steel':material('worn gunmetal',[(.035,.04,.037),(.12,.135,.13),(.29,.29,.26)],.49,.78,.4,.025),
 'brass':material('aged narrow brass straps',[(.16,.11,.047),(.36,.27,.13),(.5,.41,.23)],.49,.65,.6,.02),
 'sand':material('coarse khaki canvas',[(.052,.043,.027),(.18,.145,.085),(.30,.255,.165)],.95,0,.65,.07),
 'sand_seam':material('sandbag dark sewn piping',[(.065,.05,.029),(.14,.11,.058)],.97),
 'dark':material('dark entrance and joints',[(.012,.014,.013),(.028,.034,.031)],.94),
 'glass':material('searchlight lens',[(.38,.43,.39),(.65,.69,.60)],.2,.45,.08,.005)
}
def finish(o,key,bevel=0):
 o.data.materials.append(mats[key]);objects.append(o)
 if bevel:
  mod=o.modifiers.new('Rounded chipped edge','BEVEL');mod.width=bevel;mod.segments=2
  bpy.context.view_layer.objects.active=o;bpy.ops.object.modifier_apply(modifier=mod.name)
 return o

def box(name,loc,size,key='concrete',bevel=.6):
 bpy.ops.mesh.primitive_cube_add(size=1,location=loc);o=bpy.context.object;o.name=name;o.dimensions=size;bpy.ops.object.transform_apply(location=False,rotation=False,scale=True);return finish(o,key,bevel)

def taper(name,loc,bottom,top,height,key='concrete',bevel=.8):
 x,y,z=loc;v=[]
 for dims,dz in [(bottom,0),(top,height)]:
  for a,b in [(-1,-1),(1,-1),(1,1),(-1,1)]:v.append((x+a*dims[0]/2,y+b*dims[1]/2,z+dz))
 mesh=bpy.data.meshes.new(name);mesh.from_pydata(v,[],[(3,2,1,0),(4,5,6,7),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7)]);mesh.update();o=bpy.data.objects.new(name,mesh);scene.collection.objects.link(o);return finish(o,key,bevel)

def beam(name,a,b,r,key='steel',vertices=10,r2=None):
 a,b=Vector(a),Vector(b);d=b-a;bpy.ops.mesh.primitive_cone_add(vertices=vertices,radius1=r,radius2=r if r2 is None else r2,depth=d.length,location=(a+b)/2);o=bpy.context.object;o.name=name;o.rotation_euler=d.to_track_quat('Z','Y').to_euler();return finish(o,key)

def ball(name,loc,size,key='steel',seg=20,rings=10):
 bpy.ops.mesh.primitive_uv_sphere_add(segments=seg,ring_count=rings,radius=1,location=loc);o=bpy.context.object;o.name=name;o.scale=size;bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
 for f in o.data.polygons:f.use_smooth=True
 return finish(o,key)

def line(name,points,r=.18,key='steel',closed=False):
 curve=bpy.data.curves.new(name,'CURVE');curve.dimensions='3D';curve.resolution_u=1;curve.bevel_depth=r;curve.bevel_resolution=0
 sp=curve.splines.new('POLY');sp.points.add(len(points)-1)
 for p,v in zip(sp.points,points):p.co=(*v,1)
 sp.use_cyclic_u=closed;o=bpy.data.objects.new(name,curve);scene.collection.objects.link(o);bpy.context.view_layer.objects.active=o;o.select_set(True);bpy.ops.object.convert(target='MESH');o=bpy.context.object;finish(o,key);o.select_set(False);return o

def panel_front(x,y,z,w,h):
 box('riveted iron plate',(x,y,z),(w,1.15,h),'rust',.25)
 for dx in [-w/2+1.5,w/2-1.5]:
  for dz in [-h/2+1.5,0,h/2-1.5]:beam('iron rivet',(x+dx,y-.8,z+dz),(x+dx,y-1.2,z+dz),.55,'steel',8)

def panel_side(x,y,z,w,h):
 box('side iron plate',(x,y,z),(1.1,w,h),'rust',.25)
 for dy in [-w/2+1.5,w/2-1.5]:
  for dz in [-h/2+1.5,h/2-1.5]:beam('side rivet',(x+.8,y+dy,z+dz),(x+1.2,y+dy,z+dz),.55,'steel',8)

def bag(x,y,z,angle=0):
 angle+=random.uniform(-.13,.13)
 length=random.uniform(5.4,6.1);width=random.uniform(3.05,3.45);thick=random.uniform(1.95,2.2)
 phase=random.uniform(0,math.tau)
 bpy.ops.mesh.primitive_uv_sphere_add(segments=24,ring_count=10,radius=1,location=(x,y,z));o=bpy.context.object;o.name='bulging cloth sandbag with pinched ends'
 for v in o.data.vertices:
  a=v.co.copy();u=math.copysign(abs(a.x)**.65,a.x)
  pinch=1-.29*abs(u)**5
  folds=1+.065*math.sin(u*19+phase)*abs(u)**2
  v.co=(u*length,math.copysign(abs(a.y)**.75,a.y)*width*pinch*folds,
        math.copysign(abs(a.z)**.9,a.z)*thick*pinch*folds+.13*math.sin(u*5+phase))
 o.rotation_euler.z=angle
 for f in o.data.polygons:f.use_smooth=True
 finish(o,'sand')
 pts=[]
 for i in range(33):
  t=math.tau*i/32;u=math.copysign(abs(math.cos(t))**.65,math.cos(t));ax=u*length
  ay=math.copysign(abs(math.sin(t))**.75,math.sin(t))*width*(1-.29*abs(u)**5)
  pts.append((x+ax*math.cos(angle)-ay*math.sin(angle),y+ax*math.sin(angle)+ay*math.cos(angle),z+.13*math.sin(u*5+phase)))
 line('visible canvas sewn edge',pts,.105,'sand_seam',closed=True)
 # Creased gathered fabric at both short ends, visible as modeled ridges.
 for side in [-1,1]:
  pts=[]
  for j in range(5):
   ax=side*length*(.79+.035*j);ay=(j-2)*width*.15
   pts.append((x+ax*math.cos(angle)-ay*math.sin(angle),y+ax*math.sin(angle)+ay*math.cos(angle),z+thick*(.63-.07*j)))
  line('gathered cloth fold',pts,.10,'sand')

# Foundation and lower defensive courtyard, frontage faces world -Y.
taper('heavy sloped foundation',(0,0,0),(108,106),(96,94),19)
box('courtyard floor',(0,-8,19),(84,72,2),'concrete',.25)
for side in [-1,1]:
 taper('thick battered flank',(side*44,0,17),(18,91),(13,85),27)
 box('parapet coping',(side*44,-1,45),(16,90,5),'concrete',1)
 # Segmented angled buttresses, bronze seam straps and steel inserts.
 for y in [-42,-12,19,42]:
  taper('buttress lower',(side*50,y,0),(13,13),(8,11),31)
  taper('buttress upper',(side*47,y,31),(8,11),(6,10),18)
  box('buttress band',(side*49,y,27),(10,12,.65),'brass',.1)
 for y in [-27,4,32]:
  for z in [13,32]:
   if side==1:panel_side(54 if z<20 else 52,y,z,19,15)
   else:box('left armor panel',(-54 if z<20 else -52,y,z),(1.3,19,15),'rust',.25)
  box('armored parapet top',(side*44,y,47.8),(13,20,1.5),'rust',.2)
# Split front wall around the armored entrance.
for x in [-34,34]:
 taper('front wall',(x,-45,14),(31,15),(29,11),24)
 box('front coping',(x,-45,39),(30,15,4),'concrete',.8)
 panel_front(x,-53,17,25,24)
 for z in [8,29]:box('bronze horizontal band',(x,-53.7,z),(28,.5,.55),'brass',.1)
box('entrance dark recess',(0,-49,17),(33,3,32),'dark',.15)
for x in [-7.7,7.7]:panel_front(x,-51,16,14.4,29)
beam('door central seam',(0,-52,2),(0,-52,31),.45,'steel')
for side in [-1,1]:
 taper('door framing buttress',(side*20,-46,0),(13,24),(9,18),40)
 box('door frame cap',(side*20,-45,41),(13,21,5),'concrete',.8)
# Main intermediate platform and armored sloping access canopy.
box('rear platform',(0,25,39),(87,43,41),'concrete',1.1)
box('access roof block',(-8,-15,37),(37,35,8),'concrete',.8)
canopy=box('entrance armored sloping canopy',(-8,-32,40),(38,29,2.4),'rust',.35);canopy.rotation_euler.x=math.radians(12)
for x in [-24,8]:
 for y in [-41,-32,-22]:ball('canopy rivet',(x,y,41+(y+32)*.21),(.6,.6,.4),'steel',8,4)
# Sandbag breastworks, offset rows and a return along the right courtyard.
for layer in range(3):
 for x in [-35,-25,20,30,40]:bag(x+(layer%2)*2,-35,43+layer*3.65)
 for x in range(-31,39,10):bag(x+(layer%2)*3,-14,45+layer*3.65)
 for y in [-28,-19,-10,0]:bag(32,y+(layer%2)*2,43+layer*3.65,math.pi/2)
# Upper command room is inset from the curtain walls.
taper('command bunker',(0,20,53),(71,54),(66,50),29)
for x in [-22,0,22]:panel_front(x,-7.3,65,18,19)
for y in [7,30]:panel_side(34.5,y,66,17,20)
# Horizontal brass construction bands and narrow dark joints.
for z in [58,76]:
 box('command front brass trim',(0,-7.9,z),(68,.7,.65),'brass',.15)
 for side in [-1,1]:box('command side brass trim',(side*34,20,z),(.7,51,.65),'brass',.15)
# Roof coping leaves a recessed radar deck.
box('roof working deck',(0,20,82),(63,48,2),'steel',.4)
for x in [-33,33]:box('roof concrete parapet',(x,20,85),(7,56,9),'concrete',1.0)
for y in [-5,45]:box('roof concrete parapet',(0,y,85),(63,7,9),'concrete',1.0)
for x in [-22,0,22]:box('bolted roof hatch',(x,20,83.6),(17,22,.55),'steel',.2)
# Radar pedestal, support ribs, steel spherical radome and geodesic seams.
beam('radar plinth',(0,21,83),(0,21,87),10,'steel',20)
beam('radar equipment column',(0,21,85),(0,21,95),5,'steel',16)
for i in range(8):
 t=i*math.tau/8;beam('radar flared support',(9*math.cos(t),21+9*math.sin(t),84),(5*math.cos(t),21+5*math.sin(t),95),.8,'rust',8)
beam('radar bearing ring',(0,21,94),(0,21,97),8,'steel',24)
ball('metal radar globe',(0,21,110),(13,13,13),'steel',32,16)
bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=2,radius=13.18,location=(0,21,110));ico=bpy.context.object
edges=[(ico.matrix_world@ico.data.vertices[e.vertices[0]].co,ico.matrix_world@ico.data.vertices[e.vertices[1]].co) for e in ico.data.edges];bpy.data.objects.remove(ico,do_unlink=True)
for a,b in edges:
 center=Vector((0,21,110));points=[center+((a-center).lerp(b-center,j/5)).normalized()*13.22 for j in range(6)]
 line('radome geodesic seam',points,.12,'brass')
# Lattice communications mast to the rear right, long slender radio aerials.
for x,y,height in [(24,34,142),(-23,29,129),(-22,0,116),(25,6,115)]:
 box('aerial mounting foot',(x,y,84.5),(5,5,3),'rust',.3)
 beam('aerial base',(x,y,84),(x,y,105),.65,'steel',10,r2=.38)
 beam('aerial whip',(x,y,103),(x,y,height),.3,'steel',8,r2=.08)
 if height==142:
  for dx in [-2,2]:beam('lattice upright',(x+dx,y,87),(x+dx,y,130),.36,'steel',8)
  for z in range(90,130,6):
   beam('mast cross brace',(x-2,y,z),(x+2,y,z+6),.22,'rust',6)
   beam('mast rung',(x-2,y,z),(x+2,y,z),.25,'steel',6)
  for z in [116,129]:beam('radio crossarm',(x-6,y,z),(x+6,y,z),.3,'steel',8)
# Small searchlights and power cables.
for x,y,z in [(-25,-1,105),(9,-4,86)]:
 beam('searchlight barrel',(x,y,z),(x,y-3.2,z+1),3.4,'steel',16,r2=4)
 lens=ball('recessed searchlight glass',(x,y-3.4,z+1),(3.1,.45,3.1),'glass',16,8)
 line('curved light cable',[(x,y,z-2),(x+3,y+2,z-6),(x+2,y+4,84)],.24,'dark')
# Small mechanical ground-level ventilation and a hatch, no lettering from the source image.
box('generator access hatch',(25,-54,5),(16,2,9),'rust',.3)
for x in range(19,32,2):box('hatch grille slat',(x,-55.3,5),(.65,.55,6),'steel',.06)
beam('hatch intake pipe',(31,-54,9),(39,-54,9),2.2,'steel',12)

print('GEOMETRY',len(objects),'parts',flush=True)
bpy.ops.object.select_all(action='DESELECT')
for o in objects:o.select_set(True)
bpy.context.view_layer.objects.active=objects[0];bpy.ops.object.join();o=bpy.context.object;o.name=NAME
bpy.ops.object.transform_apply(location=False,rotation=True,scale=True)
bpy.context.scene.cursor.location=(0,0,0);bpy.ops.object.origin_set(type='ORIGIN_CURSOR')
# Same 236-unit footprint as existing five main-city models; no changes to gameplay grid.
bounds=[o.matrix_world@v.co for v in o.data.vertices];width=max(max(v.x for v in bounds)-min(v.x for v in bounds),max(v.y for v in bounds)-min(v.y for v in bounds));scale=236/width
for v in o.data.vertices:v.co*=scale
bpy.ops.object.mode_set(mode='EDIT');bpy.ops.mesh.select_all(action='SELECT');bpy.ops.mesh.normals_make_consistent(inside=False);bpy.ops.object.mode_set(mode='OBJECT')
project_uv(o)
mod=o.modifiers.new('Runtime triangles','TRIANGULATE');bpy.ops.object.modifier_apply(modifier=mod.name)
# Record real geometry dimensions, then render a fast review before baking.
coords=[v.co for v in o.data.vertices];height=max(v.z for v in coords)
scene.world=bpy.data.worlds.new('Soft daylight');scene.world.use_nodes=True;scene.world.node_tree.nodes['Background'].inputs[0].default_value=(.7,.75,.8,1);scene.world.node_tree.nodes['Background'].inputs[1].default_value=.55
bpy.ops.object.camera_add(location=(365,-520,420));camera=bpy.context.object;camera.rotation_euler=(Vector((0,0,height*.43))-camera.location).to_track_quat('-Z','Y').to_euler();camera.data.type='ORTHO';camera.data.ortho_scale=height*1.30;scene.camera=camera
for loc,power,size in [((-260,-330,500),4500000,300),((330,-50,250),2300000,250),((20,350,400),3400000,220)]:
 bpy.ops.object.light_add(type='AREA',location=loc);light=bpy.context.object;light.data.energy=power;light.data.shape='DISK';light.data.size=size;light.rotation_euler=(-light.location).to_track_quat('-Z','Y').to_euler()
bpy.ops.mesh.primitive_plane_add(size=2000,location=(0,0,-.3));floor=bpy.context.object;floor.name='preview_floor';fm=bpy.data.materials.new('preview_floor');fm.diffuse_color=(.32,.34,.34,1);floor.data.materials.append(fm)
scene.render.engine='CYCLES';scene.cycles.samples=16;scene.render.resolution_x=1050;scene.render.resolution_y=1100;scene.render.resolution_percentage=100
scene.render.image_settings.file_format='PNG';scene.view_settings.view_transform='AgX';scene.render.filepath=str(OUT/'previews/geometry.png');bpy.ops.render.render(write_still=True)
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'authoring.blend'))
if '--preview-only' in sys.argv:raise SystemExit(0)
floor.hide_render=True;bpy.ops.object.select_all(action='DESELECT');o.select_set(True);bpy.context.view_layer.objects.active=o
baking.bake(o,NAME,MATS,resolution=2048,color_gain=1.0,cavity_strength=.35,atlas_margin=.003)
arm=baking.rig(o);arm.name=NAME+'_rig';scene.frame_start=1;scene.frame_end=30
pb=arm.pose.bones['root'];pb.rotation_mode='XYZ';pb.keyframe_insert('rotation_euler',frame=1);pb.keyframe_insert('rotation_euler',frame=30);arm.animation_data.action.name=NAME+'_idle'
bpy.ops.export_scene.fbx(filepath=str(MODELS/(NAME+'.fbx')),use_selection=True,object_types={'MESH','ARMATURE'},axis_forward='-Y',axis_up='Z',bake_anim=True,bake_anim_use_all_actions=False,bake_anim_use_nla_strips=False,add_leaf_bones=False)
# Separate height-coordinate mesh for the construction dissolve effect.
uv=o.data.uv_layers.active;saved=[tuple(p.uv) for p in uv.data]
for loop in o.data.loops:
 v=o.data.vertices[loop.vertex_index].co;uv.data[loop.index].uv=((v.x+v.y*.32)/236+.5,1-(.05+.35*v.z/height))
bpy.ops.export_scene.fbx(filepath=str(MODELS/(NAME+'_flow.fbx')),use_selection=True,object_types={'MESH','ARMATURE'},axis_forward='-Y',axis_up='Z',bake_anim=False,add_leaf_bones=False)
for p,v in zip(uv.data,saved):p.uv=v
floor.hide_render=False;arm.hide_render=True;scene.cycles.samples=32;scene.render.filepath=str(OUT/'previews/final.png');bpy.ops.render.render(write_still=True)
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'main_base_bunker.blend'))
(OUT/'manifest.json').write_text(json.dumps({'name':NAME,'triangles':len(o.data.polygons),'vertices':len(o.data.vertices),'dimensions':list(o.dimensions),'min_z':min(v.co.z for v in o.data.vertices),'front':'authoring -Y; engine east at yaw 0; southwest at entity yaw 225','runtime_yaw':225,'revision':2,'import_scale':.01,'texture_resolution':2048,'root_bone':'root','levels':[1,2,3,4,5]},indent=2))
print('BUNKER_COMPLETE',len(o.data.polygons),'triangles',flush=True)
