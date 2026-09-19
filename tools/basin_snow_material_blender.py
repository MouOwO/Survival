"""Model authored slate, then bake independent maps for a flat buildable floor.
The reference images are never sampled. No original Blender scene is deleted.
"""
import bpy, math, os, random, json, time, traceback
from mathutils import Vector
ROOT=r'D:\steam\steamapps\common\dota 2 beta\game\dota_addons\survival'
OUT=os.path.join(ROOT,'output','basin_review','snow_material')
os.makedirs(OUT,exist_ok=True)

def run():
 started=time.time();rng=random.Random(913)
 scene=bpy.data.scenes.new('Basin_Snow_Slate_Bake');bpy.context.window.scene=scene
 scene.render.engine='CYCLES';scene.cycles.samples=12
 try:
  prefs=bpy.context.preferences.addons['cycles'].preferences;prefs.compute_device_type='HIP';prefs.get_devices()
  for device in prefs.devices:device.use=device.type=='HIP'
  scene.cycles.device='GPU'
 except Exception:scene.cycles.device='CPU'
 scene.world=bpy.data.worlds.new('Slate bake world');scene.world.use_nodes=True
 next(n for n in scene.world.node_tree.nodes if n.type=='BACKGROUND').inputs[0].default_value=(.65,.75,.85,1)
 scene.view_settings.view_transform='Standard'
 materials=[]
 # sRGB palette is converted to linear for diffuse baking.
 def lin(v):return v/12.92 if v<=.04045 else ((v+.055)/1.055)**2.4
 for i,rgb in enumerate([(111,141,161),(123,151,169),(100,130,153),(131,155,169),(118,144,162),(106,136,151)]):
  m=bpy.data.materials.new('Authored blue slate '+str(i));m.use_nodes=True;ns=m.node_tree.nodes;ls=m.node_tree.links;bs=next(n for n in ns if n.type=='BSDF_PRINCIPLED')
  tex=ns.new('ShaderNodeTexNoise');tex.inputs['Scale'].default_value=.028;tex.inputs['Detail'].default_value=2.2
  coord=ns.new('ShaderNodeTexCoord');ls.new(coord.outputs['Object'],tex.inputs['Vector'])
  ramp=ns.new('ShaderNodeValToRGB');base=tuple(lin(c/255) for c in rgb)
  ramp.color_ramp.elements[0].color=tuple(v*.84 for v in base)+(1,);ramp.color_ramp.elements[1].color=tuple(v*1.12 for v in base)+(1,);ls.new(tex.outputs['Fac'],ramp.inputs[0])
  ao=ns.new('ShaderNodeAmbientOcclusion');ao.inputs['Distance'].default_value=27
  mix=ns.new('ShaderNodeMixRGB');mix.blend_type='MULTIPLY';mix.inputs[0].default_value=.65;ls.new(ramp.outputs[0],mix.inputs[1]);ls.new(ao.outputs['Color'],mix.inputs[2]);ls.new(mix.outputs[0],bs.inputs['Base Color'])
  bump=ns.new('ShaderNodeBump');bump.inputs['Strength'].default_value=.14;bump.inputs['Distance'].default_value=.8;ls.new(tex.outputs['Fac'],bump.inputs['Height']);ls.new(bump.outputs[0],bs.inputs['Normal']);bs.inputs['Roughness'].default_value=.8
  materials.append(m)
 dark=bpy.data.materials.new('Slate dark seams');dark.diffuse_color=(.035,.070,.10,1);dark.use_nodes=True;next(n for n in dark.node_tree.nodes if n.type=='BSDF_PRINCIPLED').inputs['Base Color'].default_value=(.035,.070,.10,1)
 high=[]
 def solid(name,points,z,bottom,material,bevel=0):
  n=len(points);verts=[(x,y,bottom) for x,y in points]+[(x,y,z) for x,y in points]
  faces=[tuple(reversed(range(n))),tuple(n+i for i in range(n))]+[(i,(i+1)%n,n+(i+1)%n,n+i)for i in range(n)]
  me=bpy.data.meshes.new(name);me.from_pydata(verts,[],faces);me.materials.append(material);ob=bpy.data.objects.new(name,me);scene.collection.objects.link(ob);high.append(ob)
  if bevel:
   mod=ob.modifiers.new('Worn stone edges','BEVEL');mod.width=bevel;mod.segments=2
   ob.modifiers.new('Weighted corner normals','WEIGHTED_NORMAL')
  return ob
 solid('continuous mortar bed',[(-1400,-1400),(1400,-1400),(1400,1400),(-1400,1400)],-1,-8,dark)
 radii=[0,190,380,590,810,1050,1450];counts=[7,11,16,21,26,32]
 for band,(lo,hi,count) in enumerate(zip(radii[:-1],radii[1:],counts)):
  offset=(band%2)*.43
  for i in range(count):
   a=(i+offset)/count*math.tau+.005;b=(i+1+offset)/count*math.tau-.005
   r0=lo+2+rng.uniform(0,3);r1=hi-2-rng.uniform(0,3);p=[]
   for j in range(7):
    t=a+(b-a)*j/6;rr=r1+rng.uniform(-2,2);p.append((rr*math.cos(t),rr*math.sin(t)))
   for j in range(6,-1,-1):
    t=a+(b-a)*j/6;rr=r0+rng.uniform(-min(2,r0*.2),min(2,r0*.2));p.append((rr*math.cos(t),rr*math.sin(t)))
   solid('slate_%02d_%02d'%(band,i),p,6+rng.uniform(-1,2),-2,materials[rng.randrange(len(materials))],2.2)
 # Low bake target has the exact UV layout subsequently assigned in Hammer.
 me=bpy.data.meshes.new('Slate UV target');me.from_pydata([(-1280,-1280,-12),(1280,-1280,-12),(1280,1280,-12),(-1280,1280,-12)],[],[(0,1,2,3)])
 uv=me.uv_layers.new(name='UVMap')
 for loop,xy in zip(uv.data,[(0,0),(1,0),(1,1),(0,1)]):loop.uv=xy
 low=bpy.data.objects.new('Flat walkable material target',me);scene.collection.objects.link(low)
 target=bpy.data.materials.new('Bake target');target.use_nodes=True;low.data.materials.append(target);node=target.node_tree.nodes.new('ShaderNodeTexImage');target.node_tree.nodes.active=node
 for ob in scene.objects:ob.select_set(False)
 for ob in high:ob.select_set(True)
 low.select_set(True);bpy.context.view_layer.objects.active=low
 scene.render.bake.use_selected_to_active=True;scene.render.bake.cage_extrusion=48;scene.render.bake.max_ray_distance=64;scene.render.bake.margin=8
 scene.render.bake.use_pass_direct=False;scene.render.bake.use_pass_indirect=False;scene.render.bake.use_pass_color=True
 scene.render.bake.normal_space='TANGENT';scene.render.bake.normal_g='NEG_Y'
 files=[]
 for kind,bake_type in [('color','DIFFUSE'),('normal','NORMAL'),('roughness','ROUGHNESS')]:
  im=bpy.data.images.new('snow_slate_'+kind,width=2048,height=2048,alpha=False)
  if kind!='color':im.colorspace_settings.name='Non-Color'
  node.image=im;bpy.ops.object.bake(type=bake_type)
  im.filepath_raw=os.path.join(OUT,'snow_slate_'+kind+'.png');im.file_format='PNG';im.save();files.append(im.filepath_raw)
 # A separate conservative reflectance control accompanies the roughness bake.
 # Source 2 consumes reflectance here, not a generic metallic/roughness pack.
 im=bpy.data.images.new('snow_slate_reflectance',width=16,height=16,alpha=False);im.colorspace_settings.name='Non-Color';im.generated_color=(.06,.06,.06,1);im.filepath_raw=os.path.join(OUT,'snow_slate_reflectance.png');im.file_format='PNG';im.save();files.append(im.filepath_raw)
 low.hide_render=True
 bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT,'authored_snow_slate.blend'))
 report={'status':'complete','seconds':time.time()-started,'stoneObjects':len(high)-1,'textureSize':2048,'mapping':'unique arena UV; world x [-1280,1280], y [1600,4160]','normalConvention':'tangent +X -Y +Z','files':files,'source':'independent Blender geometry and procedural stone paint; no concept image sampled'}
 with open(os.path.join(OUT,'bake_report.json'),'w',encoding='utf8')as f:json.dump(report,f,indent=2)

def task():
 try:run()
 except Exception:
  with open(os.path.join(OUT,'bake_error.txt'),'w',encoding='utf8')as f:f.write(traceback.format_exc())
 return None
bpy.app.timers.register(task,first_interval=.25)
print('Snow slate geometry/bake job scheduled; results under '+OUT)
