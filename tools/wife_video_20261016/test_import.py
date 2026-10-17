"""Check imported rewards against the independently reviewed video transcript."""
import hashlib
import json
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'server'))
from archive_backend.bundle import read_csv

CSV = ROOT / 'data/csv/存档系统'
REFERENCE = json.loads((ROOT / 'data/reference/wife_tooltips_20261016.json').read_text(encoding='utf-8'))
BASE = 'caf4493bb7ad373a43ca81c19f961d4fd288a47112866ba93df62013852f7a59'


class ImportedVideoTests(unittest.TestCase):
    def test_names_tooltips_effects_caps_and_deferred_entries(self):
        items = read_csv(CSV / 'archive_social_items.csv')['rows']
        old = {r['item_id']:r for r in items if r['pool_id'] == 'ex'}
        wives = {r['item_id']:r for r in items if r['pool_id'] == 'wife'}
        self.assertEqual(len(wives), 40)
        self.assertEqual(len({r['display_name'] for r in wives.values()}), 40)
        for source in REFERENCE['items']:
            identity = f"wife_{source['index']:02}"
            row = wives[identity]
            self.assertTrue(row['enabled'])
            self.assertEqual(row['display_name'], source['name'])
            self.assertEqual(row['description'], source['tooltip'])
            self.assertEqual(row['quality'], source['quality'])
            self.assertEqual(row['max_owned'], old[f"ex_{source['index']:02}"]['max_owned'])
            if 'special' in source:
                self.assertIs(row['draw_enabled'], False)
                self.assertIn('待适配', row['availability_note'])
                self.assertFalse(row.get('effect_ids'))
                self.assertFalse(row.get('effect_values'))
            else:
                self.assertIsNot(row.get('draw_enabled'), False)
                self.assertEqual(row['effect_ids'], [source['field']])
                self.assertEqual([float(v) for v in row['effect_values']], [source['value']])
        self.assertEqual(sum(r.get('draw_enabled') is not False for r in wives.values()), 38)

    def test_existing_rewards_unchanged_except_reviewed_rarity(self):
        base = json.loads((ROOT / 'server/bundles' / BASE / 'bundle.json').read_bytes())
        rows = read_csv(CSV / 'archive_social_items.csv')['rows']
        current = [r for r in rows if r['pool_id'] != 'wife']
        previous = base['configs']['archive_social_items']['rows']
        self.assertEqual(len(current), len(previous))
        for now, old in zip(current, previous):
            self.assertEqual({k: v for k, v in now.items() if k != 'quality'},
                             {k: v for k, v in old.items() if k != 'quality'})
            index = int(now['item_id'].rsplit('_', 1)[1])
            expected = 'N' if index <= 5 else 'R' if index <= 15 else 'SR' if index <= 27 else 'SSR' if index <= 37 else 'UR'
            self.assertEqual(now['quality'], expected)

    def test_independent_rose_and_challenge(self):
        rules = {r['pool_id']:r for r in read_csv(CSV / 'archive_social_rules.csv')['rows']}
        wife = rules['wife']
        self.assertEqual((wife['currency_id'], wife['currency_name'], wife['draw_cost'], wife['daily_limit']), ('rose','玫瑰',1,10))
        self.assertNotIn('rose', [r['currency_id'] for key,r in rules.items() if key != 'wife'])
        definitions = read_csv(CSV / 'archive_challenge_definitions.csv')['rows']
        challenge = next(r for r in definitions if r['challenge_id'] == 'social_wife')
        self.assertEqual((challenge['building_id'],challenge['slot_order'],challenge['reward_kind'],challenge['reward_key']), (3,11,'social_ticket','wife'))
        self.assertEqual(len([r for r in definitions if r['building_id'] == 3 and r['enabled']]), 11)
        stats = read_csv(CSV / 'archive_challenge_stats.csv')['rows']
        old = {r['difficulty_id']:r for r in stats if r['challenge_id'] == 'social_ex'}
        wife = {r['difficulty_id']:r for r in stats if r['challenge_id'] == 'social_wife'}
        self.assertEqual(set(wife), {'N'+str(n) for n in range(1,11)})
        for difficulty,row in wife.items():
            for key,value in old[difficulty].items():
                if key not in ('stats_id','challenge_id','notes'):
                    self.assertEqual(row[key], value)

    def test_all_portraits_have_independent_matching_character_assets(self):
        sys.path.insert(0, str(ROOT / 'tools'))
        from read_archive_icons import read_icons
        rows = read_icons('wife')
        manifest = json.loads((ROOT / 'data/ui/wife_portraits_v1.json').read_text(encoding='utf-8'))
        old = json.loads((ROOT / 'data/ui/archive_portraits_v3.json').read_text(encoding='utf-8'))
        self.assertEqual(len(rows), 40)
        self.assertEqual(len({r['runtime_uri'] for r in rows}), 40)
        self.assertEqual(len({r['icon_path'] for r in rows}), 40)
        for row in rows:
            identity = row['item_id']
            asset = manifest['items'][identity]
            self.assertEqual(row['art_status'], 'generated_wife_portrait_v1')
            self.assertEqual(row['icon_path'], f'custom_game/wife_portraits_v1/{identity}.png')
            self.assertEqual(asset['id'], identity)
            self.assertEqual(asset['display_name'], row['display_name'])
            self.assertTrue(asset['canonical_name'])
            self.assertTrue(asset['series'])
            self.assertEqual(asset['generator'], 'built-in image_gen')
            self.assertEqual(row['runtime_uri'], row['small_runtime_uri'])
            self.assertEqual(row['runtime_uri'], asset['runtime_uri'])
            relative = row['runtime_uri'].removeprefix('s2r://') + '_c'
            self.assertTrue((ROOT / relative).is_file(), relative)
            self.assertEqual(hashlib.sha256((ROOT / 'panorama/src/images' / row['icon_path']).read_bytes()).hexdigest(), row['sha256'])
            self.assertEqual(row['sha256'], asset['sha256'])
            if identity == 'wife_19':
                self.assertEqual(asset['generation_kind'], 'reused_correct_character')
                self.assertEqual(asset['reused_from'], 'ex_27')
                self.assertEqual(row['sha256'], old['ex_27']['sha256'])
            else:
                self.assertEqual(asset['generation_kind'], 'new_generation')
                self.assertNotIn(row['sha256'], {r['sha256'] for r in old.values()})


if __name__ == '__main__':
    unittest.main()
