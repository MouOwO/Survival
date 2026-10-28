"""Read-only tests of the reviewed patch, release scope and fail-closed pins."""
from pathlib import Path
import copy
import importlib.util
import json
import sys
import unittest
from unittest.mock import patch

sys.dont_write_bytecode = True
spec = importlib.util.spec_from_file_location('ten_sin_builder', Path(__file__).with_name('build_release.py'))
builder = importlib.util.module_from_spec(spec)
spec.loader.exec_module(builder)


class ReleaseTests(unittest.TestCase):
    def test_frozen_patch(self):
        raw = builder.target_source()
        self.assertEqual(builder.checksums(raw), builder.PINS['target'])
        self.assertIn(b'events.HERO_READY, prepare_after_hero_summoned', raw)
        # Earlier unrelated practice-count changes stay outside this overlay.
        self.assertNotIn(b'local authored_count = balance.supports_mode', raw)
        self.assertEqual(set(builder.TARGET_PINS), {'scripts/vscripts/systems/challenge_session_service.lua'})

    def test_local_drift_rejected(self):
        pins = copy.deepcopy(builder.PINS)
        pins['local_source']['sha256'] = '0' * 64
        with patch.object(builder, 'PINS', pins), self.assertRaisesRegex(ValueError, 'local source drift'):
            builder.target_source()

    def test_patch_drift_rejected(self):
        pins = copy.deepcopy(builder.PINS)
        pins['patch']['sha256'] = '0' * 64
        with patch.object(builder, 'PINS', pins), self.assertRaisesRegex(ValueError, 'patch drift'):
            builder.target_source()

    def test_target_drift_rejected(self):
        pins = copy.deepcopy(builder.PINS)
        pins['target']['sha256'] = '0' * 64
        with patch.object(builder, 'PINS', pins), self.assertRaisesRegex(ValueError, 'output mismatch'):
            builder.target_source()

    def test_only_existing_plaintext_change(self):
        before = json.loads((builder.BASE / builder.pack.handoff.MANIFEST).read_bytes())
        policy = json.loads((builder.ROOT / 'tools/lua_protection_policy.json').read_bytes())
        after = builder.projection(before, policy)
        old = {r['path']: r for r in before['files']}
        new = {r['path']: r for r in after['files']}
        self.assertEqual(old.keys(), new.keys())
        self.assertEqual({p for p in old if old[p] != new[p]}, set(builder.TARGET_PINS))
        protected = {r['path'] for r in builder.parent.protection.selected_files(list(old), policy)}
        self.assertEqual(len(protected), 180)
        self.assertTrue(all(old[p] == new[p] for p in protected))
        invalid = {'scripts/vscripts/core/release_policy.lua': builder.PINS['target']}
        with patch.object(builder, 'TARGET_PINS', invalid), self.assertRaises(ValueError):
            builder.projection(before, policy)


if __name__ == '__main__':
    unittest.main()
