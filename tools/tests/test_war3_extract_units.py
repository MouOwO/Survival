"""Small independent format fixtures; no game, archive or map execution."""
from __future__ import annotations

import importlib.util
import json
import struct
import tempfile
import unittest
from pathlib import Path

SPEC = importlib.util.spec_from_file_location("war3_extract_units", Path(__file__).resolve().parents[1] / "war3_extract_units.py")
units = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(units)


def slk(header, rows):
    result = ['ID;PWXL;N;E', f'B;X{len(header)};Y{len(rows)+1};D0']
    for row_number, row in enumerate([header] + rows, 1):
        for column, value in enumerate(row, 1):
            if value is None:
                continue
            token = '"' + value.replace('"', '""') + '"' if isinstance(value, str) else str(value)
            result.append(f'C;X{column};Y{row_number};K{token}')
    return ('\n'.join(result) + '\nE\n').encode('utf-8')


def sample_members():
    return {
        units.SLK_MEMBERS['data']: slk(['unitID', 'race', 'movetp'], [['h001', 'creeps', 'foot'], ['h003', 'creeps', None]]),
        units.SLK_MEMBERS['balance']: slk(['unitBalanceID', 'HP', 'def', 'spd'], [['h001', 1000, 117.6, 270], ['h003', 50, 0, None]]),
        units.SLK_MEMBERS['weapons']: slk(['unitWeapID', 'dmgplus1', 'dice1', 'sides1', 'cool1', 'rangeN1'],
            [['h001', 20, 2, 6, 1.5, 128], ['h003', None, 1, 1, 1, 128]]),
        units.SLK_MEMBERS['ui']: slk(['unitUIID', 'file', 'modelScale'], [['h001', 'monster.mdl', 1.0], ['h003', 'other.mdl', 1.0]]),
        units.SLK_MEMBERS['abilities']: slk(['unitAbilID', 'abilList'], [['h001', 'A001,A002'], ['h003', '_']]),
        r'Units\CampaignUnitStrings.txt': '[h001]\nName=|cffff0000试验BOSS|r\nUbertip=do not export this long description\n[h003]\nName=普通\n'.encode('utf-8'),
    }


def w3u_object(table, old_id, new_id, modifications):
    result = old_id.encode() + (new_id.encode() if new_id else b'\0'*4) + struct.pack('<i', len(modifications))
    for field, kind, value in modifications:
        result += field.encode() + struct.pack('<i', kind)
        if kind == 0:
            result += struct.pack('<i', value)
        elif kind in (1, 2):
            result += struct.pack('<f', value)
        else:
            result += value.encode('utf-8') + b'\0'
        result += (new_id if table == 'custom' else old_id).encode()
    return result


class UnitExtractionTests(unittest.TestCase):
    def test_sparse_cells_are_not_forward_filled_and_quotes_survive(self):
        blob = ('ID;PWXL;N;E\nB;X3;Y3;D0\n'
            'C;X1;Y1;K"id"\nC;X2;K"name"\nC;X3;K"HP"\n'
            'C;X1;Y2;K"h001"\nC;X2;K"Boss; ""quoted"""\nC;X3;K100\n'
            'C;X1;Y3;K"h002"\nC;X3;K0\nE\n').encode()
        # A direct quote/semicolon fixture has no dependency on the writer above.
        rows, info = units.parse_slk(blob, 'sample.slk')
        self.assertEqual(rows['h001']['name']['value'], 'Boss; "quoted"')
        self.assertNotIn('name', rows['h002'])
        self.assertEqual(rows['h002']['HP']['value'], 0)
        self.assertEqual(rows['h002']['HP']['source']['row'], 3)
        self.assertEqual(info['rows'], 2)
        with self.assertRaisesRegex(units.ParseError, 'duplicate cell'):
            units.parse_slk(blob.replace(b'E\n', b'C;X3;Y3;K2\nE\n'), 'duplicate.slk')

    def test_weapon_dice_are_not_lost_and_missing_base_is_unknown(self):
        data, manifest, unknowns, patches = units.build_units(sample_members())
        row, sparse = data['units']
        self.assertEqual((row['attack1_base'], row['attack1_dice'], row['attack1_sides']), (20, 2, 6))
        self.assertEqual((row['attack1_min'], row['attack1_max']), (22, 32))
        self.assertEqual(row['armor'], 117.6)
        self.assertIsNone(sparse['attack1_base'])
        self.assertIsNone(sparse['attack1_min'])
        self.assertIsNone(sparse['movement_speed'])
        self.assertEqual(row['ability_ids'], ['A001', 'A002'])
        self.assertEqual(sparse['ability_ids'], [])
        self.assertEqual(row['name_plain'], '试验BOSS')
        self.assertIn('ConvertUnitState(0x12)', row['computed_note'])
        self.assertIn('before JASS setters', row['computed_note'])
        self.assertEqual(manifest['unit_count'], 2)
        self.assertEqual(unknowns['issues'], [])
        self.assertEqual(patches, [])

    def test_custom_parent_is_explicit_and_object_patch_wins(self):
        blobs = sample_members()
        original = w3u_object('original', 'h001', None, [('umdl', 3, 'patched.mdl')])
        child = w3u_object('custom', 'h001', 'h002', [('uhpm', 0, 2500), ('unam', 3, '子怪'), ('udef', 2, 118.5)])
        blobs['war3map.w3u'] = struct.pack('<ii', 2, 1) + original + struct.pack('<i', 1) + child
        data, manifest, _, patches = units.build_units(blobs)
        by_id = {row['raw_id']: row for row in data['units']}
        parent, child = by_id['h001'], by_id['h002']
        self.assertEqual(parent['model'], 'patched.mdl')
        self.assertEqual(child['model'], 'patched.mdl')
        self.assertEqual(child['object_parent_id'], 'h001')
        self.assertEqual(child['hp'], 2500)
        self.assertEqual(child['armor'], 118.5)
        self.assertEqual(child['attack1_max'], 32)
        self.assertEqual(child['provenance']['attack1_base']['inherited_from'], 'h001')
        self.assertEqual(child['provenance']['hp']['file'], 'war3map.w3u')
        self.assertEqual(manifest['parsing']['war3map.w3u']['bytes_parsed'], len(blobs['war3map.w3u']))
        self.assertEqual(len(patches), 4)

    def test_truncated_or_unsupported_objects_do_not_silently_parse(self):
        valid = struct.pack('<iii', 2, 0, 0)
        for blob in (valid[:-1], valid + b'junk', struct.pack('<iii', 3, 0, 0)):
            with self.assertRaises(units.ParseError):
                units.parse_w3u(blob)
        blobs = sample_members()
        child = w3u_object('custom', 'xxxx', 'h002', [])
        blobs['war3map.w3u'] = struct.pack('<iii', 2, 0, 1) + child
        with self.assertRaisesRegex(units.ParseError, 'unavailable parent'):
            units.build_units(blobs)

    def test_creation_ids_are_static_evidence_and_dynamic_calls_stay_unknown(self):
        source = b'''// CreateUnit(Player(12), 'fake', 0, 0, 0)
function Spawn takes nothing returns nothing
  call BJDebugMsg("CreateUnit(Player(12), 'fake', 0, 0, 0)")
  set u=CreateUnit(Player(12), 0x68303031, F(1, 2), 0, 0)
  set u=CreateUnit(Player(12), 'h002', 0, 0, 0)
  set u=CreateUnit(Player(0), FourCC("h003"), 0, 0, 0)
  set u=CreateUnit(Player(12), dynamic_ids[index], 0, 0, 0)
endfunction
'''
        evidence, unresolved, info = units.extract_creation_evidence(source)
        self.assertEqual(set(evidence), {'h001', 'h002', 'h003'})
        self.assertEqual(evidence['h001'][0]['line'], 4)
        self.assertEqual(evidence['h001'][0]['function'], 'Spawn')
        self.assertEqual(info['creation_calls'], 4)
        self.assertEqual(unresolved[0]['type_expression'], 'dynamic_ids[index]')
        self.assertEqual(units.literal_raw_id(str(int.from_bytes(b'h001', 'big'))), 'h001')

    def test_outputs_omit_descriptions_and_conflicting_inputs_fail(self):
        data, manifest, unknowns, patches = units.build_units(sample_members())
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            hashes = units.write_outputs(root / 'out', data, manifest, unknowns, patches)
            exported = (root / 'out' / 'units_base.json').read_text(encoding='utf-8')
            self.assertNotIn('do not export this long description', exported)
            self.assertEqual(json.loads(exported)['units'][0]['hp'], 1000)
            self.assertEqual(len(hashes), 5)
            first, second = root/'first'/'Units', root/'second'/'Units'
            first.mkdir(parents=True); second.mkdir(parents=True)
            (first/'UnitData.slk').write_bytes(b'a')
            (second/'UnitData.slk').write_bytes(b'b')
            with self.assertRaisesRegex(units.ParseError, 'conflicting extracted copies'):
                units.read_members(None, [first.parent, second.parent])
            (first/'UnitData.slk').write_bytes(b'two')
            with self.assertRaisesRegex(units.ParseError, 'remaining extraction budget'):
                units.read_members(None, [first.parent], limit=1)
            with self.assertRaisesRegex(units.ParseError, 'one byte and 32 MiB'):
                units.read_members(None, [first.parent], limit=0)


if __name__ == '__main__':
    unittest.main()
