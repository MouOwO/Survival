"""Reusable 256-unit environment modules authored in the connected Blender.
No reference board is read by this script or bound to a material.
"""
import bpy, os, math, json, random, bmesh
from mathutils import Vector,Matrix
ROOT=r'D:\steam\steamapps\common\dota 2 beta\game\dota_addons\survival'
OUT=os.path.join(ROOT,'output','xianxia_kit'); MODELS=os.path.join(OUT,'models')
scene=bpy.data.scenes.new('Xianxia modular asset library');bpy.context.window.scene=scene
scene.unit_settings.system='NONE';registry=[];objects={}
materials={}
for name in ['stone','rock','roof','wood','grass','earth','bronze','array','water','leaf','blossom','ground_blend']:
    canonical='materials/xianxia_kit/xx_'+name+'.vmat'
    old=bpy.data.materials.get(canonical)
    if old:old.name='previous_'+name
    m=bpy.data.materials.new(canonical);m.use_nodes=True;nodes=m.node_tree.nodes;bs=next(n for n in nodes if n.type=='BSDF_PRINCIPLED')
    tex=nodes.new('ShaderNodeTexImage');tex.image=bpy.data.images.load(os.path.join(OUT,'materials','xx_'+name+'_color.png'),check_existing=True)
    m.node_tree.links.new(tex.outputs['Color'],bs.inputs['Base Color']);bs.inputs['Roughness'].default_value=.8
    if name in ['leaf','blossom']:
        # Geometry foliage has its own contour. Do not sample transparent cutout
        # RGB outside its disk through generic world UVs (it becomes black).
        m.node_tree.links.remove(bs.inputs['Base Color'].links[0])
        bs.inputs['Base Color'].default_value=(.17,.30,.13,1)if name=='leaf'else(.72,.36,.43,1)
        bs.inputs['Subsurface Weight'].default_value=.12
    if name=='bronze':bs.inputs['Metallic'].default_value=.55
    for suffix,socket in [('normal','Normal'),('roughness','Roughness')]:
        p=os.path.join(OUT,'materials','xx_'+name+'_'+suffix+'.png')
        if not os.path.exists(p):continue
        t=nodes.new('ShaderNodeTexImage');t.image=bpy.data.images.load(p,check_existing=True);t.image.colorspace_settings.name='Non-Color'
        if suffix=='normal':
            n=nodes.new('ShaderNodeNormalMap');n.inputs['Strength'].default_value=.55;m.node_tree.links.new(t.outputs['Color'],n.inputs['Color']);m.node_tree.links.new(n.outputs['Normal'],bs.inputs[socket])
        else:m.node_tree.links.new(t.outputs['Color'],bs.inputs[socket])
    materials[name]=m

class Builder:
    def __init__(self):self.v=[];self.f=[];self.mi=[]
    def mesh(self,v,f,mat):
        k=len(self.v);self.v.extend(v);self.f.extend([tuple(k+i for i in face)for face in f]);self.mi.extend([list(materials).index(mat)]*len(f))
    def box(self,c,s,mat='stone',angle=0):
        co,si=math.cos(angle),math.sin(angle);v=[]
        for z in [-1,1]:
            for x,y in [(-1,-1),(1,-1),(1,1),(-1,1)]:
                px=x*s[0]/2;py=y*s[1]/2;v.append((c[0]+px*co-py*si,c[1]+px*si+py*co,c[2]+z*s[2]/2))
        self.mesh(v,[(3,2,1,0),(4,5,6,7),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7)],mat)
    def tube(self,points,radii,mat='wood',sides=8):
        ps=list(map(Vector,points));v=[]
        for i,p in enumerate(ps):
            d=ps[min(i+1,len(ps)-1)]-ps[max(0,i-1)];d.normalize();u=d.cross(Vector((0,0,1)))
            if u.length<.01:u=d.cross(Vector((0,1,0)))
            u.normalize();w=d.cross(u).normalized();r=radii[i] if isinstance(radii,list)else radii
            v.extend([tuple(p+r*(u*math.cos(j*math.tau/sides)+w*math.sin(j*math.tau/sides)))for j in range(sides)])
        f=[tuple(reversed(range(sides))),tuple((len(ps)-1)*sides+j for j in range(sides))]
        for i in range(len(ps)-1):
            for j in range(sides):f.append((i*sides+j,i*sides+(j+1)%sides,(i+1)*sides+(j+1)%sides,(i+1)*sides+j))
        self.mesh(v,f,mat)
    def ring(self,c,r,t,mat='bronze',start=0,end=math.tau,steps=40):
        self.tube([(c[0]+r*math.cos(a),c[1]+r*math.sin(a),c[2])for a in [start+(end-start)*i/steps for i in range(steps+1)]],t,mat,6)
    def lathe(self,profile,mat='bronze',sides=24,c=(0,0,0)):
        v=[(c[0]+r*math.cos(i*math.tau/sides),c[1]+r*math.sin(i*math.tau/sides),c[2]+z)for r,z in profile for i in range(sides)]
        f=[tuple(reversed(range(sides))),tuple((len(profile)-1)*sides+i for i in range(sides))]
        for j in range(len(profile)-1):
            for i in range(sides):f.append((j*sides+i,j*sides+(i+1)%sides,(j+1)*sides+(i+1)%sides,(j+1)*sides+i))
        self.mesh(v,f,mat)
    def rock(self,c,s,seed=1):
        rng=random.Random(seed);v=[];sides=7
        for k,z in enumerate([0,.18,.68,1]):
            factor=[.87,1,.84,.44][k]
            for j in range(sides):
                a=j*math.tau/sides;rr=factor*rng.uniform(.88,1.1);v.append((c[0]+s[0]*math.cos(a)*rr/2,c[1]+s[1]*math.sin(a)*rr/2,c[2]+s[2]*z))
        f=[tuple(reversed(range(sides))),tuple(3*sides+i for i in range(sides))]
        for k in range(3):
            for j in range(sides):f.append((k*sides+j,k*sides+(j+1)%sides,(k+1)*sides+(j+1)%sides,(k+1)*sides+j))
        self.mesh(v,f,'rock')
    def leaf(self,c,length,width,angle,mat='leaf'):
        co,si=math.cos(angle),math.sin(angle)
        ridge=width*.09
        v=[(c[0]+a*co-b*si,c[1]+a*si+b*co,c[2]+z)for a,b,z in [(0,0,0),(length*.45,-width/2,ridge*.4),(length,0,0),(length*.45,width/2,ridge*.4),(length*.45,0,ridge)]]
        self.mesh(v,[(0,1,4),(1,2,4),(2,3,4),(3,0,4)],mat)
    def finish(self,name,category,bevel=0,notes=''):
        me=bpy.data.meshes.new(name);me.from_pydata(self.v,[],self.f);me.update();o=bpy.data.objects.new(name,me);scene.collection.objects.link(o)
        for m in materials.values():me.materials.append(m)
        for p,mi in zip(me.polygons,self.mi):
            p.material_index=mi
            if list(materials)[mi]=='wood':p.use_smooth=True
        bpy.ops.object.select_all(action='DESELECT');o.select_set(True);bpy.context.view_layer.objects.active=o
        if bevel:
            mod=o.modifiers.new('Small real edge bevel','BEVEL');mod.width=bevel;mod.segments=1;mod.affect='EDGES';bpy.ops.object.modifier_apply(modifier=mod.name)
        mod=o.modifiers.new('Export triangles','TRIANGULATE');bpy.ops.object.modifier_apply(modifier=mod.name)
        if any(p.area<1e-7 for p in o.data.polygons):
            bm=bmesh.new();bm.from_mesh(o.data);bmesh.ops.remove_doubles(bm,verts=list(bm.verts),dist=.00001);bmesh.ops.dissolve_degenerate(bm,edges=list(bm.edges),dist=.00001);bmesh.ops.triangulate(bm,faces=list(bm.faces));bm.to_mesh(o.data);bm.free()
        uv=o.data.uv_layers.new(name='UVMap')
        for p in o.data.polygons:
            axis=max(range(3),key=lambda a:abs(p.normal[a]));axes=[a for a in range(3)if a!=axis]
            for li in p.loop_indices:
                v=o.data.vertices[o.data.loops[li].vertex_index].co;uv.data[li].uv=(v[axes[0]]/256,v[axes[1]]/256)
        bpy.ops.object.material_slot_remove_unused()
        o.data.transform(Matrix.Rotation(-math.pi/2,4,'Z'))
        bpy.ops.export_scene.fbx(filepath=os.path.join(MODELS,name+'.fbx'),use_selection=True,object_types={'MESH'},apply_unit_scale=True,axis_forward='X',axis_up='Z',add_leaf_bones=False,bake_anim=False)
        o.data.transform(Matrix.Rotation(math.pi/2,4,'Z'))
        bounds=[[min(v.co[i]for v in o.data.vertices)for i in range(3)],[max(v.co[i]for v in o.data.vertices)for i in range(3)]]
        used=sorted(set(p.material_index for p in o.data.polygons));entry={'name':name,'category':category,'triangles':len(o.data.polygons),'bounds':bounds,'materials':[o.data.materials[i].name for i in used],'notes':notes,'pivot':'module origin, z=0 walkway for terrain; ground for props','units':'Source units (FBX ModelDoc import_scale .01)'}
        registry.append(entry);objects[name]=o
        with open(os.path.join(OUT,'asset_manifest.json'),'w')as f:json.dump(registry,f,indent=2)
        return o

def scroll(b,c,scale=1,axis='XY'):
    pts=[]
    for i in range(29):
        a=i/28*math.pi*2.4;r=(1-i/34)*16*scale;u=math.cos(a)*r;v=math.sin(a)*r
        pts.append((c[0]+u,c[1]+v,c[2])if axis=='XY'else(c[0]+u,c[1],c[2]+v))
    b.tube(pts,1.6*scale,'bronze',5)
def roof(b,width,depth,z,height,hip=True):
    if width<160:
        # Small stone lantern: a closed swept cap, not a full building roof.
        r=width/2
        lower=[(-r,-r,z+7),(r,-r,z+7),(r,r,z+7),(-r,r,z+7)]
        upper=[(-r,-r,z+14),(r,-r,z+14),(r,r,z+14),(-r,r,z+14),(-15,-15,z+height),(15,-15,z+height),(15,15,z+height),(-15,15,z+height)]
        b.mesh(lower+upper,[(3,2,1,0),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7),(4,5,9,8),(5,6,10,9),(6,7,11,10),(7,4,8,11),(8,9,10,11)],'stone')
        return
    def point(t,u,side):
        w=width/2*(1-t)+(22 if hip else width/2)*t;d=depth/2*(1-t)+12*t
        x=u*w;y=-d;zz=z+height*t+32*(1-t)**5+24*abs(u)**5*(1-t)
        if side==1:y=-y
        return (x,y,zz)
    for side in [0,1]:
        v=[point(i/10,j/16*2-1,side)for i in range(11)for j in range(17)]
        f=[(i*17+j,i*17+j+1,(i+1)*17+j+1,(i+1)*17+j)for i in range(10)for j in range(16)]
        if side==1:f=[tuple(reversed(face))for face in f]
        b.mesh(v,f,'roof');b.mesh([(x,y,z-9)for x,y,z in v],[tuple(reversed(face))for face in f],'wood')
        for j in range(25):
            pts=[point(i/10,j/24*2-1,side)for i in range(11)];b.tube(pts,3.2,'roof',6)
            p=pts[0];b.lathe([(4,0),(4,5),(3,7)],'bronze',8,c=(p[0],p[1],p[2]-4))
        for u in [-1,1]:b.tube([point(i/12,u,side)for i in range(13)],5,'bronze',8)
        b.tube([point(0,j/16*2-1,side)for j in range(17)],5,'wood',8)
    if hip:
        # End hips are independent curved planes, sharing the same corner slopes.
        for sign in [-1,1]:
            v=[]
            for i in range(11):
                t=i/10
                for j in range(17):
                    u=j/8-1;v.append((sign*(width/2*(1-t)+22*t),u*(depth/2*(1-t)+12*t),z+height*t+32*(1-t)**5+24*abs(u)**5*(1-t)))
            faces=[(i*17+j,i*17+j+1,(i+1)*17+j+1,(i+1)*17+j)for i in range(10)for j in range(16)]
            if sign<0:faces=[tuple(reversed(face))for face in faces]
            b.mesh(v,faces,'roof');b.mesh([(x,y,z-9)for x,y,z in v],[tuple(reversed(f))for f in faces],'wood')
            for j in range(15):b.tube([v[i*17+round(j/14*16)]for i in range(11)],3,'roof',6)
    b.tube([(-width*.2 if not hip else -22,0,z+height+5),(width*.2 if not hip else 22,0,z+height+5)],7,'bronze',8)

def terrain():
    for name,kind in [('t01_shore_straight','straight'),('t02_shore_outer','outer'),('t03_shore_inner','inner')]:
        b=Builder();rects=[(0,0,512,128)]if kind=='straight'else[(0,0,512,128),(192,192,128,256)]
        if kind=='inner':rects=[(0,0,512,128),(-192,-192,128,256)]
        for x,y,w,d in rects:
            b.box((x,y,-140),(w,d,216),'rock');b.box((x,y,-24),(w,d,16),'stone');b.box((x,y,-42),(w+2,d+2,12),'bronze')
            for i in range(round(w/64)):
                for j in range(max(1,round(d/64))):b.box((x-w/2+(i+.5)*64,y-d/2+(j+.5)*64,-7),(63,63,14),'stone')
            for i in range(round(w/70)):
                b.rock((x-w/2+35+i*70,y-d/2+10,-248),(85,50,180+(i%3)*22),i+13)
        b.finish(name,'terrain',.8,'512-unit sockets; top z=0, underside -248. Corners use 128-unit shore depth.')
    for ramp in [False,True]:
        b=Builder()
        if ramp:
            b.mesh([(-192,-128,-128),(192,-128,-128),(192,128,-128),(-192,128,-128),(192,128,0),(-192,128,0)],[(0,3,2,1),(0,1,4,5),(1,2,4),(2,3,5,4),(3,0,5)],'stone')
        else:
            for i in range(8):b.box((0,-128+(i+.5)*32,-128+(i+1)*8),(384,32,(i+1)*16),'stone')
        for s in [-1,1]:b.tube([(s*207,-132,-118),(s*207,136,12)],12,'stone',8)
        b.finish('t04_ramp'if ramp else't04_stairs','terrain',.7,'Clear width 384; rise128/run256. Use invisible gameplay ramp collision in map.')
    for kind in ['straight','corner','broken']:
        b=Builder();b.box((0,0,-5),(256,256,10),'ground_blend')
        for i in range(4):
            for j in range(4):
                keep=(i<2)if kind=='straight'else(i<2 or j<2)if kind=='corner'else((i+j*3)%5!=0)
                if keep:b.box((-96+i*64,-96+j*64,0),(61,61,7),'stone')
                elif(i+j)%2==0:b.rock((-96+i*64,-96+j*64,0),(20,22,12),i+j*9)
        b.finish('t05_transition_'+kind,'terrain',.7,'Reusable geometry paving edge with irregular missing stones; base material blend supplied separately.')
    for kind in ['straight','corner','post']:
        b=Builder();segments=[(0,0,0)]if kind=='straight'else[(0,0,0),(128,128,math.pi/2)]if kind=='corner'else[]
        for x,y,a in segments:
            b.box((x,y,35),(240,22,44),'stone',a);b.box((x,y,63),(250,30,12),'stone',a)
            if a==0:
                for px in [-64,0,64]:scroll(b,(x+px,y-12,36),.7,'XZ')
        for x,y in ([(-128,0),(128,0)]if kind=='straight'else[(-128,0),(128,0),(128,256)]if kind=='corner'else[(0,0)]):
            for z,w,h,mat in [(8,44,16,'stone'),(42,30,52,'stone'),(75,42,12,'stone'),(84,38,7,'roof')]:b.box((x,y,z),(w,w,h),mat)
        b.finish('t06_rail_'+kind,'terrain',1,'Low railing 88 units high; no auto collision. Leave stairs clear.')
    b=Builder();b.lathe([(256,-24),(256,-4),(248,0)],'stone',64)
    for r in [108,157,207,232]:b.ring((0,0,1),r,1.6)
    for i in range(4):a=i*math.pi/2;scroll(b,(185*math.cos(a),185*math.sin(a),2),1.4)
    b.finish('t07_array_dais','terrain',.6,'512 diameter; flat engraved-style bronze inlay above stone disc.')

def architecture():
    b=Builder()
    for z,w,h in [(10,512,20),(27,480,14),(44,448,20)]:b.box((0,0,z),(w,w,h),'stone')
    for i in range(3):b.box((0,-265-i*24,8+(2-i)*8),(176,28,16+(2-i)*16),'stone')
    for x in [-164,164]:
        for y in [-164,164]:
            b.box((x,y,72),(60,60,36));b.box((x,y,96),(46,46,14));b.tube([(x,y,98),(x,y,357)],14,'wood',12)
            for z,w in [(310,72),(335,94),(353,116)]:b.box((x,y,z),(w,32,16),'wood');b.box((x,y,z),(32,w,16),'wood')
    for y in [-166,166]:b.box((0,y,363),(382,26,30),'wood')
    for x in [-166,166]:b.box((x,0,363),(26,382,30),'wood')
    roof(b,520,520,375,135,True);b.lathe([(15,505),(20,518),(9,538),(0,560)],'bronze',12)
    for x in [-228,228]:
        for y in [-228,228]:b.tube([(x,y,399),(x,y,362)],2,'bronze',6);b.lathe([(7,348),(9,355),(4,366)],'bronze',10,c=(x,y,0))
    b.finish('a01_pavilion','architecture',.6,'Open four-column pavilion; structural tiled hip roof, brackets, finial and bells.')
    b=Builder()
    for x in [-328,328]:
        for z,w,h in [(12,112,24),(36,92,24),(90,74,84),(141,86,18)]:b.box((x,0,z),(w,w,h))
        b.box((x,0,305),(40,40,310),'wood');scroll(b,(x,-39,95),1.5,'XZ')
        for z,w in [(397,95),(425,133),(450,158)]:b.box((x,0,z),(w,46,18),'wood')
    b.box((0,0,451),(720,42,36),'wood');b.box((0,0,398),(628,24,24),'wood')
    for x in [-242,242]:scroll(b,(x,-24,414),1,'XZ')
    roof(b,832,272,470,112,False);b.finish('a02_gateway','architecture',.8,'Clear passage 582 wide; decoration has no collision and never occupies the opening.')
    b=Builder()
    for z,w,h in [(8,104,16),(24,82,16),(63,48,62),(102,92,16)]:b.box((0,0,z),(w,w,h),'stone')
    for x in [-28,28]:
        for y in [-28,28]:b.box((x,y,134),(10,10,54),'stone')
    b.box((0,0,132),(30,30,40),'bronze');roof(b,116,116,162,26,True);b.lathe([(10,188),(13,198),(0,218)],'stone',10)
    b.finish('a03_stone_lamp','architecture',.7,'Unlit prop by default. No flame particle or dynamic point light attached.')
    b=Builder();b.lathe([(27,26),(43,44),(48,68),(42,87),(50,92),(42,99),(31,112),(10,127)],'bronze',32)
    for a in [0,math.tau/3,math.tau*2/3]:
        b.tube([(29*math.cos(a),29*math.sin(a),35),(38*math.cos(a),38*math.sin(a),15),(46*math.cos(a),46*math.sin(a),5)],[8,7,5],'bronze',8)
    for s in [-1,1]:b.tube([(s*40,0,70),(s*66,0,82),(s*70,0,103),(s*59,0,112),(s*54,0,102)],5,'bronze',8)
    for r,z in [(43,49),(48,88),(27,115)]:b.ring((0,0,z),r,2)
    b.finish('a03_censer','architecture',.5,'Reusable bronze censer; smoke is optional and not baked into the mesh.')

def vegetation():
    for flower in [False,True]:
        for variant in range(2):
            rng=random.Random(813+variant+10*flower);b=Builder();height=(460 if flower else 560)*(1 if variant==0 else .72)
            trunk=[(math.sin(i*.8)*19+i*(13 if variant else 3),math.sin(i*.6)*13,height*i/7)for i in range(8)]
            b.tube(trunk,[26*(1-i/8)**1.15+2 for i in range(8)],'wood',10)
            for k in range(18 if flower else 15):
                t=2+k%6;start=Vector(trunk[t]);a=k*2.399;length=145+(5-t)*17;end=start+Vector((math.cos(a)*length,math.sin(a)*length,30+rng.random()*32))
                mid=start.lerp(end,.58)+Vector((0,0,-12));b.tube([start,mid,end],[12,6,2],'wood',8)
                for j in range(9 if flower else 6):
                    u=(j+1)/10;tip=mid.lerp(end,u)+Vector((rng.uniform(-48,48),rng.uniform(-48,48),rng.uniform(5,26)))
                    b.tube([mid.lerp(end,u*.8),tip],[2.7,.7],'wood',5)
                    if flower:
                        for f in range(7):
                            c=tip+Vector((rng.uniform(-23,23),rng.uniform(-23,23),rng.uniform(-8,14)))
                            for petal in range(5):b.leaf(c,10+rng.random()*4,9,petal*math.tau/5,'blossom')
                    else:
                        for f in range(18):
                            c=tip+Vector((rng.uniform(-39,39),rng.uniform(-30,30),rng.uniform(-5,12)))
                            for needle in range(3):b.leaf(c,19+rng.random()*13,4,a+needle*2.1,'leaf')
            for k in range(4):b.rock((rng.uniform(-42,42),rng.uniform(-35,35),0),(45,32,24+rng.random()*18),k)
            b.finish(('v02_peach_'if flower else'v01_pine_')+str(variant),'vegetation',0,'Curved tapering trunk; individually modeled foliage; no opaque canopy balls.')
    for i in range(3):
        b=Builder();b.rock((0,0,0),(95+i*38,72+i*19,90+i*66),64+i);b.finish('v03_rock_'+str(i),'vegetation',1)
    for name in ['fern','grass','shrub']:
        b=Builder();rng=random.Random(18)
        for k in range(10):
            a=k*2.399;length=35+rng.random()*25
            if name=='fern':
                for j in range(7):
                    t=j/7;c=(math.cos(a)*length*t,math.sin(a)*length*t,math.sin(t*math.pi)*16)
                    for side in [-1,1]:b.leaf(c,(1-t)*17+4,7,a+side*.9)
            else:
                for j in range(5):b.leaf((rng.uniform(-14,14),rng.uniform(-14,14),j*3),length if name=='grass'else 24,3 if name=='grass'else 14,a)
        b.finish('v03_'+name,'vegetation',0)

def save_library():
    for i,(name,o)in enumerate(objects.items()):o.location=((i%6)*1100,(i//6)*1100,270 if name.startswith('t0')else 0)
    bpy.data.libraries.write(os.path.join(OUT,'xianxia_library.blend'),{scene},fake_user=True)
    print(json.dumps({'assets':len(registry),'triangles':sum(a['triangles']for a in registry),'file':os.path.join(OUT,'xianxia_library.blend')}))
