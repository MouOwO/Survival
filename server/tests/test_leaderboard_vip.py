"""Public VIP badge contract plus the existing ranking regression suite."""
import copy
import importlib
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parent))
base = importlib.import_module('test_endless_leaderboard')


class VipLeaderboardTests(base.LeaderboardTests):
    def test_recharge_grade_and_purchased_medal_are_independent(self):
        self.app.rpc_client.rows[0].update(vip_level=12, vip_medal_level=0)
        self.app.rpc_client.rows[1].update(vip_level=2, vip_medal_level=1)
        result = self.ranking.read({'account_id': '100'})
        self.assertEqual(result['entries'][0]['vip_level'], 12)
        self.assertEqual(result['entries'][0]['vip_medal_level'], 0)
        self.assertEqual(result['entries'][1]['vip_level'], 2)
        self.assertEqual(result['entries'][1]['vip_medal_level'], 1)
        self.assertEqual(result['entries'][2]['vip_level'], 0)
        self.assertEqual(result['entries'][2]['vip_medal_level'], 0)
        self.assertEqual(result['self']['rank'], 1)

    def test_badge_changes_alter_digest_without_rank_changes(self):
        first = self.ranking.read({'account_id': '100'})
        self.app.rpc_client.rows[0]['vip_level'] = 1
        second = self.ranking.read({'account_id': '100', 'revision': first['revision']})
        self.assertFalse(second['unchanged'])
        self.assertEqual(second['self'], first['self'])
        self.app.rpc_client.rows[0]['vip_medal_level'] = 1
        third = self.ranking.read({'account_id': '100', 'revision': second['revision']})
        self.assertFalse(third['unchanged'])
        stable = self.ranking.read({'account_id': '100', 'revision': third['revision']})
        self.assertTrue(stable['unchanged'])
        self.assertNotIn('entries', stable)

    def test_invalid_badges_fail_closed(self):
        for key, maximum in [('vip_level', 12), ('vip_medal_level', 10)]:
            for value in [-1, maximum + 1, True, '1', 1.5, None, {}, []]:
                with self.subTest(key=key, value=value):
                    rows = copy.deepcopy(self.app.rpc_client.rows)
                    try:
                        self.app.rpc_client.rows[0][key] = value
                        with self.assertRaises(ValueError):
                            self.ranking.read({'account_id': '100'})
                    finally:
                        self.app.rpc_client.rows = rows

    def test_client_cannot_set_badge_and_no_private_recharge_is_returned(self):
        for key in ('vip_level', 'vip_medal_level'):
            with self.assertRaises(ValueError):
                self.ranking.read({'account_id': '100', key: 12})
        self.app.rpc_client.rows[0].update(vip_recharge_total_fen=1250000,
                                          vip_claimed={'vip_medal_10': True})
        row = self.ranking.read({'account_id': '100'})['entries'][0]
        self.assertNotIn('vip_recharge_total_fen', row)
        self.assertNotIn('vip_claimed', row)


if __name__ == '__main__':
    unittest.main(verbosity=2)
