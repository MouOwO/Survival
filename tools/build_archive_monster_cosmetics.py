"""Import the approved archive challenge outfits from the installed Dota item schema.

The resulting CSVs are the runtime authority. --check compares without writing.
No workshop IDs or model paths are inferred from translated names.
"""
from __future__ import annotations

import argparse
import re
from pathlib import Path

from build_wave_monster_cosmetics import Vpk
from build_boss_cosmetic_batch import read_csv_document, render_csv, replace_data_rows

ROOT = Path(__file__).resolve().parents[1]
RESOURCES = ROOT / 'data/csv/资源系统'
ARCHETYPES = ROOT / 'data/csv/存档系统/archive_challenge_definitions.csv'
# challenge: (official hero, bundle/item definition, dragon form skin)
SPECS = {
    **{f'shadow_{i}': ('shadow_demon', '21717', '') for i in range(1, 5)},
    **{f'cage_{i}': ('dragon_knight', '17999', str(i - 1)) for i in range(1, 4)},
    **{f'cage_{i}': ('jakiro', '29124', '') for i in range(4, 7)},
    'hunt_01': ('sven', '21842', ''),
    'hunt_02': ('mars', '36244', ''),
    'hunt_03': ('doom_bringer', '21216', ''),
    'hunt_04': ('spectre', '21361', ''),
    'hunt_05': ('faceless_void', '22826', ''),
    'hunt_06': ('antimage', '24920', ''),
    'hunt_07': ('kunkka', '21027', ''),
    'hunt_08': ('pudge', '21188', ''),
    'hunt_09': ('weaver', '21811', ''),
    'hunt_10': ('legion_commander', '34333', ''),
    'hunt_11': ('clinkz', '21040', ''),
    'hunt_12': ('rubick', '29096', ''),
    **{f'social_{key}': ('ogre_magi', '21256', '') for key in ('friend', 'ex', 'beast')},
}
# Explicit additions have priority over bundle components in the same slot.
EXTRAS = {
    'hunt_01': ['7876'], 'hunt_02': ['13572'], 'hunt_03': ['4446'],
    'hunt_04': ['6894'], 'hunt_05': ['4020'], 'hunt_06': ['8271', '8324'],
    'hunt_07': ['5321'], 'hunt_08': ['4007'], 'hunt_09': ['7813'],
    'hunt_10': ['5810'], 'hunt_11': ['13009'], 'hunt_12': ['12451', '9521'],
}
STYLES = {'hunt_08': '1'}  # Feast of Abscession: The Grand Abscess (green).



def parse_kv(text):
    tokens = iter(t for t in re.findall(r'//[^\n]*|"(?:\\.|[^"\\])*"|[{}]|[^\s{}"]+', text)
                  if not t.startswith('//'))
    def block():
        result = {}
        for key in tokens:
            if key == '}': return result
            value = next(tokens)
            key = key.strip('"')
            unique = key
            while unique in result: unique += '_'
            result[unique] = block() if value == '{' else value.strip('"')
        return result
    return block()


def modifiers(item):
    return [v for k, v in item.get('visuals', {}).items()
            if k.startswith('asset_modifier') and isinstance(v, dict)]


def import_rows(vpk):
    schema = parse_kv(vpk.read('scripts/items/items_game.txt').decode('utf-8-sig'))['items_game']
    items = schema['items']
    by_name = {v.get('name'): k for k, v in items.items()}
    heroes = parse_kv(vpk.read('scripts/npc/npc_heroes.txt').decode('utf-8-sig'))['DOTAHeroes']
    loc = parse_kv(vpk.read('resource/localization/items_schinese.txt').decode('utf-8-sig'))['lang']['Tokens']
    loc = {k.lower(): v for k, v in loc.items()}
    particle_bindings = {v['system']: v for v in schema['attribute_controlled_attached_particles'].values()
                         if isinstance(v, dict) and 'system' in v}
    output = {name: [] for name in ('asset_catalog', 'asset_components', 'asset_effects', 'asset_activity_modifiers')}
    models = {}
    for order, (archetype, (hero, item_id, form_skin)) in enumerate(SPECS.items(), 100):
        hero = 'npc_dota_hero_' + hero
        selected = items[item_id]
        label = loc.get(selected.get('item_name', '').lstrip('#').lower(), selected['name'])
        ids = EXTRAS.get(archetype, []) + ([by_name[name] for name in selected['bundle']] if 'bundle' in selected else [item_id])
        style = STYLES.get(archetype, '0')
        def active_modifiers(item):
            return [m for m in modifiers(item) if m.get('style', style) == style
                    and m.get('spawn_in_loadout_only') != '1' and not m.get('criteria')]
        body = heroes[hero]['Model']
        asset_id = 'monster_archive_' + archetype
        skin = form_skin
        components, particles, activities = [], [], []
        slots = set()
        selected_ids = []
        for child_id in ids:
            item = items[child_id]
            if hero not in item.get('used_by_heroes', {}): continue
            slot = item.get('item_slot', 'weapon')
            if slot.startswith('ability') or slot in ('summon', 'taunt', 'shapeshift') and not form_skin:
                continue
            # Overrides were inserted first; keep one component per occupied slot.
            if slot in slots: continue
            slots.add(slot)
            selected_ids.append(child_id)
        # A single-slot Arcana still needs the hero's other default wearable slots.
        if not form_skin:
            for child_id, item in items.items():
                if item.get('prefab') != 'default_item' or hero not in item.get('used_by_heroes', {}): continue
                slot = item.get('item_slot', 'weapon')
                if 'persona' in slot or slot.startswith('ability') or slot in ('shapeshift', 'summon'):
                    continue
                if hero == 'npc_dota_hero_pudge' and slot not in ('weapon', 'offhand_weapon'): continue
                if slot not in slots and item.get('model_player'):
                    slots.add(slot)
                    selected_ids.append(child_id)
        replacements = {m['asset']: m['modifier'] for child_id in selected_ids
                        for m in active_modifiers(items[child_id]) if m.get('type') == 'particle' and m.get('modifier')}
        for child_id in selected_ids:
            item = items[child_id]
            slot = item.get('item_slot', 'weapon')
            visuals = item.get('visuals', {})
            item_skin = visuals.get('styles', {}).get(style, {}).get('skin', visuals.get('skin', '0'))
            model = item.get('model_player', '')
            if model and not form_skin:
                components.append((slot, child_id, model, item_skin))
            if slot == 'costume':
                skin = visuals.get('skin', '1')
            for modifier in active_modifiers(item):
                kind, path = modifier.get('type'), modifier.get('modifier', '')
                if kind == 'entity_model' and modifier.get('asset') == hero:
                    body = path
                elif kind == 'hero_model_change' and form_skin:
                    body = path
                elif kind == 'model_skin':
                    skin = modifier['skin']
                elif kind == 'activity' and modifier.get('asset') == 'ALL' and path:
                    activities.append(path)
                elif kind == 'particle_create' and path:
                    owner = slot if model and not form_skin else ''
                    particles.append((replacements.get(path, path), owner, child_id))
                elif kind == 'additional_wearable' and modifier.get('asset') and not form_skin:
                    components.append((slot + '_additional', child_id, modifier['asset'], visuals.get('skin', '0')))
        model_replacements = {m['asset']: m['modifier'] for child_id in selected_ids
                              for m in active_modifiers(items[child_id])
                              if m.get('type') == 'model' and m.get('asset') and m.get('modifier')}
        components = [(slot, child, model_replacements.get(path, path), cskin)
                      for slot, child, path, cskin in components]
        if archetype == 'hunt_08':
            components = [(slot, child, path, '1' if slot == 'back' else cskin)
                          for slot, child, path, cskin in components]
        models[archetype] = body
        vpk.verify(body)
        for _, _, model, _ in components: vpk.verify(model)
        for path, _, _ in particles: vpk.verify(path)
        output['asset_catalog'].append(dict(
            asset_id=asset_id, display_name=label, asset_type='model' if form_skin else 'model_bundle', primary_model=body,
            default_sequence='idle', model_scale='1', model_skin=skin or '0',
            load_group='monster_default_wearables', load_order=str(order), priority='650',
            first_use_wave='0', resident_policy='permanent', async_unit_name='asset_proxy_' + asset_id,
            portrait_unit_name=hero, enabled='1',
            notes=f'{archetype}；官方bundle/item={item_id}；附加={EXTRAS.get(archetype, [])}；style={style}；世界饰品独立于基础头像。'))
        for index, (slot, child_id, model, component_skin) in enumerate(components, 1):
            output['asset_components'].append(dict(
                component_key=asset_id + ':' + slot, asset_id=asset_id, component_id=slot,
                model_path=model, entity_class='prop_dynamic', attach_mode='bone_merge',
                default_sequence='idle', model_scale='1', model_skin=component_skin,
                sort_order=str(index), enabled='1', notes=f'{label}；官方ItemDef={child_id}'))
        for index, (path, owner, child_id) in enumerate(dict.fromkeys(particles), 1):
            effect_id = 'ambient_' + str(index)
            binding = particle_bindings.get(path, {})
            if binding.get('attach_entity') == 'parent': owner = ''
            controls = '|'.join(str(cp['control_point_index']) + '=' + cp['attachment']
                                for cp in binding.get('control_points', {}).values()
                                if cp.get('attach_type') == 'point_follow' and cp.get('attachment'))
            output['asset_effects'].append(dict(
                effect_key=asset_id + ':' + effect_id, asset_id=asset_id, effect_group_id='wave_cosmetic_ambient',
                effect_id=effect_id, effect_role='ambient', phase='persistent', particle_path=path,
                owner_component_id=owner, attach_type='PATTACH_' + binding.get('attach_type', 'absorigin_follow').upper(),
                control_profile=controls,
                sort_order=str(index), enabled='1', notes=f'官方ItemDef={child_id} particle_create'))
        for index, activity in enumerate(dict.fromkeys(activities), 1):
            output['asset_activity_modifiers'].append(dict(
                modifier_key=asset_id + ':' + activity, asset_id=asset_id, modifier_name=activity,
                sort_order=str(index), enabled='1', notes=f'{label}官方动作修饰'))
        print(f'{archetype}: {label} [{item_id}] components={len(components)} particles={len(particles)}')
    return output, models


def sync(output, models, check):
    asset_ids = {row['asset_id'] for row in output['asset_catalog']}
    changes = []
    rows, bom, newline, raw = read_csv_document(ARCHETYPES)
    headers = rows[0]
    if 'default_wearable_asset_id' not in headers:
        headers.append('default_wearable_asset_id')
        for row in rows[1:]:
            row.append('饰品资源ID' if row and row[0].startswith('#中文') else 'string' if row and row[0].startswith('#types:') else '')
    seen = set()
    for row in rows[1:]:
        if not row or row[0] not in models: continue
        archetype = row[0]
        seen.add(archetype)
        row.extend([''] * (len(headers) - len(row)))
        row[headers.index('model_path')] = models[archetype]
        row[headers.index('default_wearable_asset_id')] = 'monster_archive_' + archetype
    assert seen == set(models), 'archetype not found: ' + str(set(models) - seen)
    expected = render_csv(rows, bom, newline)
    changes.append(expected != raw)
    if not check and expected != raw: ARCHETYPES.write_bytes(expected)
    for name, data in output.items():
        changes.append(replace_data_rows(RESOURCES / (name + '.csv'), 'asset_id', asset_ids, data, check))
    npc = ROOT / 'scripts/npc/npc_units_custom.txt'
    raw = npc.read_bytes()
    text = raw.decode('utf-8-sig')
    newline = '\r\n' if '\r\n' in text else '\n'
    text = text.replace('\r\n', '\n')
    begin, end = '    // BEGIN ARCHIVE_MONSTER_COSMETICS', '    // END ARCHIVE_MONSTER_COSMETICS'
    lines = [begin]
    for asset in output['asset_catalog']:
        asset_id = asset['asset_id']
        lines += ['    "' + asset['async_unit_name'] + '"', '    {',
                  '        "BaseClass" "npc_dota_creature"',
                  '        "Model" "' + asset['primary_model'] + '"',
                  '        "precache"', '        {']
        for component in output['asset_components']:
            if component['asset_id'] == asset_id: lines.append('            "model" "' + component['model_path'] + '"')
        for effect in output['asset_effects']:
            if effect['asset_id'] == asset_id: lines.append('            "particle" "' + effect['particle_path'] + '"')
        lines += ['        }', '    }']
    lines.append(end)
    block = '\n'.join(lines)
    if begin in text:
        start = text.index(begin)
        stop = text.index(end, start) + len(end)
        text = text[:start] + block + text[stop:]
    else:
        stop = text.rfind('\n}')
        assert stop >= 0
        text = text[:stop] + '\n' + block + text[stop:]
    expected = (('\ufeff' if raw.startswith(b'\xef\xbb\xbf') else '') + text.replace('\n', newline)).encode('utf-8')
    changes.append(expected != raw)
    if not check and expected != raw: npc.write_bytes(expected)
    return any(changes)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--vpk', type=Path, default=ROOT.parents[1] / 'dota/pak01_dir.vpk')
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    output, models = import_rows(Vpk(args.vpk))
    changed = sync(output, models, args.check)
    print('ARCHIVE_MONSTER_COSMETICS_' + ('STALE' if args.check and changed else 'PASS'))
    return int(args.check and changed)


if __name__ == '__main__':
    raise SystemExit(main())
