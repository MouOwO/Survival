import copy
import hashlib
import json
from pathlib import Path
import sys
from types import SimpleNamespace
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'server'))
sys.path.insert(0, str(ROOT / 'tools'))
from archive_backend.lottery_catalog import catalog_document, public_catalog
from archive_backend.service import ArchiveService
from patch_lottery_catalog_handler import patch_handler


class LotteryCatalogTests(unittest.TestCase):
    def source(self):
        pool = dict(id='map', revision='r1', display_name='地图奖池', single_cost=1,
            ten_cost=10, tickets=500, unlocked=True, unlock_progress=10, update_unread=True,
            pity=[dict(quality='ssr', label='十连保底', threshold=10, private_counter=9)],
            update_notice=dict(summary='更新', effective_date='', single_draw_probabilities='已公布', raw_weights=[1, 2]))
        return [dict(version=6, selected_pool_id='map', selected_pool=pool, pools=[pool],
            items=[dict(id='one', name='宝物', quality='ur', icon='items/one.png', max_owned=1,
                owned_count=3, owned=True, at_max_owned=True, item_weight=500, effects=[1])],
            pity=pool['pity'], tickets=500, starjoy_points=22, shop_points=99, draws=80,
            account_id='123', map_level=88)]

    def test_projection_excludes_all_player_state_and_private_rules(self):
        source = self.source()
        before = copy.deepcopy(source)
        result = public_catalog(source)
        self.assertEqual(source, before)
        text = json.dumps(result)
        for private in ('tickets', 'owned_count', 'at_max_owned', 'unlocked', 'unlock_progress',
                        'update_unread', 'raw_weights', 'private_counter', 'item_weight',
                        'starjoy_points', 'shop_points', 'account_id', 'map_level', 'draws'):
            self.assertNotIn('"' + private + '"', text)
        self.assertEqual(result['snapshots'][0]['items'][0]['quality'], 'ur')
        self.assertEqual(result['snapshots'][0]['selected_pool']['update_notice']['summary'], '更新')

    def test_ascii_md5_uses_exact_immutable_worker_document(self):
        bundle = SimpleNamespace(configs={'immutable': True}, directory=ROOT, hash='a' * 64)
        worker = SimpleNamespace(stdout=json.dumps({'ok': True, 'snapshots': self.source()}).encode())
        with patch('archive_backend.lottery_catalog.subprocess.run', return_value=worker) as run:
            document = catalog_document(bundle, 'lua')
        serialized = document['catalog_json']
        self.assertTrue(serialized.isascii())
        self.assertEqual(hashlib.md5(serialized.encode('ascii')).hexdigest(), document['catalog_md5'])
        self.assertEqual(json.loads(serialized), document['catalog'])
        self.assertEqual(document['config_hash'], bundle.hash)
        self.assertEqual(run.call_args.kwargs['cwd'], bundle.directory)
        payload = json.loads(run.call_args.kwargs['input'])
        self.assertEqual(payload['configs'], bundle.configs)
        self.assertEqual(payload['profile']['save']['content_inventory'], {})
        self.assertEqual(payload['command']['kind'], 'lottery_snapshot')

    def test_conditional_endpoint_avoids_catalog_body_and_database(self):
        service = ArchiveService(None, SimpleNamespace(hash='a' * 64), 'lua')
        document = dict(catalog_md5='b' * 32, config_hash='a' * 64, catalog_json='{"schema":1}')
        with patch('archive_backend.lottery_catalog.build_catalog', return_value=document) as build:
            initial = service.lottery_catalog({'md5': ''})
            same = service.lottery_catalog({'md5': 'b' * 32})
        self.assertEqual(build.call_count, 1)
        self.assertFalse(initial['unchanged'])
        self.assertEqual(initial['catalog_json'], document['catalog_json'])
        self.assertTrue(same['unchanged'])
        self.assertNotIn('catalog_json', same)

    def test_route_patch_preserves_auth_and_is_reproducible(self):
        source = '''def handle(self, payload):
                self.authorize(payload)
                if self.path == "/other":
                    response = {}
                elif self.path == "/v1/lottery/snapshot":
                    if not archive: raise ApiError("archive_disabled", 503)
                    response = archive.lottery_snapshot(payload)
                else:
                    raise ApiError("route_not_found", 404)
'''
        updated = patch_handler(source)
        compile(updated, 'patched_handler', 'exec')
        self.assertEqual(updated.count('self.authorize(payload)'), 1)
        self.assertEqual(updated.count('archive_disabled'), 2)
        self.assertIn('archive.lottery_catalog(payload)', updated)
        self.assertEqual(updated, patch_handler(updated))


if __name__ == '__main__':
    unittest.main()
