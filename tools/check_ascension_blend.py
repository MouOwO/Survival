"""Check actual packed meshes and the unobstructed combat surface, not labels."""
import sys,json,math,struct
from pathlib import Path
import bpy
from mathutils import Vector
from mathutils.bvhtree import BVHTree
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tools'))
from ascension_arena_spec import stage,REVISION
OUT=ROOT/'output/ascension_arenas'
bpy.ops.wm.open_mainfile(filepath=str(OUT/'ascension_arenas.blend'))
assets=json.loads((OUT/'asset_manifest.json').read_text(encoding='utf-8'))
rows=[]
for a in assets:
    m=a['meta'];rank=m['rank'];scene=bpy.data.scenes[f'{rank:02} - {m["label"]}']
    obj=next(o for o in scene.objects if o.type=='MESH' and o.get('rank')==rank)
    mesh=obj.data
    assert len(mesh.polygons)==a['triangles'],(rank,'triangle count')
    assert all(len(f.vertices)==3 and f.area>1e-9 for f in mesh.polygons),(rank,'degenerate triangles')
    assert all(math.isfinite(x) for v in mesh.vertices for x in v.co),(rank,'nonfinite vertex')
    assert mesh.uv_layers.get('SurfaceUV') is not None,(rank,'missing UV')
    assert all(mat['surface_revision']==REVISION for mat in mesh.materials),(rank,'wrong material version')
    for mat in mesh.materials:
        for node in mat.node_tree.nodes:
            if node.type=='TEX_IMAGE':assert node.image and node.image.packed_file,(rank,mat.name,'unpacked image')
    bvh=BVHTree.FromPolygons([v.co for v in mesh.vertices],[list(f.vertices) for f in mesh.polygons],all_triangles=True)
    heights=[]
    # Dense samples within the intentionally empty center: a missed ray finds a
    # real hole; a tall hit catches a misplaced pillar/cloud ornament.
    for iy in range(15):
        for ix in range(41):
            x=(ix/40-.5)*(m['clear_combat_size'][0]-2)
            y=(iy/14-.5)*(m['clear_combat_size'][1]-2)
            p,n,index,distance=bvh.ray_cast(Vector((x,y,m['deck_z']+200)),Vector((0,0,-1)),300)
            assert p is not None,(rank,'open combat hole',x,y)
            assert m['deck_z']-4 <= p.z <= m['deck_z']+1.0,(rank,'obstruction or floor discontinuity',x,y,p.z)
            heights.append(p.z)
    rows.append(dict(rank=rank,triangles=len(mesh.polygons),combat_rays=len(heights),
                     sampled_floor_min=min(heights),sampled_floor_max=max(heights),packed_materials=len(mesh.materials)))
images=[]
for rank in range(1,11):
    for view,size in [('hero',(1400,1000)),('top',(1400,760)),('side',(1400,470))]:
        file=OUT/'previews'/f'arena_{rank:02}_{view}.png'
        data=file.read_bytes()
        assert data[:8]==b'\x89PNG\r\n\x1a\n' and struct.unpack('>II',data[16:24])==size,file
        images.append(str(file.relative_to(OUT)))
result=dict(status='PASS',revision=REVISION,meshes=rows,preview_files=images,
            total_combat_rays=sum(r['combat_rays'] for r in rows),runtime_verified=False,
            note='Actual Blender geometry raycast and packed texture checks; no claim of in-game navigation.')
(OUT/'blend_verification.json').write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8')
print('ASCENSION_BLEND_VERIFY_PASS',len(rows),'models',result['total_combat_rays'],'combat rays',flush=True)
