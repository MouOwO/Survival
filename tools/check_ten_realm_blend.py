"""Validate the saved ten-realm Blender asset using its actual geometry.

Run only after the exporter has saved the packed blend:
    blender --background --python tools/check_ten_realm_blend.py
Optional arguments after ``--``: --blend PATH --output PATH.

This checks the authored source meshes and preview scenes.  It does not assert
that Source 2 collision compilation, navigation or in-game rendering passed.
"""
import argparse
import json
import math
import sys
import traceback
from pathlib import Path

import bpy
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT/'tools'))
from ten_realm_spec import NAMESPACE, REVISION, NAMES, PALETTE, WATER_Z, realm


PARTS = ('combat_floor', 'shore', 'closed_walls', 'biome_dressing')
AREA_EPSILON = 1e-10
UV_AREA_EPSILON = 1e-13


def require(condition, *details):
    if not condition:
        raise AssertionError(details)


def finite(values):
    return all(math.isfinite(float(value)) for value in values)


def bounds_of(points):
    return [[min(p[i] for p in points) for i in range(3)],
            [max(p[i] for p in points) for i in range(3)]]


def close_vector(a, b, tolerance=1e-4):
    return all(abs(x-y) <= tolerance for x, y in zip(a, b))


def exported_parts(scene, rank):
    objects = [o for o in scene.objects if o.type == 'MESH'
               and o.get('realm_rank') == rank and bool(o.get('exported'))]
    found = {}
    for obj in objects:
        part = obj.get('part')
        require(part in PARTS, scene.name, obj.name, 'unexpected part', part)
        require(part not in found, scene.name, rank, 'duplicate exported part', part)
        require(obj.name.startswith(f'realm_{rank:02}__{part}'), obj.name, 'part/name disagreement')
        found[part] = obj
    require(set(found) == set(PARTS), scene.name, rank, 'missing parts', sorted(found))
    return found


def material_check(material, checked):
    if material.name in checked:
        return
    require(material.use_nodes and material.node_tree, material.name, 'missing material nodes')
    require(material.get('namespace') == NAMESPACE, material.name, 'wrong material namespace')
    require(material.get('surface_revision') == REVISION+'_material_response_v1',
            material.name, 'wrong material revision', material.get('surface_revision'))
    key = material.name.replace('\\', '/').rsplit('/', 1)[-1].split('.vmat')[0]
    require(key in PALETTE, material.name, 'unknown material key')
    require(material.name.replace('\\', '/') == f'materials/{NAMESPACE}/{key}.vmat',
            material.name, 'material must retain its VMAT path')
    images = []
    principled = []
    for node in material.node_tree.nodes:
        if node.type == 'TEX_IMAGE':
            image = node.image
            require(image is not None, material.name, node.name, 'missing image')
            require(bool(image.packed_file) or bool(image.packed_files),
                    material.name, image.name, 'texture is not packed')
            require(image.size[0] > 0 and image.size[1] > 0, image.name, 'invalid texture dimensions')
            images.append(image.name)
        if node.type == 'EMISSION':
            socket = node.inputs.get('Strength')
            require(socket and not socket.is_linked and abs(socket.default_value) < 1e-8,
                    material.name, 'emissive shader')
        if node.type == 'BSDF_PRINCIPLED':
            principled.append(node)
            strength = node.inputs.get('Emission Strength')
            require(strength and not strength.is_linked and abs(strength.default_value) < 1e-8,
                    material.name, 'nonzero or linked emission strength')
    require(principled, material.name, 'missing Principled surface')
    require(len(images) >= 4, material.name, 'missing color/normal/roughness/metallic inputs', images)
    require(any('_normal' in image for image in images), material.name, 'missing normal image')
    require(any('_color' in image for image in images), material.name, 'missing color image')
    checked[material.name] = dict(key=key, packed_images=sorted(set(images)), emissive=False)


def mesh_check(obj, rank, part, materials):
    mesh = obj.data
    require(mesh.vertices and mesh.polygons, rank, part, 'empty mesh')
    require(not obj.modifiers, rank, part, 'unexpected unevaluated modifiers')
    require(close_vector(obj.location, (0,0,0)), rank, part, 'solo origin changed')
    require(close_vector(obj.scale, (1,1,1)), rank, part, 'solo scale changed')
    require(all(abs(obj.matrix_world[i][j]-Matrix.Identity(4)[i][j]) < 1e-5
                for i in range(4) for j in range(4)), rank, part, 'nonidentity transform')
    require(all(finite(vertex.co) for vertex in mesh.vertices), rank, part, 'nonfinite vertex')
    require(all(finite(vertex.normal) and .8 <= vertex.normal.length <= 1.01
                for vertex in mesh.vertices), rank, part, 'invalid vertex normal or loose vertex')
    require(all(len(face.vertices) == 3 for face in mesh.polygons), rank, part, 'nontriangulated mesh')
    require(all(face.area > AREA_EPSILON and finite(face.normal) and face.normal.length > .99
                for face in mesh.polygons), rank, part, 'degenerate triangle or invalid face normal')
    require(mesh.materials and all(material is not None for material in mesh.materials),
            rank, part, 'empty material slot')
    require(all(0 <= face.material_index < len(mesh.materials) for face in mesh.polygons),
            rank, part, 'invalid face material index')
    uv = mesh.uv_layers.get('SurfaceUV')
    require(uv is not None and len(uv.data) == len(mesh.loops), rank, part, 'missing SurfaceUV')
    require(all(finite(loop.uv) for loop in uv.data), rank, part, 'NaN UV')
    zero_uv = []
    wood_triangles = 0
    for face in mesh.polygons:
        a,b,c = [uv.data[index].uv for index in face.loop_indices]
        area = abs((b.x-a.x)*(c.y-a.y)-(b.y-a.y)*(c.x-a.x))*.5
        if area <= UV_AREA_EPSILON:
            zero_uv.append(face.index)
        key = mesh.materials[face.material_index].name.rsplit('/',1)[-1].split('.vmat')[0]
        if key in ('wood','wood_light','wood_end','bark'):
            wood_triangles += 1
    require(not zero_uv, rank, part, 'collapsed UV triangles', zero_uv[:12], len(zero_uv))
    for material in mesh.materials:
        material_check(material, materials)
    return dict(name=obj.name, part=part, vertices=len(mesh.vertices), triangles=len(mesh.polygons),
                bounds=bounds_of([v.co for v in mesh.vertices]), materials=len(mesh.materials),
                wood_triangles_with_valid_uv=wood_triangles, degenerate_triangles=0,
                collapsed_uv_triangles=0)


def bvh_of(objects, accept=None):
    vertices, faces = [], []
    for obj in objects:
        offset = len(vertices)
        vertices.extend(obj.matrix_world@v.co for v in obj.data.vertices)
        for face in obj.data.polygons:
            if accept is None or accept(face):
                faces.append(tuple(offset+i for i in face.vertices))
    require(faces, 'empty raycast surface')
    # A nonzero Blender BVH epsilon expands triangles and can return a hit in
    # front of the actual wall plane near thin bevels. Use the exact triangles
    # for closure/gap checks instead of an inflated collision envelope.
    return BVHTree.FromPolygons(vertices, faces, all_triangles=True, epsilon=0)


def ground_checks(parts, spec):
    bvh = bvh_of(list(parts.values()))
    heights = []
    normal_z = []
    # A 20-unit pitch catches holes and any misplaced tree, post or coastal rock.
    # Ray origin is above the tallest dressing, so overhangs are also detected.
    for iy in range(30):
        for ix in range(30):
            x, y = -285+570*ix/29, -285+570*iy/29
            p, normal, index, distance = bvh.ray_cast(Vector((x,y,600)), Vector((0,0,-1)), 650)
            require(p is not None, spec['rank'], 'floor hole', x, y)
            require(-1 <= p.z <= .5001, spec['rank'], 'combat surface obstruction', x, y, p.z)
            # Sub-unit stone bevels deliberately have sloping normals. Their
            # walkable clearance is determined by actual height; retain the
            # normal statistics without treating a 0.6-unit bevel as a ramp.
            require(finite(normal) and normal.length > .99, spec['rank'], 'invalid floor hit normal', x, y)
            heights.append(p.z)
            normal_z.append(normal.z)
    markers = {}
    for marker in ('entry','spawn'):
        cx,cy,cz = spec[marker]
        samples = []
        for dx,dy in ((0,0),(-16,0),(16,0),(0,-16),(0,16),(-12,-12),(12,12)):
            p,normal,index,distance=bvh.ray_cast(Vector((cx+dx,cy+dy,600)),Vector((0,0,-1)),650)
            require(p is not None and -1 <= p.z <= .5001 and finite(normal) and normal.length > .99,
                    spec['rank'], marker, 'landing area is not flat', dx, dy, tuple(p) if p is not None else None)
            samples.append(p.z)
        markers[marker]=dict(center=spec[marker],samples=len(samples),min_z=min(samples),max_z=max(samples))
    return dict(grid_rays=len(heights),sampled_min_z=min(heights),sampled_max_z=max(heights),
                sampled_normal_z_min=min(normal_z),landings=markers)


def wall_checks(obj, spec):
    points=[vertex.co for vertex in obj.data.vertices]
    bounds=bounds_of(points)
    require(close_vector(bounds[0][:2],(-350,-350),.01)
            and close_vector(bounds[1][:2],(350,350),.01), spec['rank'],'wall footprint is not 700 square',bounds)
    rays=[]
    for axis in (0,1):
        cross=1-axis
        for sign in (-1,1):
            # Test the actual continuous wall skin at 322..350. Pillars and
            # ornamental plates protrude inward to 306; exclude those faces
            # instead of falsely interpreting their early hits as a bad wall.
            skin=bvh_of([obj],lambda f,a=axis,s=sign: min(s*obj.data.vertices[i].co[a] for i in f.vertices)>=321.9)
            distances=[]
            for h in (spec['wall_height']*.31,spec['wall_height']*.63):
                for j in range(69):
                    along=-340+680*j/68
                    origin=Vector((0,0,h));origin[cross]=along
                    direction=Vector((0,0,0));direction[axis]=sign
                    p,normal,index,distance=skin.ray_cast(origin,direction,365)
                    require(p is not None,spec['rank'],'open wall',axis,sign,along,h)
                    coordinate=p[axis]*sign
                    require(321.89<=coordinate<=350.01,spec['rank'],'wrong wall position',axis,sign,along,coordinate)
                    distances.append(coordinate)
            rays.append(dict(axis='XY'[axis],sign=sign,rays=len(distances),min=min(distances),max=max(distances)))
    return dict(bounds=bounds,footprint=[700,700],sides=rays,total_rays=sum(x['rays']for x in rays))


def dressing_checks(obj, rank):
    """Use connected mesh pieces, not the all-around assembly's global AABB."""
    mesh=obj.data
    parent=list(range(len(mesh.vertices)))
    def find(i):
        while parent[i]!=i:
            parent[i]=parent[parent[i]]
            i=parent[i]
        return i
    for edge in mesh.edges:
        a,b=(find(i)for i in edge.vertices)
        if a!=b:parent[b]=a
    groups={}
    for vertex in mesh.vertices:
        groups.setdefault(find(vertex.index),[]).append(vertex.co)
    bounds=bounds_of([v.co for v in mesh.vertices])
    require(all(-580<=bounds[0][i]<=bounds[1][i]<=580 for i in (0,1)),rank,'dressing outside extent',bounds)
    for component,vertices in groups.items():
        b=bounds_of(vertices)
        require(any(b[0][i]>=308.0 or b[1][i]<=-308.0 for i in (0,1)),
                rank,'dressing AABB invades clear combat space',component,b)
    return dict(bounds=bounds,connected_pieces=len(groups),interior_keep_out_half_extent=308,
                all_component_bounds_clear=True)


def water_check(scene):
    water=[obj for obj in scene.objects if obj.type=='MESH' and obj.name.startswith('Preview water (not exported)')]
    require(water,scene.name,'missing separate preview water')
    z=[]
    for obj in water:
        require(not obj.get('exported'),scene.name,obj.name,'preview water marked exported')
        z.extend((obj.matrix_world@vertex.co).z for vertex in obj.data.vertices)
    require(all(abs(height-WATER_Z)<1e-4 for height in z),scene.name,'water height changed',min(z),max(z))
    return dict(objects=len(water),z=WATER_Z,exported=False)


def check(blend, output):
    result=dict(status='RUNNING',revision=REVISION,blend=str(blend),rooms=[],materials={},
                runtime_verified=False,note='Saved Blender source mesh validation; compiled collision/navigation and in-game rendering require separate checks.')
    try:
        require(blend.is_file(),'missing authored blend',str(blend))
        bpy.ops.wm.open_mainfile(filepath=str(blend))
        overview=bpy.data.scenes.get('00 - All ten realms')
        require(overview is not None,'missing overview scene')
        total_rays=0
        for rank,label in enumerate(NAMES,1):
            scene=bpy.data.scenes.get(f'{rank:02} - {label}')
            require(scene is not None,rank,'missing solo scene',label)
            spec=realm(rank)
            parts=exported_parts(scene,rank)
            meshes=[mesh_check(parts[part],rank,part,result['materials'])for part in PARTS]
            ground=ground_checks(parts,spec)
            wall=wall_checks(parts['closed_walls'],spec)
            dressing=dressing_checks(parts['biome_dressing'],rank)
            water=water_check(scene)
            overview_parts=exported_parts(overview,rank)
            for part,instance in overview_parts.items():
                require(instance.data is parts[part].data,rank,part,'overview duplicates mesh instead of instancing')
                require(close_vector(instance.location,(*spec['review_xy'],0)),rank,part,'wrong overview placement',tuple(instance.location))
                require(close_vector(instance.scale,(1,1,1)),rank,part,'overview scale changed')
            total_rays+=ground['grid_rays']+sum(m['samples']for m in ground['landings'].values())+wall['total_rays']
            result['rooms'].append(dict(rank=rank,label=label,parts=meshes,
                                        total_triangles=sum(m['triangles']for m in meshes),
                                        combat=ground,walls=wall,dressing=dressing,water=water))
            print('TEN_REALM_BLEND_ROOM_PASS',rank,label,flush=True)
        all_exported=[o for o in overview.objects if o.type=='MESH' and o.get('exported')]
        require(len(all_exported)==40,'overview must contain exactly 40 exported part instances',len(all_exported))
        result.update(status='PASS',total_geometry_rays=total_rays,
                      total_triangles=sum(r['total_triangles']for r in result['rooms']),
                      checked_materials=len(result['materials']))
    except Exception as error:
        result.update(status='FAIL',error=str(error),traceback=traceback.format_exc())
        raise
    finally:
        output.parent.mkdir(parents=True,exist_ok=True)
        output.write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8')
    print('TEN_REALM_BLEND_CHECK_PASS',len(result['rooms']),'rooms',result['total_geometry_rays'],'geometry rays',flush=True)
    return result


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--blend',type=Path,default=ROOT/'output'/NAMESPACE/'ten_realm_arenas.blend')
    parser.add_argument('--output',type=Path,default=ROOT/'output'/NAMESPACE/'blend_check.json')
    args=parser.parse_args(sys.argv[sys.argv.index('--')+1:]if'--'in sys.argv else[])
    check(args.blend,args.output)


if __name__=='__main__':
    main()
