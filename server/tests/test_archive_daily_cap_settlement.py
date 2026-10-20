"""Exercise current packaged Lua through the durable archive prepare/commit API."""
import copy
import hashlib
import hmac
import json
import math
import subprocess
import unittest
from unittest.mock import patch

from server.tests import test_archive_backend as fixtures
from archive_backend.bundle import Bundle
from archive_backend.daily_limits import snapshot


class DailyCapSettlementTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        fixtures.ArchiveTests.setUpClass.__func__(cls)

    def setUp(self):
        fixtures.ArchiveTests.setUp(self)
        self.sessions = {}
        original = self.db.rpc

        def rpc(name, payload):
            if name == 'match_profile_context':
                session = payload['p_session']
                return {'ok': True, 'account_id': payload['p_account'],
                        'match_session_id': session, 'mode': self.sessions[session]}
            return original(name, payload)

        self.db.rpc = rpc

    command = fixtures.ArchiveTests.command
    send = fixtures.ArchiveTests.send

    @property
    def archive(self):
        return self.profile['save']['archive']

    def clear(self, mode='standard', difficulty='n1'):
        payload = self.command('mode_clear', difficulty_id=difficulty, count=1)
        session = 'daily_cap_match_' + str(self.n)
        payload['match_session_id'] = session
        self.sessions[session] = mode
        result = self.service.command(payload)
        self.assertTrue(result['ok'], result)
        return payload

    def prepare(self, command, config_hash=None):
        return self.db.rpc('archive_prepare', {'p_account': self.account, 'p_id': command['id'],
            'p_hash': config_hash or self.bundle.hash,
            'p_fingerprint': hashlib.sha256(json.dumps(command, sort_keys=True).encode()).hexdigest(),
            'p_command': command})

    def online(self, identifier, seconds):
        # Only the trusted SQL outbox can prepare this command. It is deliberately
        # excluded from the HTTP command field allowlist.
        command = {'id': 'online:' + identifier, 'kind': 'online_checkpoint',
                   'session': identifier, 'actual_seconds': seconds, 'map_seconds': seconds}
        result = self.service.finish_prepared(self.account, command['id'], self.prepare(command))
        self.assertTrue(result['ok'], result)

    def test_global_twenty_is_shared_across_modes_and_cold_has_its_own_ten(self):
        for _ in range(10):
            self.clear('cold')
        self.clear('cold')
        self.assertEqual(self.archive['daily']['20000']['clear_total'], 10)
        self.assertEqual(self.archive['daily']['20000']['mode_cold'], 10)
        self.assertEqual(self.archive['cold_clear_counts']['n1'], 10)
        for _ in range(10):
            self.clear('rich')
        self.clear('standard')
        self.clear('pure')
        self.assertEqual(self.archive['daily']['20000']['clear_total'], 20)
        self.assertEqual(self.archive['daily']['20000']['mode_rich'], 10)
        self.assertEqual(self.archive['rich_clear_counts']['n1'], 10)
        self.assertEqual(self.archive.get('clear_counts', {}).get('n1', 0), 0)
        self.assertEqual(self.archive['mode_clear_counts'].get('pure', {}).get('n1', 0), 0)

    def test_double_clear_last_slot_counts_once_and_awards_only_four_hundred_faith(self):
        self.archive.update(daily={'20000': {'clear_total': 19}},
                            standard_clear_counts={'n1': 7}, clear_counts={'n1': 7})
        self.profile['save']['content_inventory'] = {'commerce_p005': 1}
        self.clear()
        self.assertEqual(self.archive['daily']['20000']['clear_total'], 20)
        self.assertEqual(self.archive['clear_counts']['n1'], 8)
        self.assertEqual(self.archive['standard_clear_counts']['n1'], 8)
        self.assertEqual(self.archive['mode_clear_counts']['standard']['n1'], 8)
        self.assertEqual(self.archive['buildings']['faith'], 400)
        self.assertEqual(self.archive['buildings']['earned_by_day']['20000'], 400)
        self.clear()
        self.assertEqual(self.archive['standard_clear_counts']['n1'], 8)
        self.assertEqual(self.archive['buildings']['faith'], 400)

    def test_boss_cap_counts_actual_accepted_kills(self):
        self.archive.update(daily={'20000': {'boss_total': 299}}, boss_kills=1200)
        self.assertTrue(self.send('boss_kill')['ok'])
        self.assertTrue(self.send('boss_kill')['ok'])
        self.assertEqual(self.archive['boss_kills'], 1201)
        self.assertEqual(self.archive['daily']['20000']['boss_total'], 300)

    def test_endless_last_point_is_partial_and_best_wave_still_records(self):
        self.archive.update(daily={'20000': {'endless_total': 49999}}, endless_score=123)
        self.assertTrue(self.send('endless', wave=11, difficulty=10)['ok'])
        self.assertEqual(self.archive['daily']['20000']['endless_total'], 50000)
        self.assertEqual(self.archive['endless_score'], 124)
        self.assertEqual(self.archive['endless_best_wave'], 11)
        self.assertTrue(self.send('endless', wave=12, difficulty=10)['ok'])
        self.assertEqual(self.archive['endless_score'], 124)
        self.assertEqual(self.archive['endless_best_wave'], 12)

    def test_coins_cap_does_not_stop_clock_and_spending_does_not_release_quota(self):
        self.archive.update(daily={'20000': {'coins_total': 7999}},
            online={'actual_seconds': 0, 'map_seconds': 0, 'coins': 7999,
                    'map_level': 0, 'work_levels': {}, 'cursors': {}})
        self.online('cap_clock_1', 180)
        self.assertEqual(self.archive['online']['coins'], 8000)
        self.online('cap_clock_2', 120)
        self.assertEqual(self.archive['online']['coins'], 8000)
        self.assertEqual(self.archive['online']['actual_seconds'], 300)
        self.assertEqual(self.archive['online']['map_seconds'], 300)
        self.assertTrue(self.send('work_upgrade', item_id='work_01', expected_level=0)['ok'])
        self.assertEqual(self.archive['online']['coins'], 7400)
        self.online('cap_clock_3', 60)
        self.assertEqual(self.archive['online']['coins'], 7400)
        self.assertEqual(self.archive['online']['actual_seconds'], 360)
        self.assertEqual(self.archive['daily']['20000']['coins_total'], 8000)

    def old_bundle(self, shared):
        data = json.loads((self.bundle.directory / 'bundle.json').read_bytes())
        data['configs'].pop('archive_daily_limits')
        rule = next(r for r in data['configs']['archive_cooperative_reward_rules']['rows'] if r['rule_id'] == 'default')
        rule['shared_challenge_roll'] = shared
        data['sources']['systems/archive_settlement.lua'] = 'error("legacy_uncapped_reducer_must_not_run")\n'
        raw = json.dumps(data, ensure_ascii=False, sort_keys=True, separators=(',', ':'), allow_nan=False).encode()
        digest = hashlib.sha256(raw).hexdigest()
        directory = self.bundle.directory.parent / digest
        directory.mkdir(exist_ok=True)
        for name, source in data['sources'].items():
            target = directory / name
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(source, encoding='utf-8', newline='\n')
        (directory / 'bundle.json').write_bytes(raw)
        return Bundle(directory)

    def test_old_pending_challenge_observes_current_quota_and_original_seed_policy(self):
        for shared in (False, True):
            with self.subTest(recorded_shared_roll=shared):
                self.archive.clear()
                self.archive['daily'] = {'20000': {'shadow_total': 79}}
                old = self.old_bundle(shared)
                command = {'id': 'oldcap' + str(shared) + ':challenge_kind:shadow_4', 'kind': 'challenge',
                           'challenge_id': 'shadow_4', 'kill_sequence': 4, 'difficulty_id': 'n10'}
                prepared = self.prepare(command, old.hash)
                captured = []
                original_run = subprocess.run

                def capture(*args, **kwargs):
                    captured.append(json.loads(kwargs['input']))
                    return original_run(*args, **kwargs)

                with patch('archive_backend.service.subprocess.run', side_effect=capture):
                    result = self.service.finish_prepared(self.account, command['id'], prepared)
                self.assertTrue(result['ok'], result)
                self.assertEqual(self.archive['daily']['20000']['shadow_total'], 80)
                self.assertEqual(sum(self.archive['shadow_counts'].values()), 1)
                self.assertIn('archive_daily_limits', captured[0]['configs'])
                scope = command['id'].split(':', 1)[0] + ':challenge_kind:shadow_4' if shared else self.account + ':' + command['id']
                expected = int.from_bytes(hmac.new(self.app.account_id_pepper.encode(), scope.encode(),
                    hashlib.sha256).digest()[:4], 'big') % 2147483646 + 1
                self.assertEqual(captured[0]['seed'], expected)
                before = copy.deepcopy(self.profile)
                self.assertTrue(self.service.finish_prepared(self.account, command['id'], self.db.resume(self.account, command['id']))['ok'])
                self.assertEqual(self.profile, before)

    def test_old_pending_non_challenge_rewards_cannot_run_the_uncapped_reducer(self):
        old = self.old_bundle(False)
        cases = [
            ('boss_kill', {}, 'boss_total', 300, 'boss_kills', 7),
            ('endless', {'wave': 11, 'difficulty': 10}, 'endless_total', 50000, 'endless_score', 7),
            ('clear', {'difficulty_id': 'n1', 'count': 1}, 'clear_total', 20, 'clear_counts', {'n1': 7}),
            ('online_checkpoint', {'session': 'old_online', 'actual_seconds': 60, 'map_seconds': 60},
             'coins_total', 8000, 'online', {'actual_seconds': 0, 'map_seconds': 0, 'coins': 7,
                                          'map_level': 0, 'work_levels': {}, 'cursors': {}}),
        ]
        for kind, fields, counter, maximum, saved_key, before in cases:
            with self.subTest(kind=kind):
                self.archive.clear()
                self.archive.update(daily={'20000': {counter: maximum}}, **{saved_key: copy.deepcopy(before)})
                command = dict(id='oldroute:' + kind, kind=kind, **fields)
                result = self.service.finish_prepared(self.account, command['id'], self.prepare(command, old.hash))
                self.assertTrue(result['ok'], result)
                self.assertEqual(self.archive['daily']['20000'][counter], maximum)
                if kind == 'online_checkpoint':
                    self.assertEqual(self.archive['online']['coins'], before['coins'])
                    self.assertEqual(self.archive['online']['actual_seconds'], 60)
                else:
                    self.assertEqual(self.archive[saved_key], before)

    def lua_snapshot(self, profile, now):
        code = '''
local input=require("core/json_decoder").decode(io.read("*a"))
for name,config in pairs(input.configs) do
 local m={rows=config.rows,by_id={}}
 for _,row in ipairs(m.rows) do m.by_id[row[config.key]]=row end
 package.loaded["config/generated/"..name]=m
end
require("systems/archive_calendar").set_clock(function() return input.now end)
io.write(require("core/json_encoder").encode(require("systems/archive_daily_limits").snapshot(input.profile)))
'''
        result = subprocess.run([self.lua, '-e', code], cwd=self.bundle.directory,
            input=json.dumps({'profile': profile, 'configs': self.bundle.configs, 'now': now}, ensure_ascii=False).encode(),
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=True)
        return json.loads(result.stdout)

    def test_python_and_lua_projection_agree_at_midnight_and_pass_expiry(self):
        midnight = 20001 * 86400 - 28800
        profile = copy.deepcopy(self.profile)
        profile['save']['archive'] = {'daily': {'20000': {'cage_total': 70, 'fragment_01': 25, 'coins_total': 8000},
            '20001': {'cage_total': 1}}, 'buildings': {'earned_by_day': {'20000': 2900}}}
        profile['save']['daily_limits'] = {'day_key': '20000', 'by_key': {'fishing': {'earned': 80}}}
        for now, expiry in ((midnight-1, midnight+1), (midnight-1, midnight-2), (midnight, midnight+1), (midnight+2, midnight+1)):
            with self.subTest(now=now, expiry=expiry):
                profile['entitlements'] = {'archive_pass': {'active': True, 'expires_at': expiry}}
                python = snapshot(profile, self.bundle, now=now)
                lua = self.lua_snapshot(profile, now)
                self.assertEqual(python, lua)
                self.assertEqual(python['day_key'], str(math.floor((now+28800)/86400)))
                self.assertEqual(python['by_key']['cage']['limit'], 60)
                self.assertEqual(python['by_key']['fragment_01']['limit'], 20)


if __name__ == '__main__':
    unittest.main()
