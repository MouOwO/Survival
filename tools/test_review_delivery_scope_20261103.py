"""Read-only scope report contracts, temporary JSON only; no game/VPK/SDK."""
import contextlib
import hashlib
import importlib.util
import io
import json
from pathlib import Path
import tempfile
import unittest
from unittest import mock

SPEC=importlib.util.spec_from_file_location('complete_scope_review_under_test',Path(__file__).with_name('review_delivery_scope_20261103.py'))
m=importlib.util.module_from_spec(SPEC);SPEC.loader.exec_module(m)


class ScopeReviewTests(unittest.TestCase):
    def test_all_author_families_map_to_actual_source_paths_without_claiming_compile(self):
        self.assertEqual(m.author_paths('panorama/scripts/custom_game/a.vjs_c'),[('game','panorama/src/scripts/custom_game/a.js'),('content','panorama/scripts/custom_game/a.js')])
        self.assertEqual(m.author_paths('panorama/images/a.vtex_c'),[('content','panorama/images/a.vtex')])
        self.assertEqual(m.author_paths('panorama/images/a.vsvg_c'),[('content','panorama/images/a.svg')])
        self.assertEqual(m.author_paths('scripts/a.lua'),[])

    def test_only_requested_resource_digest_and_size_are_indexed(self):
        with tempfile.TemporaryDirectory(prefix='scope-manifest-json-') as folder:
            path=Path(folder)/'manifest.json';path.write_text(json.dumps(dict(content_sha256='a'*64,files=[dict(path='panorama/a.vjs_c',sha256='b'*64,bytes=10),dict(path='other',sha256='c'*64,bytes=20)])))
            index,docs,size=m.read_manifests([path],{'panorama/a.vjs_c'})
            self.assertEqual(set(index),{('panorama/a.vjs_c','b'*64,10)})
            self.assertEqual(docs[0]['sha256'],hashlib.sha256(path.read_bytes()).hexdigest())
            self.assertEqual(size,path.stat().st_size)

    def test_local_manifest_document_count_is_bounded(self):
        with tempfile.TemporaryDirectory(prefix='scope-manifest-bound-') as folder:
            path=Path(folder)/'manifest.json';path.write_text('{"files":[]}')
            with self.assertRaisesRegex(ValueError,'manifest_document_budget_exceeded'):m.read_manifests([path]*65,set())

    def test_output_never_overwrites_previous_scope_evidence(self):
        output=m.ROOT/'output';output.mkdir(exist_ok=True)
        with tempfile.TemporaryDirectory(prefix='scope-review-only-',dir=output) as folder:
            target=Path(folder)/'existing.json';target.write_bytes(b'{"original":true}')
            value=dict(kind='review',initial_counts={},decision_counts={})
            with mock.patch.object(m,'review',return_value=value),self.assertRaisesRegex(ValueError,'preserve_previous_evidence'):m.main(['--output',str(target)])
            self.assertEqual(target.read_bytes(),b'{"original":true}')


if __name__=='__main__':unittest.main()
