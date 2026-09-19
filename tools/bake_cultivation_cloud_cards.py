"""Bake original smooth cloud cards from 3D density fields, without simulation.
The cards are a fixed-lighting, fixed-view approximation, not runtime volumes.
Run in the connected Blender. The user's existing scenes are preserved.
"""
import bpy, math, json, os, random
from mathutils import Vector

ROOT = r'D:\steam\steamapps\common\dota 2 beta\game\dota_addons\survival'
OUT = os.path.join(ROOT, 'output', 'survival_world_v2', 'cloud_cards')
os.makedirs(OUT, exist_ok=True)
scene = bpy.data.scenes.new('Cultivation morning cloud bake')
bpy.context.window.scene = scene
scene.render.engine = 'CYCLES'
scene.cycles.samples = 128
scene.cycles.use_denoising = True
scene.cycles.volume_bounces = 2
scene.render.resolution_x = 2048
scene.render.resolution_y = 1024
scene.render.resolution_percentage = 100
scene.render.image_settings.file_format = 'PNG'
scene.render.image_settings.color_mode = 'RGBA'
scene.render.film_transparent = True
scene.view_settings.view_transform = 'AgX'
scene.view_settings.exposure = 0
world = bpy.data.worlds.new('Cloud morning fill')
world.use_nodes = True
background = next(n for n in world.node_tree.nodes if n.type=='BACKGROUND')
background.inputs[0].default_value = (.68,.78,.88,1)
background.inputs[1].default_value = .7
scene.world = world

def aim(obj, point):
    obj.rotation_euler = (Vector(point)-obj.location).to_track_quat('-Z','Y').to_euler()
camera_data=bpy.data.cameras.new('Cloud orthographic camera')
camera=bpy.data.objects.new('Cloud orthographic camera',camera_data)
scene.collection.objects.link(camera)
camera.location=(0,-14,20)
aim(camera,(0,0,0))
camera_data.type='ORTHO'
camera_data.ortho_scale=26
scene.camera=camera
for name,loc,energy,size,color in [('soft sunrise',(-8,-6,16),2800,12,(1,.96,.89)),('sky fill',(10,5,12),1800,16,(.77,.87,1))]:
    d=bpy.data.lights.new(name,'AREA'); d.energy=energy; d.shape='DISK'; d.size=size; d.color=color
    o=bpy.data.objects.new(name,d); scene.collection.objects.link(o); o.location=loc; aim(o,(0,0,0))

bpy.ops.mesh.primitive_cube_add(size=2)
cloud=bpy.context.object; cloud.name='Cloud density field'; cloud.scale=(12,4,4)
material=bpy.data.materials.new('Smooth layered cloud density'); material.use_nodes=True
cloud.data.materials.append(material)
nodes=material.node_tree.nodes; nodes.clear(); links=material.node_tree.links
output=nodes.new('ShaderNodeOutputMaterial')
volume=nodes.new('ShaderNodeVolumePrincipled'); volume.inputs['Color'].default_value=(.88,.92,.96,1)
volume.inputs['Anisotropy'].default_value=.15
links.new(volume.outputs['Volume'],output.inputs['Volume'])
coord=nodes.new('ShaderNodeTexCoord')

def mathnode(op,a,b=None):
    n=nodes.new('ShaderNodeMath'); n.operation=op
    if hasattr(a,'node'): links.new(a,n.inputs[0])
    else: n.inputs[0].default_value=a
    if b is not None:
        if hasattr(b,'node'): links.new(b,n.inputs[1])
        else: n.inputs[1].default_value=b
    return n.outputs[0]

def make_density(seed,band):
    # Remove the prior density graph while keeping output/volume/coordinates.
    for n in list(nodes):
        if n not in (output,volume,coord): nodes.remove(n)
    rng=random.Random(seed); total=None
    # Irregular overlapping lobes form one continuous mass, with a tapered tail.
    centers = [(.14+i*.061,.5+rng.uniform(-.15,.15),.5+rng.uniform(-.08,.12),rng.uniform(.08,.135)) for i in range(12)] if band else [(.16+i*.062,.5+rng.uniform(-.15,.15),.5+rng.uniform(-.12,.17),rng.uniform(.10,.17)) for i in range(12)]
    for x,y,z,r in centers:
        sub=nodes.new('ShaderNodeVectorMath');sub.operation='SUBTRACT';links.new(coord.outputs['Generated'],sub.inputs[0]);sub.inputs[1].default_value=(x,y+rng.uniform(-.07,.07),z)
        div=nodes.new('ShaderNodeVectorMath');div.operation='DIVIDE';links.new(sub.outputs[0],div.inputs[0]);div.inputs[1].default_value=(r,(.16 if band else .29)+rng.random()*.07,(.17 if band else .27)+rng.random()*.06)
        length=nodes.new('ShaderNodeVectorMath');length.operation='LENGTH';links.new(div.outputs[0],length.inputs[0])
        falloff=mathnode('MAXIMUM',mathnode('SUBTRACT',1,length.outputs['Value']),0)
        lobe=mathnode('POWER',falloff,1.35)
        total=lobe if total is None else mathnode('MAXIMUM',total,lobe)
    noise=nodes.new('ShaderNodeTexNoise');noise.noise_dimensions='4D';noise.inputs['W'].default_value=seed
    noise.inputs['Scale'].default_value=10;noise.inputs['Detail'].default_value=3;noise.inputs['Roughness'].default_value=.55
    links.new(coord.outputs['Generated'],noise.inputs['Vector'])
    erosion=mathnode('ADD',mathnode('MULTIPLY',noise.outputs['Fac'],.30),.025)
    density=mathnode('MULTIPLY',mathnode('MAXIMUM',mathnode('SUBTRACT',total,erosion),0),.8 if band else 1.7)
    links.new(density,volume.inputs['Density'])

jobs=[('morning_billows_a',11,False),('morning_billows_b',29,False),('morning_ribbon_a',37,True),('morning_ribbon_b',61,True)]
status={'state':'rendering','completed':[],'resolution':[2048,1024],'renderer':'Cycles 128 samples, denoised','limitation':'Fixed morning lighting and a baked oblique view; use modest angle/scale changes.'}
def save_status():
    with open(os.path.join(OUT,'bake_status.json'),'w',encoding='utf8') as f: json.dump(status,f,ensure_ascii=False,indent=2)
save_status()
def next_bake():
    if not jobs:
        status['state']='complete';save_status()
        bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT,'morning_cloud_cards.blend'))
        return None
    name,seed,band=jobs.pop(0)
    try:
        make_density(seed,band)
        scene.render.filepath=os.path.join(OUT,name+'.png')
        bpy.ops.render.render(write_still=True,scene=scene.name)
        status['completed'].append(name);save_status()
        return .2
    except Exception as e:
        status['state']='error';status['error']=str(e);save_status();return None
bpy.app.timers.register(next_bake, first_interval=1)
print('Started four original cloud card bakes:', OUT)
