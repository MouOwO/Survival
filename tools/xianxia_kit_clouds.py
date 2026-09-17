"""Bake four NEW independent cloud fields in Blender, on transparent film.
Lit RGBA is explicitly a fixed-view approximation; never used as a normal map.
"""
import bpy, math, random, os, json, sys
from mathutils import Vector
ROOT=r'D:\steam\steamapps\common\dota 2 beta\game\dota_addons\survival'
OUT=os.path.join(ROOT,'output','xianxia_kit','clouds');os.makedirs(OUT,exist_ok=True)
scene=bpy.context.scene;scene.render.engine='CYCLES';scene.cycles.samples=96;scene.cycles.use_denoising=True;scene.cycles.volume_bounces=3
try:
 prefs=bpy.context.preferences.addons['cycles'].preferences;prefs.compute_device_type='HIP';prefs.get_devices()
 for device in prefs.devices:device.use=device.type=='HIP' and '9070' in device.name
 if any(d.use for d in prefs.devices):scene.cycles.device='GPU';print('Cloud baking on RX 9070 XT',flush=True)
except Exception as e:print('CPU bake fallback:',e,flush=True)
scene.render.resolution_x=1536;scene.render.resolution_y=896;scene.render.resolution_percentage=100
scene.render.image_settings.file_format='PNG';scene.render.image_settings.color_mode='RGBA';scene.render.film_transparent=True
scene.view_settings.view_transform='AgX';scene.view_settings.exposure=0
for o in list(scene.objects):bpy.data.objects.remove(o,do_unlink=True)
scene.world=bpy.data.worlds.new('Cloud diffuse sky');scene.world.use_nodes=True
bg=next(n for n in scene.world.node_tree.nodes if n.type=='BACKGROUND');bg.inputs[0].default_value=(.55,.67,.81,1);bg.inputs[1].default_value=.22
def aim(o,p):o.rotation_euler=(Vector(p)-o.location).to_track_quat('-Z','Y').to_euler()
c=bpy.data.objects.new('Cloud bake view',bpy.data.cameras.new('Cloud bake view'));scene.collection.objects.link(c);c.location=(0,-17,11);aim(c,(0,0,1));c.data.type='ORTHO';c.data.ortho_scale=27;scene.camera=c
for name,loc,energy,size,color in [('Sun softness',(-10,-2,14),10500,3,(1,.94,.85)),('Blue sky',(8,5,10),750,10,(.65,.8,1))]:
    d=bpy.data.lights.new(name,'AREA');d.energy=energy;d.size=size;d.color=color;o=bpy.data.objects.new(name,d);scene.collection.objects.link(o);o.location=loc;aim(o,(0,0,1))
bpy.ops.mesh.primitive_cube_add(size=2);o=bpy.context.object;o.name='Procedural cloud volume';o.scale=(11,4.5,5);o.location.z=1
m=bpy.data.materials.new('Eroded cloud density');m.use_nodes=True;o.data.materials.append(m)
nodes=m.node_tree.nodes;nodes.clear();links=m.node_tree.links
output=nodes.new('ShaderNodeOutputMaterial');vol=nodes.new('ShaderNodeVolumePrincipled');vol.inputs['Color'].default_value=(.87,.91,.97,1);vol.inputs['Anisotropy'].default_value=.18;links.new(vol.outputs[0],output.inputs['Volume'])
coord=nodes.new('ShaderNodeTexCoord')
def mathn(op,a,b=None):
    n=nodes.new('ShaderNodeMath');n.operation=op
    for i,v in enumerate([a,b]):
        if v is None:continue
        if hasattr(v,'node'):links.new(v,n.inputs[i])
        else:n.inputs[i].default_value=v
    return n.outputs[0]
def field(seed,kind):
    for n in list(nodes):
        if n not in [output,vol,coord]:nodes.remove(n)
    rng=random.Random(seed);total=None
    warp=nodes.new('ShaderNodeTexNoise');warp.noise_dimensions='4D';warp.inputs['Scale'].default_value=8;warp.inputs['Detail'].default_value=4;warp.inputs['Roughness'].default_value=.7;warp.inputs['W'].default_value=seed;links.new(coord.outputs['Generated'],warp.inputs['Vector'])
    scaled=nodes.new('ShaderNodeVectorMath');scaled.operation='SCALE';scaled.inputs['Scale'].default_value=.065;links.new(warp.outputs['Color'],scaled.inputs[0])
    warped=nodes.new('ShaderNodeVectorMath');warped.operation='ADD';links.new(coord.outputs['Generated'],warped.inputs[0]);links.new(scaled.outputs[0],warped.inputs[1])
    count=12 if kind in [1,2]else 8
    lobes=[]
    for i in range(count):
        xx=.16+.66*(i/(count-1));yy=.49+rng.uniform(-.13,.13);zz=.41+rng.uniform(-.05,.09)
        if kind==1:zz+=.10*math.sin(i*.7)**2
        if kind==2:zz+=.16*math.exp(-((xx-.42)/.19)**2)
        if kind==3:zz+=.07*math.sin(xx*9);yy+=.06*math.sin(xx*8)
        rr=rng.uniform(.08,.145);dims=(rr,(.20 if kind<3 else .11)*rng.uniform(.8,1.2),(.22 if kind<3 else .08)*rng.uniform(.8,1.2))
        lobes.append(((xx,yy,zz),dims))
        for j in range(5 if kind<3 else 3):
            a=rng.uniform(0,math.tau);r=rng.uniform(.35,.85)
            center=(xx+math.cos(a)*dims[0]*r,yy+math.sin(a)*dims[1]*r,zz+rng.uniform(-.25,.6)*dims[2])
            lobes.append((center,tuple(d*rng.uniform(.3,.56)for d in dims)))
    for center,dims in lobes:
        sub=nodes.new('ShaderNodeVectorMath');sub.operation='SUBTRACT';links.new(warped.outputs[0],sub.inputs[0]);sub.inputs[1].default_value=center
        div=nodes.new('ShaderNodeVectorMath');div.operation='DIVIDE';links.new(sub.outputs[0],div.inputs[0]);div.inputs[1].default_value=dims
        le=nodes.new('ShaderNodeVectorMath');le.operation='LENGTH';links.new(div.outputs[0],le.inputs[0])
        lobe=mathn('MAXIMUM',mathn('SUBTRACT',1,le.outputs['Value']),0)
        total=lobe if total is None else mathn('MAXIMUM',total,lobe)
    detail=nodes.new('ShaderNodeTexNoise');detail.inputs['Scale'].default_value=42;detail.inputs['Detail'].default_value=5;detail.inputs['Roughness'].default_value=.7;links.new(coord.outputs['Generated'],detail.inputs['Vector'])
    erosion=mathn('ADD',mathn('MULTIPLY',warp.outputs['Fac'],.13),mathn('MULTIPLY',detail.outputs['Fac'],.22 if kind<4 else .5))
    density=mathn('MAXIMUM',mathn('SUBTRACT',total,erosion),0)
    density=mathn('MULTIPLY',mathn('POWER',density,1.3 if kind<4 else 1.8),30 if kind<3 else 8 if kind==3 else 1.3)
    if kind>=3:
        # Continuous sinuous ribbons instead of repeated ellipsoid puffs.
        sep=nodes.new('ShaderNodeSeparateXYZ');links.new(warped.outputs[0],sep.inputs[0]);px,py,pz=sep.outputs['X'],sep.outputs['Y'],sep.outputs['Z'];ribbon=None
        for j in range(3):
            centerY=mathn('ADD',mathn('MULTIPLY',mathn('SINE',mathn('ADD',mathn('MULTIPLY',px,11),j*2)),.075),.43+j*.055)
            centerZ=mathn('ADD',mathn('MULTIPLY',mathn('SINE',mathn('ADD',mathn('MULTIPLY',px,8),j)),.036),.41+j*.035)
            dy=mathn('DIVIDE',mathn('SUBTRACT',py,centerY),.10 if kind==3 else .065)
            dz=mathn('DIVIDE',mathn('SUBTRACT',pz,centerZ),.065 if kind==3 else .024)
            dist=mathn('SQRT',mathn('ADD',mathn('MULTIPLY',dy,dy),mathn('MULTIPLY',dz,dz)))
            lobe=mathn('MAXIMUM',mathn('SUBTRACT',1,dist),0);ribbon=lobe if ribbon is None else mathn('MAXIMUM',ribbon,lobe)
        fade=mathn('MINIMUM',mathn('MULTIPLY',mathn('SUBTRACT',px,.09),7),mathn('MULTIPLY',mathn('SUBTRACT',.91,px),7))
        fade=mathn('MINIMUM',mathn('MAXIMUM',fade,0),1)
        fineCut=mathn('MULTIPLY',detail.outputs['Fac'],.65)
        density=mathn('MULTIPLY',mathn('MULTIPLY',mathn('POWER',mathn('MAXIMUM',mathn('SUBTRACT',ribbon,fineCut),0),1.4),fade),5 if kind==3 else .8)
    links.new(density,vol.inputs['Density'])
status={'complete':False,'items':[],'lighting':'fixed soft morning lighting','runtimeLimitation':'Baked oblique-view RGBA; cannot substitute for true runtime volume. Use at intended view and limited scale; do not tile dense copies.'}
if '--resume' in sys.argv:
 old=json.load(open(os.path.join(OUT,'cloud_manifest.json')))
 status['items']=old['items']
json.dump(status,open(os.path.join(OUT,'cloud_manifest.json'),'w'),indent=2)
for name,seed,kind in [('c01_cloud_sea',108,1),('c02_cliff_cloud',204,2),('c03_cloud_band',319,3),('c04_thin_mist',427,4)]:
    if '--ribbons' in sys.argv and kind<3:continue
    if '--ribbons' not in sys.argv and any(x['name']==name for x in status['items']):continue
    field(seed,kind);scene.render.filepath=os.path.join(OUT,name+'.png');bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT,name+'.blend'));bpy.ops.render.render(write_still=True)
    status['items']=[i for i in status['items']if i['name']!=name]
    status['items'].append({'name':name,'size':[1536,896],'alpha':'straight RGBA on transparent film','kind':kind});json.dump(status,open(os.path.join(OUT,'cloud_manifest.json'),'w'),indent=2)
status['complete']=True;json.dump(status,open(os.path.join(OUT,'cloud_manifest.json'),'w'),indent=2)
