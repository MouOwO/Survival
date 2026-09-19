"""Build the approved ten native Blender arena models and Source 2 sources.

blender --background --threads 8 --python tools/build_ascension_arenas.py
Optional -- --no-render / --render-only (uses the packed authored blend).
"""
import json, math, sys
from pathlib import Path
import bpy, bmesh
from mathutils import Matrix, Vector

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT/'tools'))
from ascension_arena_spec import NAMESPACE as NS, PALETTE, REVISION, FOOTPRINT, stage

OUT=ROOT/'output'/NS
SOURCE=OUT/'source'
MODELS=SOURCE/'models'/NS
MATS=SOURCE/'materials'/NS
PREVIEWS=OUT/'previews'
for p in (OUT, MODELS, MATS, PREVIEWS): p.mkdir(parents=True, exist_ok=True)
HEADER='<!-- kv3 encoding:text:version{e21c7f3c-8a33-41c5-9977-a76d3a32aa0d} format:modeldoc28:version{fb63b6ca-f435-4aa0-a2c7-c66ddc651dca} -->\n'
HERO_POSITION=tuple(v*FOOTPRINT[0]/700 for v in (820,-1120,880))
HERO_SCALE=max(FOOTPRINT[0]*1.33,FOOTPRINT[1]*2.0)
TOP_SCALE=max(FOOTPRINT[0],FOOTPRINT[1]*1400/760)*1.18
SIDE_SCALE=FOOTPRINT[0]*1.16
OVERVIEW_SCALE=4700


def collision_file(name, index, shape):
    c,s=shape['center'],shape['size']
    vertices=[(c[0]+x*s[0]/2,c[1]+y*s[1]/2,c[2]+z*s[2]/2)
              for z in (-1,1) for x,y in [(-1,-1),(1,-1),(1,1),(-1,1)]]
    faces=[(3,2,1,0),(4,5,6,7),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7)]
    file=f'{name}_collision_{index}.obj'
    (MODELS/file).write_text('\n'.join(['o collision']+
        ['v %.6f %.6f %.6f'%(y,z,x) for x,y,z in vertices]+
        ['f '+' '.join(str(i+1) for i in f) for f in faces])+'\n')
    return '{_class="PhysicsHullFile" name="hull_'+str(index)+'" filename="models/'+NS+'/'+file+'" surface_prop="stone" collision_tags="solid" import_scale=1.0}'


def export_model(job, materials, material_meta):
    name,k=job['name'],job['kit']
    mesh=bpy.data.meshes.new(name)
    mesh.from_pydata(k.v,[],k.f);mesh.update()
    obj=bpy.data.objects.new(name,mesh)
    bpy.context.scene.collection.objects.link(obj)
    for key in k.keys:mesh.materials.append(materials[key])
    smooth=getattr(k,'smooth_faces',[])
    for i,(f,mi) in enumerate(zip(mesh.polygons,k.m)):
        f.material_index=mi;f.use_smooth=bool(smooth[i]) if i<len(smooth) else False
    bm=bmesh.new();bm.from_mesh(mesh)
    ids=bm.faces.layers.int.new('author_face')
    for i,f in enumerate(bm.faces): f[ids]=i
    bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces))
    bmesh.ops.triangulate(bm,faces=list(bm.faces))
    bmesh.ops.dissolve_degenerate(bm,edges=list(bm.edges),dist=.00001)
    bm.to_mesh(mesh);bm.free();mesh.update()
    author_ids=mesh.attributes['author_face'].data
    uv=mesh.uv_layers.new(name='SurfaceUV')
    axes=getattr(k,'grain_axis',[])
    tile_width={m['name']:m['recommended_uv_tile'] for m in material_meta}
    end_caps={}
    for f in mesh.polygons:
        key=k.keys[f.material_index];source=author_ids[f.index].value;n=f.normal
        axis=axes[source] if source<len(axes) else None
        if key in ('wood','wood_light') and axis is not None:
            v=Vector(axis);v-=n*v.dot(n)
            if v.length<.001:v=Vector((0,0,1)) if abs(n.z)<.9 else Vector((0,1,0))
            v.normalize();u=v.cross(n).normalized();tile=112
        else:
            other=[i for i in range(3) if i!=max(range(3),key=lambda i:abs(n[i]))]
            u=Vector(tuple(int(i==other[0]) for i in range(3)))
            v=Vector(tuple(int(i==other[1]) for i in range(3)))
            tile=tile_width[key]
        center=None
        if key=='wood_end':
            # End grain belongs at the center of each original timber cap;
            # world-space UVs leave a tiny post sampling only parallel rings.
            if source not in end_caps:
                points=[Vector(k.v[i]) for i in k.f[source]]
                cap_center=sum(points,Vector())/len(points)
                cap_width=max(max(p.dot(a) for p in points)-min(p.dot(a) for p in points) for a in (u,v))
                end_caps[source]=(cap_center,max(cap_width*1.3,8))
            center,tile=end_caps[source]
        for li in f.loop_indices:
            p=mesh.vertices[mesh.loops[li].vertex_index].co
            uv.data[li].uv=((p-center).dot(u)/tile+.5,(p-center).dot(v)/tile+.5) if center is not None else (p.dot(u)/tile,p.dot(v)/tile)
    mesh.attributes.remove(mesh.attributes['author_face'])
    bpy.ops.object.select_all(action='DESELECT');obj.select_set(True)
    bpy.context.view_layer.objects.active=obj;bpy.ops.object.material_slot_remove_unused()
    mesh.transform(Matrix.Rotation(-math.pi/2,4,'Z'))
    bpy.ops.export_scene.fbx(filepath=str(MODELS/(name+'.fbx')),use_selection=True,
        object_types={'MESH'},axis_forward='-Y',axis_up='Z',bake_anim=False)
    mesh.transform(Matrix.Rotation(math.pi/2,4,'Z'))
    paths=[m.name for m in mesh.materials]
    nodes=['{_class="RenderMeshList" children=[{_class="RenderMeshFile" filename="models/'+NS+'/'+name+'.fbx" import_scale=0.01}]}',
           '{_class="MaterialGroupList" children=[{_class="DefaultMaterialGroup" remaps=['+','.join('{from="'+m+'" to="'+m+'"}' for m in paths)+'] use_global_default=false}]}',
           '{_class="PhysicsShapeList" children=['+','.join(collision_file(name,i,s) for i,s in enumerate(job['collision']))+']}']
    (MODELS/(name+'.vmdl')).write_text(HEADER+'{rootNode={_class="RootNode" children=['+','.join(nodes)+']}}',encoding='utf-8')
    bounds=[[min(v.co[i] for v in mesh.vertices) for i in range(3)],
            [max(v.co[i] for v in mesh.vertices) for i in range(3)]]
    assert all(-FOOTPRINT[i]/2-.01 <= bounds[0][i] < bounds[1][i] <= FOOTPRINT[i]/2+.01 for i in range(2)),(name,bounds)
    meta=job['meta']
    obj['rank']=meta['rank'];obj['layers']=meta['layers'];obj['deck_z']=meta['deck_z']
    obj['title']=meta['label'];obj['surface_revision']=REVISION
    return obj,dict(name=name,label=meta['label'],category='ascension_arena',meta=meta,
        triangles=len(mesh.polygons),vertices=len(mesh.vertices),bounds=bounds,
        materials=paths,collision_hulls=len(job['collision']),collision_count=len(job['collision']),
        collision=job['collision'],import_scale=.01,emissive=False,pivot='XY center, Z=0 bottom')


def set_camera(scene, position, target, scale):
    camera=scene.camera
    camera.location=position
    camera.rotation_euler=(Vector(target)-camera.location).to_track_quat('-Z','Y').to_euler()
    camera.data.ortho_scale=scale


def photography(scene, backdrop_material):
    scene.render.engine='CYCLES';scene.cycles.samples=24;scene.cycles.use_denoising=True
    scene.render.image_settings.file_format='PNG';scene.render.resolution_percentage=100
    scene.view_settings.view_transform='AgX'
    world=bpy.data.worlds.new(scene.name+' World');world.use_nodes=True
    world.node_tree.nodes['Background'].inputs['Color'].default_value=(.55,.58,.62,1)
    world.node_tree.nodes['Background'].inputs['Strength'].default_value=.65;scene.world=world
    cam=bpy.data.cameras.new(scene.name+' Camera');cam.type='ORTHO';cam.clip_end=30000
    scene.camera=bpy.data.objects.new(scene.name+' Camera',cam);scene.collection.objects.link(scene.camera)
    sun=bpy.data.lights.new(scene.name+' Sun','SUN');sun.energy=2.4;sun.angle=.22
    light=bpy.data.objects.new(scene.name+' Sun',sun);scene.collection.objects.link(light)
    light.rotation_euler=(.40,-.65,-.40)
    plane=bpy.data.meshes.new(scene.name+' Backdrop')
    plane.from_pydata([(-12000,-12000,-2),(12000,-12000,-2),(12000,12000,-2),(-12000,12000,-2)],[],[(0,1,2,3)])
    plane.materials.append(backdrop_material)
    ground=bpy.data.objects.new('Preview backdrop (not exported)',plane);scene.collection.objects.link(ground)
    scene['revision']=REVISION;scene['purpose']='Independent approved arena art review; not a gameplay replacement'


def render_all():
    for rank in range(1,11):
        scene=bpy.data.scenes[f'{rank:02} - {stage(rank)["label"]}'];bpy.context.window.scene=scene
        z=stage(rank)['deck_z']+stage(rank)['float_preview_offset']
        for view,pos,target,scale,size in [
            ('hero',HERO_POSITION,(0,0,z*.5),HERO_SCALE,(1400,1000)),
            ('top',(0,0,1800),(0,0,0),TOP_SCALE,(1400,760)),
            ('side',(0,-1800,z*.5),(0,0,z*.5),SIDE_SCALE,(1400,470))]:
            set_camera(scene,pos,target,scale)
            scene.render.resolution_x,scene.render.resolution_y=size
            scene.render.filepath=str(PREVIEWS/f'arena_{rank:02}_{view}.png')
            bpy.ops.render.render(write_still=True)
        set_camera(scene,HERO_POSITION,(0,0,z*.5),HERO_SCALE)
        scene.render.resolution_x=1400;scene.render.resolution_y=1000
        print('ARENA_RENDERED',rank,flush=True)
    scene=bpy.data.scenes['00 - All ten arenas'];bpy.context.window.scene=scene
    set_camera(scene,(2600,-4200,4900),(0,0,30),OVERVIEW_SCALE)
    scene.render.resolution_x=1600;scene.render.resolution_y=1800
    scene.render.filepath=str(PREVIEWS/'all_arenas.png');bpy.ops.render.render(write_still=True)


if '--render-only' in sys.argv:
    bpy.ops.wm.open_mainfile(filepath=str(OUT/'ascension_arenas.blend'));render_all()
else:
    from ascension_arena_geometry import build_arenas
    from ascension_arena_materials import write_materials, configure_blender
    bpy.ops.wm.read_factory_settings(use_empty=True)
    matmeta=write_materials(MATS)
    materials={}
    for key in PALETTE:
        mat=bpy.data.materials.new(f'materials/{NS}/{key}.vmat')
        configure_blender(mat,key,MATS);materials[key]=mat
    backdrop=bpy.data.materials.new('Preview neutral backdrop');backdrop.use_nodes=True
    backdrop.node_tree.nodes['Principled BSDF'].inputs['Base Color'].default_value=(.16,.175,.19,1)
    backdrop.node_tree.nodes['Principled BSDF'].inputs['Roughness'].default_value=.88
    overview=bpy.context.scene;overview.name='00 - All ten arenas';photography(overview,backdrop)
    manifest=[]
    for job in build_arenas():
        bpy.context.window.scene=overview
        obj,record=export_model(job,materials,matmeta);manifest.append(record)
        meta=job['meta'];rank=meta['rank']
        solo=bpy.data.scenes.new(f'{rank:02} - {meta["label"]}');photography(solo,backdrop)
        duplicate=obj.copy();duplicate.data=obj.data;solo.collection.objects.link(duplicate)
        duplicate.location=(0,0,meta['float_preview_offset'])
        obj.location=(*meta['review_xy'],meta['float_preview_offset'])
        z=meta['deck_z']+meta['float_preview_offset']
        set_camera(solo,HERO_POSITION,(0,0,z*.5),HERO_SCALE)
        solo.render.resolution_x=1400;solo.render.resolution_y=1000
        print('ARENA_EXPORTED',rank,record['triangles'],record['bounds'],flush=True)
    (OUT/'asset_manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf-8')
    (OUT/'material_manifest.json').write_text(json.dumps(matmeta,ensure_ascii=False,indent=2),encoding='utf-8')
    bpy.context.window.scene=overview;set_camera(overview,(2600,-4200,4900),(0,0,30),OVERVIEW_SCALE)
    overview.render.resolution_x=1600;overview.render.resolution_y=1800
    for screen in bpy.data.screens:
        for area in screen.areas:
            if area.type=='VIEW_3D':area.spaces.active.clip_end=30000
    bpy.ops.file.pack_all();bpy.context.preferences.filepaths.save_version=0
    bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'ascension_arenas.blend'))
    if '--no-render' not in sys.argv:render_all()
print('ASCENSION_BUILD_COMPLETE',flush=True)
