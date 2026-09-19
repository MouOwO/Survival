"""Author independent wood / attribute / greater-attribute practice samples.

Blender --background --python tools/build_themed_training_rooms.py -- wood
Uses the accepted gold layout and lighting, not the formal gameplay map.
"""
import sys,json,math
from pathlib import Path
import bpy,bmesh
from mathutils import Vector,Matrix
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tools'))
from gold_room_geometry import build_modules
from training_room_materials import THEMES,REVISION,build_materials

theme=sys.argv[sys.argv.index('--')+1] if '--' in sys.argv else 'wood'
spec=THEMES[theme];ns=spec['namespace']
OUT=ROOT/'output'/ns;SOURCE=OUT/'source';MODELS=SOURCE/'models'/ns;MATS=SOURCE/'materials'/ns
for d in (OUT,MODELS,MATS,OUT/'previews'):d.mkdir(parents=True,exist_ok=True)
if theme=='wood':
    from wood_training_geometry import replacements,extra_modules
    replaced=replacements();extras=extra_modules()
else:
    from attribute_training_geometry import replacements,extra_modules
    replaced=replacements(theme);extras=extra_modules(theme)
jobs=build_modules()
for job in jobs:
    if job['name'] in replaced:job.update(replaced[job['name']])
    if theme=='greater_attribute' and job['category']=='floor':
        # Ivory belongs on the perimeter trim. Keep the battle floor's value
        # range narrow, so random slabs don't become distracting white checks.
        kit=job['kit']
        kit.m=[kit.keys.index('stone') if kit.keys[m]=='stone_light' else m for m in kit.m]
jobs+=extras

# Reuse approved photography and native pine geometry without changing gold.
bpy.ops.wm.open_mainfile(filepath=str(ROOT/'output/gold_training_room/gold_training_room.blend'))
scene=bpy.data.scenes['Gold Practice Room - assembled'];scene.name=spec['title']+' - assembled'
library=bpy.data.scenes['B01-B16 Modular Library'];library.name=spec['title']+' - Modular Library'
bpy.context.window.scene=scene
native_mesh=bpy.data.objects.get('B15_native_pine_preview').data.copy()
for obj in list(bpy.data.objects):
    if obj.type=='EMPTY' or (obj.type=='MESH' and obj.name!='Preview backdrop (not exported)'):
        bpy.data.objects.remove(obj,do_unlink=True)
groups={c.name:c for c in scene.collection.children}
materials,matmeta=build_materials(theme,MATS)
HEADER='<!-- kv3 encoding:text:version{e21c7f3c-8a33-41c5-9977-a76d3a32aa0d} format:modeldoc28:version{fb63b6ca-f435-4aa0-a2c7-c66ddc651dca} -->\n'


def collision_file(name,index,shape):
    if 'vertices' in shape:verts=shape['vertices']
    else:
        c,s=shape['center'],shape['size']
        verts=[(c[0]+x*s[0]/2,c[1]+y*s[1]/2,c[2]+z*s[2]/2)
               for z in (-1,1) for x,y in [(-1,-1),(1,-1),(1,1),(-1,1)]]
    faces=[(3,2,1,0),(4,5,6,7),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7)]
    file=f'{name}_collision_{index}.obj'
    (MODELS/file).write_text('\n'.join(['o collision']+['v %.6f %.6f %.6f'%(y,z,x) for x,y,z in verts]+
                            ['f '+' '.join(str(i+1) for i in face) for face in faces])+'\n')
    surface='wood' if theme=='wood' and name.startswith(('b03','b04','b05','b06')) else 'stone'
    return '{_class="PhysicsHullFile" name="hull_'+str(index)+'" filename="models/'+ns+'/'+file+'" surface_prop="'+surface+'" collision_tags="solid" import_scale=1.0}'


objects={};manifest=[]
for index,job in enumerate(jobs):
    name,k=job['name'],job['kit'];mesh=bpy.data.meshes.new(name)
    mesh.from_pydata(k.v,[],k.f);mesh.update()
    obj=bpy.data.objects.new(name,mesh);scene.collection.objects.link(obj)
    # k.keys differs between specialized kits; bind by key, never palette index.
    for key in k.keys:mesh.materials.append(materials[key])
    for face,mi in zip(mesh.polygons,k.m):face.material_index=mi
    bm=bmesh.new();bm.from_mesh(mesh);source_index=bm.faces.layers.int.new('author_face')
    for i,face in enumerate(bm.faces):face[source_index]=i
    bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces))
    bmesh.ops.triangulate(bm,faces=list(bm.faces))
    bmesh.ops.dissolve_degenerate(bm,edges=list(bm.edges),dist=.00001)
    bm.to_mesh(mesh);bm.free();mesh.update()
    author_ids=mesh.attributes['author_face'].data
    uv=mesh.uv_layers.new(name='SurfaceUV')
    axes=getattr(k,'grain_axis',[])
    for face in mesh.polygons:
        key=k.keys[face.material_index];source=author_ids[face.index].value
        axis=axes[source] if source<len(axes) else None
        n=face.normal
        if key in ('wood','wood_light','bark') and axis is not None:
            v=Vector(axis);v-=n*v.dot(n)
            if v.length<.001:v=Vector((0,0,1)) if abs(n.z)<.9 else Vector((0,1,0))
            v.normalize();u=v.cross(n).normalized();tile=112
        else:
            dominant=max(range(3),key=lambda i:abs(n[i]));other=[i for i in range(3) if i!=dominant]
            u=Vector(tuple(1 if i==other[0] else 0 for i in range(3)))
            v=Vector(tuple(1 if i==other[1] else 0 for i in range(3)))
            tile=160 if key.startswith('stone') or key=='rock' else 112 if key.startswith('wood') or key=='bark' else 95 if key.startswith('mineral') else 90 if key=='teal' else 75
        for li in face.loop_indices:
            p=mesh.vertices[mesh.loops[li].vertex_index].co
            uv.data[li].uv=(p.dot(u)/tile,p.dot(v)/tile)
    mesh.attributes.remove(mesh.attributes['author_face'])
    bpy.ops.object.select_all(action='DESELECT');obj.select_set(True);bpy.context.view_layer.objects.active=obj
    bpy.ops.object.material_slot_remove_unused()
    mesh.transform(Matrix.Rotation(-math.pi/2,4,'Z'))
    bpy.ops.export_scene.fbx(filepath=str(MODELS/(name+'.fbx')),use_selection=True,object_types={'MESH'},axis_forward='-Y',axis_up='Z',bake_anim=False)
    mesh.transform(Matrix.Rotation(math.pi/2,4,'Z'))
    paths=[m.name for m in mesh.materials]
    nodes=['{_class="RenderMeshList" children=[{_class="RenderMeshFile" filename="models/'+ns+'/'+name+'.fbx" import_scale=0.01}]}',
           '{_class="MaterialGroupList" children=[{_class="DefaultMaterialGroup" remaps=['+','.join('{from="'+m+'" to="'+m+'"}' for m in paths)+'] use_global_default=false}]}']
    if job['collision']:nodes.append('{_class="PhysicsShapeList" children=['+','.join(collision_file(name,i,s) for i,s in enumerate(job['collision']))+']}')
    (MODELS/(name+'.vmdl')).write_text(HEADER+'{rootNode={_class="RootNode" children=['+','.join(nodes)+']}}',encoding='utf-8')
    bounds=[[min(v.co[i] for v in mesh.vertices) for i in range(3)],[max(v.co[i] for v in mesh.vertices) for i in range(3)]]
    manifest.append(dict(name=name,label=job['label'],category=job['category'],triangles=len(mesh.polygons),vertices=len(mesh.vertices),
                         bounds=bounds,materials=paths,collision_hulls=len(job['collision']),import_scale=.01,
                         pivot='module origin, Z=0 walking plane or bottom',emissive=False))
    obj['component']=job['label'];obj['native_resource']=False
    scene.collection.objects.unlink(obj);library.collection.objects.link(obj)
    obj.location=((index%6)*430,(index//6)*480,0);objects[name]=obj
    print('THEME_MODULE',theme,name,len(mesh.polygons),flush=True)

layout=json.loads((ROOT/'output/gold_training_room/room_layout.json').read_text(encoding='utf-8'))
for p in layout['placements']:
    # Keep walking boards coherent instead of checkerboard grain directions.
    if theme=='wood' and p['group']=='01 Paving':p['yaw']=0 if p['name']!='b01_niche_floor' else p['yaw']

# Theme props are kept outside the playable rectangle; no spawn obstructions.
extra_positions=[(-1168,-750,0,12),(1180,680,0,190),(-610,1320,0,170),(690,-1300,0,0)]
for i,(x,y,z,yaw) in enumerate(extra_positions):
    if extras:
        layout['placements'].append(dict(name=extras[i%len(extras)]['name'],origin=[x,y,z-12],yaw=yaw,
                                         scale=.90 if i>1 else 1,native=False,group='04 Edge planting'))
for index,p in enumerate(layout['placements']):
    data=native_mesh if p['native'] else objects[p['name']].data
    obj=bpy.data.objects.new(p['name']+'__'+str(index),data);groups[p['group']].objects.link(obj)
    obj.location=p['origin'];obj.rotation_euler=(math.radians(p.get('pitch',0)),0,math.radians(p['yaw']));obj.scale=(p['scale'],)*3
for m in layout['markers']:
    m['name']=m['name'].replace('challenge_02','challenge_'+spec['challenge'])
    obj=bpy.data.objects.new(m['name'],None);groups['03 Functional landmarks'].objects.link(obj)
    obj.location=m['origin'];obj.empty_display_type='PLAIN_AXES';obj.empty_display_size=36;obj['role']=m['role']
layout.update(theme=theme,namespace=ns,surface_revision=REVISION,main_map_modified=False)
for sc in (scene,library):
    sc['surface_revision']=REVISION;sc['purpose']=spec['title']+' independent art sample; no emission'
    sc.render.engine='CYCLES';sc.cycles.samples=24;sc.cycles.use_denoising=True
scene['theme_description']=spec['description']
camera=scene.camera;camdata=camera.data
def shot(name,position,target,ortho,resolution):
    camera.location=position;camera.rotation_euler=(Vector(target)-camera.location).to_track_quat('-Z','Y').to_euler()
    camdata.ortho_scale=ortho;scene.render.resolution_x,scene.render.resolution_y=resolution
    scene.render.filepath=str(OUT/'previews'/(name+'.png'));bpy.ops.render.render(write_still=True)

(OUT/'asset_manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf-8')
(OUT/'material_manifest.json').write_text(json.dumps(matmeta,ensure_ascii=False,indent=2),encoding='utf-8')
(OUT/'room_layout.json').write_text(json.dumps(layout,ensure_ascii=False,indent=2),encoding='utf-8')
shot('room_overview',(2600,-3700,3500),(0,90,20),3970,(1600,1500))
shot('room_top',(0,50,4500),(0,50,0),3650,(1500,1700))
shot('material_detail',(-420,-1860,660),(-745,-1055,70),980,(1400,1000))
shot('entry_detail',(580,410,620),(0,1110,90),1020,(1400,1000))
# Return saved file to an overall scene for convenient opening.
camera.location=(2600,-3700,3500);camera.rotation_euler=(Vector((0,90,20))-camera.location).to_track_quat('-Z','Y').to_euler()
camdata.ortho_scale=3970;scene.render.resolution_x=1600;scene.render.resolution_y=1500
scene.render.filepath=str(OUT/'previews/room_overview.png')
for screen in bpy.data.screens:
    for area in screen.areas:
        if area.type=='VIEW_3D':area.spaces.active.clip_end=30000
# Drop unreferenced old gold meshes/images before packing the new standalone file.
bpy.ops.outliner.orphans_purge(do_recursive=True)
bpy.ops.file.pack_all();bpy.context.preferences.filepaths.save_version=0
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/(ns+'.blend')))
print('THEME_ROOM_COMPLETE',theme,len(manifest),len(layout['placements']),flush=True)
