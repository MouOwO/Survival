"""Blender prototype: 128-unit footprint, Z-up, front -Y. Run via Blender MCP."""
import bpy, math, os, json
from mathutils import Vector

OUT = os.path.join(os.path.dirname(os.path.dirname(__file__)), 'output', 'gothic_keep_v1')
os.makedirs(OUT, exist_ok=True)
scene = bpy.data.scenes.new('Gothic Keep | Prototype 01')
bpy.context.window.scene = scene
asset = bpy.data.collections.new('GOTHIC_KEEP_ASSET')
scene.collection.children.link(asset)
stage = bpy.data.collections.new('PRESENTATION_ONLY')
scene.collection.children.link(stage)

def mat(name, color, metal=0, rough=.65, glow=0):
    m=bpy.data.materials.new(name); m.diffuse_color=(*color,1); m.use_nodes=True
    p=next(n for n in m.node_tree.nodes if n.type=='BSDF_PRINCIPLED'); p.inputs['Base Color'].default_value=(*color,1)
    p.inputs['Metallic'].default_value=metal; p.inputs['Roughness'].default_value=rough
    if glow: p.inputs['Emission Color'].default_value=(*color,1); p.inputs['Emission Strength'].default_value=glow
    return m
stone=mat('Basalt | blue grey',(.19,.235,.28))
trim=mat('Carved limestone',(.39,.43,.46))
dark=mat('Recess shadow',(.018,.025,.034))
roof=mat('Midnight slate',(.035,.095,.14),.35,.38)
gold=mat('Aged brass',(.46,.29,.095),.72,.32)
glass=mat('Amber lancet glass',(1,.39,.065),.1,.25,2)
wood=mat('Black oak gate',(.055,.029,.019))
red=mat('Crimson banners',(.30,.017,.035),0,.85)

def finish(o,name,m,collection=asset):
    o.name=name
    for c in list(o.users_collection): c.objects.unlink(o)
    collection.objects.link(o)
    if m:o.data.materials.append(m)
    return o
def box(name,loc,size,m,bevel=.5):
    bpy.ops.mesh.primitive_cube_add(size=1,location=loc); o=bpy.context.object; o.scale=size
    bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
    finish(o,name,m)
    if bevel:
        mod=o.modifiers.new('Soft carved edges','BEVEL');mod.width=bevel;mod.segments=2
        o.modifiers.new('Weighted normals','WEIGHTED_NORMAL')
    return o
def cone(name,loc,r1,r2,depth,m,verts=8):
    bpy.ops.mesh.primitive_cone_add(vertices=verts,radius1=r1,radius2=r2,depth=depth,location=loc,rotation=(0,0,math.pi/8))
    return finish(bpy.context.object,name,m)
def beam(name,a,b,width,m):
    mid=(Vector(a)+Vector(b))/2; o=box(name,mid,(width,width,(Vector(b)-Vector(a)).length),m,.15)
    o.rotation_euler=(Vector(b)-Vector(a)).to_track_quat('Z','Y').to_euler(); return o
def mesh(name,verts,faces,m):
    me=bpy.data.meshes.new(name);me.from_pydata(verts,[],faces);me.update()
    o=bpy.data.objects.new(name,me);asset.objects.link(o);o.data.materials.append(m);return o
def lancet(name,x,y,z,w,h,m,angle=0):
    # Filled pointed-arch silhouette, rotated to the facade.
    pts=[(-w/2,0),(-w/2,h*.62),(-w*.36,h*.80),(0,h),(w*.36,h*.80),(w/2,h*.62),(w/2,0)]
    verts=[(x+px*math.cos(angle),y+px*math.sin(angle),z+pz) for px,pz in pts]
    return mesh(name,verts,[tuple(range(7))],m)
def window(x,y,z,w=7,h=18,angle=0):
    # nested silhouettes leave a broad readable stone surround
    nx,ny=math.sin(angle),-math.cos(angle)
    lancet('Pointed stone surround',x,y,z,w+3,h+3,trim,angle)
    lancet('Deep arch recess',x+nx*.15,y+ny*.15,z+1,w+1,h+1,dark,angle)
    lancet('Warm stained glass',x+nx*.3,y+ny*.3,z+2,w-1,h-2,glass,angle)
    beam('Window mullion',(x+nx*.5,y+ny*.5,z+2),(x+nx*.5,y+ny*.5,z+h-1),.65,gold)
def gable(name,cx,cy,w,d,z,h):
    verts=[(cx-w/2,cy-d/2,z),(cx+w/2,cy-d/2,z),(cx,cy-d/2,z+h),
           (cx-w/2,cy+d/2,z),(cx+w/2,cy+d/2,z),(cx,cy+d/2,z+h)]
    mesh(name,verts,[(0,2,1),(3,4,5),(0,3,5,2),(1,2,5,4),(0,1,4,3)],roof)
    for yy in [cy-d/2,cy+d/2]:
        beam('Gable brass edge',(cx-w/2,yy,z),(cx,yy,z+h),1.3,gold)
        beam('Gable brass edge',(cx+w/2,yy,z),(cx,yy,z+h),1.3,gold)
    beam('Roof ridge',(cx,cy-d/2,z+h),(cx,cy+d/2,z+h),2,gold)

box('Foundation / 128 x 128',(0,0,2),(128,128,4),dark,3)
box('Upper foundation',(0,0,5),(122,118,3),trim,2)
box('Great hall',(0,8,38),(65,77,64),stone,1)
for zz in [9,21,63,69]:box('Hall belt course',(0,8,zz),(69,81,2),trim)
gable('Great hall steep slate roof',0,8,75,85,71,36)
for yy in [-20,-5,10,25,40]:
    for sign in [-1,1]:
        x=sign*36
        box('Buttress plinth',(x,yy,10),(9,11,8),trim)
        box('Buttress pier',(x,yy,32),(6,7,40),stone)
        beam('Flying buttress',(sign*41,yy,37),(sign*31,yy,64),4,trim)
        cone('Buttress pinnacle',(x,yy,65),4,0,14,roof,4)
        if yy in [-5,10,25]:window(sign*32.65,yy,36,7,20,angle=sign*math.pi/2)

# Four unequal-height towers frame the hall; rear pair echo the central belfry.
for x,y,height in [(-45,-35,69),(45,-35,69),(-44,39,85),(44,39,85)]:
    cone('Octagonal tower base',(x,y,11),17,17,10,trim)
    cone('Octagonal tower shaft',(x,y,(height+14)/2),13.5,13.5,height-14,stone)
    for zz in [17,36,height-5,height]:cone('Tower carved cornice',(x,y,zz),15,15,2.5,trim)
    # Narrow stone ribs articulate each octagonal face.
    for a in range(8):
        ang=a*math.pi/4+math.pi/8
        xx=x+12.6*math.cos(ang); yy=y+12.6*math.sin(ang)
        beam('Tower rib',(xx,yy,18),(xx,yy,height-5),1.5,trim)
    window(x,y-13.6,43,6,17)
    window(x+13.6,y,43,6,17,math.pi/2)
    cone('Tower flared eave',(x,y,height+3),18,15,6,roof)
    cone('Tower needle roof',(x,y,height+23),16,0,37,roof)
    for zz,rr in [(height+8,14),(height+19,9.5),(height+29,5.3)]:cone('Spire brass band',(x,y,zz),rr,rr,.7,gold)
    cone('Tower finial',(x,y,height+45),1.1,0,12,gold)

# Front portal, rose window, deep oak gate, broad readable stair.
box('Entrance pavilion',(0,-37,30),(36,25,46),stone)
gable('Portal gable',0,-39,43,29,54,23)
for i in range(5):box('Entrance stair',(0,-58+i*3.3,6+i*.95),(34-i*.9,5,1.7),trim,.3)
lancet('Carved gateway',0,-49.7,10,26,39,trim)
lancet('Gateway shadow',0,-50,11,22,35,dark)
lancet('Oak double door',0,-50.25,11,18,31,wood)
for x in [-6,-3,0,3,6]:beam('Door oak plank',(x,-50.6,12),(x,-50.6,33),.6,gold)
for z in [17,26]:box('Door iron strap',(0,-50.8,z),(17,.6,1),gold,.1)
for x in [-17,17]:
    box('Gate pier',(x,-51,31),(4,5,43),trim)
    cone('Gate pinnacle',(x,-51,61),4,0,17,roof,4)
    box('Crimson hanging banner',(x*1.5,-33,46),(7,1,18),red,.1)
    beam('Banner pole',(x*1.5-5,-33,57),(x*1.5+5,-33,57),1,gold)
    mesh('Banner pointed tail',[(x*1.5-3.5,-33.6,37),(x*1.5+3.5,-33.6,37),(x*1.5,-33.6,32)],[(0,1,2)],red)

# Rose window on upper front wall.
def disc(name,loc,r,depth,m):
    bpy.ops.mesh.primitive_cylinder_add(vertices=32,radius=r,depth=depth,location=loc,rotation=(math.pi/2,0,0));return finish(bpy.context.object,name,m)
disc('Rose carved rim',(0,-34.8,83),10,1.2,gold)
disc('Rose glass',(0,-35.5,83),8.5,.6,glass)
for a in range(8):
    t=a*math.pi/4;beam('Rose tracery',(0,-36,83),(8*math.cos(t),-36,83+8*math.sin(t)),.9,stone)
disc('Rose centre',(0,-36.5,83),2.2,.7,gold)

# Tall central bell tower: main silhouette landmark.
box('Central belfry',(0,22,113),(26,28,37),stone)
for z in [98,126,133]:box('Belfry cornice',(0,22,z),(30,32,2.5),trim)
for x in [-7,7]:window(x,7.8,106,6,19)
for y in [16,28]:window(13.2,y,106,6,19,math.pi/2)
cone('Crown slate spire',(0,22,156),23,0,46,roof,4)
for x in [-13,13]:
    for y in [9,35]:cone('Belfry corner needle',(x,y,142),4,0,23,roof,4)
beam('Crown finial',(0,22,177),(0,22,189),1.3,gold)
beam('Crown crossbar',(-4,22,184),(4,22,184),1.1,gold)

# Subtle masonry joints; broad courses survive a game-scale view.
for z in [28,40,52]:
    for x in [-32.6,32.6]:box('Masonry horizontal joint',(x,8,z),(.12,74,.45),dark,0)

scene.world=bpy.data.worlds.new('Slate studio world');scene.world.use_nodes=True
next(n for n in scene.world.node_tree.nodes if n.type=='BACKGROUND').inputs[0].default_value=(.065,.09,.14,1)
next(n for n in scene.world.node_tree.nodes if n.type=='BACKGROUND').inputs[1].default_value=.45
ground=box('Studio ground',(0,0,-2),(20000,20000,2),mat('Backdrop',(.035,.048,.069)),0)
asset.objects.unlink(ground);stage.objects.link(ground)
def area(name,loc,power,color,size):
    data=bpy.data.lights.new(name,'AREA');data.energy=power;data.color=color;data.shape='DISK';data.size=size
    o=bpy.data.objects.new(name,data);stage.objects.link(o);o.location=loc;o.rotation_euler=(Vector((0,0,60))-o.location).to_track_quat('-Z','Y').to_euler()
area('Warm key',(-140,-190,300),1600000,(1,.81,.63),180)
area('Cool rim',(170,90,260),2200000,(.45,.68,1),150)
area('Soft front',(100,-240,130),650000,(.7,.83,1),140)
camdata=bpy.data.cameras.new('Preview camera');cam=bpy.data.objects.new('Preview camera',camdata);stage.objects.link(cam)
cam.location=(260,-360,280);cam.rotation_euler=(Vector((0,0,78))-cam.location).to_track_quat('-Z','Y').to_euler();camdata.type='ORTHO';camdata.ortho_scale=255;camdata.clip_end=10000;scene.camera=cam
scene.render.engine='CYCLES';scene.cycles.samples=40;scene.cycles.use_denoising=True
scene.render.resolution_x=1200;scene.render.resolution_y=1200;scene.render.resolution_percentage=100
scene.render.image_settings.file_format='PNG';scene.render.filepath=os.path.join(OUT,'gothic_keep_preview.png')
scene.view_settings.view_transform='AgX'
scene.unit_settings.system='NONE'
bpy.ops.object.select_all(action='DESELECT')
for o in asset.objects:o.select_set(True)
bpy.context.view_layer.objects.active=next(iter(asset.objects))
for screen in bpy.data.screens:
    for a in screen.areas:
        if a.type=='VIEW_3D':
            a.spaces.active.region_3d.view_distance=300;a.spaces.active.region_3d.view_location=(0,0,75)
            a.spaces.active.region_3d.view_rotation=cam.rotation_euler.to_quaternion();a.spaces.active.clip_end=10000
            a.spaces.active.shading.type='MATERIAL'
scene['scale_note']='Source-style raw coordinates: base 128 x 128, grid 64, footprint 2 x 2; height 189. Preview prototype, not compiled into Dota.'
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT,'gothic_keep_v1.blend'))
# Portable mesh/material preview; studio setup excluded.
bpy.ops.export_scene.gltf(filepath=os.path.join(OUT,'gothic_keep_v1.glb'),export_format='GLB',use_selection=True,export_apply=True)
print(json.dumps({'blend':os.path.join(OUT,'gothic_keep_v1.blend'),'asset_objects':len(asset.objects),'footprint':[128,128],'height':189}))


