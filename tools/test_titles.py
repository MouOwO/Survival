"""Title progression and receipt regressions against the real packaged worker."""
from pathlib import Path
import copy
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path[:0] = [str(ROOT / 'output/python_test_runtime'), str(ROOT / 'server'), str(ROOT / 'tools')]
from lupa.lua51 import LuaRuntime
from test_vip_rewards import fixtures, LocalWorkerService
from archive_backend.bundle import build, Bundle
from archive_backend.service import ArchiveError

TITLE_IDS = ('peak_perfection', 'jinghong', 'youlong', 'jian_tianya', 'tianxia_diyi',
             'cangqiong', 'sihai', 'daoyuan', 'chushen')


class TitleBackendTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.TemporaryDirectory()
        cls.addClassCleanup(cls.tmp.cleanup)
        digest = build(ROOT, Path(cls.tmp.name), False)
        cls.bundle = Bundle(Path(cls.tmp.name) / digest)

    def setUp(self):
        self.db = fixtures.Database(self.bundle)
        self.app = fixtures.App(self.db)
        self.svc = LocalWorkerService(self.app, self.bundle, 'unused')
        self.profile = self.db.profile(self.app._database_account_id('100'))
        self.n = 0

    @property
    def archive(self):
        return self.profile['save']['archive']

    @property
    def stats(self):
        return self.profile['save']['gameplay_stats']

    def operation(self, kind, **fields):
        self.n += 1
        return {'account_id': '100', 'config_hash': self.bundle.hash,
                'command': {'id': 'titles_' + str(self.n) + ':request', 'kind': kind, **fields}}

    def command(self, title):
        return self.operation('title_equip', title_id=title)

    def reconcile(self):
        result = self.svc.command(self.operation('endless_reconcile'))
        self.assertTrue(result['ok'], result)
        return result

    def endless(self, wave):
        result = self.svc.command(self.operation('endless', wave=wave, difficulty=1))
        self.assertTrue(result['ok'], result)
        return result

    def test_csv_order_levels_and_required_waves(self):
        rows = self.bundle.configs['archive_titles']['rows']
        self.assertEqual([row['title_id'] for row in rows], list(TITLE_IDS))
        self.assertEqual([row['title_level'] for row in rows], list(range(1, 10)))
        self.assertEqual([row['required_wave'] for row in rows], list(range(1, 642, 80)))

    def test_every_title_requires_its_saved_wave_boundary(self):
        for level, title in enumerate(TITLE_IDS):
            required = level * 80 + 1
            with self.subTest(title=title, required_wave=required):
                # Seed trusted saved progress, not fields in the client request.
                self.archive['endless_best_wave'] = required - 1
                before = copy.deepcopy(self.profile['save'])
                denied = self.svc.command(self.command(title))
                self.assertFalse(denied['ok'])
                self.assertTrue(denied['terminal'])
                self.assertEqual(self.profile['save'], before)
                self.archive['endless_best_wave'] = required
                original_stats = copy.deepcopy(self.stats)
                self.assertTrue(self.svc.command(self.command(title))['ok'])
                self.assertEqual(self.archive['equipped_title'], title)
                self.assertIs(self.archive['title_selection_manual'], True)
                self.assertEqual(self.stats, original_stats)

    def test_automatic_title_covers_each_full_band_and_caps_at_nine(self):
        samples = [(0, '')]
        for level, title in enumerate(TITLE_IDS):
            samples.append((level * 80 + 1, title))
            samples.append(((level + 1) * 80, title))
        samples.extend([(1000, 'chushen'), (1000000, 'chushen')])
        for wave, title in samples:
            with self.subTest(saved_wave=wave):
                self.profile['save']['archive'] = {'endless_best_wave': wave}
                self.reconcile()
                self.assertEqual(self.archive.get('equipped_title', ''), title)
                self.assertIsNot(self.archive.get('title_selection_manual'), True)

    def test_legacy_equipped_title_migrates_to_highest_and_survives_reload(self):
        for equipped in (None, '', 'peak_perfection', 'chushen', 'missing'):
            for marker in (None, False, 1, 'true'):
                with self.subTest(equipped=equipped, old_manual_marker=marker):
                    self.profile['save']['archive'] = {'endless_best_wave': 321}
                    if equipped is not None:
                        self.archive['equipped_title'] = equipped
                    if marker is not None:
                        self.archive['title_selection_manual'] = marker
                    self.reconcile()
                    self.assertEqual(self.archive['equipped_title'], 'tianxia_diyi')
                    fresh = LocalWorkerService(self.app, self.bundle, 'unused')
                    reloaded = fresh.profile({'account_id': '100'})['save']['archive']
                    self.assertEqual(reloaded['equipped_title'], 'tianxia_diyi')

    def test_legacy_ownership_and_unearned_equipped_title_do_not_unlock(self):
        for wave, wanted in ((0, ''), (80, 'peak_perfection')):
            with self.subTest(saved_wave=wave):
                self.profile['save']['archive'] = {
                    'endless_best_wave': wave, 'endless_score': 999999,
                    'titles_owned': {title: True for title in TITLE_IDS},
                    'equipped_title': 'chushen', 'title_selection_manual': True,
                }
                before = copy.deepcopy(self.profile['save'])
                for title in (TITLE_IDS if wave == 0 else TITLE_IDS[1:]):
                    denied = self.svc.command(self.command(title))
                    self.assertFalse(denied['ok'], title)
                    self.assertTrue(denied['terminal'])
                    self.assertEqual(self.profile['save'], before)
                self.reconcile()
                self.assertEqual(self.archive.get('equipped_title', ''), wanted)

    def test_invalid_title_and_injected_ownership_or_progress_are_rejected(self):
        before = copy.deepcopy(self.profile['save'])
        for value in ('missing', {}, [], None, 1, True, '../chushen'):
            with self.subTest(invalid_title=value), self.assertRaises(ArchiveError):
                self.svc.command(self.command(value))
        injected = {
            'titles_owned': {'chushen': True}, 'equipped_title': 'chushen',
            'title_selection_manual': True, 'endless_best_wave': 1000,
            'wave': 1000, 'required_wave': 0, 'title_level': 9,
            'unlocked_by_default': True, 'player_id': 0, 'effects': {'initial_wood': 9999},
        }
        for key, value in injected.items():
            for kind in ('title_equip', 'endless_reconcile'):
                command = self.command('chushen') if kind == 'title_equip' else self.operation(kind)
                command['command'][key] = value
                with self.subTest(kind=kind, injected=key), self.assertRaises(ArchiveError):
                    self.svc.command(command)
        self.assertEqual(self.profile['save'], before)
        self.assertEqual(self.db.ops, {}, 'Rejected metadata never reaches receipt preparation')

    def test_manual_lower_title_and_empty_selection_restore_auto_without_stats(self):
        self.archive['endless_best_wave'] = 241
        self.archive['clear_counts'] = {'n1': 10}
        self.stats['starjoy_points'] = 200
        original_stats = copy.deepcopy(self.stats)
        command = self.command('peak_perfection')
        self.assertTrue(self.svc.command(command)['ok'])
        self.assertEqual(self.archive['equipped_title'], 'peak_perfection')
        self.assertIs(self.archive['title_selection_manual'], True)
        self.assertEqual(self.stats, original_stats, 'Cosmetics cannot claim pending gameplay rewards')
        saved = copy.deepcopy(self.profile['save'])
        self.assertTrue(self.svc.command(command)['ok'])
        self.assertEqual(self.profile['save'], saved)
        fresh = LocalWorkerService(self.app, self.bundle, 'unused')
        self.assertEqual(fresh.profile({'account_id': '100'})['save'], saved)
        self.assertTrue(fresh.command(self.command(''))['ok'])
        self.assertEqual(self.archive['equipped_title'], 'jian_tianya')
        self.assertIsNot(self.archive.get('title_selection_manual'), True)
        self.assertEqual(self.stats, original_stats)
        self.assertFalse(self.archive.get('completed'), 'Equipping does not reconcile unrelated rewards')

    def test_endless_settlement_advances_auto_title_without_downgrading_best(self):
        for wave, best, title in ((1, 1, 'peak_perfection'), (80, 80, 'peak_perfection'),
                                  (81, 81, 'jinghong'), (80, 81, 'jinghong'),
                                  (161, 161, 'youlong'), (641, 641, 'chushen'),
                                  (1000, 1000, 'chushen'), (1, 1000, 'chushen')):
            with self.subTest(settled_wave=wave, saved_best=best):
                self.endless(wave)
                self.assertEqual(self.archive['endless_best_wave'], best)
                self.assertEqual(self.archive['equipped_title'], title)
                self.assertIsNot(self.archive.get('title_selection_manual'), True)

    def test_explicit_lower_title_survives_progress_until_auto_is_restored(self):
        self.archive['endless_best_wave'] = 81
        self.assertTrue(self.svc.command(self.command('peak_perfection'))['ok'])
        self.endless(161)
        self.assertEqual(self.archive['equipped_title'], 'peak_perfection')
        self.assertIs(self.archive['title_selection_manual'], True)
        self.reconcile()
        self.assertEqual(self.archive['equipped_title'], 'peak_perfection')
        self.assertTrue(self.svc.command(self.command(''))['ok'])
        self.assertEqual(self.archive['equipped_title'], 'youlong')
        self.assertIsNot(self.archive.get('title_selection_manual'), True)
        self.endless(241)
        self.assertEqual(self.archive['equipped_title'], 'jian_tianya')

    def test_lost_title_reply_retries_same_receipt_without_stats_or_extra_commit(self):
        self.archive['endless_best_wave'] = 241
        original_stats = copy.deepcopy(self.stats)
        command = self.command('peak_perfection')
        self.db.lose_reply = True
        with self.assertRaises(TimeoutError):
            self.svc.command(command)
        saved = copy.deepcopy(self.profile)
        self.db.lose_reply = False
        self.assertTrue(self.svc.command(command)['ok'])
        self.assertEqual(self.profile, saved)
        self.assertEqual(self.stats, original_stats)
        self.assertEqual(len(self.db.ops), 1)
        self.assertEqual(self.archive['equipped_title'], 'peak_perfection')
        self.assertIs(self.archive['title_selection_manual'], True)
        changed = copy.deepcopy(command)
        changed['command']['title_id'] = 'jinghong'
        self.assertEqual(self.svc.command(changed)['error'], 'archive_id_conflict')
        self.assertEqual(self.profile, saved)

    def test_lost_endless_reply_retries_without_duplicate_progress_rewards_or_title(self):
        self.endless(81)
        command = self.operation('endless', wave=161, difficulty=1)
        self.db.lose_reply = True
        with self.assertRaises(TimeoutError):
            self.svc.command(command)
        saved = copy.deepcopy(self.profile)
        self.assertEqual(self.archive['endless_best_wave'], 161)
        self.assertEqual(self.archive['equipped_title'], 'youlong')
        self.db.lose_reply = False
        self.assertTrue(self.svc.command(command)['ok'])
        self.assertEqual(self.profile, saved)
        fresh = LocalWorkerService(self.app, self.bundle, 'unused')
        self.assertEqual(fresh.profile({'account_id': '100'})['save'], saved['save'])


if __name__ == '__main__':
    LuaRuntime(unpack_returned_tuples=True).execute(
        (ROOT / 'scripts/vscripts/tests/test_titles.lua').read_text(encoding='utf-8'))
    LuaRuntime(unpack_returned_tuples=True).execute(
        (ROOT / 'scripts/vscripts/tests/test_title_equip_eligibility.lua').read_text(encoding='utf-8'))
    unittest.main(verbosity=2)
