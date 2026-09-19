"""Additive detail assets; preserve the approved source kit and all user scenes."""
import bpy,os,math,json,random,bmesh
from mathutils import Vector,Matrix
ROOT=r'D:\steam\steamapps\common\dota 2 beta\game\dota_addons\survival'
base=bpy.app.driver_namespace['xxkit']
OUT=os.path.join(ROOT,'output','xianxia_kit','detail_pass');MODELS=os.path.join(OUT,'models')
os.makedirs(MODELS,exist_ok=True)
scene=bpy.data.scenes.new('Xianxia detail and junction modules');bpy.context.window.scene=scene
materials=base['materials'];registry=[];objects={}
source=open(os.path.join(ROOT,'tools','xianxia_kit_models.py'),encoding='utf8').read()
exec(source[source.index('class Builder:'):source.index('def terrain():')],globals())
def copy_builder(name):
    o=base['objects'][name];b=Builder();b.v=[tuple(v.co)for v in o.data.vertices]
    b.f=[tuple(p.vertices)for p in o.data.polygons]
    b.mi=[list(materials.values()).index(o.data.materials[p.material_index])for p in o.data.polygons]
    return b
b=copy_builder('a01_pavilion')
for x in [-164,164]:
    for y in [-164,164]:
        for axis in [0,1]:
            for sign in [-1,1]:
                pts=[Vector((x,y,290)),Vector((x,y,308)),Vector((x,y,332))]
                pts[1][axis]+=sign*34;pts[2][axis]+=sign*61
                b.tube(pts,[9,8,6],'wood',6)
for side in [-1,1]:
    for i in range(25):
        x=(i/24*2-1)*260;z=375+32+24*abs(x/260)**5
        b.tube([(x,side*260,z),(x,side*265,z)],4.8,'roof',10)
        b.tube([(x,side*265,z),(x,side*266,z)],2.1,'bronze',8)
b.finish('a01_pavilion_detail','architecture',0,'Added curved brackets and outward-facing ceramic tile-end disks. Same approved base dimensions.')
for variant in range(2):
    b=copy_builder('v01_pine_'+str(variant))
    for j in range(7):
        a=j*math.tau/7+.2*variant;length=58+j%3*14
        b.tube([(0,0,33),(math.cos(a)*length*.45,math.sin(a)*length*.45,10),(math.cos(a)*length,math.sin(a)*length,2)],[9,6,1],'wood',7)
    b.finish('v01_pine_rooted_'+str(variant),'vegetation',0,'Visible tapering roots ground the trunk without opaque canopy clusters.')
# Socket at x=+-128, top z=0. Continuous closed backing, shallow 128-unit face.
for corner in [False,True]:
    b=Builder();rects=[(0,0,256,48)]
    if corner:rects=[(0,0,256,48),(104,104,48,160)]
    for x,y,w,d in rects:
        b.box((x,y,-72),(w,d,112),'rock');b.box((x,y,-13),(w,d+4,10),'stone')
        for i in range(round(w/64)):
            b.box((x-w/2+32+i*64,y,-4),(64,d+6,8),'stone')
        for i in range(round(w/64)):
            b.rock((x-w/2+32+i*64,y-d/2,-124),(64,20,95+i%2*12),80+i)
    b.finish('t08_platform_corner'if corner else't08_platform_edge','terrain',.5,'256-unit sockets; 128-unit shallow solid face; top z=0; no gold stripe or overhanging paper plane.')
b=Builder()
for i in range(8):
    b.box((16+i*32,0,(-128-i*16)/2),(32,28,128-i*16),'stone')
b.finish('t08_stair_cheek','terrain',.4,'Side coping matches existing eight 32-unit treads with 16-unit drops. Decorative side only; does not cover walking lanes.')
for i,o in enumerate(objects.values()):o.location=((i%3)*950,(i//3)*1000,128)
bpy.data.libraries.write(os.path.join(OUT,'xianxia_detail_modules.blend'),{scene},fake_user=True)
bpy.app.driver_namespace['xxdetail']=dict(objects=objects,scene=scene,registry=registry,OUT=OUT)
print(json.dumps({'assets':len(registry),'triangles':sum(a['triangles']for a in registry),'path':OUT}))
