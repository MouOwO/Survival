"""Pure queue/streaming contracts. Temporary local Git only; no SDK/network."""
from collections import Counter
from pathlib import Path
import copy
import contextlib
import hashlib
import importlib.util
import io
import json
import subprocess
import tempfile
import unittest
from unittest import mock

SPEC = importlib.util.spec_from_file_location('pending_inventory_under_test', Path(__file__).with_name('release_pending_inventory.py'))
m = importlib.util.module_from_spec(SPEC); SPEC.loader.exec_module(m)


def entry(oid='1' * 40, size=3):
    return dict(mode='100644', kind='blob', oid=oid, bytes=size)


def fact(digest, size=3):
    return dict(hash_state='VERIFIED', sha256=digest, git_sha256=digest, bytes=size)


def classify(path, *, role='game', old=None, current=None, old_sha='a' * 64,
             digest='b' * 64, deferred=False, bindings=(), extra_facts=None, dirty=(), production=()):
    old = entry() if old is None else old
    current = entry('2' * 40) if current is None else current
    resource, _ = m._resource(role, path, {path: {}})
    inputs = {'game': {}, 'content': {}}
    inputs[role][path] = old
    heads = {'game': {}, 'content': {}}
    if current:
        heads[role][path] = current
    facts = {role + ':' + path: fact(digest), **(extra_facts or {})}
    historical = {role + ':' + path: dict(repo=role, path=path, status='DEFERRED_UNRELEASED_OUTSIDE_THIS_TASK')} if deferred else {}
    return m.classify_inventory(baseline_inventory=inputs, head_inventory=heads,
                               parent_manifest={'files': [dict(path=resource or path, sha256=old_sha)]},
                               deferred_sources=historical, blob_facts=facts, bindings=bindings,
                               dirty=dirty, production_resources=production)


class QueueTests(unittest.TestCase):
    def test_unchanged_oid_but_unpublished_history_is_pending(self):
        result = classify('scripts/vscripts/systems/test_feature.lua', current=entry(), deferred=True)
        self.assertEqual(result['rows'][0]['status'], 'PENDING_RUNTIME_UPDATE')
        self.assertEqual(result['counts']['historical_sources'], 1)
        self.assertFalse(result['ready_for_publication'])

    def test_all_old_and0201_deferrals_union_even_unchanged(self):
        same = entry()
        old = {'game': {'scripts/a.lua': same}, 'content': {'panorama/scripts/a.js': same}}
        result = m.pending_source_keys(old, old,
            {'x': dict(repo='game', path='scripts/a.lua')},
            {'y': dict(repo='content', path='panorama/scripts/a.js')})
        self.assertEqual(result, {('game', 'scripts/a.lua'), ('content', 'panorama/scripts/a.js')})

    def test_parent_byte_equality_does_not_silently_clear_historical_review(self):
        result = classify('scripts/a.lua', current=entry(), deferred=True, digest='a' * 64)
        self.assertEqual(result['rows'][0]['status'], 'HISTORICAL_REVIEW_REQUIRED_PARENT_BYTES_MATCH')
        self.assertTrue(result['rows'][0]['blocking'])

    def test_author_change_without_binding_blocks_even_if_artifact_old(self):
        result = classify('panorama/src/scripts/a.js')
        self.assertEqual(result['rows'][0]['resource'], 'panorama/scripts/a.vjs_c')
        self.assertEqual(result['rows'][0]['status'], 'UNCOMPILED_BINDING_REQUIRED')
        self.assertFalse(result['ready_for_full_build'])

    def test_content_author_is_mapped_to_compiled_candidate_but_not_auto_accepted(self):
        result = classify('panorama/styles/custom_game/a.css', role='content')
        self.assertEqual(result['rows'][0]['resource'], 'panorama/styles/custom_game/a.vcss_c')
        self.assertEqual(result['rows'][0]['status'], 'UNCOMPILED_BINDING_REQUIRED')

    def test_deleted_runtime_remains_explicit_pending_removal(self):
        result = classify('scripts/a.lua', current={})
        self.assertEqual(result['rows'][0]['status'], 'RUNTIME_REMOVAL_PENDING')
        self.assertIsNone(result['rows'][0]['source']['head_oid'])
        self.assertTrue(result['rows'][0]['blocking'])

    def test_dirty_is_separate_from_immutable_inventory(self):
        result = classify('scripts/a.lua', current=entry(), dirty=[dict(repo='game', path='scripts/a.lua', change=' M')])
        self.assertEqual(result['rows'], [])
        self.assertEqual(result['counts']['dirty_runtime'], 1)
        self.assertEqual(result['dirty'][0]['status'], 'DIRTY_LOCAL_RUNTIME')
        self.assertFalse(result['ready_for_full_build'])
        self.assertFalse(result['dirty'][0]['copied_or_hashed'])

    def test_unknown_source_mapping_is_not_ignored(self):
        path = 'data/csv/feature/input.csv'
        result = m.classify_inventory(baseline_inventory={'game': {path: entry()}},
            head_inventory={'game': {path: entry('2' * 40)}}, parent_manifest={'files': []},
            blob_facts={'game:' + path: fact('b' * 64)})
        self.assertEqual(result['counts']['rows'], 1)
        self.assertEqual(result['rows'][0]['status'], 'UNMAPPED_SOURCE_PENDING')
        self.assertTrue(result['rows'][0]['blocking'])

    def test_production_override_is_not_raw_head_overlay(self):
        result = classify('addoninfo.txt')
        self.assertEqual(result['rows'][0]['status'], 'PRODUCTION_TRANSFORM_REQUIRED')
        result = classify('scripts/vscripts/core/release_policy.lua', production=['scripts/vscripts/core/release_policy.lua'])
        self.assertEqual(result['rows'][0]['status'], 'PRODUCTION_TRANSFORM_REQUIRED')

    def test_compiled_artifact_cannot_bypass_missing_source_binding(self):
        result = classify('panorama/scripts/a.vjs_c')
        self.assertEqual(result['rows'][0]['status'], 'UNBOUND_COMPILED_ARTIFACT')

    def test_valid_source_and_artifact_binding_selects_pending_runtime(self):
        source = 'panorama/src/scripts/a.js'; artifact = 'panorama/scripts/a.vjs_c'
        binding = dict(resource=artifact, output=dict(repo='game', path=artifact),
                       inputs=[dict(repo='game', path=source, sha256='b' * 64)], artifact_sha256='c' * 64)
        result = classify(source, bindings=[binding], extra_facts={'game:' + artifact: fact('c' * 64)})
        self.assertEqual(result['rows'][0]['status'], 'PENDING_RUNTIME_UPDATE')
        self.assertEqual(result['rows'][0]['candidate']['sha256'], 'c' * 64)
        self.assertFalse(result['ready_for_publication'])

    def test_stale_binding_does_not_prove_current_author_was_compiled(self):
        source = 'panorama/src/scripts/a.js'; artifact = 'panorama/scripts/a.vjs_c'
        binding = dict(resource=artifact, output=dict(repo='game', path=artifact),
                       inputs=[dict(repo='game', path=source, sha256='d' * 64)], artifact_sha256='c' * 64)
        result = classify(source, bindings=[binding], extra_facts={'game:' + artifact: fact('c' * 64)})
        self.assertEqual(result['rows'][0]['status'], 'UNCOMPILED_BINDING_REQUIRED')

    def test_missing_lfs_is_never_parent_hash_equality_from_pointer(self):
        result = classify('panorama/images/a.vtex_c', extra_facts={'game:panorama/images/a.vtex_c': dict(
            hash_state='LFS_OBJECT_MISSING', sha256=None, lfs=True, lfs_declared_sha256='a' * 64)})
        self.assertEqual(result['rows'][0]['status'], 'LFS_OBJECT_MISSING')
        self.assertTrue(result['rows'][0]['blocking'])


class BatchGitTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='pending-inventory-local-git-')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        subprocess.run(['git', 'init', '-q', str(self.root)], check=True, capture_output=True)

    def object(self, raw):
        value = subprocess.run(['git', '-C', str(self.root), 'hash-object', '-w', '--stdin'],
                               input=raw, check=True, capture_output=True).stdout.decode().strip()
        return entry(value, len(raw))

    def facts(self, tree, budget=None):
        counts = Counter()
        values = m.read_git_facts(self.root, tree, set(tree), budget or m.HashBudget(), counts)
        return values, counts

    def pointer(self, content, present=True):
        digest = hashlib.sha256(content).hexdigest()
        raw = ('version https://git-lfs.github.com/spec/v1\noid sha256:' + digest + '\nsize ' + str(len(content)) + '\n').encode()
        if present:
            target = self.root/'.git/lfs/objects'/digest[:2]/digest[2:4]/digest
            target.parent.mkdir(parents=True); target.write_bytes(content)
        return raw, digest

    def test_lfs_resolves_actual_local_object_without_fetching(self):
        content = b'actual binary\x00' * 300
        pointer, digest = self.pointer(content)
        result, counts = self.facts({'panorama/images/a.vtex_c': self.object(pointer)})
        row = result['panorama/images/a.vtex_c']
        self.assertEqual(row['sha256'], digest)
        self.assertNotEqual(row['sha256'], row['git_sha256'])
        self.assertEqual(row['bytes'], len(content))
        self.assertEqual(counts['git_fact_batches'], 1)
        self.assertEqual(counts['lfs_files_read'], 1)
        self.assertEqual(counts['git_processes'], 2)  # common-dir plus one persistent batch

    def test_absent_lfs_object_stays_unresolved_without_network(self):
        pointer, digest = self.pointer(b'missing', present=False)
        result, counts = self.facts({'a.vtex_c': self.object(pointer)})
        self.assertEqual(result['a.vtex_c']['hash_state'], 'LFS_OBJECT_MISSING')
        self.assertIsNone(result['a.vtex_c']['sha256'])
        self.assertEqual(counts['lfs_files_read'], 0)

    def test_lfs_real_content_budget_is_enforced_separately_from_small_pointer(self):
        pointer, digest = self.pointer(b'x' * 4096)
        result, counts = self.facts({'a.vtex_c': self.object(pointer)}, m.HashBudget(total=2048, per_blob=1024))
        self.assertEqual(result['a.vtex_c']['hash_state'], 'HASH_BUDGET_EXCEEDED')
        self.assertEqual(counts['lfs_files_read'], 0)

    def test_large_normal_git_blob_is_not_read_over_budget(self):
        result, counts = self.facts({'a.webm': self.object(b'x' * 4096)}, m.HashBudget(total=1024, per_blob=512))
        self.assertEqual(result['a.webm']['hash_state'], 'HASH_BUDGET_EXCEEDED')
        self.assertEqual(counts['git_blob_requests'], 0)

    def test_same_oid_paths_use_one_git_blob_request(self):
        value = self.object(b'a shared immutable blob')
        result, counts = self.facts({'a.lua': value, 'b.lua': value})
        self.assertEqual(result['a.lua']['sha256'], result['b.lua']['sha256'])
        self.assertEqual(counts['git_blob_requests'], 1)


class RegisteredBaselineTests(unittest.TestCase):
    def fixture(self):
        spec = importlib.util.spec_from_file_location('pending_rollforward_fixture', Path(__file__).with_name('test_release_baseline_rollforward.py'))
        helper = importlib.util.module_from_spec(spec); spec.loader.exec_module(helper)
        f = helper.Fixture()
        # Bind the actual serialized controls rather than accepting a READY flag.
        raw = lambda value: (json.dumps(value, sort_keys=True, separators=(',', ':')) + '\n').encode()
        f.evidence['manifest_sha256'] = m.sha(raw(f.manifest))
        f.evidence['package_report_sha256'] = m.sha(raw(f.report))
        f.evidence['journal_sha256'] = m.sha(raw(f.journal))
        f.receipt['package_report_sha256'] = f.evidence['package_report_sha256']
        f.receipt['canonical_journal_sha256'] = f.evidence['journal_sha256']
        f.seal()
        baseline = f.advance()
        names = {name: 'output/release_baselines/synthetic_' + name + '.json' for name in
                 ('baseline', 'manifest', 'package_report', 'verified_delivery', 'previous_baseline')}
        values = {names['baseline']: baseline, names['manifest']: f.manifest, names['package_report']: f.report,
                  names['verified_delivery']: f.evidence, names['previous_baseline']: f.previous}
        hashes = {name: m.sha(raw(value)) for name, value in values.items()}
        entry = dict(sha256=hashes[names['baseline']])
        for key in ('manifest', 'package_report', 'verified_delivery', 'previous_baseline'):
            entry[key + '_path'] = names[key];entry[key + '_sha256'] = hashes[names[key]]
        registry = dict(schema=1, entries={names['baseline']: entry,
            names['previous_baseline']: dict(sha256=hashes[names['previous_baseline']])})
        def read(path, digest):
            self.assertEqual(hashes[path], digest)
            return copy.deepcopy(values[path])
        return f, baseline, names, values, hashes, registry, read

    def test_registered_verified_partial_baseline_keeps_real_pending_history(self):
        f, baseline, names, values, hashes, registry, read = self.fixture()
        with mock.patch.object(m, 'BASELINE_SHA256', hashes[names['previous_baseline']]):
            loaded, manifest, package = m.load_registered_baseline(m.ROOT, names['baseline'], hashes[names['baseline']], registry, read_json=read)
        self.assertEqual(loaded, baseline)
        self.assertEqual(manifest, f.manifest)
        self.assertEqual(package, f.report)
        self.assertIn('game:' + f.history, loaded['deferred_sources'])
        self.assertNotEqual(loaded['source_inventory']['game'][f.history]['oid'], f.trees['game']['entries'][f.history]['oid'])
        self.assertFalse(loaded['full_head_publication_claimed'])

    def test_registry_and_exact_baseline_raw_hash_are_required(self):
        f, baseline, names, values, hashes, registry, read = self.fixture()
        for kind in ('not_registered', 'wrong_hash', 'unknown_schema', 'missing_previous_registration'):
            with self.subTest(kind=kind):
                supplied = copy.deepcopy(registry); digest = hashes[names['baseline']]
                if kind == 'not_registered': del supplied['entries'][names['baseline']]
                elif kind == 'wrong_hash': digest = '0' * 64
                elif kind == 'unknown_schema': supplied['schema'] = 2
                else: del supplied['entries'][names['previous_baseline']]
                with self.assertRaises(RuntimeError):
                    m.load_registered_baseline(m.ROOT, names['baseline'], digest, supplied, read_json=read)

    def test_registration_does_not_accept_mixed_receipts_or_self_claimed_success(self):
        for kind in ('sdk_only', 'wrong_manifest', 'old_download', 'wrong_volume', 'wrong_report', 'changed_journal'):
            with self.subTest(kind=kind):
                f, baseline, names, values, hashes, registry, original = self.fixture()
                def read(path, digest):
                    value = original(path, digest)
                    if path == names['verified_delivery']:
                        if kind == 'sdk_only': value.pop('download_receipt')
                        elif kind == 'wrong_manifest': value['manifest_sha256'] = '0' * 64
                        elif kind == 'old_download': value['download_receipt']['release_sequence'] -= 1
                        elif kind == 'wrong_volume': value['download_receipt']['verification']['package_files'][1]['sha256'] = '0' * 64
                        elif kind == 'wrong_report': value['package_report_sha256'] = '0' * 64
                        else: value['download_receipt']['canonical_journal_unchanged'] = False
                    return value
                with mock.patch.object(m, 'BASELINE_SHA256', hashes[names['previous_baseline']]), self.assertRaises((RuntimeError, ValueError)):
                    m.load_registered_baseline(m.ROOT, names['baseline'], hashes[names['baseline']], registry, read_json=read)

    def test_minimal_ancestor_registration_does_not_replace_ancestor_delivery_proof(self):
        f, baseline, names, values, hashes, registry, read = self.fixture()
        with self.assertRaisesRegex(RuntimeError, 'registered_control_path_or_sha_invalid'):
            m.load_registered_baseline(m.ROOT, names['baseline'], hashes[names['baseline']], registry, read_json=read)

    def test_ancestor_cycles_and_depth_are_bounded_without_accepting_ready_flags(self):
        f, baseline, names, values, hashes, registry, read = self.fixture()
        current = registry['entries'][names['baseline']]
        current['previous_baseline_path'] = names['baseline']
        current['previous_baseline_sha256'] = hashes[names['baseline']]
        with self.assertRaisesRegex(RuntimeError, 'ancestry_cycle'):
            m.load_registered_baseline(m.ROOT, names['baseline'], hashes[names['baseline']], registry, read_json=read)
        with self.assertRaisesRegex(RuntimeError, 'ancestry_limit'):
            m.load_registered_baseline(m.ROOT, names['baseline'], hashes[names['baseline']], registry, read_json=read, _ancestry=tuple(str(n) for n in range(32)))

    def test_sparse_registration_cannot_absorb_unpublished_head_or_drop_deferrals(self):
        for kind in ('head_inventory', 'extra_path', 'drop_history', 'rewrite_anchors', 'remove_source_without_binding'):
            with self.subTest(kind=kind):
                f, baseline, *_ = self.fixture(); value = copy.deepcopy(baseline)
                if kind == 'head_inventory': value['source_inventory']['game'][f.history] = f.trees['game']['entries'][f.history]
                elif kind == 'extra_path': value['source_inventory']['game']['scripts/unshipped.lua'] = entry()
                elif kind == 'drop_history': del value['deferred_sources']['game:' + f.history]
                elif kind == 'rewrite_anchors': value['source_anchors']['game'] = 'f' * 40
                else: del value['source_inventory']['game'][f.history]
                with self.assertRaises(RuntimeError): m._verify_sparse_rollforward(f.previous, value, f.report)

    def test_registered_paths_and_control_bytes_are_checked_before_use(self):
        for path in ('../outside.json', 'output/../outside.json', 'C:/outside.json', '/output/a.json', 'output\\a.json', 'output/a.txt'):
            self.assertFalse(m._registered_path(path), path)
        with tempfile.TemporaryDirectory(prefix='pending-registered-controls-') as directory:
            root = Path(directory); target = root/'output/control.json';target.parent.mkdir();target.write_bytes(b'{"actual":1}')
            self.assertEqual(m._registered_json(root, 'output/control.json', m.sha(target.read_bytes())), {'actual': 1})
            with self.assertRaisesRegex(RuntimeError, 'fixed_baseline_or_plan_hash_changed'):
                m._registered_json(root, 'output/control.json', '0' * 64)

    def test_cli_registered_triplet_is_all_or_none_without_io(self):
        for argv in (['--baseline', 'output/a.json'], ['--baseline-sha256', 'a' * 64],
                     ['--baseline-registry-sha256', 'b' * 64], ['--baseline', 'output/a.json', '--baseline-sha256', 'a' * 64]):
            with self.subTest(argv=argv), mock.patch.object(m, '_read_json', side_effect=AssertionError('partial CLI must not read controls')):
                with contextlib.redirect_stderr(io.StringIO()), self.assertRaises(SystemExit) as raised: m.main(argv)
                self.assertEqual(raised.exception.code, 2)

    def test_cli_registered_branch_uses_registered_manifest_and_checks_dirty_without_writes(self):
        baseline = dict(source_inventory=dict(game={}, content={}), deferred_sources={}, parent_sequence=101,
                        parent_manifest_sha256='1' * 64, official_parent_manifest='123')
        parent = dict(files=[], content_sha256='2' * 64)
        plan = dict(source_artifact_pins={})
        def read(path, expected=None):
            return {'schema': 1, 'entries': {}} if path == m.BASELINE_REGISTRY else dict(business_modules=[], generated_prefix='scripts/vscripts/config/generated/', generated_exclusions=[])
        def git(root, *args, counts): return (('a' if root == m.ROOT else 'b') * 40 + '\n').encode()
        with (mock.patch.object(m, '_read_json', side_effect=read), mock.patch.object(m, 'load_registered_baseline', return_value=(baseline, parent, plan)) as registered,
             mock.patch.object(m, '_git', side_effect=git), mock.patch.object(m, 'git_tree', return_value={}),
             mock.patch.object(m, 'git_dirty', side_effect=lambda root, role, counts: [dict(repo=role, path='scripts/local.lua', change=' M')] if role == 'game' else []),
             mock.patch.object(m, 'read_git_facts', return_value={})):
            output = io.StringIO()
            with contextlib.redirect_stdout(output): code = m.main(['--baseline', 'output/a.json', '--baseline-sha256', 'a' * 64, '--baseline-registry-sha256', 'b' * 64, '--check'])
        self.assertEqual(code, 2);registered.assert_called_once()
        value = json.loads(output.getvalue())
        self.assertEqual(value['baseline_mode'], 'REGISTERED_SDK_AND_OFFICIAL_DOWNLOAD_VERIFIED_BASELINE')
        self.assertEqual(value['recorded_parent_sequence'], 101)
        self.assertEqual(value['counts']['dirty_runtime'], 1)
        self.assertFalse(value['ready_for_publication'])
        self.assertEqual((value['bytes_written'], value['git_mutations'], value['sdk_calls'], value['network_calls']), (0, 0, 0, 0))


if __name__ == '__main__':
    unittest.main()
