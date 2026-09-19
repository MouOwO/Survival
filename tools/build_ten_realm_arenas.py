"""Build ten approved square arenas as editable Blender parts + Source 2 assets.

blender --background --threads 10 --python tools/build_ten_realm_arenas.py
-- --no-render builds only; -- --render-only [--ranks 1,2] renders saved geometry.
"""
import json, math, sys, gc
from pathlib import Path
import bpy, bmesh
from mathutils import Matrix, Vector

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tools'))
from ten_realm_spec import NAMESPACE as NS, PALETTE, REVISION, FOOTPRINT, WATER_Z, realm

OUT=ROOT/'output'/NS;SOURCE=OUT/'source';MODELS=SOURCE/'models'/NS
MATS=SOURCE/'materials'/NS;PREVIEWS=OUT/'previews'
for path in(OUT,MODELS,MATS,PREVIEWS):path.mkdir(parents=True,exist_ok=True)
HEADER='<!-- kv3 encoding:text:version{e21c7f3c-8a33-41c5-9977-a76d3a32aa0d} format:modeldoc28:version{fb63b6ca-f435-4aa0-a2c7-c66ddc651dca} -->\n'


def bounds(points):
    return [[min(p[i]for p in points)for i in range(3)],
            [max(p[i]for p in points)for i in range(3)]]


def collision_file(name,index,shape):
    c,s=shape['center'],shape['size']
    v=[(c[0]+x*s[0]/2,c[1]+y*s[1]/2,c[2]+z*s[2]/2)
       for z in(-1,1)for x,y in[(-1,-1),(1,-1),(1,1),(-1,1)]]
    f=[(3,2,1,0),(4,5,6,7),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7)]
    file=f'{name}_collision_{index}.obj'
    (MODELS/file).write_text('\n'.join(['o collision']+['v %.6f %.6f %.6f'%(y,z,x)for x,y,z in v]+
        ['f '+' '.join(str(i+1)for i in face)for face in f])+'\n')
    return '{_class="PhysicsHullFile" name="hull_'+str(index)+'" filename="models/'+NS+'/'+file+'" surface_prop="stone" collision_tags="solid" import_scale=1.0}'


def create_part(job,part,materials,material_meta):
    k=job['kit'];v0,v1=part['vertices'];f0,f1=part['faces']
    name=job['name']+'__'+part['name']
    mesh=bpy.data.meshes.new(name)
    mesh.from_pydata(k.v[v0:v1],[],[tuple(i-v0 for i in face)for face in k.f[f0:f1]])
    mesh.update()
    for key in k.keys:mesh.materials.append(materials[key])
    for i,polygon in enumerate(mesh.polygons):
        polygon.material_index=k.m[f0+i]
        polygon.use_smooth=k.smooth_faces[f0+i]
    bm=bmesh.new();bm.from_mesh(mesh);layer=bm.faces.layers.int.new('author_face')
    for i,face in enumerate(bm.faces):face[layer]=f0+i
    bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces))
    bmesh.ops.triangulate(bm,faces=list(bm.faces))
    bmesh.ops.dissolve_degenerate(bm,edges=list(bm.edges),dist=.00001)
    bm.to_mesh(mesh);bm.free();mesh.update()
    ids=mesh.attributes['author_face'].data
    uv=mesh.uv_layers.new(name='SurfaceUV')
    tiles={m['name']:m['recommended_uv_tile']for m in material_meta}
    end_caps={}
    for face in mesh.polygons:
        key=k.keys[face.material_index];index=ids[face.index].value;n=face.normal
        axis=k.grain_axis[index] if index<len(k.grain_axis)else None
        if key in('wood','wood_light','bark') and axis is not None:
            v=Vector(axis);v-=n*v.dot(n)
            if v.length<.001:v=Vector((0,0,1))if abs(n.z)<.9 else Vector((0,1,0))
            v.normalize();u=v.cross(n).normalized();tile=112
        else:
            axes=[i for i in range(3)if i!=max(range(3),key=lambda j:abs(n[j]))]
            u=Vector(tuple(int(i==axes[0])for i in range(3)))
            v=Vector(tuple(int(i==axes[1])for i in range(3)));tile=tiles[key]
        center=None
        if key=='wood_end':
            if index not in end_caps:
                points=[Vector(k.v[i])for i in k.f[index]]
                center=sum(points,Vector())/len(points)
                span=max(max(p.dot(a)for p in points)-min(p.dot(a)for p in points)for a in(u,v))
                end_caps[index]=(center,max(span*1.3,8))
            center,tile=end_caps[index]
        for li in face.loop_indices:
            p=mesh.vertices[mesh.loops[li].vertex_index].co
            uv.data[li].uv=((p-center).dot(u)/tile+.5,(p-center).dot(v)/tile+.5)if center is not None else(p.dot(u)/tile,p.dot(v)/tile)
    mesh.attributes.remove(mesh.attributes['author_face'])
    obj=bpy.data.objects.new(name,mesh);bpy.context.scene.collection.objects.link(obj)
    bpy.ops.object.select_all(action='DESELECT');obj.select_set(True);bpy.context.view_layer.objects.active=obj
    bpy.ops.object.material_slot_remove_unused()
    obj['realm_rank']=job['meta']['rank'];obj['part']=part['name'];obj['exported']=True
    obj['surface_revision']=REVISION;obj['footprint_game_units']=[700,700]
    obj['title']=job['label']
    return obj,dict(name=part['name'],triangles=len(mesh.polygons),vertices=len(mesh.vertices),
                    bounds=bounds([v.co for v in mesh.vertices]),materials=[m.name for m in mesh.materials])


def export_model(job,materials,material_meta):
    objects=[];parts=[]
    for part in job['kit'].parts:
        obj,record=create_part(job,part,materials,material_meta);objects.append(obj);parts.append(record)
    bpy.ops.object.select_all(action='DESELECT')
    for obj in objects:
        obj.select_set(True);obj.data.transform(Matrix.Rotation(-math.pi/2,4,'Z'))
    bpy.context.view_layer.objects.active=objects[0]
    bpy.ops.export_scene.fbx(filepath=str(MODELS/(job['name']+'.fbx')),use_selection=True,
                            object_types={'MESH'},axis_forward='-Y',axis_up='Z',bake_anim=False)
    for obj in objects:obj.data.transform(Matrix.Rotation(math.pi/2,4,'Z'))
    mats=sorted({m.name for obj in objects for m in obj.data.materials})
    nodes=['{_class="RenderMeshList" children=[{_class="RenderMeshFile" filename="models/'+NS+'/'+job['name']+'.fbx" import_scale=0.01}]}',
           '{_class="MaterialGroupList" children=[{_class="DefaultMaterialGroup" remaps=['+','.join('{from="'+m+'" to="'+m+'"}'for m in mats)+'] use_global_default=false}]}',
           '{_class="PhysicsShapeList" children=['+','.join(collision_file(job['name'],i,s)for i,s in enumerate(job['collision']))+']}']
    (MODELS/(job['name']+'.vmdl')).write_text(HEADER+'{rootNode={_class="RootNode" children=['+','.join(nodes)+']}}',encoding='utf-8')
    k=job['kit'];meta=job['meta']
    meta.update(part_geometry=parts,dressing_elements=getattr(k,'dressing_elements',[]),
                dressing_summary=getattr(k,'dressing_summary',{}))
    wall=next(p for p in parts if p['name']=='closed_walls')['bounds']
    assert all(abs(wall[0][a]+350)<.02 and abs(wall[1][a]-350)<.02 for a in(0,1)),wall
    meta['wall_bounds']=wall
    meta['shoreline_bounds']=next(p for p in parts if p['name']=='shore')['bounds']
    allbounds=bounds(k.v)
    assert all(-580<=allbounds[0][i]<allbounds[1][i]<=580 for i in(0,1)),allbounds
    record=dict(name=job['name'],label=job['label'],category='ten_realm_arena',meta=meta,
                bounds=allbounds,triangles=sum(p['triangles']for p in parts),vertices=sum(p['vertices']for p in parts),
                materials=mats,collision=job['collision'],collision_count=len(job['collision']),
                collision_hulls=len(job['collision']),import_scale=.01,emissive=False,
                pivot='Square enclosed platform XY center; playable deck Z=0; natural shore below')
    return objects,record


def camera(scene,position,target,scale):
    scene.camera.location=position
    scene.camera.rotation_euler=(Vector(target)-scene.camera.location).to_track_quat('-Z','Y').to_euler()
    scene.camera.data.ortho_scale=scale


def photography(scene,water,overview=False):
    scene.render.engine='CYCLES';scene.cycles.samples=24;scene.cycles.use_denoising=True
    scene.render.image_settings.file_format='PNG';scene.render.resolution_percentage=100
    scene.render.threads_mode='FIXED';scene.render.threads=10
    scene.view_settings.view_transform='AgX'
    scene.view_settings.exposure=.35
    world=bpy.data.worlds.new(scene.name+' World');world.use_nodes=True
    world.node_tree.nodes['Background'].inputs['Color'].default_value=(.67,.75,.86,1)
    world.node_tree.nodes['Background'].inputs['Strength'].default_value=.65;scene.world=world
    cam=bpy.data.cameras.new(scene.name+' Camera');cam.type='ORTHO';cam.clip_end=30000
    scene.camera=bpy.data.objects.new(scene.name+' Camera',cam);scene.collection.objects.link(scene.camera)
    light=bpy.data.lights.new(scene.name+' Sun','SUN');light.energy=2.4;light.angle=.16
    sun=bpy.data.objects.new(scene.name+' Sun',light);scene.collection.objects.link(sun);sun.rotation_euler=(.39,-.62,-.45)
    size=9000 if overview else 2200
    mesh=bpy.data.meshes.new(scene.name+' Ocean')
    mesh.from_pydata([(-size,-size,WATER_Z),(size,-size,WATER_Z),(size,size,WATER_Z),(-size,size,WATER_Z)],[],[(0,1,2,3)])
    mesh.materials.append(water);uv=mesh.uv_layers.new(name='SurfaceUV')
    for loop in mesh.loops:
        p=mesh.vertices[loop.vertex_index].co;uv.data[loop.index].uv=(p.x/256,p.y/256)
    plane=bpy.data.objects.new('Preview water (not exported)',mesh);scene.collection.objects.link(plane)
    plane['exported']=False;plane['water_z']=WATER_Z
    scene['revision']=REVISION;scene['purpose']='Actual authored Blender geometry; 700-square battle platform with natural coast'


def render_all():
    ranks=range(1,11)
    if '--ranks' in sys.argv:ranks=[int(v)for v in sys.argv[sys.argv.index('--ranks')+1].split(',')]
    if '--overview-only' in sys.argv:ranks=[]
    for rank in ranks:
        scene=bpy.data.scenes[f'{rank:02} - {realm(rank)["label"]}'];bpy.context.window.scene=scene
        views=[('hero',(1060,-1300,1350),(0,0,14),1540,(1400,1100)),
               ('top',(0,0,1900),(0,0,0),1300,(1100,1100)),
               ('detail',(650,-950,560),(120,-365,-6),700,(1280,960))]
        if '--hero-only' in sys.argv:views=views[:1]
        for view,pos,target,scale,size in views:
            camera(scene,pos,target,scale);scene.render.resolution_x,scene.render.resolution_y=size
            scene.render.filepath=str(PREVIEWS/f'realm_{rank:02}_{view}.png')
            bpy.ops.render.render(write_still=True)
        camera(scene,(1060,-1300,1350),(0,0,14),1540)
        print('REALM_RENDERED',rank,flush=True)
    if '--overview-only' in sys.argv or ('--ranks' not in sys.argv and '--hero-only' not in sys.argv):
        scene=bpy.data.scenes['00 - All ten realms'];bpy.context.window.scene=scene
        camera(scene,(3500,-6200,8200),(0,0,0),8000)
        scene.render.resolution_x=1700;scene.render.resolution_y=2200
        scene.render.filepath=str(PREVIEWS/'all_realms.png');bpy.ops.render.render(write_still=True)


if '--render-only' in sys.argv:
    bpy.ops.wm.open_mainfile(filepath=str(OUT/'ten_realm_arenas.blend'));render_all()
else:
    from ten_realm_geometry import build_realms
    from ten_realm_materials import write_materials,configure_blender
    bpy.ops.wm.read_factory_settings(use_empty=True)
    matmeta=write_materials(MATS)
    materials={}
    for key in PALETTE:
        mat=bpy.data.materials.new(f'materials/{NS}/{key}.vmat')
        configure_blender(mat,key,MATS);materials[key]=mat
    overview=bpy.context.scene;overview.name='00 - All ten realms';photography(overview,materials['water'],True)
    manifest=[]
    for job in build_realms():
        bpy.context.window.scene=overview
        objects,record=export_model(job,materials,matmeta);manifest.append(record)
        meta=job['meta'];rank=meta['rank']
        solo=bpy.data.scenes.new(f'{rank:02} - {meta["label"]}');photography(solo,materials['water'])
        for obj in objects:
            duplicate=obj.copy();duplicate.data=obj.data;solo.collection.objects.link(duplicate)
            duplicate.location=(0,0,0);obj.location=(*meta['review_xy'],0)
        camera(solo,(1060,-1300,1350),(0,0,14),1540)
        solo.render.resolution_x=1400;solo.render.resolution_y=1100
        print('REALM_EXPORTED',rank,record['triangles'],record['bounds'],flush=True)
    (OUT/'asset_manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf-8')
    (OUT/'material_manifest.json').write_text(json.dumps(matmeta,ensure_ascii=False,indent=2),encoding='utf-8')
    bpy.context.window.scene=overview;camera(overview,(3500,-6200,8200),(0,0,0),8000)
    overview.render.resolution_x=1700;overview.render.resolution_y=2200
    for screen in bpy.data.screens:
        for area in screen.areas:
            if area.type=='VIEW_3D':
                space=area.spaces.active
                space.clip_end=30000
                space.region_3d.view_perspective='CAMERA'
                space.region_3d.view_camera_zoom=0
                space.shading.type='MATERIAL'
                space.shading.use_scene_world=True
                space.shading.use_scene_lights=True
    bpy.ops.file.pack_all();bpy.context.preferences.filepaths.save_version=0
    bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'ten_realm_arenas.blend'))
    if '--no-render' not in sys.argv:render_all()
print('TEN_REALM_BUILD_COMPLETE',flush=True)
