"""Read-only compiled/static validation of the ten 700-square island arenas.

Run after build/install. Writes only output/ten_realm_arenas/verification.json;
embedded VPK resources are inspected through resourceinfo's virtual paths.
PASS is asset/source/spatial verification, not in-game visual or movement QA.
No Blender or generation module is imported.
"""
import hashlib
import json
import math
import re
import struct
import subprocess
import zlib
from functools import lru_cache
from pathlib import Path

from asset_validation import CONTENT, installed_source, verify_map_vpk
from ten_realm_spec import NAMESPACE, REVISION, PALETTE, FOOTPRINT, CLEAR_HALF, WATER_Z, realm

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'output' / NAMESPACE
SOURCE = OUT / 'source'
INSPECTOR = ROOT.parents[1] / 'bin/win64/resourceinfo.exe'
REVIEW = 'ten_realm_arenas_review'


def read_json(path):
    return json.loads(Path(path).read_text(encoding='utf-8-sig'))


@lru_cache(maxsize=220)
def dump(path):
    path = Path(path)
    path = path if path.is_absolute() else ROOT / path
    return subprocess.check_output([str(INSPECTOR), '-i', str(path), '-all']).decode('utf-8', errors='replace')


def near(a, b, tolerance=.04):
    return abs(float(a)-float(b)) <= tolerance


def same(a, b, tolerance=.04):
    return len(a) == len(b) and all(near(x, y, tolerance) for x, y in zip(a, b))


def same_bounds(a, b, tolerance=.04):
    return len(a) == len(b) == 2 and all(same(x, y, tolerance) for x, y in zip(a, b))


def union_bounds(bounds):
    return [[min(b[0][i] for b in bounds) for i in range(3)],
            [max(b[1][i] for b in bounds) for i in range(3)]]


def bounds_of(points):
    return [[min(p[i] for p in points) for i in range(3)],
            [max(p[i] for p in points) for i in range(3)]]


def parsed_bounds(text):
    mins = re.findall(r'm_vMinBounds\s*=\s*\[([^\]]+)\]', text)
    maxs = re.findall(r'm_vMaxBounds\s*=\s*\[([^\]]+)\]', text)
    assert len(mins) == len(maxs), 'Unpaired compiled bounds'
    result = []
    for low, high in zip(mins, maxs):
        b = [[float(v.strip()) for v in row.split(',')] for row in (low, high)]
        assert all(len(row) == 3 and all(math.isfinite(v) for v in row) for row in b)
        result.append(b)
    return result


def compiled_float(text, key, expected, material):
    match = re.search(r'm_name = "'+re.escape(key)+r'"\s+m_flValue = ([\d.eE+-]+)', text)
    assert match and near(float(match[1]), expected, .001), (material, 'compiled float', key, expected)


def own_relative(path):
    p = path.replace('\\', '/').lower()
    return (p.startswith('models/'+NAMESPACE+'/') or p.startswith('materials/'+NAMESPACE+'/')
            or p == f'maps/{REVIEW}.vmap' or p.startswith('maps/prefabs/ten_realm_arena_'))


def fresh_dependencies(text, name):
    """Check compiler RED2 input CRCs against actual current installed bytes."""
    checked = []
    pattern = (r'\{\s*m_RelativeFilename = "([^"]+)"\s+m_SearchPath = "([^"]*)"\s*'
               r'm_nFileCRC = (\d+)\s+m_bOptional = (true|false)\s*'
               r'm_bFileExists = (true|false)\s*m_bIsGameFile = (true|false)\s*\}')
    for match in re.finditer(pattern, text):
        relative, search_path, crc, optional, existed, game_file = match.groups()
        if not own_relative(relative):
            continue
        assert search_path in ('dota_addons/survival', ''), (name, 'unexpected dependency search path', search_path)
        target = (ROOT if game_file == 'true' else CONTENT) / relative
        if game_file == 'true' and not target.is_file() and (Path(str(target)+'_c')).is_file():
            target = Path(str(target)+'_c')
        if optional == 'true' and existed == 'false':
            # The compiler records absent optional texture-setting sidecars.
            assert not target.exists() and int(crc) == 0, (name, 'optional dependency changed', relative)
            continue
        assert target.is_file(), (name, 'missing input dependency', relative)
        actual = zlib.crc32(target.read_bytes())
        assert actual == int(crc), (name, 'stale compiled input', relative, actual, int(crc))
        checked.append(relative)
    return sorted(set(checked))


def physics_bounds(text, name):
    match = re.search(r'--- vmdl block PHYS[^\n]*\n([\s\S]*?)(?=\n--- |\Z)', text)
    assert match, (name, 'missing PHYS block')
    physics = match[1]
    hulls = parsed_bounds(physics)
    assert len(hulls) == len(re.findall(r'\bm_Hull\s*=', physics)) == 5, (name, 'actual compiled PHYS hull count', len(hulls))
    for key in ('physics_shape_count', 'physics_shape_hull_count'):
        count = re.search(r'\b'+key+r'\s*=\s*(\d+)', text)
        assert count and int(count[1]) == 5, (name, key)
    return hulls


def check_asset(asset):
    meta = asset['meta']; rank = meta['rank']; expected = realm(rank); name = asset['name']
    for key, value in expected.items():
        assert meta[key] == value, (name, 'specification mismatch', key)
    assert name == expected['name'] and asset['label'] == expected['label']
    assert asset['category'] == 'ten_realm_arena' and not asset['emissive']
    assert asset['collision_count'] == asset['collision_hulls'] == len(asset['collision']) == 5
    assert asset['vertices'] > 0 and asset['triangles'] > 0 and meta['wall_closed']
    bounds = asset['bounds']
    assert all(-580.04 <= bounds[0][i] < bounds[1][i] <= 580.04 for i in (0,1)), (name, 'shore envelope')
    parts = {p['name']:p for p in meta['part_geometry']}
    assert set(parts) == {'combat_floor','shore','closed_walls','biome_dressing'}
    assert all(p['vertices'] > 0 and p['triangles'] > 0 for p in parts.values())
    assert sum(p['vertices'] for p in parts.values()) == asset['vertices']
    assert sum(p['triangles'] for p in parts.values()) == asset['triangles']
    assert same_bounds(union_bounds([p['bounds'] for p in parts.values()]), bounds)
    walls = parts['closed_walls']['bounds']
    assert same(walls[0][:2],[-350,-350]) and same(walls[1][:2],[350,350]), (name, 'walled platform is not 700-square')
    assert same_bounds(meta['wall_bounds'], walls) and walls[1][2] >= meta['wall_height']
    shore = parts['shore']['bounds']
    assert same_bounds(meta['shoreline_bounds'],shore) and shore[0][2] < WATER_Z < shore[1][2]
    assert all(shore[0][i] < -350 and shore[1][i] > 350 for i in (0,1)), (name, 'missing exterior shore')
    floor = parts['combat_floor']['bounds']
    assert floor[0][2] <= 0 <= floor[1][2] <= .75, (name, 'combat surface has raised obstacles',floor)
    assert meta['dressing_elements'] and meta['dressing_summary']['rank'] == rank
    for detail in meta['dressing_elements']:
        b = detail['bounds']
        assert not detail['collision'] and not detail['emissive']
        assert all(-580.04 <= b[0][i] <= b[1][i] <= 580.04 for i in (0,1))
        assert any(b[0][i] >= CLEAR_HALF or b[1][i] <= -CLEAR_HALF for i in (0,1)), (name, 'dressing blocks interior', detail['label'])
    wanted = [dict(center=[0,0,-8],size=[700,700,16])]
    for axis in (0,1):
        for sign in (-1,1):
            center=[0,0,55];size=[700,700,110];center[axis]=sign*328;size[axis]=44
            wanted.append(dict(center=center,size=size))
    for actual, want in zip(asset['collision'],wanted):
        assert same(actual['center'],want['center']) and same(actual['size'],want['size']), (name,'collision shape')
    model = f'models/{NAMESPACE}/{name}.vmdl'
    source = (SOURCE/model).read_text(encoding='utf-8-sig')
    assert source.count('_class="PhysicsHullFile"') == 5
    compiled = dump(model+'_c')
    render_bounds = parsed_bounds(compiled.split('--- vmdl block PHYS')[0])
    assert render_bounds and same_bounds(union_bounds(render_bounds),bounds), (name,'compiled actual render bounds',render_bounds,bounds)
    observed_hulls = physics_bounds(compiled,name)
    for shape in asset['collision']:
        b = [[shape['center'][i]+sign*shape['size'][i]/2 for i in range(3)] for sign in (-1,1)]
        matches = [i for i,observed in enumerate(observed_hulls) if same_bounds(b,observed)]
        assert len(matches)==1, (name,'compiled hull shape mismatch',b,observed_hulls)
        observed_hulls.pop(matches[0])
    for material in asset['materials']:
        assert material.startswith(f'materials/{NAMESPACE}/') and material in compiled, (name,'material dependency',material)
    dependencies = fresh_dependencies(compiled,name)
    assert model in dependencies and f'models/{NAMESPACE}/{name}.fbx' in dependencies
    assert len([p for p in dependencies if p.endswith('.obj')]) == 5
    return dict(name=name,rank=rank,compiled_render_bounds=True,compiled_render_meshes=len(render_bounds),
                physics_hulls=5,physics_hull_bounds_match=True,part_geometry=4,dressing_elements=len(meta['dressing_elements']),
                interior_obstruction=False,triangles=asset['triangles'],fresh_compiler_inputs=len(dependencies))


def png_stats(path):
    """Read generated RGB8 PNGs and sample spatial variance, without Pillow."""
    data=path.read_bytes();assert data[:8]==b'\x89PNG\r\n\x1a\n',path
    offset=8;compressed=[];width=height=None
    while offset<len(data):
        size=struct.unpack_from('!I',data,offset)[0];kind=data[offset+4:offset+8]
        chunk=data[offset+8:offset+8+size];crc=struct.unpack_from('!I',data,offset+8+size)[0]
        assert zlib.crc32(kind+chunk)==crc,(path,'PNG CRC')
        if kind==b'IHDR':
            width,height,depth,mode,compression,filtering,interlace=struct.unpack('!2I5B',chunk)
            assert depth==8 and mode==2 and interlace==0,(path,'unsupported generated PNG')
        elif kind==b'IDAT':compressed.append(chunk)
        offset+=12+size
    assert width==height==1024,(path,'texture resolution')
    raw=zlib.decompress(b''.join(compressed));stride=width*3+1
    assert len(raw)==stride*height and all(raw[y*stride]==0 for y in range(height)),(path,'generated RGB filter contract')
    samples=[[raw[y*stride+1+x*3+c]/255 for c in range(3)]
             for y in range(0,height,16) for x in range(0,width,16)]
    means=[sum(p[c] for p in samples)/len(samples) for c in range(3)]
    std=[math.sqrt(sum((p[c]-means[c])**2 for p in samples)/len(samples)) for c in range(3)]
    return dict(size=[width,height],mean=means,spatial_std=std,grayscale=all(p[0]==p[1]==p[2] for p in samples))


def check_material(material):
    key=material['name'];relative=f'materials/{NAMESPACE}/{key}.vmat'
    assert material['revision']==REVISION+'_material_response_v1' and not material['emissive']
    assert material['engine_reflectance_channel']=='linear R' and material['normal_std']>.000001
    assert material['color_std']>.001 and material['recommended_uv_tile']>0
    text=dump(relative+'_c')
    assert 'global_lit_simple' in text and 'F_NORMAL_MAP = 1' in text and 'F_SPECULAR = 1' in text,key
    assert 'F_FULLBRIGHT = 1' not in text and 'F_SELF_ILLUM = 1' not in text,(key,'emission')
    if material['double_sided']:
        assert 'F_RENDER_BACKFACES = 1' in text,(key,'missing backfaces')
    for param,value in [('g_flSpecularIntensity',material['specular_intensity']),('g_flBumpStrength',material['bump_strength']),('g_flSpecularBloom',0.)]:
        compiled_float(text,param,value,key)
    spec=re.search(r'm_name = "g_tSpecular"\s+m_pValue = resource:"([^"]+)"',text)
    assert spec and f'/{key}_reflectance_' in spec[1],(key,'reflection not bound')
    assert f'{key}_normal' in text and f'{key}_color' in text,(key,'missing normal/color')
    textures=sorted(set(re.findall(r'resource:"(materials/'+NAMESPACE+r'/[^\"]+\.vtex)"',text)))
    assert len(textures)>=3,(key,'compiled texture dependencies')
    fresh=fresh_dependencies(text,key)
    assert relative in fresh,(key,'missing source VMAT dependency')
    texture_inputs=[]
    for texture in textures:
        path=ROOT/(texture+'_c');assert path.is_file(),(key,'missing compiled texture',texture)
        texture_inputs.extend(fresh_dependencies(dump(path),texture))
    stats={}
    for suffix in ('color','normal','reflectance','roughness','metallic'):
        p=SOURCE/f'materials/{NAMESPACE}/{key}_{suffix}.png'
        stats[suffix]=png_stats(p)
        if suffix in ('reflectance','roughness','metallic'):
            assert stats[suffix]['grayscale'],(key,suffix,'must be scalar')
    assert max(stats['color']['spatial_std'])>.0001,(key,'actual color PNG constant')
    assert max(stats['normal']['spatial_std'][:2])>.00005,(key,'actual normal PNG constant')
    assert stats['reflectance']['spatial_std'][0]>0,(key,'actual reflection PNG constant')
    if key in ('gold','bronze','iron'):
        assert material['metallic_mean']>.15 and material['reflectance_mean']>.15,(key,'metal response absent')
    else:
        assert near(material['metallic_mean'],0,.00001),(key,'dielectric accidentally metallic')
    return dict(name=key,type=material['type'],normal=True,reflection=True,double_sided=material['double_sided'],
                specular_intensity=material['specular_intensity'],fresh_inputs=len(set(fresh+texture_inputs)),
                texture_payloads_verified=5,spatial_color_std=max(stats['color']['spatial_std']),emission=False)


def mesh_positions(text):
    streams=re.finditer(r'"name" "string" "position:0"[\s\S]*?"data" "vector3_array"\s*\[([^\]]*)\]',text)
    return [[[float(x) for x in m[1].split()] for m in re.finditer(r'"([^\"]+)"',s[1])] for s in streams]


def check_support(points, support):
    assert len(points)==8 and same_bounds(bounds_of(points),support['bounds']),'serialized support mismatch'
    assert support['size']==[612,612] and not support['rendered']
    assert near(support['top']-support['bottom'],4)
    assert support['material']==f'materials/{NAMESPACE}/floor_support.vmat'


def check_nav(text,layout):
    match=re.search(r'"gridnavFlags" "\w+_array"\s*\[([^\]]*)\]',text)
    assert match,'serialized navigation mask missing'
    flags=[int(v) for v in re.findall(r'"([^\"]+)"',match[1])]
    assert len(flags)==128*128
    counts={str(rank):0 for rank in range(1,11)}
    for y in range(128):
        for x in range(128):
            px,py=-4096+x*64+32,-4096+y*64+32
            matches=[p for p in layout['placements'] if abs(px-p['origin'][0])<306 and abs(py-p['origin'][1])<306]
            assert len(matches)<=1
            assert flags[y*128+x]==(0 if matches else 1),('nav outside combat floor',x,y)
            if matches:counts[str(matches[0]['rank'])]+=1
    assert counts==layout['open_cells_by_rank']==layout['navigation']['open_cells_by_rank']
    assert sum(counts.values())==layout['open_grid_cells']==layout['navigation']['open_cells']
    assert all(count>0 for count in counts.values())
    hidden=re.search(r'"cellsHidden" "\w+_array"\s*\[([^\]]*)\]',text)
    assert hidden and set(re.findall(r'"([^\"]+)"',hidden[1]))=={'1'},'native floor unexpectedly visible'
    assert '"gridWidth" "int" "32"' in text and '"gridHeight" "int" "32"' in text
    return counts


def marker_present(text,marker):
    # Confine the origin match to this entity; the helper serializes origin
    # after entity_properties, while some existing VMAPs put it before them.
    name='"targetname" "string" "'+marker['name']+'"'
    assert name in text,('marker absent',marker['name'])
    at=text.index(name);start=text.rfind('"CMapEntity"',0,at)
    end=text.find('"CMap',at+len(name))
    block=text[start:end if end!=-1 else len(text)]
    origin=re.search(r'"origin" "vector3" "([^"]+)"',block)
    assert origin and same([float(v) for v in origin[1].split()],marker['origin']),('marker origin',marker['name'])


def check_layout(assets,layout,map_meta):
    assert layout['namespace']==NAMESPACE and layout['review']==REVIEW and not layout['main_map_modified']
    assert layout['footprint']==[700,700] and layout['clear_combat_size']==[612,612]
    assert len(layout['placements'])==len(layout['supports'])==len(layout['prefabs'])==10 and len(layout['markers'])==30
    assert layout['review_bounds']==[[-4096,-4096],[4096,4096]]
    relative=f'maps/{REVIEW}.vmap';text=(SOURCE/relative).read_text(encoding='utf-8-sig')
    assert text.count('"classname" "string" "prop_static"')==10
    assert text.count('"classname" "string" "info_target"')==30
    assert text.count('"classname" "string" "env_global_light"')==1 and 'info_particle_system' not in text
    assert sorted(re.findall(r'"model" "string" "([^\"]+)"',text))==[f'models/{NAMESPACE}/realm_{i:02}.vmdl' for i in range(1,11)]
    meshes=mesh_positions(text);assert len(meshes)==11,('expected 10 supports and 1 sea',len(meshes))
    envelopes=[];clearance=math.inf
    for index,(asset,placement,support,prefab) in enumerate(zip(assets,layout['placements'],layout['supports'],layout['prefabs'])):
        rank=index+1;spec=realm(rank);origin=spec['review_xy']+[128]
        assert placement['name']==asset['name'] and placement['rank']==rank and same(placement['origin'],origin)
        assert placement['yaw']==0 and placement['scale']==1 and placement['collision_count']==5
        assert placement['footprint']==[700,700] and placement['clear_combat_size']==[612,612]
        assert near(placement['world_deck_z'],128) and near(placement['world_water_z'],86)
        world=[[v+origin[i] for i,v in enumerate(row)] for row in asset['bounds']]
        assert same_bounds(world,placement['world_model_bounds']) and same_bounds(asset['bounds'],placement['local_model_bounds'])
        assert all(-4096<=world[0][i]<world[1][i]<=4096 for i in (0,1))
        for other in envelopes:
            assert not all(world[0][i]<other[1][i] and other[0][i]<world[1][i] for i in (0,1)),'island shore envelopes overlap'
            gaps=[max(world[0][i]-other[1][i],other[0][i]-world[1][i],0) for i in (0,1)]
            clearance=min(clearance,math.hypot(*gaps))
        envelopes.append(world);check_support(meshes[index],support)
        assert near(support['top'],127.25) and near(support['bottom'],123.25)
        rank_markers=[m for m in layout['markers'] if m['rank']==rank]
        expected_names={spec['entry_marker'],spec['spawn_marker'],f'ten_realm_arena_{rank:02}_center'}
        assert {m['name'] for m in rank_markers}==expected_names
        for marker in rank_markers:
            local=spec['entry'] if marker['kind']=='entry' else spec['spawn'] if marker['kind']=='spawn' else [0,0,0]
            assert marker['local_floor_position']==local and same(marker['origin'],[local[0]+origin[0],local[1]+origin[1],152])
            marker_present(text,marker)
        assert prefab['path']==f'prefabs/ten_realm_arena_{rank:02}' and prefab['origin']==[0,0,0]
        assert prefab['placement']['origin']==[0,0,0] and not prefab['water']['included']
        assert not prefab['includes_review_lighting'] and not prefab['includes_grid']
        ptext=(SOURCE/('maps/'+prefab['path']+'.vmap')).read_text(encoding='utf-8-sig')
        assert ptext.count('"classname" "string" "prop_static"')==1 and ptext.count('"classname" "string" "info_target"')==3
        assert not any(s in ptext for s in ('env_global_light','info_player_start','DotaTileGrid','info_particle_system','ocean_surface.vmat','world_bounds'))
        pmeshes=mesh_positions(ptext);assert len(pmeshes)==1
        check_support(pmeshes[0],prefab['supports'][0]);assert near(prefab['supports'][0]['top'],-.75)
        assert len(prefab['markers'])==3 and {m['name'] for m in prefab['markers']}==expected_names
        for marker in prefab['markers']:
            assert same(marker['origin'],marker['local_floor_position'][:2]+[24])
            marker_present(ptext,marker)
    assert near(clearance,layout['min_envelope_clearance'])
    assert all(same(a[:2],b) for a,b in zip(union_bounds(envelopes),layout['occupied_bounds']))
    water=layout['water']
    assert water['nonsolid'] and not water['navigable'] and not water['included_in_prefabs']
    assert water['shared_ocean_meshes']==1 and water['world_z']==86 and water['local_z']==-42
    assert same_bounds(bounds_of(meshes[-1]),[[-4096,-4096,85],[4096,4096,86]])
    assert same_bounds(water['bounds'],bounds_of(meshes[-1]))
    nav=check_nav(text,layout)
    assert map_meta['review']==REVIEW and map_meta['instances']==map_meta['customAssets']==10 and map_meta['supportCount']==10
    assert map_meta['markers']==[m['name'] for m in layout['markers']] and map_meta['prefabs']==[p['path'] for p in layout['prefabs']]
    assert map_meta['water']==water and map_meta['navigation']==layout['navigation']
    assert map_meta['emissiveEntities']==0 and not map_meta['mainMapModified']
    support=dump(f'materials/{NAMESPACE}/floor_support.vmat_c')
    assert 'dota.nav.walkable = 1.0' in support and 'mapbuilder.nodraw = 1.0' in support
    ocean=dump(f'materials/{NAMESPACE}/ocean_surface.vmat_c')
    for required in ('multiblend','F_SCROLL_WAVES = 1','F_NORMAL_MAP = 1','F_SPECULAR = 1','mapbuilder.nonsolid = 1.0','mapbuilder.water = 1.0'):
        assert required in ocean,('ocean compiled contract',required)
    assert 'dota.nav.walkable = 1.0' not in ocean and 'F_SELF_ILLUM = 1' not in ocean and 'F_FULLBRIGHT = 1' not in ocean
    assert 'materials/main_island/' not in ocean,'ocean still depends on old room namespace'
    fresh_dependencies(support,'floor_support');fresh_dependencies(ocean,'ocean_surface')
    return dict(markers=30,prefabs=10,supports=10,shared_nonnavigable_ocean=True,navigation_grid=[128,128],
                open_cells_by_rank=nav,min_envelope_clearance=clearance,main_map_modified=False,runtime_verified=False)


def vpk_payloads(path):
    """Read checked VPK entries to inspect embedded resources, not timestamps."""
    data=path.read_bytes();magic,version,tree_size=struct.unpack_from('<III',data)
    assert magic==0x55AA1234 and version in (1,2)
    cursor=28 if version==2 else 12;tree_end=cursor+tree_size;payloads={}
    def string():
        nonlocal cursor
        end=data.index(b'\0',cursor,tree_end);value=data[cursor:end].decode('utf-8');cursor=end+1
        return value
    while extension:=string():
        while directory:=string():
            while name:=string():
                crc,preload_size,archive,offset,size,terminator=struct.unpack_from('<IHHIIH',data,cursor);cursor+=18
                assert terminator==65535
                preload=data[cursor:cursor+preload_size];cursor+=preload_size
                if archive==0x7FFF:payload=data[tree_end+offset:tree_end+offset+size]
                else:
                    archive_path=path.with_name(path.stem.removesuffix('_dir')+f'_{archive:03}.vpk')
                    with archive_path.open('rb') as stream:stream.seek(offset);payload=stream.read(size)
                entry=f'{directory}/{name}.{extension}' if directory!=' ' else f'{name}.{extension}'
                assert len(payload)==size and zlib.crc32(preload+payload)==crc,(entry,'VPK payload CRC')
                payloads[entry]=preload+payload
    assert cursor==tree_end
    return payloads


def check_vpk():
    path=ROOT/f'maps/{REVIEW}.vpk'
    count=verify_map_vpk(path);payloads=vpk_payloads(path);assert count==len(payloads)
    compile_info=read_json(OUT/'compile.json')
    assert compile_info['map']==path.name and hashlib.sha256(path.read_bytes()).hexdigest().lower()==compile_info['sha256'].lower(),'VPK differs from completed installation record'
    inspect_extensions=('.vmap_c','.vwrld_c','.vwnod_c','.vents_c','.vent_c')
    references=set();fresh=[];inspected=[]
    for name,payload in payloads.items():
        if not name.endswith(inspect_extensions):continue
        text=dump(str(path)+'/'+name);inspected.append(name);fresh.extend(fresh_dependencies(text,name))
        references.update(re.findall(r'models/'+NAMESPACE+r'/realm_\d\d\.vmdl',text))
    # If an own compiled asset is embedded, it must match current output.
    for name,payload in payloads.items():
        if own_relative(name) and (ROOT/name).is_file():
            assert (ROOT/name).read_bytes()==payload,(name,'stale embedded compiled resource')
    expected={f'models/{NAMESPACE}/realm_{i:02}.vmdl' for i in range(1,11)}
    assert expected<=references,('map VPK lacks realm references',sorted(expected-references))
    assert any(n.endswith('.vmap_c') for n in inspected)
    return dict(entries=count,sha256=compile_info['sha256'],embedded_resources_inspected=len(inspected),
                realm_model_references=len(references),fresh_own_compiler_inputs=len(set(fresh)),payload_crc=True)


def main():
    assets=read_json(OUT/'asset_manifest.json');materials=read_json(OUT/'material_manifest.json')
    layout=read_json(OUT/'layout.json');map_meta=read_json(OUT/'map_manifest.json')
    assert [a['name'] for a in assets]==[f'realm_{i:02}' for i in range(1,11)]
    assert len(materials)==len(PALETTE)==50 and {m['name'] for m in materials}==set(PALETTE)
    blend=OUT/(NAMESPACE+'.blend');assert blend.is_file() and blend.stat().st_size>1024
    copied=0
    for source in SOURCE.rglob('*'):
        if source.is_file():
            relative=source.relative_to(SOURCE).as_posix()
            assert own_relative(relative),('unexpected installation scope',relative)
            installed_source(source,relative);copied+=1
    model_checks=[]
    for asset in assets:
        model_checks.append(check_asset(asset));print('TEN_REALM_MODEL_VERIFIED',asset['name'],flush=True)
    material_checks=[]
    for material in materials:
        material_checks.append(check_material(material));print('TEN_REALM_MATERIAL_VERIFIED',material['name'],flush=True)
    by_name={m['name']:m for m in materials};wet_checks=[]
    for dry,wet in [('sand','sand_wet'),('basalt','basalt_wet'),('slate','slate_wet'),('rock','rock_wet')]:
        assert by_name[wet]['roughness_mean']<by_name[dry]['roughness_mean']-.10,(dry,wet,'wet surface not smoother')
        assert by_name[wet]['reflectance_mean']>by_name[dry]['reflectance_mean']+.035,(dry,wet,'wet response missing')
        wet_checks.append([dry,wet])
    spatial=check_layout(assets,layout,map_meta);vpk=check_vpk()
    report=dict(status='PASS',namespace=NAMESPACE,revision=REVISION,custom_models=10,material_sets=50,
                footprint=list(FOOTPRINT),markers=30,prefabs=10,collision_hulls_per_realm=5,
                source2_bounds_and_dependencies=model_checks,compiled_materials=material_checks,
                dry_wet_material_pairs=wet_checks,spatial=spatial,compiled_map=REVIEW+'.vpk',vpk=vpk,
                installed_sources_match=True,installed_source_files=copied,packed_blender_source=blend.name,
                main_map_modified=False,runtime_verified=False,
                runtime_note='Compiled geometry/materials, file CRCs and static navigation layout verified. In-game appearance, movement and combat are not claimed.')
    (OUT/'verification.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
    print('TEN_REALM_ARENAS_VERIFY_PASS 10 models 50 materials 30 markers 10 prefabs',flush=True)
    return report


if __name__=='__main__':
    try:
        main()
    except Exception as error:
        if OUT.exists():
            (OUT/'verification.json').write_text(json.dumps(dict(status='FAIL',namespace=NAMESPACE,
                revision=REVISION,error=str(error),runtime_verified=False),ensure_ascii=False,indent=2),encoding='utf-8')
        raise
