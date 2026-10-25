"""Independent syntax fixtures plus optional private-source snapshot regression.

The original JASS is deliberately not checked in. Set WAR3_JASS to a locally
extracted supported script, or use the documented ignored extraction directory.
No JASS, Lua, native map code or Warcraft installation is executed by these tests.
"""
from __future__ import annotations

import contextlib
import hashlib
import importlib.util
import io
import json
import os
import tempfile
import unittest
from decimal import Decimal
from pathlib import Path

ROOT=Path(__file__).resolve().parents[2]
SPEC=importlib.util.spec_from_file_location('war3_waves',ROOT/'tools/war3_extract/waves.py')
waves=importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(waves)
PRIVATE_JASS=Path(os.environ.get('WAR3_JASS',str(ROOT/'output/war3_monster_feasibility_20261025/extracted/war3map.j')))
PRIVATE_MISC=Path(os.environ.get('WAR3_MISC',str(ROOT/'output/original_map_extract_20261025/extras/war3mapMisc.txt')))


class StaticFixtureTests(unittest.TestCase):
    def test_only_finite_literal_arithmetic_is_allowed(self):
        self.assertEqual(waves.safe_number('(2 + 3) * (8 / 4) - -1'),11)
        self.assertEqual(waves.safe_number('0x20 / +2'),16)
        for expression in ('True','"2"','unknown','2**8','[1][0]',
                           '__import__("os").system("exit")','(lambda: 3)()',
                           '1e999','1e308 * 1e308'):
            with self.subTest(expression=expression),self.assertRaises(ValueError):
                waves.safe_number(expression)

    def test_three_valued_conditions_keep_unknown_gates_and_reject_wrong_modes(self):
        self.assertIsNone(waves.condition_value('UnknownMapCall() == true',{}))
        self.assertFalse(waves.condition_value('(UnknownMapCall() == true) and (mode != 4)',{'mode':4}))
        self.assertTrue(waves.condition_value('(UnknownMapCall() == true) or (mode == 4)',{'mode':4}))
        self.assertTrue(waves.condition_value('ModuloInteger(wave, 5) == 0',{'wave':20}))
        guard={'line':1,'condition':'(xgdg_tDAA != 1) and (xgdg_tDAA != 5)','branch':True}
        self.assertFalse(waves.guard_possible([guard],{'xgdg_tDAA':5}))
        self.assertTrue(waves.guard_possible([guard],{'xgdg_tDAA':2}))
        self.assertTrue(waves.guard_possible([dict(guard,branch=False)],{'xgdg_tDAA':1}))

    def test_arguments_and_rawids_are_syntax_not_execution(self):
        self.assertEqual(waves.split_args('A(1, B(2,3)), "comma, and \\\"quote\\\"", ids[1], 5'),
                         ['A(1, B(2,3))','"comma, and \\\"quote\\\""','ids[1]','5'])
        self.assertEqual(waves.rawid('0x68303049'),'h00I')
        self.assertIsNone(waves.rawid('0xFF000000'))

    def test_finite_multiplier_loop_retains_decimal_and_source_evidence(self):
        lines=['set xgdg_nAAA=12','set xgdg_pAAA=4.00','set xgdg_LAAA=1.50',
               'set xgdg_oBAA=2.50','set xgdg_MBAA=2.00','set ydul_u=1','loop',
               'exitwhen ydul_u > 2','set xgdg_pAAA=( xgdg_pAAA * 1.30 )',
               'set xgdg_LAAA=( xgdg_LAAA * 1.10 )','set xgdg_oBAA=( xgdg_oBAA * 1.50 )',
               'set xgdg_MBAA=( xgdg_MBAA * 1.05 )','set ydul_u=ydul_u + 1','endloop','else']
        record={'function':'FixtureOnly','line':1,'text':lines[0],
                'guards':[{'line':100,'condition':'( ( xgdg_tDAA == 2 ) )','branch':True},
                          {'line':101,'condition':'( GetClickedButtonBJ() == LoadButtonHandle(YDLOC, key, 0x1234) )','branch':True}]}
        [row]=waves.literal_difficulty_rows(lines,[record])
        self.assertEqual((row['mode_id'],row['difficulty'],row['button_key']),(2,12,'0x1234'))
        self.assertEqual(Decimal(row['multiplier_exact_decimal']['xgdg_pAAA']),Decimal('6.76'))
        self.assertEqual(Decimal(row['multiplier_exact_decimal']['xgdg_LAAA']),Decimal('1.815'))
        self.assertEqual(row['loop_repeat'],2)
        self.assertEqual(row['assignments'][-1]['line'],12)
        self.assertEqual(row['assignments'][-1]['repeat'],2)

    def test_unknown_revision_fails_before_creating_outputs(self):
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp);source=root/'war3map.j';source.write_bytes(b'function Fake takes nothing returns nothing\nendfunction\n')
            output=root/'out'
            with self.assertRaisesRegex(waves.UnsupportedSourceRevision,'unsupported_source_revision'):
                waves.extract(source,output)
            self.assertFalse(output.exists())
            error=io.StringIO()
            with contextlib.redirect_stderr(error),self.assertRaises(SystemExit) as caught:
                waves.main(['--jass',str(source),'--output',str(output)])
            self.assertEqual(caught.exception.code,2)
            self.assertIn('unsupported_source_revision',error.getvalue())
            self.assertFalse(output.exists())

    def test_misc_coefficients_are_explicit_and_missing_fields_stay_unknown(self):
        with tempfile.TemporaryDirectory() as temp:
            path=Path(temp)/'war3mapMisc.txt'
            path.write_text('[Other]\nStrHitPointBonus=999\n[Misc]\nStrHitPointBonus=5\nAgiDefenseBonus=0\nStrAttackBonus=0.1\n',encoding='utf-8')
            data=waves.parse_hero_misc(path)
            self.assertEqual(data['coefficients']['StrHitPointBonus']['value'],5)
            self.assertEqual(data['coefficients']['StrHitPointBonus']['source']['line'],4)
            self.assertEqual(data['missing_coefficients'],['AgiAttackSpeedBonus'])
            self.assertFalse(data['native_execution_verified'])
            self.assertEqual(data['reference_snapshot_hero_hp_examples'][0]['derived_native_hp_input'],10005)
            self.assertIn('not dynamically parsed',data['reference_snapshot_hero_hp_examples'][0]['source']['scope'])
            path.write_text('[Misc]\nStrHitPointBonus=5\nStrHitPointBonus=6\n',encoding='utf-8')
            with self.assertRaisesRegex(ValueError,'duplicate hero coefficient'):
                waves.parse_hero_misc(path)


@unittest.skipUnless(PRIVATE_JASS.is_file(),'Private original JASS unavailable; set WAR3_JASS for supported-snapshot checks')
class SupportedSnapshotTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp=tempfile.TemporaryDirectory()
        cls.before=hashlib.sha256(PRIVATE_JASS.read_bytes()).hexdigest()
        cls.out=Path(cls.temp.name)/'out'
        cls.report=waves.extract(PRIVATE_JASS,cls.out,PRIVATE_MISC if PRIVATE_MISC.is_file() else None)
        cls.compositions=json.loads((cls.out/'nominal_wave_compositions.json').read_text(encoding='utf-8'))['rows']

    @classmethod
    def tearDownClass(cls):
        cls.temp.cleanup()

    def test_full_snapshot_counts_and_input_immutability(self):
        report=self.report;rows=report['difficulty_rows_all_variants']
        self.assertEqual(len(rows),299)
        self.assertEqual(sum(r['directly_bound_to_matching_N_label'] for r in rows),235)
        self.assertEqual(sum(r['selector_mode_compatible'] for r in rows),217)
        self.assertEqual(len(self.compositions),7015)
        self.assertEqual(len({(r['mode_id'],r['difficulty'],r['wave']) for r in self.compositions}),7015)
        self.assertEqual(hashlib.sha256(PRIVATE_JASS.read_bytes()).hexdigest(),self.before)
        self.assertEqual(self.before,waves.SUPPORTED_JASS_SHA256)
        self.assertEqual(report['validation']['status'],'PASS')
        self.assertEqual(set(p.name for p in self.out.iterdir()),{'wave_rules.json','difficulty_table.json','schedule_profiles.json','nominal_wave_compositions.json'})

    def test_dialog_conditions_do_not_expose_legacy_or_mode_hidden_tiers(self):
        rows=self.report['difficulty_rows_all_variants']
        visible={mode:sorted(r['difficulty'] for r in rows if r['mode_id']==mode and r['selector_mode_compatible'])for mode in range(1,8)}
        for mode,maximum in {1:9,2:50,3:50,4:22,5:9,6:45,7:32}.items():
            self.assertEqual(visible[mode],list(range(1,maximum+1)))
        standard2=[r for r in rows if r['mode_id']==1 and r['difficulty']==2]
        self.assertGreater(len(standard2),1)
        self.assertEqual([r['multipliers']['xgdg_pAAA']for r in standard2 if r['selector_mode_compatible']],[4])
        self.assertIn(3.5,[r['multipliers']['xgdg_pAAA']for r in standard2 if not r['selector_mode_compatible']])

    def test_normal_leader_scourge_and_shortcut_are_separate_formula_paths(self):
        rules=self.report['derived_rules'];writes={r['line']:r for r in self.report['formula_writes_in_order']}
        self.assertEqual(rules['leader_non_scourge']['hp_factor'],'10*pAAA')
        self.assertEqual(rules['leader_scourge']['hp_factor'],'2*pAAA')
        self.assertTrue(rules['leader_scourge']['replaces_not_stacks_with_elite_or_ordinary'])
        self.assertIn('xgdg_tDAA == 6',next(g['condition']for g in writes[26237]['guards']if g['line']==26236))
        self.assertEqual(next(g['condition']for g in writes[36425]['guards']if g['line']==36424),'( ( xgdg_tDAA == 3 ) )')
        self.assertIn('0.50',writes[36444]['text'])
        self.assertIn('9, 102',next(g['condition']for g in writes[36444]['guards']if g['line']==36443))
        self.assertFalse(any('9, 102' in g['condition']for r in writes.values()if 26221<=r['line']<=26548 for g in r['guards']))
        for rule in rules.values():
            if isinstance(rule,dict) and 'sources_refs' in rule:
                self.assertTrue(all(r['function'] and r['line'] for r in rule['sources_refs']))

    def test_wave_composition_keeps_leader_boss_and_rotation_counts(self):
        rows={(r['mode_id'],r['difficulty'],r['wave']):r for r in self.compositions}
        self.assertEqual(rows[1,2,1]['nominal_unit_count'],14)
        rich4=rows[4,2,4]
        self.assertEqual(rich4['ordinary_rawid_counts'],{'h00I':59})
        self.assertEqual(rich4['leader']['count'],1)
        self.assertEqual(rich4['nominal_unit_count'],60)
        self.assertEqual(rows[4,2,5]['assault_boss']['rawid'],'H012')
        self.assertEqual(rows[4,2,5]['ordinary_callback_count'],59)
        self.assertEqual(rows[4,2,8]['ordinary_rawid_counts'],{'h01Z':39,'h04X':20})
        self.assertEqual(rows[1,2,24]['ordinary_rawid_counts'],{'h023':20,'h054':20,'h053':19})
        self.assertEqual(rows[3,2,8]['ordinary_rawid_counts'],{'h01Z':29})
        self.assertEqual(rows[3,2,8]['scourge_random_role_split']['elite_probability_percent'],50)
        self.assertEqual(max(r['wave']for r in self.compositions if r['difficulty']==1),25)

    def test_timing_exposes_global_wave_overlap_instead_of_silently_normalizing_it(self):
        profiles={(r['mode_id'],r['difficulty']):r for r in self.report['main_schedule_profiles']}
        self.assertEqual(profiles[2,1]['bands'][0]['spawn_timer_duration_seconds'],90)
        self.assertEqual(profiles[2,1]['bands'][0]['time_relationship_to_next_wave'],'same_timestamp_boundary')
        self.assertEqual(profiles[2,11]['bands'][0]['spawn_timer_duration_seconds'],120)
        self.assertEqual(profiles[2,11]['bands'][0]['time_relationship_to_next_wave'],'overlap')
        self.assertEqual(profiles[2,20]['bands'][0]['timer_iterations'],5)
        self.assertEqual(profiles[2,40]['bands'][0]['timer_iterations'],3)
        self.assertEqual(profiles[7,20]['bands'][0]['timer_iterations'],10)
        self.assertEqual(profiles[1,1]['assault_boss_waves'],[5,10,15,20,25])
        self.assertEqual(profiles[1,2]['assault_boss_waves'],[5,10,15,20,25,30])


if __name__=='__main__':
    unittest.main()
