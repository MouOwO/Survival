"""Behavioral data contract for video archive challenges; no live game/network."""
import csv
import importlib.util
import json
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CSV = ROOT / 'data/csv/存档系统'
FACTS = json.loads((ROOT / 'data/balance/archive_video_20261029.json').read_text(encoding='utf8'))


def rows(name, key):
    with (CSV / name).open(encoding='utf-8-sig', newline='') as handle:
        return [r for r in csv.DictReader(handle) if r.get(key) and not r[key].startswith('#')]


class ArchiveVideoContract(unittest.TestCase):
    def test_four_sparse_grids_and_user_cancelled_pal(self):
        definitions = {r['challenge_id']: r for r in rows('archive_challenge_definitions.csv', 'challenge_id')}
        actions = rows('archive_challenge_actions.csv', 'action_id')
        self.assertEqual(len(definitions), 36)
        self.assertEqual(len(actions), 7)
        slots = {(int(r['building_id']), int(r['slot_order'])) for r in [*definitions.values(), *actions]}
        self.assertEqual(len(slots), 43)
        self.assertNotIn((4, 8), slots)
        self.assertNotIn('pet', definitions)
        self.assertEqual([definitions[f'hunt_{i:02}']['display_name'] for i in range(9, 13)],
                         ['神兽狩猎-奥蕾莉亚', '神兽狩猎-乌瑟尔', '神兽狩猎-泰蕾苟萨', '神兽狩猎-古尔丹'])
        self.assertEqual([int(definitions[f'hunt_{i:02}']['slot_order']) for i in range(9, 13)], [5, 6, 7, 8])
        self.assertEqual((definitions['hunt_16']['building_id'], definitions['hunt_16']['slot_order']), ('4', '4'))
        self.assertEqual((definitions['social_wife']['building_id'], definitions['social_wife']['slot_order']), ('4', '9'))
        for index in range(1, 5):
            action = next(r for r in actions if r['action_id'] == f'return_{index}')
            self.assertEqual((action['building_id'], action['slot_order']), (str(index), '12'))

    def test_evidence_and_unlocks_are_not_fabricated(self):
        by_id = {r['challenge_id']: r for r in FACTS['challenges']}
        self.assertEqual(FACTS['sources']['conditions']['sha256'], 'dcb2079b74dccdd90f919b76efce9fa45198b45f0f89ccbffe4e704ac9af87b1')
        self.assertEqual(FACTS['sources']['related']['sha256'], '27d3c04410504913e116f333e937f0441a43be7db25272672a5199459a16cf04')
        self.assertTrue(FACTS['excluded_features'][0]['excluded_by_user_20261029'])
        for key in ['social_beast', 'social_ex', 'social_friend', 'football', 'watermelon']:
            self.assertEqual(by_id[key]['min_difficulty'], 1)
        for key in ['social_wife', 'social_concubine']:
            self.assertEqual(by_id[key]['min_difficulty'], 10)
        for key, prerequisite in [('social_ex', 'beast'), ('social_friend', 'ex'), ('social_wife', 'friend'), ('social_concubine', 'friend')]:
            row = by_id[key]
            self.assertEqual(row['reward_requirement_pool'], prerequisite)
            self.assertEqual(row['reward_requirement_count'], 100)
            self.assertEqual(row['evidence']['reward_requirement_comparison'], 'strictly_greater_than')
        for row in FACTS['challenges']:
            self.assertFalse(row['stat_evidence']['health']['observed_in_attached_video'])
            self.assertFalse(row['stat_evidence']['war3_armor']['observed_in_attached_video'])
        self.assertEqual(by_id['social_concubine']['stat_evidence']['attack']['precision'], 'rounded_display_only_unknown_exact_integer')
        self.assertEqual(by_id['football']['stats']['count'], 5)
        self.assertIn('视频未列群数', by_id['football']['stats_notes'])

    def test_v3_final_health_armor_speed_preserved_and_precise_attacks(self):
        source = json.loads((ROOT / 'data/balance/human_spec_v3/normalized.json').read_text(encoding='utf8'))
        reference = {r['name']: r for r in source['save_challenges']}
        authored = [r for r in FACTS['challenges'] if r['stat_evidence']['health']['source'] == 'human_spec_v3_final_authored_value']
        self.assertEqual(len(authored), 29)
        for row in authored:
            origin = reference[row['stat_evidence']['health']['v3_name']]
            self.assertEqual(row['stats']['health'], origin['health'])
            self.assertEqual(row['stats']['war3_armor'], origin['war3_armor'])
            self.assertEqual(row['stats']['attack_speed'], origin['attack_speed'] / 100)
        by_id = {r['challenge_id']: r['stats'] for r in FACTS['challenges']}
        self.assertEqual(by_id['hunt_06']['attack'], 42000000)
        self.assertEqual(by_id['hunt_07']['attack'], 84000000)
        self.assertEqual(by_id['hunt_08']['attack'], 168000002)
        self.assertEqual(by_id['football']['attack'], 64901248)
        self.assertEqual(by_id['watermelon']['attack'], 360000000)
        for key in ['social_beast', 'social_ex', 'social_friend', 'social_wife', 'social_concubine']:
            self.assertEqual(by_id[key]['health'], 32000000)
            self.assertEqual(by_id[key]['attack'], 649000000)
            self.assertEqual(by_id[key]['war3_armor'], 7992)

    def test_real_lua_resolver_ignores_mode_and_high_difficulty_multipliers(self):
        specification = importlib.util.spec_from_file_location('archive_fixture_builder', ROOT / 'tools/build_configs.py')
        module = importlib.util.module_from_spec(specification)
        specification.loader.exec_module(module)
        lua = shutil.which('lua5.1') or shutil.which('lua') or r'C:\Program Files\lua\bin\lua5.1.exe'
        with tempfile.TemporaryDirectory(prefix='archive_contract_20261029_') as temporary:
            temporary = Path(temporary)
            generated = temporary / 'config/generated'
            generated.mkdir(parents=True)
            module.build(CSV / 'archive_challenge_stats.csv', generated / 'archive_challenge_stats.lua')
            test = temporary / 'check.lua'
            test.write_text('''package.path = [=[%s/?.lua]=] .. ";scripts/vscripts/?.lua;" .. package.path
package.loaded["config/human_monster_rules"] = {data = {}}
local resolver = require("config/human_challenge_balance")
local stats = require("config/generated/archive_challenge_stats")
local checked = 0
for _, source in ipairs(stats.rows) do
    if source.difficulty_id == "N1" then
        for _, mode in ipairs({"standard", "pure", "rich", "cold", "scourge"}) do
            for difficulty = 1, 50 do
                local value = assert(resolver.archive(source.challenge_id, "N" .. difficulty, mode))
                assert(value.fixed_archive_stats and value.human_spec)
                assert(value.difficulty_id == "N" .. difficulty)
                for _, key in ipairs({"health", "attack", "war3_armor", "attack_speed", "count"}) do
                    assert(value[key] == source[key], source.challenge_id .. " " .. key)
                end
                checked = checked + 1
            end
        end
    end
end
assert(checked == 9000)
assert(resolver.archive("pet", "N1") == nil)
assert(resolver.archive("not_a_challenge", "N50") == nil)
local football = resolver.archive("football", "N50", "scourge")
assert(football.attack == 64901248 and football.count == 5 and football.health == 32000000)
assert(resolver.archive("hunt_09", "N15").attack == 5500002)
assert(resolver.archive("social_concubine", "N50").attack == 649000000)
print("ARCHIVE_FIXED_RESOLVER_PASS " .. checked)
''' % temporary.as_posix(), encoding='utf8')
            result = subprocess.run([lua, str(test)], cwd=ROOT, capture_output=True, text=True, encoding='utf8')
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn('ARCHIVE_FIXED_RESOLVER_PASS 9000', result.stdout)


if __name__ == '__main__':
    unittest.main()
