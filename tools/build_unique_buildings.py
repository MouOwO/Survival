"""Author six original RTS building meshes; run with Blender --background --python.

Sources and previews stay in output/unique_buildings. Z-up, front -Y,
128-unit footprint. FBX's centimetre conversion is undone by import_scale=.01.
"""
import bpy
import math
import json
import random
import sys
from pathlib import Path
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'output/unique_buildings'
MODELS = OUT / 'source/models/survival_buildings'
MATS = OUT / 'source/materials/survival_buildings'
for p in (MODELS, MATS, OUT / 'previews'):
    p.mkdir(parents=True, exist_ok=True)
bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
scene.name = 'Survival original buildings'
palette = {
    'basalt': (.13,.18,.23), 'stone': (.34,.40,.43),
    'limestone': (.65,.65,.53), 'shadow': (.025,.035,.045),
    'wood': (.23,.105,.043), 'wood_light': (.43,.24,.095),
    'slate': (.035,.17,.25), 'teal': (.035,.36,.36),
    'brass': (.66,.40,.105), 'gold': (.95,.62,.12),
    'blue': (.12,.67,.88), 'ivory': (.80,.83,.73),
    'red': (.53,.045,.045), 'green': (.23,.39,.08),
    'earth': (.19,.135,.075), 'wheat': (.76,.52,.14),
}
palette.update(stone=(.24,.265,.23),limestone=(.40,.39,.30),ivory=(.53,.53,.41),
               slate=(.065,.095,.09),teal=(.11,.18,.14),brass=(.28,.19,.09),
               gold=(.52,.33,.09),blue=(.08,.38,.42),red=(.27,.045,.026))
materials = {}
for key, color in palette.items():
    path = 'materials/survival_buildings/' + key + '.vmat'
    m = bpy.data.materials.new(path)
    m.diffuse_color = (*color,1)
    m.use_nodes = True
    bs = m.node_tree.nodes.get('Principled BSDF')
    bs.inputs['Base Color'].default_value = (*color,1)
    bs.inputs['Roughness'].default_value = .65
    if key in ('gold','brass'): bs.inputs['Metallic'].default_value = .55
    materials[key] = m
    # Shared solid-color materials: no external texture or workshop dependency.
    tint = ' '.join(str(round(c ** (1/2.2),5)) for c in color)
    (MATS / (key+'.vmat')).write_text('"Layer0"\n{\n "shader" "global_lit_simple.vfx"\n "TextureColor" "['+tint+' 1]"\n "g_vColorTint" "[1 1 1 0]"\n}\n')
parts = []
assets = []
manifest = []
sys.path.insert(0, str(ROOT/'tools'))
import unique_building_detail as detail
import unique_building_art_v3 as art
import unique_building_bake as baking
detail.prepare_materials(materials, palette, MATS)

def finish(o, name, mat):
    o.name = name
    o.data.materials.append(materials[mat])
    parts.append(o)
    return o

def box(name, c, s, mat='stone', bevel=.5):
    bpy.ops.mesh.primitive_cube_add(size=1, location=c)
    o = bpy.context.object
    o.scale = s
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    finish(o,name,mat)
    if bevel:
        mod=o.modifiers.new('Carved edges','BEVEL'); mod.width=bevel; mod.segments=1
        bpy.ops.object.modifier_apply(modifier=mod.name)
    return o

def cone(name, c, r, top, h, mat='stone', sides=12):
    bpy.ops.mesh.primitive_cone_add(vertices=sides, radius1=r, radius2=top, depth=h, location=c)
    return finish(bpy.context.object,name,mat)

def beam(name,a,b,w,mat='brass'):
    v=Vector(b)-Vector(a)
    o=box(name,(Vector(a)+Vector(b))/2,(w,w,v.length),mat,.15)
    o.rotation_euler=v.to_track_quat('Z','Y').to_euler()
    return o

def mesh(name,v,f,mat):
    me=bpy.data.meshes.new(name); me.from_pydata(v,[],f); me.update()
    o=bpy.data.objects.new(name,me); scene.collection.objects.link(o)
    return finish(o,name,mat)

def ring(name,c,r,t,mat='brass',rot=(0,0,0)):
    bpy.ops.mesh.primitive_torus_add(major_segments=40,minor_segments=6,location=c,major_radius=r,minor_radius=t,rotation=rot)
    for face in bpy.context.object.data.polygons: face.use_smooth=True
    return finish(bpy.context.object,name,mat)

def crystal(c,r,h,mat='blue'):
    cone('Crystal lower', (c[0],c[1],c[2]+h*.15),0,r,h*.3,mat,6)
    cone('Crystal crown', (c[0],c[1],c[2]+h*.65),r,0,h*.7,mat,6)

def base(round_base=False):
    if round_base:
        cone('Foundation',(0,0,3),62,62,6,'basalt',32)
        cone('Paving',(0,0,7),59,59,3,'limestone',32)
    else:
        box('Foundation',(0,0,3),(124,124,6),'basalt',2)
        box('Paving',(0,0,7),(120,120,3),'limestone',1)
    for i in range(3): box('Entrance step',(0,-57+i*5,9+i*2),(34,9,3),'stone')

def roof(cx,cy,w,d,z,h,mat='slate'):
    v=[(cx-w/2,cy-d/2,z),(cx+w/2,cy-d/2,z),(cx,cy-d/2,z+h),
       (cx-w/2,cy+d/2,z),(cx+w/2,cy+d/2,z),(cx,cy+d/2,z+h)]
    mesh('Gabled roof',v,[(0,2,1),(3,4,5),(0,3,5,2),(1,2,5,4),(0,1,4,3)],mat)
    for y in (cy-d/2,cy+d/2):
        for s in (-1,1): beam('Roof edge',(cx+s*w/2,y,z),(cx,y,z+h),2,'wood_light')
    beam('Ridge',(cx,cy-d/2,z+h),(cx,cy+d/2,z+h),3,'brass')
    for t in (.25,.5,.75):
        for s in (-1,1): beam('Roof tile courses',(cx+s*w/2*(1-t),cy-d/2,z+h*t+.3),(cx+s*w/2*(1-t),cy+d/2,z+h*t+.3),.65,mat)

def window(x,y,z,w=8,h=16):
    box('Window frame',(x,y,z),(w+3,2,h+3),'limestone')
    box('Window glass',(x,y-1.2,z),(w,1,h),'blue',.15)
    beam('Mullion',(x,y-2,z-h/2),(x,y-2,z+h/2),1,'brass')

def banner(x,y,z,mat='red'):
    beam('Banner mast',(x,y,9),(x,y,z+5),2,'brass')
    beam('Banner crossbar',(x-9,y,z),(x+9,y,z),2,'brass')
    # Solid double-sided cloth with a swallowtail silhouette.
    pts=[(x-8,y,z-2),(x+8,y,z-2),(x+8,y,z-29),(x,y,z-24),(x-8,y,z-29)]
    mesh('Pennant',pts+[(a,b+1,c) for a,b,c in pts],[(4,3,2,1,0),(5,6,7,8,9)]+[(i,(i+1)%5,(i+1)%5+5,i+5) for i in range(5)],mat)
    box('Banner crest',(x,y-.6,z-13),(3,1,12),'gold',.1)

def export(name):
    detail.refine(name, globals())
    art.redesign(name, globals())
    bpy.ops.object.select_all(action='DESELECT')
    for o in parts: o.select_set(True)
    bpy.context.view_layer.objects.active=parts[0]
    bpy.ops.object.join(); o=bpy.context.object; o.name=name
    scene.cursor.location=(0,0,0); bpy.ops.object.origin_set(type='ORIGIN_CURSOR')
    # Recalculate all closed mesh normals, triangulate deterministically.
    bpy.ops.object.mode_set(mode='EDIT'); bpy.ops.mesh.select_all(action='SELECT')
    bpy.ops.mesh.normals_make_consistent(inside=False); bpy.ops.object.mode_set(mode='OBJECT')
    detail.project_uv(o)
    mod=o.modifiers.new('Runtime triangles','TRIANGULATE'); bpy.ops.object.modifier_apply(modifier=mod.name)
    baking.bake(o,name,MATS)
    arm=baking.rig(o)
    bpy.ops.export_scene.fbx(filepath=str(MODELS/(name+'.fbx')),use_selection=True,object_types={'MESH','ARMATURE'},axis_forward='-Y',axis_up='Z',bake_anim=False,add_leaf_bones=False)
    arm.hide_render=True;arm.hide_set(True)
    used=sorted({slot.material.name for slot in o.material_slots})
    remaps=','.join('{from='+json.dumps(m)+' to='+json.dumps(m)+'}' for m in used)
    header='<!-- kv3 encoding:text:version{e21c7f3c-8a33-41c5-9977-a76d3a32aa0d} format:modeldoc28:version{fb63b6ca-f435-4aa0-a2c7-c66ddc651dca} -->\n'
    (MODELS/(name+'.vmdl')).write_text(header+'{rootNode={_class="RootNode" children=[{_class="RenderMeshList" children=[{_class="RenderMeshFile" name="'+name+'" filename="models/survival_buildings/'+name+'.fbx" import_scale=0.01}]},{_class="MaterialGroupList" children=[{_class="DefaultMaterialGroup" remaps=['+remaps+'] use_global_default=false}]}]}}')
    # Explicit selection hitbox, using Source 2's native static-prop format.
    # No physics mesh: navigation and blocking remain owned by the building grid.
    model_path=MODELS/(name+'.vmdl')
    height=float(o.dimensions.z)
    sets=[]
    for set_name,r,top in [('default',56,height),('select_low',60,min(height,100)),('select_high',40,min(height,76))]:
        sets.append('{_class="HitboxSet" name="'+set_name+'" children=[{_class="Hitbox" name="root" parent_bone="root" hitbox_mins=[-'+str(r)+',-'+str(r)+',0] hitbox_maxs=['+str(r)+','+str(r)+','+str(top)+'] surface_property="default" translation_only=false group_id=0}]}')
    hitbox='{_class="HitboxSetList" children=['+','.join(sets)+']}'
    skeleton='{_class="BoneMarkupList" children=[] bone_cull_type="None"}'
    model_path.write_text(model_path.read_text()[:-3]+','+hitbox+','+skeleton+']}}')
    bounds=[list(o.dimensions),[min((o.matrix_world@Vector(v))[i] for v in o.bound_box) for i in range(3)]]
    manifest.append(dict(name=name,revision=3,triangles=len(o.data.polygons),dimensions=bounds[0],minimum=bounds[1],materials=used,uv_layers=len(o.data.uv_layers),texture_resolution=1024,root_bone='root',selection_sets=['default','select_low','select_high'],baseplate=False))
    assets.append(o); parts.clear(); o.hide_render=True; o.hide_set(True)

def research(advanced=False):
    base()
    box('Laboratory lower hall',(0,8,30),(72,65,43),'stone')
    for x in (-34,34):
        for y in (-22,38): box('Buttress',(x,y,33),(8,9,49),'limestone')
    for x in (-22,0,22):window(x,-25,33,10,20)
    for z in (13,51):box('Hall cornice',(0,8,z),(79,71,4),'limestone')
    cone('Observatory drum',(0,10,65),29,29,24,'slate',16)
    for z in (54,76):ring('Drum gold band',(0,10,z),29,1.7)
    cone('Observatory shoulder',(0,10,81),33,14,10,'teal',16)
    cone('Armillary pedestal',(0,10,91),12,9,12,'brass')
    for rot in ((math.pi/2,0,0),(math.pi/2,.65,.6),(0,.7,0)):
        ring('Armillary orbit',(0,10,115),25,1.8,'brass',rot)
    crystal((0,10,102),8,27)
    for x in (-47,47):
        cone('Side spire',(x,25,36),10,10,54,'stone',8)
        cone('Spire cap',(x,25,70),14,0,25,'slate',8)
    box('Entrance desk',(0,-40,19),(25,17,12),'wood')
    book=box('Open folio',(0,-40,27),(21,15,2),'ivory');book.rotation_euler.x=.2
    if advanced:
        for x in (-46,46):
            crystal((x,25,84),6,23)
            banner(x,-36,65,'teal')
        ring('Outer celestial orbit',(0,10,115),32,1.3,'blue',(1.1,.4,0))
    export('advanced_research_lab' if advanced else 'research_lab')

research();research(True)

base()
random.seed(54)
for x,y,z,sx,sy,sz in [(-29,20,34,58,69,58),(23,24,42,58,68,74),(0,39,54,50,39,64),(-45,-7,25,26,39,37),(41,-7,28,34,41,43)]:
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=1,radius=1,location=(x,y,z))
    o=finish(bpy.context.object,'Faceted ore rock','stone');o.scale=(sx/2,sy/2,sz/2)
box('Dark mine entrance',(0,-17,29),(39,4,41),'shadow')
for x in (-23,23):box('Mine timber post',(x,-23,31),(8,10,47),'wood_light')
box('Mine lintel',(0,-24,55),(58,12,9),'wood_light')
for x in (-22,22):
    for z in (17,44):box('Iron brace',(x,-29.2,z),(9,1,4),'basalt',.1)
for x in (-10,10):beam('Minecart rail',(x,-58,11),(x,-14,11),2,'basalt')
for y in (-53,-43,-33,-23):box('Rail sleeper',(0,y,9),(31,4,2),'wood')
for x,y,z in [(-34,4,48),(32,11,64),(14,38,79),(-42,28,53)]:
    for j in range(3):crystal((x+j*3,y+j*2,z),3.5,9+j*2,'gold')
box('Minecart chassis',(0,-43,15),(24,19,4),'basalt')
box('Minecart ore bed',(0,-43,22),(23,18,12),'wood')
for x in (-13,13):
    for y in (-49,-37):
        o=cone('Cart wheel',(x,y,14),4,4,2,'basalt',12);o.rotation_euler.y=math.pi/2
for x in (-7,0,7):crystal((x,-44,28),4,9,'gold')
beam('Winch post',(42,33,10),(42,33,87),4,'wood_light')
beam('Crane arm',(42,33,87),(12,33,87),4,'wood_light')
beam('Crane brace',(42,33,62),(20,33,87),3,'wood')
beam('Hanging chain',(14,33,86),(14,33,64),.8,'basalt')
export('gold_mine')

base()
box('Barn masonry',( -18,17,26),(55,62,35),'limestone')
for x in (-45,9):
    for y in (-13,46):box('Barn timber', (x,y,28),(4,4,39),'wood')
roof(-18,17,65,71,46,27,'teal')
box('Barn door',(-18,-15,25),(25,2,30),'wood')
for x in (-25,-18,-11):box('Door planks',(x,-16.2,25),(1,1,29),'wood_light',0)
for s in (-1,1):beam('Cross braced door',(-30,-17,12 if s<0 else 37),(-6,-17,37 if s<0 else 12),2,'wood_light')
window(-18,-19,57,8,9)
cone('Grain silo',(39,29,31),15,15,44,'wood_light',16)
for z in (12,27,48):ring('Silo hoop',(39,29,z),15,1.3,'basalt')
cone('Silo roof',(39,29,59),19,0,16,'teal',16)
box('Vegetable bed',(30,-23,10),(45,47,4),'earth')
for x in (16,28,40):
    for y in (-39,-30,-21,-12):
        beam('Wheat stalk',(x,y,12),(x,y,25),.8,'wheat')
        for sign in (-1,1):beam('Wheat ear',(x,y,19),(x+sign*3,y,26),1.7,'wheat')
for x in (-52,52):
    for y in (-45,-15,15,46):box('Fence post',(x,y,17),(3,3,18),'wood_light')
    for z in (16,22):beam('Fence rail',(x,-45,z),(x,46,z),2,'wood_light')
for y in (-40,-28):
    cone('Grain sack',(-29,y,15),6,5,12,'wheat',10)
export('population_farm')

base(True)
for z,r in ((11,46),(16,39),(21,31)):cone('Altar step',(0,3,z),r,r,5,'ivory',12)
ring('Sacred circle',(0,3,24),28,1.5,'brass')
cone('Sword stone',(0,3,33),16,12,20,'stone',8)
# Tall faceted blade, point planted in the altar.
mesh('Hero sword blade',[(-7,3,46),(7,3,46),(-7,3,86),(7,3,86),(0,0,66),(0,6,66),(0,3,36)],[(0,2,4),(2,3,4),(3,1,4),(1,6,4),(6,0,4),(2,0,5),(3,2,5),(1,3,5),(6,1,5),(0,6,5)],'ivory')
beam('Sword fuller',(0,-.2,48),(0,-.2,83),1.4,'blue')
box('Golden crossguard',(0,3,87),(32,8,5),'gold')
cone('Sword grip',(0,3,96),3,3,15,'slate',8)
crystal((0,3,104),5,10,'blue')
for x in (-37,37):
    cone('Sanctuary pillar',(x,24,38),7,7,56,'ivory',8)
    for z in (13,63):cone('Pillar cap',(x,24,z),11,11,5,'brass',8)
    crystal((x,24,67),6,16)
    banner(x,-31,56,'slate')
# Wing-shaped stone rays form an immediately legible altar silhouette.
for side in (-1,1):
    for i in range(4):beam('Radiant wing',(side*12,21,55-i*6),(side*(32+i*5),21,88-i*10),3,'ivory')
export('hero_altar')

base(True)
cone('Arena floor',(0,0,10),47,47,5,'earth',32)
ring('Arena boundary',(0,0,13),39,1.5,'brass')
for i in range(19):
    a=-math.pi/4+i*math.tau/24
    x,y=49*math.cos(a),49*math.sin(a)
    o=box('Arena perimeter',(x,y,24),(15,10,26),'stone');o.rotation_euler.z=a+math.pi/2
    o=box('Arena crenellation',(x,y,40),(8,12,7),'limestone');o.rotation_euler.z=a+math.pi/2
for x in (-33,33):
    box('Gate tower',(x,-33,34),(19,19,48),'basalt')
    box('Gate crown',(x,-33,59),(23,23,5),'limestone')
    for dx in (-7,7):box('Gate merlon',(x+dx,-33,65),(6,20,8),'stone')
    banner(x,-33,96)
box('Challenge emblem plinth',(0,36,39),(27,12,47),'basalt')
for side in (-1,1):
    beam('Crossed challenge blade',(-side*17,27+side*.8,48),(side*17,27+side*.8,77),4,'ivory')
    beam('Sword hilt',(-side*22,27,44),(-side*16,27,49),3,'brass')
    beam('Crossguard',(-side*22,27,52),(-side*12,27,44),3,'gold')
for x in (-21,21):
    cone('Brazier pedestal',(x,-9,20),6,4,18,'basalt',8)
    cone('Brazier bowl',(x,-9,30),5,8,6,'brass',8)
    crystal((x,-9,33),5,13,'gold')
export('challenge_arena')

(OUT/'manifest.json').write_text(json.dumps(manifest,indent=2))
# Reproducible orthographic previews use the actual exported meshes.
scene.render.engine='CYCLES';scene.cycles.samples=48
scene.render.resolution_x=1000;scene.render.resolution_y=1000;scene.render.resolution_percentage=100
scene.world=bpy.data.worlds.new('Studio');scene.world.use_nodes=True
scene.world.node_tree.nodes['Background'].inputs[0].default_value=(.19,.23,.29,1)
scene.world.node_tree.nodes['Background'].inputs[1].default_value=.6
bpy.ops.object.camera_add(location=(205,-285,235));camera=bpy.context.object
camera.rotation_euler=(Vector((0,0,48))-camera.location).to_track_quat('-Z','Y').to_euler()
camera.data.type='ORTHO';camera.data.ortho_scale=200;scene.camera=camera
for loc,power,size in [((70,-140,240),1100000,160),((-150,-15,130),650000,140),((70,150,200),950000,110)]:
    bpy.ops.object.light_add(type='AREA',location=loc);o=bpy.context.object;o.data.energy=power*.38;o.data.shape='DISK';o.data.size=size
    o.rotation_euler=(Vector((0,0,30))-o.location).to_track_quat('-Z','Y').to_euler()
bpy.ops.mesh.primitive_plane_add(size=2000);floor=bpy.context.object;floor.name='Preview floor - do not export';floor.location.z=-.5
floor.data.materials.append(materials['shadow'])
for o in assets:
    o.hide_render=False;o.hide_set(False)
    scene.render.filepath=str(OUT/'previews'/(o.name+'.png'));bpy.ops.render.render(write_still=True)
    o.hide_render=True;o.hide_set(True)
for i,o in enumerate(assets):
    o.hide_render=False;o.hide_set(False);o.location=((i%3-1)*170,(i//3)*185,0)
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'survival_buildings.blend'))
print('UNIQUE_BUILDINGS_COMPLETE',json.dumps(manifest))
