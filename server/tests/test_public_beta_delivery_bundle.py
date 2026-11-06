"""Actual old production bundle -> narrow beta bundle, isolated real-Lua tests.

No application credentials, live HTTP, cloud database or real player rows.
"""
from __future__ import annotations

import copy
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import types
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'server/tests'))
import test_public_beta_gift as beta_tests
from archive_backend.bundle import Bundle
from archive_backend.config_compatibility import accepts, upgrades
from archive_backend.service import ArchiveError, ArchiveService

spec = importlib.util.spec_from_file_location(
    'public_beta_delivery_builder', ROOT / 'tools/public_beta_bundle_20261106/build.py')
builder = importlib.util.module_from_spec(spec)
spec.loader.exec_module(builder)
patch_spec = importlib.util.spec_from_file_location(
    'public_beta_service_patch', ROOT / 'tools/public_beta_bundle_20261106/service_patch.py')
service_patch = importlib.util.module_from_spec(patch_spec)
patch_spec.loader.exec_module(service_patch)
PARENT = 'd573588b64d2ea6d1431c856d52e0515b5ed471cfdf6af4456ff618d0f568488'
SOURCE = 'b4c2d904b6e520c2e1c62656cd2c05772b38e3f6'


class PublicBetaDeliveryTests(beta_tests.PublicBetaGiftTests):
    @classmethod
    def setUpClass(cls):
        cls.lua = os.environ.get('LUA_EXECUTABLE') or shutil.which('lua5.1') or shutil.which('lua')
        if not cls.lua:
            raise RuntimeError('Set LUA_EXECUTABLE to run actual bundle settlement')
        cls.temporary = tempfile.TemporaryDirectory(prefix='public-beta-narrow-bundle-')
        cls.addClassCleanup(cls.temporary.cleanup)
        cls.destination = Path(cls.temporary.name)
        cls.parent_source = ROOT / 'server/bundles' / PARENT
        cls.parent_raw = (cls.parent_source / 'bundle.json').read_bytes()
        cls.parent_document = json.loads(cls.parent_raw)
        # Put both immutable revisions beside each other, exactly like server
        # recovery, so legacy receipt tests actually execute the old reducer.
        cls.parent = Bundle(builder.write_candidate(cls.parent_document, cls.destination))
        cls.document = builder.prepare(cls.parent_source, SOURCE)
        cls.bundle = Bundle(builder.write_candidate(cls.document, cls.destination))
        # Reconstruct the exact live service without an ignored-output fixture:
        # strip only the reviewed public-beta additions from the immutable
        # source and retain the live onboarding route. Its full SHA must match
        # the independent read-only remote audit before deriving a patch.
        service_raw = builder.git_blob(SOURCE, builder.SERVICE)
        text = service_raw.decode('utf8')
        old_validation = '            if not tier or tier.get("enabled") is not True or tier.get("track") != c.get("track"):\n'
        first = text.index('            # The public-beta switch stops new settlement in Lua, while a\n')
        last = text.index('                raise ArchiveError("archive_benefit_invalid")\n', first)
        text = text[:first] + old_validation + text[last:]
        text = text.replace('        from .public_beta_gift import scope as scope_public_beta_gift\n        command=scope_public_beta_gift(self,payload,command)\n', '', 1)
        text = text.replace('            from .public_beta_gift import validate_pending as validate_public_beta_gift\n            validate_public_beta_gift(self,account,command)\n            from .public_beta_gift import current_activity_error\n            public_beta_error=current_activity_error(self,command)\n', '', 1)
        text = text.replace('            if public_beta_error:\n                result={\'ok\':False,\'error\':public_beta_error}\n            elif legacy_error:\n', '            if legacy_error:\n', 1)
        onboarding = ('        # Account tutorial metadata has its own protocol and SQL persistence.\n'
                      '        # It neither settles rewards nor depends on a reward configuration hash.\n'
                      '        from .onboarding import KINDS as onboarding_kinds, command as onboarding_command\n'
                      '        if isinstance(kind, str) and kind in onboarding_kinds:\n'
                      '            try:\n'
                      '                return onboarding_command(self.app, payload)\n'
                      '            except ValueError as error:\n'
                      '                raise ArchiveError(str(error)) from error\n')
        anchor = '        if not accepts(self.bundle, requested_hash, kind):'
        cls.parent_service = text.replace(anchor, onboarding + anchor, 1).encode('utf8')
        cls.patched_service, cls.patch_binding = service_patch.derive(cls.parent_service, service_raw)
        namespace = {'__name__': 'archive_backend.derived_public_beta_test', '__package__': 'archive_backend'}
        exec(compile(cls.patched_service, '<derived-public-beta-test>', 'exec'), namespace)
        # Existing helper imports and the derived class share one error type.
        namespace['ArchiveError'] = ArchiveError
        cls.derived_class = namespace['ArchiveService']

    def setUp(self):
        super().setUp()
        onboarding = types.ModuleType('archive_backend.onboarding')
        onboarding.KINDS = frozenset({'onboarding_state', 'onboarding_finish'})
        def unexpected_onboarding(*args):
            raise AssertionError('Public-beta test must not enter the unrelated onboarding route')
        onboarding.command = unexpected_onboarding
        self.onboarding_patch = patch.dict(sys.modules, {'archive_backend.onboarding': onboarding})
        self.onboarding_patch.start()
        self.addCleanup(self.onboarding_patch.stop)
        self.service = self.derived_class(self.app, self.bundle, self.lua)

    def test_actual_old_production_rejects_new_tier_before_database(self):
        old = ArchiveService(self.app, self.parent, self.lua)
        request = self.request()
        request['config_hash'] = PARENT
        with self.assertRaisesRegex(ArchiveError, '^archive_benefit_invalid$'):
            old.command(request)
        self.assertFalse(self.db.ops)
        self.assertEqual(self.inventory(), {})
        error = json.dumps({'ok': False, 'error': 'archive_benefit_invalid'}, separators=(',', ':'))
        self.assertEqual(len(error.encode()), 46, 'Matches native HTTP400 body size; not proof of remote body')

    def test_only_approved_tier_and_activity_module_change(self):
        before, after = self.parent_document, self.document
        configs = [key for key in before['configs'] if before['configs'][key] != after['configs'][key]]
        sources = [key for key in before['sources'] if before['sources'][key] != after['sources'][key]]
        self.assertEqual(configs, ['archive_benefit_rewards'])
        self.assertEqual(sources, ['systems/archive_benefit_rewards.lua'])
        self.assertEqual(after['configs']['archive_benefit_rewards']['rows'][:-1],
                         before['configs']['archive_benefit_rewards']['rows'])
        self.assertEqual(after['configs']['archive_benefit_rewards']['rows'][-1], builder.RULE)
        self.assertEqual(self.parent_raw, (self.parent_source / 'bundle.json').read_bytes())

    def test_old_benefit_hash_does_not_upgrade_or_grant_new_tier(self):
        self.assertTrue(accepts(self.bundle, PARENT, 'benefit_claim'))
        self.assertFalse(upgrades(self.bundle, PARENT, 'benefit_claim'))
        request = self.request()
        request['config_hash'] = PARENT
        result = self.service.command(request)
        self.assertFalse(result['ok'])
        self.assertEqual(self.inventory(), {}, 'Old reducer must not silently acquire a new reward')
        self.assertTrue(self.service.command(self.request())['ok'])
        self.assertEqual(self.inventory(), {'special_lottery_ticket': 2})

    def test_old_regular_benefit_receipt_remains_recoverable(self):
        tier = 'daily_time_30'
        day = str((self.db.timestamp + 10800) // 86400)
        self.profile['save']['archive']['benefits'] = {'days': {day: {'seconds': 3600, 'claimed': {}}}}
        request = self.request()
        request['config_hash'] = PARENT
        request['command'].update(track='daily_time', tier_id=tier)
        result = self.service.command(request)
        self.assertTrue(result['ok'])
        self.assertEqual(self.inventory(), {'lottery_ticket': 1})
        # The same legacy eligibility/reducer applies; no forced public-beta
        # upgrade or inventory shortcut is allowed, successful or denied.
        snapshot = copy.deepcopy(self.profile)
        replay = self.service.command(request)
        self.assertEqual(result['ok'], replay['ok'])
        self.assertEqual(self.profile, snapshot)

    def test_exact_service_patch_preserves_live_onboarding_and_rejects_drift(self):
        self.assertEqual(hashlib.sha256(self.parent_service).hexdigest(), service_patch.PARENT_SERVICE_SHA)
        self.assertTrue(self.patch_binding['outside_methods_unchanged'])
        self.assertTrue(self.patch_binding['retained_onboarding'])
        self.assertIn(b'from .onboarding import KINDS as onboarding_kinds', self.patched_service)
        with self.assertRaisesRegex(ValueError, 'actual_parent_service_changed'):
            service_patch.derive(self.parent_service + b'\n', builder.git_blob(SOURCE, builder.SERVICE))
        bad = builder.git_blob(SOURCE, builder.SERVICE).replace(b'def _command(self,payload):', b'def _command(self,payload):\n        print("unrelated")', 1)
        with self.assertRaisesRegex(ValueError, 'public_beta_method_outside_patch_changed'):
            service_patch.derive(self.parent_service, bad)

    def test_joint_candidate_probe_actual_lua_without_live_services(self):
        with tempfile.TemporaryDirectory(prefix='joint-ws4-probe-') as directory:
            root = Path(directory)
            old, new = root / 'parent', root / 'candidate'
            for destination in (old, new):
                backend = destination / 'backend/archive_backend'
                shutil.copytree(ROOT / 'server/archive_backend', backend,
                                ignore=shutil.ignore_patterns('__pycache__', '*.pyc'))
                # Local repository retired onboarding; production retains it.
                # For this isolated probe only, make unrelated invocation fail
                # rather than importing any real external application service.
                (backend / 'onboarding.py').write_text(
                    'KINDS=frozenset({"onboarding_state","onboarding_finish"})\n'
                    'def command(*args):raise AssertionError("unexpected_onboarding")\n', encoding='utf8')
                builder.write_candidate(self.parent_document, destination / 'addon/server/bundles')
            (old / 'backend/archive_backend/service.py').write_bytes(self.parent_service)
            (old / 'backend/archive_backend/match_modes.py').write_bytes(builder.git_blob(SOURCE, 'server/archive_backend/match_modes.py'))
            (new / 'backend/archive_backend/service.py').write_bytes(self.patched_service)
            builder.write_candidate(self.document, new / 'addon/server/bundles')
            script = ('import importlib.util,json,pathlib,sys; '
                      'spec=importlib.util.spec_from_file_location("joint_probe",sys.argv[1]); '
                      'module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module); '
                      'result=module.run(sys.argv[2],sys.argv[3],sys.argv[4],sys.argv[5],'
                      'pathlib.Path(sys.argv[6]).read_text(encoding="utf8"),'
                      'pathlib.Path(sys.argv[7]).read_text(encoding="utf8"),sys.argv[8]); '
                      'print(json.dumps(result))')
            completed = subprocess.run([sys.executable, '-B', '-c', script,
                str(ROOT / 'tools/public_beta_wire_release_20261106/probe.py'), str(old), str(new),
                PARENT, self.bundle.hash, str(ROOT / 'scripts/vscripts/systems/http_profile_wire.lua'),
                str(ROOT / 'tools/test_http_profile_wire.lua'), self.lua],
                stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=40)
            self.assertEqual(completed.returncode, 0, completed.stderr.decode('utf8', errors='replace'))
            result = json.loads(completed.stdout.decode('utf8').splitlines()[-1])
            self.assertTrue(result['ok'])
            self.assertEqual(result['checks']['wire']['real_lua_vectors'], 4)
            self.assertEqual(len(result['checks']['lottery']), 3)
            self.assertEqual(result['database_writes'], 0)

    def test_refuses_unrelated_old_rule_source_and_reward_changes(self):
        csv_config = copy.deepcopy(self.document['configs']['archive_benefit_rewards'])
        args = [self.parent_document, PARENT, SOURCE, csv_config,
                self.document['csv_hashes'][builder.CSV], self.document['sources'][builder.SOURCE_NAME],
                self.document['public_beta_delivery']['source_sha256'][builder.LUA],
                self.document['compatible_config_hashes'][PARENT]['commands'],
                self.document['public_beta_delivery']['source_sha256'][builder.SERVICE]]
        csv_config['rows'][0]['required'] = 999
        with self.assertRaisesRegex(ValueError, 'existing_benefit_rule_changed'):
            builder.derive(*args)
        csv_config['rows'][0] = copy.deepcopy(self.parent_document['configs']['archive_benefit_rewards']['rows'][0])
        csv_config['rows'][-1]['base_counts'] = ['20']
        with self.assertRaisesRegex(ValueError, 'approved_public_beta_rule_required'):
            builder.derive(*args)
        csv_config['rows'][-1] = copy.deepcopy(builder.RULE)
        args[5] += '\n-- unrelated source change\n'
        args[6] = hashlib.sha256(args[5].encode()).hexdigest()
        with self.assertRaisesRegex(ValueError, 'unrelated_benefit_source_change'):
            builder.derive(*args)


if __name__ == '__main__':
    unittest.main()
