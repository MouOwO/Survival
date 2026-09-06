"""Import the approved wave outfits from the installed Dota item schema.

The resulting CSVs are the runtime authority. --check compares without writing.
No workshop IDs or model paths are inferred from translated names.
"""
from __future__ import annotations

import argparse
import io
import re
import struct
from pathlib import Path

from build_boss_cosmetic_batch import read_csv_document, render_csv, replace_data_rows

ROOT = Path(__file__).resolve().parents[1]
RESOURCES = ROOT / 'data/csv/资源系统'
ARCHETYPES = ROOT / 'data/csv/怪物与波次系统/monster_archetypes.csv'
# archetype: (official hero, bundle/item definition, dragon form skin)
SPECS = {
    'humanoid_red_axe': ('axe', '21022', ''),
    'skeleton_melee': ('clinkz', '21005', ''),
    'orc_large_melee': ('beastmaster', '21036', ''),
    'orc_small_axe': ('ogre_magi', '36001', ''),
    'demon_purple_melee': ('bloodseeker', '21789', ''),
    'boss_dreadlord': ('abyssal_underlord', '21515', ''),
    'beast_green_large': ('tidehunter', '21503', ''),
    'skeleton_bone': ('pugna', '22344', ''),
    'flying_red_gargoyle': ('dragon_knight', '9644', '1'),
    'dragon_red_large': ('dragon_knight', '31375', '1'),
    'dragon_red_small': ('dragon_knight', '8979', '1'),
    'orc_brown_large': ('magnataur', '36194', ''),
    'orc_brown_small': ('magnataur', '21794', ''),
    'flying_green_head': ('visage', '21010', ''),
    'dragon_purple_large': ('viper', '21253', ''),
    'dragon_purple_small': ('viper', '21436', ''),
    'dwarf_white_rifle': ('hoodwink', '29290', ''),
    'orc_longnose_large': ('spirit_breaker', '30452', ''),
    'orc_longnose_small': ('spirit_breaker', '20308', ''),
    'flying_carpet_mage': ('dark_willow', '21604', ''),
    'carpet_red_large': ('dark_willow', '21428', ''),
    'carpet_red_small': ('dark_willow', '20623', ''),
    'undead_red_mage_large': ('troll_warlord', '31091', ''),
    'undead_red_mage_small': ('troll_warlord', '21815', ''),
    'golem_gray_small': ('dark_seer', '21053', ''),
    'golem_gray_large': ('dark_seer', '21210', ''),
    'beast_striped_red': ('dragon_knight', '21387', ''),
    'boss_blade_demon': ('night_stalker', '21486', ''),
    'sea_beast_large': ('naga_siren', '28273', ''),
    'sea_beast_small': ('naga_siren', '21795', ''),
    'armored_horned_large': ('axe', '31373', ''),
    'armored_horned_small': ('axe', '21694', ''),
    'dragon_black_red_large': ('winter_wyvern', '21818', ''),
    'dragon_black_red_small': ('winter_wyvern', '21112', ''),
    'stitcher_large': ('pudge', '28270', ''),
    'stitcher_small': ('pudge', '20862', ''),
    'flying_black_bone': ('visage', '21248', ''),
    'golem_green_fire': ('necrolyte', '25023', ''),
    'boss_twinblade_demon': ('terrorblade', '5957', ''),
}


def parse_kv(text):
    tokens = iter(t for t in re.findall(r'//[^\n]*|"(?:\\.|[^"\\])*"|[{}]|[^\s{}"]+', text)
                  if not t.startswith('//'))
    def block():
        result = {}
        for key in tokens:
            if key == '}': return result
            value = next(tokens)
            result[key.strip('"')] = block() if value == '{' else value.strip('"')
        return result
    return block()


class Vpk:
    def __init__(self, path):
        self.path = Path(path)
        self.entries = {}
        with self.path.open('rb') as f:
            signature, version, tree_size = struct.unpack('<III', f.read(12))
            assert signature == 0x55AA1234 and version in (1, 2)
            if version == 2: f.read(16)
            self.data_start = f.tell() + tree_size
            tree = io.BytesIO(f.read(tree_size))
        def string():
            data = bytearray()
            while True:
                c = tree.read(1)
                if c == b'\0': return data.decode('utf-8')
                if not c: raise ValueError('truncated VPK tree')
                data.extend(c)
        while (extension := string()):
            while (directory := string()):
                while (name := string()):
                    _, size, archive, offset, length, end = struct.unpack('<IHHIIH', tree.read(18))
                    assert end == 0xffff
                    key = (directory + '/' if directory != ' ' else '') + name + '.' + extension
                    self.entries[key] = (archive, offset, length, tree.read(size))

    def read(self, key):
        archive, offset, length, preload = self.entries[key]
        path = self.path if archive == 0x7fff else self.path.with_name(f'pak01_{archive:03d}.vpk')
        with path.open('rb') as f:
            f.seek(offset + (self.data_start if archive == 0x7fff else 0))
            return preload + f.read(length)

    def verify(self, path):
        if path + '_c' not in self.entries:
            raise ValueError('compiled resource missing in installed VPK: ' + path)


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
        ids = [by_name[name] for name in selected['bundle']] if 'bundle' in selected else [item_id]
        body = heroes[hero]['Model']
        asset_id = 'monster_wave_' + archetype
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
            # Furious Nethergeist includes two mutually exclusive arms. Use its first style.
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
                if hero == 'npc_dota_hero_troll_warlord' and slot in ('weapon2', 'offhand_weapon2', 'offhand_weapon'):
                    continue
                if slot not in slots and item.get('model_player'):
                    slots.add(slot)
                    selected_ids.append(child_id)
        replacements = {m['asset']: m['modifier'] for child_id in selected_ids
                        for m in modifiers(items[child_id]) if m.get('type') == 'particle' and m.get('modifier')}
        for child_id in selected_ids:
            item = items[child_id]
            slot = item.get('item_slot', 'weapon')
            visuals = item.get('visuals', {})
            model = item.get('model_player', '')
            if model and not form_skin:
                components.append((slot, child_id, model, visuals.get('skin', '0')))
            if slot == 'costume':
                skin = visuals.get('skin', '1')
            for modifier in modifiers(item):
                kind, path = modifier.get('type'), modifier.get('modifier', '')
                if kind == 'entity_model' and modifier.get('asset') == hero:
                    body = path
                elif kind == 'hero_model_change' and form_skin:
                    body = path
                elif kind == 'activity' and modifier.get('asset') == 'ALL' and path:
                    activities.append(path)
                elif kind == 'particle_create' and path and modifier.get('style', '0') == '0':
                    owner = slot if model and not form_skin else ''
                    if hero == 'npc_dota_hero_terrorblade': owner = ''
                    particles.append((replacements.get(path, path), owner, child_id))
                elif kind == 'additional_wearable' and modifier.get('asset') and not form_skin:
                    components.append((slot + '_additional', child_id, modifier['asset'], visuals.get('skin', '0')))
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
            notes=f'{archetype}；官方bundle/item={item_id}；世界饰品独立于基础头像。'))
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
    seen = set()
    for row in rows[1:]:
        if not row or row[0] not in models: continue
        archetype = row[0]
        seen.add(archetype)
        row.extend([''] * (len(headers) - len(row)))
        row[headers.index('model_path')] = models[archetype]
        if row[headers.index('normal_flying_model_path')]:
            row[headers.index('normal_flying_model_path')] = models[archetype]
        row[headers.index('default_wearable_asset_id')] = 'monster_wave_' + archetype
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
    begin, end = '    // BEGIN WAVE_MONSTER_COSMETICS', '    // END WAVE_MONSTER_COSMETICS'
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
    print('WAVE_MONSTER_COSMETICS_' + ('STALE' if args.check and changed else 'PASS'))
    return int(args.check and changed)


if __name__ == '__main__':
    raise SystemExit(main())
