"""Generate only isolated fixture assets, never the real NPC/localization files."""
import csv
import re
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
GENERATOR = ROOT / 'tools/build_archive_challenge_assets.ps1'


class ArchiveAssets(unittest.TestCase):
    def fixture(self, root, *, count=None, fourth_model=None):
        folder = root / 'data/csv/存档系统'
        folder.mkdir(parents=True)
        (root / 'scripts/npc').mkdir(parents=True)
        (root / 'resource').mkdir(parents=True)
        (root / 'resource/addon_schinese.txt').write_text('"lang"\n{\n    "Tokens"\n    {\n    }\n}\n', encoding='utf8')

        def table(name, rows):
            with (folder / name).open('w', encoding='utf-8-sig', newline='') as handle:
                writer = csv.DictWriter(handle, fieldnames=list(rows[0]))
                writer.writeheader()
                writer.writerows(rows)

        rule = dict(rule_id='default', building_model='models/default.vmdl',
                    building_model_1='models/one.vmdl', building_model_2='models/two.vmdl',
                    building_model_3='models/three.vmdl', building_model_scale='1')
        if count is not None:
            rule['building_count'] = str(count)
        if fourth_model is not None:
            rule['building_model_4'] = fourth_model
        table('archive_challenge_rules.csv', [rule])
        base = dict(
            challenge_id='shadow_1', display_name='完整"名称"', min_difficulty=3,
            unlock_text='N3解锁，不要重复拼接', ability_icon='nevermore_shadowraze1',
            cooldown_seconds=3, building_id=1, slot_order=1, enabled=1,
            reward_kind='shadow', reward_key='1',
            description='需要：\n - N3解锁<br>挑战成功后可获得虚空之影道具',
        )
        definitions = [base,
            dict(base, challenge_id='fragment_1', slot_order=2, reward_kind='fragment',
                 description='神器碎片-光明圣器\n需要：N3解锁'),
            dict(base, challenge_id='cage_1', building_id=3, slot_order=1, reward_kind='cage',
                 description='挑战成功后获得专属奖励'),
        ]
        for tier in range(2, 5):
            definitions.append(dict(base, challenge_id='shadow_' + str(tier),
                                    building_id=4, slot_order=tier-1, reward_key=str(tier)))
        table('archive_challenge_definitions.csv', definitions)
        table('archive_shadow_items.csv', [dict(item_id='shadow_'+str(i), source_boss_difficulty=str(i), quality=quality)
                                          for i, quality in enumerate(['white', 'blue', 'purple', 'gold'], 1)])
        actions = []
        for key, floor, slot in [('endless', 2, 1), ('endless_skip', 2, 2), ('tower_solo', 2, 3)]:
            actions.append(dict(action_id=key, ability_name='ability_archive_' + key,
                                building_id=floor, slot_order=slot, display_name='控制：' + key,
                                min_difficulty=3, unlock_text='N3解锁', ability_icon='chen_hand_of_god',
                                cooldown_seconds=0, enabled=1, description='完整正文：' + key))
        table('archive_challenge_actions.csv', actions)

    def generate(self, root):
        shell = shutil.which('pwsh') or shutil.which('powershell')
        self.assertIsNotNone(shell)
        return subprocess.run([shell, '-NoProfile', '-File', str(GENERATOR), '-RepoRoot', str(root)],
                              capture_output=True, encoding='utf8', errors='replace', check=False)

    def test_default_four_buildings_configured_controls_and_full_tooltips(self):
        with tempfile.TemporaryDirectory(prefix='archive_assets_20261029_') as temporary:
            root = Path(temporary)
            self.fixture(root)
            result = self.generate(root)
            self.assertEqual(result.returncode, 0, result.stderr)
            units = (root / 'scripts/npc/npc_archive_challenges_units.txt').read_text(encoding='utf8')
            abilities = (root / 'scripts/npc/npc_archive_challenges_abilities.txt').read_text(encoding='utf8')
            localization = (root / 'resource/addon_schinese.txt').read_text(encoding='utf-8-sig')
            self.assertEqual(units.count('"npc_archive_challenge_'), 4)
            fourth = units.split('"npc_archive_challenge_4"')[1]
            self.assertIn('"Model" "models/three.vmdl"', fourth)
            for key in ['endless', 'endless_skip', 'tower_solo', 'finish']:
                self.assertEqual(abilities.count('"ability_archive_' + key + '"'), 1)
            self.assertNotIn('ability_archive_return_', abilities + localization)
            self.assertEqual(re.findall(r'"AbilityLayout" "(\d+)"', units), ['2', '3', '1', '3'])
            self.assertIn('完整\\"名称\\"', localization)
            self.assertIn('需要：\\n - N3解锁\\n挑战成功后可获得', localization)
            self.assertNotIn('<br>', localization)
            for color in ['#d7dee4', '#74c8f2', '#b680ee', '#f5c65e']:
                self.assertIn('<font color=\\"' + color + '\\">', localization)
            self.assertIn('<font color=\\"#f5c65e\\">光明圣器</font>', localization)
            self.assertIn('<font color=\\"#b680ee\\">专属奖励</font>', localization)
            self.assertNotIn('当前关卡≥', localization)
            self.assertNotIn('不要重复拼接', localization)
            self.assertIn('完整正文：endless_skip', localization)
            self.assertEqual(localization.count('// BEGIN ARCHIVE_CHALLENGE_LOCALIZATION'), 1)
            # A second generation replaces just the owned localization block.
            second = self.generate(root)
            self.assertEqual(second.returncode, 0, second.stderr)
            self.assertEqual(localization, (root / 'resource/addon_schinese.txt').read_text(encoding='utf-8-sig'))

    def test_explicit_count_and_fourth_model(self):
        with tempfile.TemporaryDirectory(prefix='archive_assets_20261029_') as temporary:
            root = Path(temporary)
            self.fixture(root, count=5, fourth_model='models/four.vmdl')
            result = self.generate(root)
            self.assertEqual(result.returncode, 0, result.stderr)
            units = (root / 'scripts/npc/npc_archive_challenges_units.txt').read_text(encoding='utf8')
            self.assertEqual(units.count('"npc_archive_challenge_'), 5)
            self.assertIn('"Model" "models/four.vmdl"', units.split('"npc_archive_challenge_4"')[1])
            self.assertIn('"Model" "models/default.vmdl"', units.split('"npc_archive_challenge_5"')[1])


if __name__ == '__main__':
    unittest.main()
