"""Cloud-only revision. Independent density fields; preserve approved kit resources.
Run with Blender --background --factory-startup --python this_file -- [--preview].
"""
import bpy, math, random, os, json, sys
from mathutils import Vector
ROOT=r'D:\steam\steamapps\common\dota 2 beta\game\dota_addons\survival'
OUT=os.path.join(ROOT,'output','xianxia_kit','cloud_revision_v2')
os.makedirs(OUT,exist_ok=True)
scene=bpy.data.scenes.new('Cloud revision - merged turbulent banks')
bpy.context.window.scene=scene
scene.render.engine='CYCLES';scene.cycles.samples=128 if '--preview' in sys.argv else 256;scene.cycles.use_denoising=True
scene.cycles.volume_bounces=4;scene.cycles.volume_step_rate=.35
prefs=bpy.context.preferences.addons['cycles'].preferences
prefs.compute_device_type='HIP';prefs.get_devices()
for d in prefs.devices:d.use=d.type=='HIP' and '9070' in d.name
if any(d.use for d in prefs.devices):scene.cycles.device='GPU'
scene.render.resolution_x=2048;scene.render.resolution_y=1536
scene.render.resolution_percentage=50 if '--preview' in sys.argv else 100
scene.render.image_settings.file_format='PNG';scene.render.image_settings.color_mode='RGBA'
scene.render.image_settings.color_depth='8';scene.render.film_transparent=True
scene.view_settings.view_transform='AgX';scene.view_settings.look='AgX - Medium High Contrast'
scene.world=bpy.data.worlds.new('Broad cool morning sky');scene.world.use_nodes=True
bg=scene.world.node_tree.nodes.get('Background');bg.inputs[0].default_value=(.74,.83,.95,1);bg.inputs[1].default_value=.25
def aim(o,p):o.rotation_euler=(Vector(p)-o.location).to_track_quat('-Z','Y').to_euler()
c=bpy.data.objects.new('Matched oblique game view',bpy.data.cameras.new('Cloud view'))
scene.collection.objects.link(c);c.data.type='ORTHO';c.data.ortho_scale=28;scene.camera=c
for name,loc,energy,size,col in [('Large morning key',(-8,2,14),9500,3,(1,.96,.89)),('Sky bounce',(8,-6,10),550,12,(.77,.87,1))]:
 d=bpy.data.lights.new(name,'AREA');d.energy=energy;d.shape='DISK';d.size=size;d.color=col
 ob=bpy.data.objects.new(name,d);scene.collection.objects.link(ob);ob.location=loc;aim(ob,(0,0,0))
bpy.ops.mesh.primitive_cube_add(size=2)
ob=bpy.context.object;ob.name='Continuous cloud density';ob.scale=(15,9,7)
mat=bpy.data.materials.new('Multiscale eroded volume');mat.use_nodes=True;ob.data.materials.append(mat)
N=mat.node_tree.nodes;L=mat.node_tree.links
def input_set(n,i,v):
 if hasattr(v,'node'):L.new(v,n.inputs[i])
 else:n.inputs[i].default_value=v
def mn(op,a,b=None,k=None):
 n=N.new('ShaderNodeMath');n.operation=op
 for i,v in enumerate([a,b,k]):
  if v is not None:input_set(n,i,v)
 return n.outputs[0]
def vn(op,a,b):
 n=N.new('ShaderNodeVectorMath');n.operation=op;input_set(n,0,a);input_set(n,1,b);return n.outputs[0]
def noise(p,scale,detail,seed):
 n=N.new('ShaderNodeTexNoise');n.noise_dimensions='4D';input_set(n,'Vector',p)
 n.inputs['Scale'].default_value=scale;n.inputs['Detail'].default_value=detail;n.inputs['Roughness'].default_value=.7;n.inputs['W'].default_value=seed
 return n
def shape(seed,kind):
 N.clear();out=N.new('ShaderNodeOutputMaterial');vol=N.new('ShaderNodeVolumePrincipled')
 vol.inputs['Color'].default_value=(.95,.965,.99,1);vol.inputs['Anisotropy'].default_value=.15
 L.new(vol.outputs[0],out.inputs['Volume'])
 tc=N.new('ShaderNodeTexCoord');p=vn('MULTIPLY',vn('SUBTRACT',tc.outputs['Generated'],(.5,.5,.5)),(30,18,14))
 coarse=noise(p,.65,3,seed);warp=vn('MULTIPLY',vn('SUBTRACT',coarse.outputs['Color'],(.5,.5,.5)),(1.8,1.8,1.5))
 p2=vn('ADD',p,warp);small=noise(p,2.2,3,seed+7)
 p2=vn('ADD',p2,vn('MULTIPLY',vn('SUBTRACT',small.outputs['Color'],(.5,.5,.5)),(.48,.48,.48)))
 rng=random.Random(seed);lobes=[]
 if kind=='sea':
  primary=[(-7,-.6,-.8,3.1,2.9,1.9),(-3.5,1,0,4,3.6,2.7),(1.3,-.5,-.3,3.6,3.4,2.2),(5.8,1,.2,3,2.8,2.6),(8,-.8,-.7,2,2,1.4)]
 elif kind=='bank':
  primary=[(-7,-.7,-1,2.8,2.6,1.6),(-3.5,.3,.1,3.5,3,3.1),(-.6,.7,1.1,3,2.8,3.4),(3,-.8,-.7,3.2,2.5,2.1),(7,.5,-1.2,2.7,2.2,1.3)]
 else:
  primary=[(-7,-.5,-.3,3.2,1.9,.9),(-3.1,.9,.1,3.3,2.7,1.4),(1.5,-.8,-.2,3.8,2.1,.85),(6.2,.4,0,3.1,2.7,1.1)]
 for x,y,z,rx,ry,rz in primary:
  lobes.append(((x,y,z),(rx,ry,rz)))
  if kind in ['sea','bank']:
   for i in range(9):
    phi=rng.uniform(0,math.tau);theta=rng.uniform(-.2,1.25);s=rng.uniform(.24,.48)
    lobes.append(((x+math.cos(phi)*math.cos(theta)*rx*.85,y+math.sin(phi)*math.cos(theta)*ry*.8,z+math.sin(theta)*rz*.9),(rx*s,ry*s,rz*s)))
 sdf=None
 for center,radii in lobes:
  local=vn('DIVIDE',vn('SUBTRACT',p2,center),radii);le=N.new('ShaderNodeVectorMath');le.operation='LENGTH';input_set(le,0,local)
  dist=mn('MULTIPLY',mn('SUBTRACT',le.outputs['Value'],1),min(radii))
  sdf=dist if sdf is None else mn('SMOOTH_MIN',sdf,dist,.5 if kind in ['sea','bank'] else 1.1)
 micro=noise(p,4.8,3,seed+19)
 erosion=mn('ADD',mn('MULTIPLY',mn('SUBTRACT',small.outputs['Fac'],.42),.45),mn('MULTIPLY',mn('SUBTRACT',micro.outputs['Fac'],.45),.16))
 inside=mn('MAXIMUM',mn('SUBTRACT',mn('MULTIPLY',sdf,-1),erosion),0)
 if kind=='mist':
  # A broad broken field, not sine tubes or overlapping oval cards.
  stretched=vn('MULTIPLY',p,(.35,1.15,1.6));mist=noise(stretched,1.15,5,seed+37)
  fragments=mn('POWER',mn('MAXIMUM',mn('SUBTRACT',mist.outputs['Fac'],.40),0),1.7)
  density=mn('MULTIPLY',mn('MULTIPLY',mn('MINIMUM',inside,1),fragments),3.8)
 elif kind=='band':
  fragments=noise(vn('MULTIPLY',p,(.6,1,1.2)),.7,4,seed+33)
  density=mn('MULTIPLY',mn('MINIMUM',inside,1.2),mn('MULTIPLY',mn('MAXIMUM',mn('SUBTRACT',fragments.outputs['Fac'],.36),0),3.8))
 else:density=mn('MULTIPLY',mn('MINIMUM',inside,1.5),4.0)
 L.new(density,vol.inputs['Density'])
jobs=[('c01_cloud_sea',108,'sea'),('c02_cliff_cloud',204,'bank'),('c03_cloud_band',319,'band'),('c04_thin_mist',427,'mist')]
if '--preview' in sys.argv:jobs=jobs[1:3]
if '--resume' in sys.argv:jobs=[j for j in jobs if not os.path.exists(os.path.join(OUT,j[0]+'.png'))]
for name,seed,kind in jobs:
 shape(seed,kind);c.location=(0,-19,21);aim(c,(0,0,.3))
 scene.render.filepath=os.path.join(OUT,name+('_draft' if '--preview' in sys.argv else '')+'.png')
 bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT,name+'.blend'))
 bpy.ops.render.render(write_still=True);print('CLOUD_DONE',name,flush=True)
json.dump({'resolution':[2048,1536],'variants':[j[0] for j in jobs],'approximation':'Fixed-view Cycles volume bake; sparse cards only. Approved models and materials unchanged.'},open(os.path.join(OUT,'revision.json'),'w'),indent=2)
