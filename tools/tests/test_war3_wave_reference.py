"""Decimal joins, branch safety and optional private original-table regression."""
from __future__ import annotations

import copy
import importlib.util
import json
import unittest
from decimal import Decimal
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location('war3_wave_reference', ROOT/'tools/war3_extract/wave_reference.py')
reference = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(reference)
PRIVATE = ROOT/'output/original_map_extract_20261025'
MISC = '[Misc]\nStrHitPointBonus=5\nAgiDefenseBonus=0\nAgiAttackSpeedBonus=0\nStrAttackBonus=0.1\n'


def fixture():
    source = {'sha256': 'fixture_same_snapshot', 'path': 'fixture.j'}
    unit = {'raw_id': 'h00I', 'hp': 500, 'armor': 8, 'attack1_base': 30,
            'primary_attribute': '_', 'strength': None, 'agility': None,
            'attack1_dice': 1, 'attack1_sides': 2,
            'provenance': {'hp': {'file': 'fixture.slk', 'line': 5},
                           'armor': {'file': 'fixture.slk', 'line': 6},
                           'attack1_base': {'file': 'fixture.slk', 'line': 7}}}
    hero = dict(unit, raw_id='H012', hp=10000, armor=100, attack1_base=650,
                primary_attribute='STR', strength=1, agility=1)
    units = {'schema': 'war3_units_base_v1', 'units': [unit, hero]}
    rules = {'source': source, 'derived_rules': {}}
    for name, hp, attack, armor, modes in [
            ('ordinary', 'pAAA', 'pAAA', 'LAAA', [1, 2, 4, 5, 6, 7]),
            ('ordinary_scourge', '3*pAAA', 'pAAA', '2*LAAA', [3]),
            ('elite_scourge', '5*pAAA', '2*pAAA', '2*LAAA', [3]),
            ('leader_non_scourge', '10*pAAA', '4*pAAA', '2*LAAA', [1, 2, 4, 5, 6, 7]),
            ('leader_scourge', '2*pAAA', '2*pAAA', 'LAAA', [3]),
            ('assault_boss', 'pAAA', 'pAAA', 'LAAA', [1, 2, 3, 4, 5])]:
        rules['derived_rules'][name] = {'hp_factor': hp, 'attack_factor': attack,
                                       'armor_factor': armor, 'modes': modes,
                                       'sources_refs': [{'function': 'FixtureSpawn', 'line': 50}]}
    difficulties = {'source': source, 'rows': []}
    for mode, p, armor in [(1, '4', '1.5'), (4, '16', '5'), (3, '1123', '14')]:
        difficulties['rows'].append({'mode_id': mode, 'difficulty': 2,
                                     'directly_bound_to_matching_N_label': True,
                                     'selector_mode_compatible': True,
                                     'multiplier_exact_decimal': {'xgdg_pAAA': p, 'xgdg_LAAA': armor},
                                     'source': {'function': 'FixtureDifficulty', 'line': 10+mode}})
    compositions = {'source': source, 'rows': []}
    for mode, wave, count in [(1, 4, 14), (1, 5, 14), (4, 5, 59), (3, 4, 29)]:
        row = {'mode_id': mode, 'difficulty': 2, 'wave': wave,
               'ordinary_rawid_counts': {'h00I': count},
               'leader': None, 'assault_boss': None,
               'time_relationship_to_next_wave': 'completes_before_next_wave'}
        if wave == 4:
            row['leader'] = {'rawid': 'h00I', 'count': 1,
                             'stat_rule': 'leader_scourge' if mode == 3 else 'leader_non_scourge'}
        if wave == 5:
            row['assault_boss'] = {'rawid': 'H012', 'count': 1, 'stat_rule': 'assault_boss'}
        if mode == 3:
            row['scourge_random_role_split'] = {'ordinary_probability_percent': 50,
                                               'elite_probability_percent': 50}
        compositions['rows'].append(row)
    return units, rules, difficulties, compositions


class ReferenceFixtureTests(unittest.TestCase):
    def test_rich_hero_hp_adds_misc_before_multiplier_and_attack_is_base_only(self):
        data = reference.build_reference(*fixture(), MISC)
        row = next(r for r in data['rows'] if r['mode_id'] == 4 and r['role'] == 'assault_boss')
        self.assertEqual(row['hp_slk_product'], '160000')
        self.assertEqual(row['hp_native_prediction'], '160080')
        self.assertEqual(row['attack_base_setter_prediction'], '10400')
        self.assertEqual(row['armor_floor'], '500')
        self.assertEqual(row['source_refs']['difficulty'], '4:N2')
        self.assertEqual(data['provenance']['units']['H012']['attack1_dice'], '1')
        self.assertIn('not final panel damage', ' '.join(data['limitations']))
        self.assertEqual(data['unresolved'], [])
        self.assertFalse(data['native_execution_verified'])
        json.dumps(data, allow_nan=False)

    def test_scourge_leader_replaces_other_role_factors_and_random_counts_stay_unknown(self):
        rows = [r for r in reference.build_reference(*fixture(), MISC)['rows'] if r['mode_id'] == 3]
        by_role = {r['role']: r for r in rows}
        self.assertEqual(by_role['leader']['hp_native_prediction'], '1123000')
        self.assertEqual(by_role['leader']['attack_base_setter_prediction'], '67380')
        self.assertEqual(by_role['leader']['armor_floor'], '112')
        self.assertEqual(by_role['ordinary']['hp_native_prediction'], '1684500')
        self.assertEqual(by_role['elite']['hp_native_prediction'], '2807500')
        self.assertEqual(by_role['ordinary']['armor_floor'], '224')
        for role in ('ordinary', 'elite'):
            self.assertIsNone(by_role[role]['count'])
            self.assertEqual(by_role[role]['spawn_trials'], 29)
            self.assertEqual(by_role[role]['probability_percent'], '50')
        self.assertEqual(by_role['leader']['count'], 1)

    def test_armor_floor_is_true_floor_and_decimal_source_wins_float_fallback(self):
        args = fixture()
        args[0]['units'][0]['armor'] = Decimal('78.4')
        args[2]['rows'][0]['multipliers'] = {'xgdg_pAAA': 999, 'xgdg_LAAA': 999}
        data = reference.build_reference(*args, MISC)
        row = next(r for r in data['rows'] if r['mode_id'] == 1 and r['wave'] == 4 and r['role'] == 'ordinary')
        self.assertEqual((row['armor_native_prediction'], row['armor_floor']), ('117.6', '117'))
        self.assertEqual(row['hp_native_prediction'], '2000')
        args[0]['units'][0]['armor'] = Decimal('-0.2')
        row = next(r for r in reference.build_reference(*args, MISC)['rows'] if r['mode_id'] == 1 and r['role'] == 'ordinary')
        self.assertEqual((row['armor_native_prediction'], row['armor_floor']), ('-0.3', '-1'))

    def test_missing_native_inputs_and_conditional_bosses_are_not_defaulted(self):
        args = fixture()
        data = reference.build_reference(*args, '[Misc]\n')
        boss = next(r for r in data['rows'] if r['role'] == 'assault_boss')
        self.assertIsNone(boss['hp_native_prediction'])
        self.assertEqual(boss['hp_slk_product'], '40000')
        self.assertEqual(boss['status'], 'unresolved')
        args[1]['derived_rules']['conditionalboss'] = {'branches': [
            {'condition': 'unknown_archive_flag', 'hp_factor': '2*pAAA'},
            {'condition': 'else', 'hp_factor': 'pAAA'}]}
        args[3]['rows'][1]['assault_boss']['stat_rule'] = 'conditionalboss'
        data = reference.build_reference(*args, MISC)
        boss = next(r for r in data['rows'] if r['mode_id'] == 1 and r['role'] == 'assault_boss')
        self.assertIsNone(boss['hp_native_prediction'])
        self.assertIsNone(boss['hp_multiplier'])
        self.assertEqual(boss['unresolved_reason'], 'unsupported_or_conditional_rule')
        self.assertEqual(len(data['unresolved_rule_definitions']['conditionalboss']['branches']), 2)

    def test_source_mismatch_duplicate_primary_and_unsafe_factor_are_rejected(self):
        args = fixture()
        args[3]['source'] = {'sha256': 'different_original_map'}
        with self.assertRaisesRegex(ValueError, 'source hashes must match'):
            reference.build_reference(*args, MISC)
        args = fixture()
        args[2]['rows'].append(copy.deepcopy(args[2]['rows'][0]))
        with self.assertRaisesRegex(ValueError, 'duplicate primary difficulty'):
            reference.build_reference(*args, MISC)
        for text in ('__import__("os").system("exit")', 'pAAA**3', 'pAAA*unknown_flag'):
            with self.subTest(text=text), self.assertRaises(ValueError):
                reference.factor_value(text, {'pAAA': Decimal('4')})

    def test_unselected_old_difficulty_variants_and_optional_flags_do_not_change_baseline(self):
        args = fixture()
        old = copy.deepcopy(args[2]['rows'][0])
        old['directly_bound_to_matching_N_label'] = False
        old['multiplier_exact_decimal']['xgdg_pAAA'] = '999'
        args[2]['rows'].append(old)
        args[1]['derived_rules']['mutable_player_flags'] = [{'key': '0x3F8387FA', 'effect': 'optional half attack'}]
        args[1]['derived_rules']['endgame_shortcut'] = {'archive_flag_modifier': {'effect': 'optional all stats half'}}
        data = reference.build_reference(*args, MISC)
        boss = next(r for r in data['rows'] if r['mode_id'] == 4 and r['role'] == 'assault_boss')
        self.assertEqual(boss['attack_base_setter_prediction'], '10400')
        self.assertEqual(boss['conditional_modifier_refs'], ['0x3F8387FA'])
        self.assertEqual(data['counts']['primary_difficulties'], 3)
        self.assertIn('archive_flag_modifier', data['excluded_conditional_path'])
        self.assertEqual(reference._conditional_refs(
            {'0x3F8387FA': {}, '0x63E6C20F': {}, '0x851E1C03': {}}, 'ordinary', 'ordinary_scourge'), [])
        self.assertEqual(reference._conditional_refs(
            {'0x3F8387FA': {}, '0x63E6C20F': {}, '0x851E1C03': {}}, 'elite', 'elite_scourge'), ['0x63E6C20F'])


@unittest.skipUnless((PRIVATE/'units/units_base.json').is_file() and (PRIVATE/'waves/wave_rules.json').is_file(),
                     'Private extracted original-map facts unavailable')
class OriginalReferenceTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        load = lambda relative: json.loads((PRIVATE/relative).read_text(encoding='utf-8'))
        cls.report = reference.build_reference(load('units/units_base.json'), load('waves/wave_rules.json'),
                                               load('waves/difficulty_table.json'), load('waves/nominal_wave_compositions.json'),
                                               (PRIVATE/'extras/war3mapMisc.txt').read_text(encoding='utf-8-sig'))

    def test_all_original_difficulties_and_normal_n2_all_thirty_waves(self):
        self.assertEqual(self.report['counts']['primary_difficulties'], 235)
        self.assertEqual(self.report['counts']['composition_contexts'], 7015)
        normal = [r for r in self.report['rows'] if r['mode_id'] == 1 and r['difficulty'] == 2]
        self.assertEqual({r['wave'] for r in normal}, set(range(1, 31)))
        self.assertEqual(sum(r['role'] == 'assault_boss' for r in normal), 6)
        self.assertEqual(self.report['coverage_issues'], [])
        self.assertEqual(self.report['unresolved'], [])
        self.assertLess(len(json.dumps(self.report, ensure_ascii=False).encode('utf-8')), 50*1024*1024)

    def test_real_rich_n2_anchors_and_hp_inputs_remain_distinct(self):
        rows = [r for r in self.report['rows'] if r['mode_id'] == 4 and r['difficulty'] == 2]
        leader = next(r for r in rows if r['wave'] == 4 and r['role'] == 'leader')
        self.assertEqual((leader['hp_native_prediction'], leader['attack_base_setter_prediction'], leader['armor_floor']),
                         ('80000', '1920', '80'))
        ordinary = next(r for r in rows if r['wave'] == 4 and r['role'] == 'ordinary')
        self.assertEqual((ordinary['hp_native_prediction'], ordinary['attack_base_setter_prediction'], ordinary['armor_floor']),
                         ('8000', '480', '40'))
        boss = next(r for r in rows if r['wave'] == 5 and r['role'] == 'assault_boss')
        self.assertEqual((boss['raw_id'], boss['hp_slk_product'], boss['hp_native_prediction']),
                         ('H012', '160000', '160080'))
        self.assertEqual(boss['source_refs']['rule'], 'assault_boss')


if __name__ == '__main__':
    unittest.main()
