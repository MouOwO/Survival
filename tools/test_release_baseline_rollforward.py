"""Synthetic metadata contracts only; no real upload, SDK, Git or file writes."""
import copy
import importlib.util
from pathlib import Path
import unittest

SPEC = importlib.util.spec_from_file_location('baseline_rollforward_under_test', Path(__file__).with_name('release_baseline_rollforward.py'))
m = importlib.util.module_from_spec(SPEC); SPEC.loader.exec_module(m)


def git_entry(tag, digest, size):
    return dict(mode='100644', kind='blob', oid=tag * 40, bytes=size, sha256=digest * 64)


class Fixture:
    def __init__(self):
        self.a = 'scripts/vscripts/systems/a.lua'
        self.b = 'panorama/scripts/custom_game/b.vjs_c'
        self.author = 'panorama/src/scripts/custom_game/b.js'
        self.mirror = 'panorama/scripts/custom_game/b.js'
        self.history = 'scripts/vscripts/systems/still_local.lua'
        self.csv = 'data/csv/unpublished.csv'
        self.sources = dict(game='a' * 40, content='b' * 40)
        old_origins = {self.a: self.frozen('a', 10), self.b: self.frozen('b', 20), self.history: self.frozen('c', 30)}
        inventory = dict(game={self.a: git_entry('1', 'a', 10), self.b: git_entry('2', 'b', 20),
                              self.author: git_entry('3', 'd', 5), self.history: git_entry('4', 'c', 30),
                              self.csv: git_entry('5', 'd', 8)},
                         content={self.mirror: git_entry('6', 'd', 5)})
        for tree in inventory.values():
            for entry in tree.values():
                entry.pop('sha256')
        self.deferred = {
            'game:' + self.a: dict(repo='game', path=self.a, status='DEFERRED_UNRELEASED_OUTSIDE_THIS_TASK', git_sha256='1' * 64),
            'game:' + self.history: dict(repo='game', path=self.history, status='DEFERRED_UNRELEASED_OUTSIDE_THIS_TASK', git_sha256='c' * 64),
            'game:' + self.csv: dict(repo='game', path=self.csv, status='DEFERRED_UNRELEASED_OUTSIDE_THIS_TASK', git_sha256='d' * 64),
        }
        self.previous = dict(schema=1, parent_sequence=100, parent_content_sha256='e' * 64,
                             parent_manifest_sha256='0' * 64, source_inventory=inventory,
                             source_anchors=dict(game='1' * 40, content='2' * 40), source_anchor_is_full_published_tree=False,
                             resource_origins=old_origins, resource_origins_sha256=m.canonical_digest(old_origins),
                             deferred_sources=copy.deepcopy(self.deferred))
        self.trees = dict(game=dict(commit=self.sources['game'], entries={
            self.a: git_entry('7', '1', 10), self.b: git_entry('8', '2', 20), self.author: git_entry('9', '3', 5),
            self.history: git_entry('a', '9', 30), self.csv: git_entry('b', '9', 8)}),
            content=dict(commit=self.sources['content'], entries={self.mirror: git_entry('c', '3', 5)}))
        self.pin = dict(git_blob=dict(sha256='3' * 64, bytes=5), compiler_input=dict(sha256='3' * 64, bytes=5),
                        normalization='IDENTITY', compiled_artifact_sha256='2' * 64,
                        content_mirror=dict(path=self.mirror, source_revision=self.sources['content'], sha256='3' * 64))
        origins = copy.deepcopy(old_origins)
        origins[self.a] = dict(kind='IMMUTABLE_GIT_RUNTIME_BLOB', source_path=self.a,
                               source_revision=self.sources['game'], parent_content_sha256='e' * 64,
                               resource_sha256='1' * 64, resource_bytes=10)
        origins[self.b] = dict(kind='BOUND_OFFICIAL_COMPILER_ARTIFACT', source_path=self.author,
                               source_revision=self.sources['game'], parent_content_sha256='e' * 64,
                               resource_sha256='2' * 64, resource_bytes=20, source_git_sha256='3' * 64,
                               compiler_input_sha256='3' * 64, compilation_binding=copy.deepcopy(self.pin))
        self.manifest = dict(file_count=3, content_sha256='f' * 64,
                             files=[dict(path=self.a, bytes=10, sha256='1' * 64), dict(path=self.b, bytes=20, sha256='2' * 64),
                                    dict(path=self.history, bytes=30, sha256='c' * 64)])
        files = [dict(name='42.vpk' if i == 0 else '42_%03d.vpk' % (i - 1), bytes=100 + i, sha256=str(i + 1) * 64) for i in range(5)]
        self.report = dict(workshop_id='42', release_sequence=101, content_sha256='f' * 64, source_revisions=self.sources,
                           baseline_release_sequence=100, baseline_content_sha256='e' * 64,
                           authenticated_parent_manifest_sha256='0' * 64, signature_valid=True, dry_run=False,
                           payload_changed=False, full_runtime_validator_passed=True, protected_modules_preserved=2,
                           files=3, package_files=files, vpk_sha256=files[0]['sha256'],
                           changed_runtime_paths=[self.a, self.b], added_runtime_paths=[], removed_runtime_paths=[],
                           target_pins={self.a: dict(bytes=10, sha256='1' * 64), self.b: dict(bytes=20, sha256='2' * 64)},
                           source_artifact_pins={self.author: copy.deepcopy(self.pin)},
                           git_runtime_lineage=dict(complete=True, unknown_changes=[], source_revisions=self.sources,
                               actual_parent_manifest_sha256='0' * 64, changed_runtime_paths=[self.a, self.b],
                               resource_origins=origins, parent_resource_origins_sha256=m.canonical_digest(old_origins),
                               deferred_sources=copy.deepcopy(self.deferred), deferred_unpublished0201_sources={
                                   'game:' + self.author: dict(repo='game', path=self.author, status='DEFERRED_UNRELEASED_0201_OUTSIDE_THIS_HOTFIX'),
                                   'content:' + self.mirror: dict(repo='content', path=self.mirror, status='DEFERRED_UNRELEASED_0201_OUTSIDE_THIS_HOTFIX')}),
                           parent_resource_origins_sha256=m.canonical_digest(old_origins))
        self.journal = dict(workshop_id='42', release_sequence=101, content_sha256='f' * 64, uploaded=True,
                            status=m.SDK_STATUS, app_id=570, legal_agreement_required=False,
                            package_files=copy.deepcopy(files), vpk_bytes=files[0]['bytes'], vpk_sha256=files[0]['sha256'])
        callback = dict(callback_id=3406, app_id=570, workshop_id='42', result=1)
        total = sum(row['bytes'] for row in files)
        query = dict(id='42', result=1, cached=False, max_cache_age_seconds=0, banned=False,
                     creator_app_id=570, consumer_app_id=570, total_files_bytes=total, time_updated=42, owner='synthetic')
        self.receipt = dict(status=m.DOWNLOAD_STATUS, workshop_id='42', release_sequence=101, content_sha256='f' * 64,
                            package_report_sha256='6' * 64, canonical_journal_sha256='7' * 64, canonical_journal_unchanged=True,
                            signed_resources_verified=3, protected_modules_verified=2, steam_manifest='123456789',
                            acf_installed_entry=dict(manifest='123456789', size=str(total)), pre_query=copy.deepcopy(query), post_query=copy.deepcopy(query),
                            download=dict(download_requested=True, callback=callback),
                            verification=dict(status='UNLISTED_WORKSHOP_DOWNLOAD_FULLY_VERIFIED', signature_valid=True,
                                vpk_sha256=files[0]['sha256'], package_files=copy.deepcopy(files), callback=copy.deepcopy(callback),
                                size_on_disk=total, expected_size_on_disk=total,
                                verification=dict(files=3, archive_count=4, **{key: True for key in m.CHECKS})))
        self.evidence = dict(signature_valid=True, signed_manifest_release_sequence=101, manifest_sha256='8' * 64,
                             package_report_sha256='6' * 64, journal_sha256='7' * 64, journal=self.journal,
                             download_receipt=self.receipt)
        self.seal()

    def frozen(self, digest, size):
        return dict(kind='FROZEN_SIGNED_RESOURCE', resource_sha256=digest * 64, resource_bytes=size,
                    source_git_origin_claimed=False, release_sequence=100)

    def seal(self):
        origins = self.report['git_runtime_lineage']['resource_origins']
        self.report['resource_origins_sha256'] = self.report['git_runtime_lineage']['resource_origins_sha256'] = m.canonical_digest(origins)
        self.evidence['manifest_object_sha256'] = m.canonical_digest(self.manifest)
        self.evidence['package_report_object_sha256'] = m.canonical_digest(self.report)

    def advance(self):
        return m.advance_baseline(self.previous, self.manifest, self.report, self.trees, self.evidence)


class RollforwardTests(unittest.TestCase):
    def test_two_resource_hotfix_advances_only_proven_outputs_and_authors(self):
        f = Fixture(); before = copy.deepcopy((f.previous, f.report, f.manifest, f.trees, f.evidence))
        result = f.advance()
        self.assertEqual(result['parent_sequence'], 101)
        self.assertEqual(result['parent_manifest_sha256'], '8' * 64)
        self.assertEqual(result['source_inventory']['game'][f.a]['oid'], '7' * 40)
        self.assertEqual(result['source_inventory']['game'][f.b]['oid'], '8' * 40)
        self.assertEqual(result['source_inventory']['game'][f.author]['oid'], '9' * 40)
        self.assertEqual(result['source_inventory']['content'][f.mirror]['oid'], 'c' * 40)
        self.assertEqual(result['source_inventory']['game'][f.history], f.previous['source_inventory']['game'][f.history])
        self.assertEqual(result['source_inventory']['game'][f.csv], f.previous['source_inventory']['game'][f.csv])
        self.assertEqual(result['source_anchors'], f.previous['source_anchors'])
        self.assertFalse(result['source_anchor_is_full_published_tree'])
        self.assertFalse(result['full_head_publication_claimed'])
        self.assertEqual((f.previous, f.report, f.manifest, f.trees, f.evidence), before)

    def test_unchanged_oid_unpublished_entry_still_remains_deferred(self):
        f = Fixture()
        f.trees['game']['entries'][f.history] = {**f.previous['source_inventory']['game'][f.history], 'sha256': 'c' * 64}
        result = f.advance()
        self.assertEqual(result['deferred_sources']['game:' + f.history], f.deferred['game:' + f.history])
        self.assertEqual(result['resource_origins'][f.history], f.previous['resource_origins'][f.history])

    def test_only_actual_input_output_coverage_clears_deferral_and_keeps_resolution_history(self):
        f = Fixture(); result = f.advance()
        self.assertNotIn('game:' + f.a, result['deferred_sources'])
        self.assertNotIn('game:' + f.author, result['deferred_sources'])
        self.assertNotIn('content:' + f.mirror, result['deferred_sources'])
        self.assertIn('game:' + f.csv, result['deferred_sources'])
        self.assertEqual(len(result['resolved_deferred_history']), 3)

    def test_new_uncovered0201_deferral_is_preserved(self):
        f = Fixture(); name = 'scripts/vscripts/systems/not_shipped.lua'
        item = dict(repo='game', path=name, status='DEFERRED_UNRELEASED_0201_OUTSIDE_THIS_HOTFIX')
        f.report['git_runtime_lineage']['deferred_unpublished0201_sources']['game:' + name] = item; f.seal()
        result = f.advance()
        self.assertEqual(result['deferred_sources']['game:' + name], item)
        self.assertNotIn(name, result['source_inventory']['game'])

    def test_mixed_old_download_or_changed_volume_is_rejected(self):
        for kind in ('old_version', 'volume', 'missing_volume', 'report_hash', 'journal_hash', 'signature', 'callback', 'cached_query'):
            with self.subTest(kind=kind):
                f = Fixture()
                if kind == 'old_version': f.receipt['release_sequence'] = 100
                elif kind == 'volume': f.receipt['verification']['package_files'][1]['sha256'] = '0' * 64
                elif kind == 'missing_volume': f.receipt['verification']['package_files'].pop()
                elif kind == 'report_hash': f.receipt['package_report_sha256'] = '0' * 64
                elif kind == 'journal_hash': f.receipt['canonical_journal_sha256'] = '0' * 64
                elif kind == 'signature': f.receipt['verification']['signature_valid'] = False
                elif kind == 'callback': f.receipt['download']['callback']['result'] = 2
                else: f.receipt['pre_query']['cached'] = True
                with self.assertRaises(ValueError): f.advance()

    def test_sdk_success_alone_or_five_local_files_never_advances_baseline(self):
        f = Fixture(); del f.evidence['download_receipt']
        with self.assertRaises(ValueError): f.advance()
        f = Fixture(); f.journal['uploaded'] = False
        with self.assertRaises(ValueError): f.advance()

    def test_wrong_target_tree_commit_or_input_hash_is_rejected(self):
        f = Fixture(); f.trees['content']['commit'] = 'f' * 40
        with self.assertRaises(ValueError): f.advance()
        f = Fixture(); f.trees['game']['entries'][f.author]['sha256'] = '0' * 64
        with self.assertRaises(ValueError): f.advance()

    def test_origin_must_match_every_signed_resource_and_preserve_untouched_provenance(self):
        f = Fixture(); f.report['git_runtime_lineage']['resource_origins'][f.b]['resource_sha256'] = '0' * 64; f.seal()
        with self.assertRaises(ValueError): f.advance()
        f = Fixture(); f.report['git_runtime_lineage']['resource_origins'][f.history]['release_sequence'] = 101; f.seal()
        with self.assertRaisesRegex(ValueError, 'provenance'): f.advance()

    def test_uncovered_deferred_history_cannot_be_rewritten(self):
        f = Fixture(); f.report['git_runtime_lineage']['deferred_sources']['game:' + f.csv]['status'] = 'ALREADY_SHIPPED'; f.seal()
        with self.assertRaisesRegex(ValueError, 'history_changed'): f.advance()

    def test_unknown_origin_kind_or_unknown_drift_is_blocked(self):
        f = Fixture(); f.report['git_runtime_lineage']['resource_origins'][f.a]['kind'] = 'READY_FROM_HEAD'; f.seal()
        with self.assertRaisesRegex(ValueError, 'unknown_runtime_origin'): f.advance()
        f = Fixture(); f.report['git_runtime_lineage']['unknown_changes'] = ['unmapped']; f.seal()
        with self.assertRaisesRegex(ValueError, 'known_runtime_lineage'): f.advance()

    def test_unmapped_removal_is_blocked(self):
        f = Fixture(); f.manifest['files'] = [r for r in f.manifest['files'] if r['path'] != f.history]; f.manifest['file_count'] = 2
        f.report['files'] = 2; f.report['removed_runtime_paths'] = [f.history]
        del f.report['git_runtime_lineage']['resource_origins'][f.history]
        f.receipt['signed_resources_verified'] = 2; f.receipt['verification']['verification']['files'] = 2; f.seal()
        with self.assertRaisesRegex(ValueError, 'removal_requires_explicit'): f.advance()

    def test_explicit_absent_runtime_and_source_removal_advances_without_sweeping_head(self):
        f = Fixture(); f.manifest['files'] = [r for r in f.manifest['files'] if r['path'] != f.history]; f.manifest['file_count'] = 2
        f.report['files'] = 2; f.report['removed_runtime_paths'] = [f.history]
        f.report['removed_source_bindings'] = {f.history: [dict(repo='game', path=f.history)]}
        del f.report['git_runtime_lineage']['resource_origins'][f.history]; del f.trees['game']['entries'][f.history]
        f.receipt['signed_resources_verified'] = 2; f.receipt['verification']['verification']['files'] = 2; f.seal()
        result = f.advance()
        self.assertNotIn(f.history, result['source_inventory']['game'])
        self.assertNotIn('game:' + f.history, result['deferred_sources'])
        self.assertEqual(result['rollforward']['removed_source_entries'], ['game:' + f.history])
        self.assertIn('game:' + f.csv, result['deferred_sources'])

    def test_changed_manifest_or_report_object_cannot_reuse_original_byte_hash_assertion(self):
        f = Fixture(); f.report['source_revision'] = '0' * 40
        with self.assertRaisesRegex(ValueError, 'authenticated_object'): f.advance()

    def test_unrelated_head_change_must_be_explicitly_deferred_and_never_absorbed(self):
        f = Fixture(); f.trees['game']['entries']['scripts/new_unmapped.lua'] = git_entry('d', '7', 4)
        with self.assertRaisesRegex(ValueError, 'unknown_unpublished_source_change'): f.advance()

    def test_missing0201_deferred_map_is_not_treated_as_empty(self):
        f = Fixture(); del f.report['git_runtime_lineage']['deferred_unpublished0201_sources']; f.seal()
        with self.assertRaisesRegex(ValueError, 'deferred_source_maps'): f.advance()

    def test_partial_lineage_cannot_claim_full_head(self):
        f = Fixture(); f.report['git_runtime_lineage']['full_head_publication_claimed'] = True; f.seal()
        with self.assertRaisesRegex(ValueError, 'cannot_claim_full_head'): f.advance()


if __name__ == '__main__':
    unittest.main()
