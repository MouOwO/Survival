"""Build monster portraits from world CSV components and installed Valve cameras.

The scene owns its body and bone-merged parts, never the player's inventory.
Backgrounds are lossless format conversions of the original Valve textures.
"""
from __future__ import annotations

import argparse
import copy
import hashlib
import json
import math
from pathlib import Path
import re
import subprocess
import uuid

from build_unit_portraits import ENGINE, ROOT, Vpk, parse_kv, rows

WORK = ROOT / 'output/monster_portraits_build'
ART = ROOT / 'art/portraits/monsters'
IMAGE = ROOT / 'panorama/src/images/custom_game/monster_portrait_backgrounds'
JS = ROOT / 'panorama/src/scripts/custom_game/monster_portrait_scenes.js'
INFO = ENGINE / 'game/bin/win64/resourceinfo.exe'
CONVERTER = ROOT / 'output/valley_decor_v2/source2viewer/Source2Viewer-CLI.exe'


def digest(data):
    return hashlib.sha256(data).hexdigest()


def write(path, data, check):
    text = isinstance(data, str)
    data = data.encode('utf8') if text else data
    if check:
        actual = path.read_bytes() if path.is_file() else None
        if text and actual is not None:
            actual = actual.replace(b'\r\n', b'\n')
            data = data.replace(b'\r\n', b'\n')
        assert actual == data, 'Stale resource: ' + str(path)
    else:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)


def balanced(text, start, left='{', right='}'):
    depth, quoted, escaped = 0, False, False
    for i in range(start, len(text)):
        c = text[i]
        if quoted:
            if escaped:
                escaped = False
            elif c == '\\':
                escaped = True
            elif c == '"':
                quoted = False
        elif c == '"':
            quoted = True
        elif c == left:
            depth += 1
        elif c == right:
            depth -= 1
            if not depth:
                return i
    raise ValueError('Unbalanced source')


def entity(text, classname):
    marker = re.search(r'"classname"\s+"string"\s+"' + re.escape(classname) + '"', text)
    assert marker, classname
    start = list(re.finditer(r'"CMapEntity"\s*\{', text[:marker.start()]))[-1].start()
    opening = text.index('{', start)
    return text[start:balanced(text, opening) + 1]


def prop(block, key, value, kind='string'):
    pattern = r'("' + re.escape(key) + r'"\s+"' + kind + r'"\s+")[^"]*(")'
    if re.search(pattern, block):
        return re.sub(pattern, lambda m: m[1] + str(value) + m[2], block, count=1)
    assert kind == 'string', (key, kind)
    start = block.index('{', block.index('"entity_properties"'))
    end = balanced(block, start)
    return block[:end] + f'\n"{key}" "string" "{value}"\n' + block[end:]


def configure(block, values):
    for key, value in values.items():
        block = prop(block, key, value)
    return block


def unique(block, seed, index):
    block = re.sub(r'("id"\s+"elementid"\s+")([^"]+)(")',
                   lambda m: m[1] + str(uuid.uuid5(uuid.NAMESPACE_URL, seed + ':' + m[2])) + m[3], block)
    return prop(block, 'nodeID', index, 'int')


def world(template, blocks, resources, seed):
    opening = template.index('[', template.index('"children" "element_array"', template.index('"world" "CMapWorld"')))
    end = balanced(template, opening, '[', ']')
    text = template[:opening + 1] + '\n' + ',\n'.join(blocks) + '\n' + template[end:]
    text = prop(text, 'mapUsageType', 'background')
    start = text.find('"map_asset_references" "string_array"')
    if start >= 0:
        opening = text.index('[', start)
        end = balanced(text, opening, '[', ']')
        text = text[:opening + 1] + '\n' + ',\n'.join(json.dumps(x) for x in sorted(set(resources))) + '\n' + text[end:]
    # Unique prefix IDs prevent the resource system sharing unrelated worlds.
    prefix = re.search(r'"\$prefix_element\$"\s*\{', text)
    end = balanced(text, text.index('{', prefix.start()))
    text = text[:prefix.start()] + '"$prefix_element$"\n{\n"id" "elementid" "' + str(uuid.uuid5(uuid.NAMESPACE_URL, seed)) + '"\n}' + text[end + 1:]
    return text


def angle(value):
    x, y, z = map(float, value.split())
    return f'{math.degrees(math.atan2(-z, math.hypot(x, y))):.8f} {math.degrees(math.atan2(y, x)):.8f} 0'


def read_sequences(vpk, model):
    path = WORK / Path(model).name
    path = path.with_suffix('.vmdl_c')
    path.write_bytes(vpk.read(model + '_c'))
    result = subprocess.run([str(INFO), '-i', str(path), '-b', 'ASEQ', '-baremode'], capture_output=True)
    assert result.returncode == 0, model
    text = result.stdout.decode('utf8', 'replace')
    sequences = []
    for match in re.finditer(r'\{\s*m_sName = "([^"]+)"\s*m_flags', text):
        block = text[match.start():balanced(text, match.start()) + 1]
        sequences.append((match[1], re.findall(r'm_name = "([^"]+)"', block)))
    assert sequences, 'No authored sequences: ' + model
    return sequences


def sequence_for(sequences, activity, modifiers):
    for wanted in (activity, 'ACT_DOTA_CAPTURE', 'ACT_DOTA_IDLE'):
        candidates = []
        for index, (name, activities) in enumerate(sequences):
            if wanted not in activities:
                continue
            extras = set(activities) - {wanted}
            if not extras.issubset(modifiers):
                continue
            candidates.append((-len(extras), name.startswith('@'), index, name))
        if candidates:
            return min(candidates)[-1]
    for name, _ in sequences:
        if name.lower() in ('idle', 'portrait'):
            return name
    raise ValueError('No matching portrait activity: ' + activity)


def background(vpk, profile, check):
    material = profile['PortraitBackgroundTexture'].lower()
    data = vpk.read(material + '_c')
    refs = sorted({p.decode('ascii') for p in re.findall(rb'[A-Za-z0-9_./-]+\.vtex', data)})
    candidates = [p for p in refs if p.startswith(material.removesuffix('.vmat') + '_')]
    assert len(candidates) == 1, (material, candidates)
    texture = candidates[0]
    name = Path(material).stem
    compiled = WORK / (name + '.vtex_c')
    compiled.write_bytes(vpk.read(texture + '_c'))
    # Lossless Source2Viewer conversion, without resize or recolouring.
    decoded = WORK / (name + '.png')
    assert CONVERTER.is_file(), 'Supply the Source2Viewer CLI with --texture-converter'
    result = subprocess.run([str(CONVERTER), '-i', str(compiled), '-o', str(WORK), '-d'], capture_output=True)
    assert result.returncode == 0, result.stderr
    assert decoded.is_file(), result.stdout
    write(IMAGE / decoded.name, decoded.read_bytes(), check)
    recipe = (ROOT / 'tools/monster_portrait_background.vtex').read_text('utf8')
    recipe = recipe.replace('panorama/images/custom_game/archive_items_v2/star_blessing_026.png',
                            'panorama/images/custom_game/monster_portrait_backgrounds/' + decoded.name)
    recipe = recipe.replace('"m_nOutputMaxDimension" "int" "256"', '"m_nOutputMaxDimension" "int" "0"')
    write(IMAGE / (name + '.vtex'), recipe, check)
    return {'texture': 's2r://panorama/images/custom_game/monster_portrait_backgrounds/' + name + '.vtex',
            'valve_material': material, 'valve_texture': texture,
            'valve_texture_sha256': digest(vpk.read(texture + '_c')), 'png_sha256': digest(decoded.read_bytes()),
            'colors': [profile.get('PortraitBackgroundColor' + str(i), '1 1 1') for i in range(1, 5)]}


def build(check=False, compile_resources=False):
    WORK.mkdir(parents=True, exist_ok=True)
    vpk = Vpk(ENGINE / 'game/dota/pak01_dir.vpk')
    portraits = parse_kv(vpk.read('scripts/npc/portraits.txt').decode('utf8'))['Portraits']
    template = (ROOT / 'tools/jugg_portrait_template.vmap').read_text('utf8')
    body_template, camera_template, light_template = [entity(template, c) for c in ('prop_dynamic', 'point_camera', 'env_global_light')]
    components, activities = {}, {}
    for row in rows('asset_components.csv'):
        if row.get('enabled') == '1':
            components.setdefault(row['asset_id'], []).append(row)
    for row in rows('asset_activity_modifiers.csv'):
        if row.get('enabled') == '1':
            activities.setdefault(row['asset_id'], set()).add(row['modifier_name'])
    assets = [r for r in rows('asset_catalog.csv') if r.get('enabled') == '1' and
              (r['load_group'] == 'monster_default_wearables' or r['asset_id'].startswith('challenge_monster_'))]
    sequences, backgrounds, scenes, config = {}, {}, {}, {}
    for asset in sorted(assets, key=lambda r: r['asset_id']):
        asset_id, model = asset['asset_id'], asset['primary_model']
        profile = copy.deepcopy(portraits['default'])
        profile.update(copy.deepcopy(portraits.get(model, {})))
        assert 'cameras' in profile, model
        camera = profile['cameras'].get('default', next(iter(profile['cameras'].values())))
        if model not in sequences:
            sequences[model] = read_sequences(vpk, model)
        sequence = sequence_for(sequences[model], profile.get('PortraitAnimationActivity', 'ACT_DOTA_CAPTURE'), activities.get(asset_id, set()))
        material = profile['PortraitBackgroundTexture']
        if material not in backgrounds:
            backgrounds[material] = background(vpk, profile, check)
        backdrop = dict(backgrounds[material])
        backdrop['colors'] = [profile.get('PortraitBackgroundColor' + str(i), '1 1 1') for i in range(1, 5)]
        parts = sorted(components.get(asset_id, []), key=lambda r: (float(r.get('sort_order') or 0), r['component_key']))
        signature = {'model': model, 'skin': asset.get('model_skin') or '0', 'sequence': sequence,
                     'parts': [{k: p.get(k, '') for k in ('component_id', 'model_path', 'parent_component_id', 'attach_mode', 'attachment_point', 'model_scale', 'model_skin', 'material_group')} for p in parts],
                     'profile': profile}
        key = digest(json.dumps(signature, sort_keys=True).encode())[:20]
        map_name = 'monster_' + key + '_v1'
        body = configure(body_template, {'targetname': 'monster_portrait_body', 'model': model, 'skin': signature['skin'],
            'parentname': '', 'parentAttachmentName': '', 'local.origin': '0 0 0', 'local.angles': '0 0 0', 'local.scales': '1 1 1', 'useLocalOffset': '0',
            'StartingAnim': sequence, 'IdleAnim': sequence, 'StartingAnimationLoopMode': 'ANIM_LOOP_MODE_LOOPING',
            'IdleAnimationLoopMode': 'ANIM_LOOP_MODE_LOOPING', 'use_animgraph': '0', 'solid': '0', 'rendercolor': '255 255 255 255'})
        for k, kind, val in [('origin', 'vector3', '0 0 0'), ('angles', 'qangle', '0 0 0'), ('scales', 'vector3', '1 1 1'), ('force_hidden', 'bool', '0'), ('editorOnly', 'bool', '0')]:
            body = prop(body, k, val, kind)
        blocks = [unique(body, key + ':body', 1)]
        for p in parts:
            parent = 'monster_part_' + p['parent_component_id'] if p['parent_component_id'] else 'monster_portrait_body'
            attachment = '!bonemerge' if p['attach_mode'] == 'bone_merge' else p['attachment_point']
            part = configure(body, {'targetname': 'monster_part_' + p['component_id'], 'model': p['model_path'], 'parentname': parent,
                'parentAttachmentName': attachment, 'useLocalOffset': '1', 'StartingAnim': '', 'IdleAnim': '',
                'skin': p['material_group'] or p['model_skin'] or '0'})
            scale = float(p['model_scale'] or 1)
            part = prop(part, 'scales', f'{scale} {scale} {scale}', 'vector3')
            part = prop(part, 'local.scales', f'{scale} {scale} {scale}')
            blocks.append(unique(part, key + ':' + p['component_id'], len(blocks) + 1))
        scene_camera = configure(camera_template, {'targetname': 'monster_portrait_camera', 'parentname': '', 'parentAttachmentName': '',
            'local.origin': '0 0 0', 'local.angles': '0 0 0', 'local.scales': '1 1 1', 'FOV': camera['PortraitFOV'], 'dof_enabled': '0',
            'ZNear': camera.get('PortraitNear', '4'), 'ZFar': camera.get('PortraitFar', '7000'), 'UseScreenAspectRatio': '0', 'aspectRatio': '1', 'fogEnable': '0'})
        scene_camera = prop(scene_camera, 'origin', camera['PortraitPosition'], 'vector3')
        scene_camera = prop(scene_camera, 'angles', camera['PortraitAngles'], 'qangle')
        light = configure(light_template, {'targetname': 'monster_portrait_light', 'StartDisabled': '0', 'parentname': '',
            'background_clear_not_required': '0', 'height_fog_density': '0',
            'color': profile['PortraitLightColor'] + ' 1', 'lightscale': profile['PortraitLightScale'],
            'ambientcolor1': profile['PortraitAmbientColor'] + ' 1', 'ambientscale1': profile['PortraitAmbientScale'],
            'ambientcolor2': profile['PortraitShadowColor'] + ' 1', 'ambientscale2': profile['PortraitShadowScale'],
            'groundscale': profile['PortraitGroundShadowScale'], 'specularcolor': profile['PortraitSpecularColor'] + ' 1',
            'ambientangles': angle(profile['PortraitAmbientDirection']), 'fov': profile['PortraitLightFOV']})
        light = prop(light, 'origin', profile['PortraitLightPosition'], 'vector3')
        light = prop(light, 'angles', profile['PortraitLightAngles'], 'qangle')
        for block in (scene_camera, light):
            block = prop(block, 'force_hidden', '0', 'bool')
            block = prop(block, 'editorOnly', '0', 'bool')
            blocks.append(unique(block, key + ':environment:' + str(len(blocks)), len(blocks) + 1))
        source = world(template, blocks, [model] + [p['model_path'] for p in parts], key)
        path = ART / (map_name + '.vmap')
        write(path, source, check)
        scenes[map_name] = path
        config[asset_id] = {'map': 'portraits/' + map_name, 'camera': 'monster_portrait_camera', 'light': 'monster_portrait_light',
            'unit': asset.get('portrait_unit_name') or '', 'model': model, 'background': backdrop['texture'],
            'colors': backdrop['colors'], 'sequence': sequence, 'components': len(parts)}
    write(JS, '// Generated by tools/build_monster_portraits.py; world components and Valve camera profiles.\n(function(){GameUI.CustomUIConfig().SurvivalMonsterPortraitScenes = ' + json.dumps(config, ensure_ascii=False, indent=2) + ';})();\n', check)
    receipt = {'schema': 1, 'assets': config, 'backgrounds': backgrounds, 'unique_scenes': len(scenes),
               'camera_source': 'Valve scripts/npc/portraits.txt', 'world_model_source': 'asset_catalog / asset_components CSV',
               'scene_animation_source': 'compiled model ASEQ activity bindings; explicit looping'}
    write(ART / 'manifest.json', json.dumps(receipt, ensure_ascii=False, indent=2) + '\n', check)
    if compile_resources:
        content = ENGINE / 'content/dota_addons/Survival'
        for source in sorted(IMAGE.glob('*')) + sorted(scenes.values()):
            relative = source.relative_to(ROOT / 'panorama/src') if source.is_relative_to(ROOT / 'panorama/src') else Path('maps/portraits') / source.name
            destination = content / ('panorama' if source.is_relative_to(IMAGE) else '') / relative
            destination.parent.mkdir(parents=True, exist_ok=True)
            if source.suffix == '.vmap':
                result = subprocess.run([str(ENGINE / 'game/bin/win64/dmxconvert.exe'), '-i', str(source), '-o', str(destination), '-oe', 'binary', '-of', 'vmap'], capture_output=True)
                assert result.returncode == 0, source
            else:
                destination.write_bytes(source.read_bytes())
            if source.suffix not in ('.vmap', '.vtex'):
                continue
            result = subprocess.run([str(ENGINE / 'game/bin/win64/resourcecompiler.exe'), '-i', str(destination), '-game', str(ENGINE / 'game/dota'), '-fshallow', '-nop4'], stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
            (WORK / (source.stem + '_compile.log')).write_bytes(result.stdout)
            assert result.returncode == 0 and b'0 failed' in result.stdout, (source, result.stdout[-2000:])
    print(json.dumps({'status': 'PASS', 'assets': len(config), 'scenes': len(scenes), 'backgrounds': len(backgrounds), 'compiled': compile_resources}))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true')
    parser.add_argument('--compile', action='store_true')
    parser.add_argument('--texture-converter', type=Path, default=CONVERTER,
                        help='Source2Viewer CLI executable, used only for lossless Valve texture decoding')
    args = parser.parse_args()
    assert not (args.check and args.compile)
    CONVERTER = args.texture_converter.resolve()
    build(args.check, args.compile)
