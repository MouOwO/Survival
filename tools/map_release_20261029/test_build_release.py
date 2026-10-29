"""Read-only scope tests against the actual immutable signed baseline manifest."""
import copy
import unittest
import build_release as build


class ScopeTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.before = build.load(build.BASE / build.pack.handoff.MANIFEST)
        cls.policy = build.load(build.ROOT / 'tools/lua_protection_policy.json')

    def test_map_and_placement_keep_protected_gate_and_backend_rows(self):
        before = copy.deepcopy(self.before)
        name = 'scripts/vscripts/config/mode_spawn_config.lua'
        after = build.project(before, {build.MAP: b'new map fixture', name: b'return {}'}, self.policy)
        old = {r['path']: r for r in before['files']}
        rows = {r['path']: r for r in after['files']}
        changed = {n for n in old if old[n] != rows[n]}
        self.assertEqual(changed, {build.MAP, name})
        self.assertEqual(after['file_count'], before['file_count'])
        self.assertEqual(before, self.before)
        self.assertNotEqual(after['content_sha256'], before['content_sha256'])
        protected = build.protection.selected_files(list(rows), self.policy)
        self.assertEqual(len(protected), 184)
        self.assertTrue(all(old[r['path']] == rows[r['path']] for r in protected))

    def test_unrelated_ui_backend_gate_and_new_paths_are_refused(self):
        for name in ('panorama/scripts/custom_game/combat_stats.vjs_c',
                     'scripts/vscripts/config/generated/archive_http_bundle.lua',
                     'scripts/vscripts/core/event_bus.lua',
                     'scripts/vscripts/systems/unreviewed_new_module.lua'):
            with self.subTest(name=name), self.assertRaises(ValueError):
                build.project(self.before, {build.MAP: b'new map fixture', name: b'changed'}, self.policy)

    def test_missing_map_is_refused(self):
        with self.assertRaises(ValueError):
            build.project(self.before, {'scripts/vscripts/config/mode_spawn_config.lua': b'changed'}, self.policy)

    def test_plan_pins_identity_and_capacity_bounds_but_not_free_space_sample(self):
        old = dict(content_sha256='pinned', disk_preflight=[dict(root='D:', required_bytes=100, free_bytes=900)])
        current = copy.deepcopy(old)
        current['disk_preflight'][0]['free_bytes'] = 899
        self.assertTrue(build.same_plan(old, current))
        current['disk_preflight'][0]['required_bytes'] = 101
        self.assertFalse(build.same_plan(old, current))
        current = copy.deepcopy(old)
        current['content_sha256'] = 'changed'
        self.assertFalse(build.same_plan(old, current))


if __name__ == '__main__':
    unittest.main()
