"""Offline lineage and scope checks; never invoke SSH, HTTP, SQL or services."""
from __future__ import annotations

import ast
import base64
import contextlib
import importlib.util
import io
import json
from pathlib import Path
import unittest
from unittest.mock import patch

HERE=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location('ws4_worker_cache_deploy',HERE/'deploy.py')
deploy=importlib.util.module_from_spec(spec)
spec.loader.exec_module(deploy)


def remote_helpers():
    """Execute only the actual remote pure transform, with no remote preamble."""
    tree=ast.parse(deploy.REMOTE)
    functions=[n for n in tree.body if isinstance(n,ast.FunctionDef)
        and n.name in ('need','fragments','derive_payloads')]
    if len(functions)!=3:raise AssertionError('remote_transform_functions_changed')
    values=dict(ast=ast,sha=deploy.sha,service='backend/archive_backend/service.py',
        expected_service=deploy.PARENT_SERVICE,SOURCE_PINS=deploy.SOURCE_PINS,
        SOURCE_METHOD=deploy.SOURCE_METHOD,DERIVED_SERVICE=deploy.DERIVED_SERVICE)
    exec(compile(ast.Module(body=functions,type_ignores=[]),'<remote pure transform>','exec'),values)
    return values


class OfflineScope(unittest.TestCase):
    def test_default_plan_cannot_start_transport_or_git_or_write_receipt(self):
        with (patch.object(deploy.subprocess,'check_output',side_effect=AssertionError('no git')),
             patch.object(deploy.importlib.util,'spec_from_file_location',side_effect=AssertionError('no transport')),
             patch.object(deploy.Path,'mkdir',side_effect=AssertionError('no writes')),
             contextlib.redirect_stdout(io.StringIO()) as stream):
            self.assertEqual(deploy.main([]),0)
        plan=json.loads(stream.getvalue())
        self.assertEqual(plan['remote_actions'],0)
        self.assertEqual(plan['source_revision'],deploy.SOURCE)
        self.assertEqual(plan['derived_payload_sha256']['backend/archive_backend/service.py'],deploy.DERIVED_SERVICE)
        self.assertIn('no tokens',plan['modes']['audit'])

    def test_other_revision_refused_before_git_or_transport(self):
        with patch.object(deploy.subprocess,'check_output',side_effect=AssertionError('no git')):
            with self.assertRaisesRegex(RuntimeError,'reviewed_s10_source_revision_required'):
                deploy.source_payloads('0'*40)

    def test_s10_actual_git_blobs_match_reviewed_source_pins(self):
        values=deploy.source_payloads(deploy.SOURCE)
        decoded={name:base64.b64decode(value,validate=True) for name,value in values.items()}
        self.assertEqual({name:deploy.sha(raw) for name,raw in decoded.items()},deploy.SOURCE_PINS)
        method=remote_helpers()['fragments'](decoded['backend/archive_backend/service.py'])[1]
        self.assertEqual(deploy.sha(method.encode()),deploy.SOURCE_METHOD)

    def test_changed_helper_refused_before_transport(self):
        with patch.object(deploy,'git_blob',return_value=b'drift'):
            with self.assertRaisesRegex(RuntimeError,'immutable_worker_cache_source_changed'):
                deploy.source_payloads(deploy.SOURCE)

    def test_controlled_parent_outside_method_is_byte_preserved(self):
        # The source deliberately has different imports/other methods. Only the
        # source settle bytes may replace the parent's exact original fragment.
        parent=b'# parent-only\nclass ArchiveService:\n    def other(self):\n        return "parent"\n\n    def settle(self):\n        return "old"\n\n# parent trailer\n'
        source=b'# source-only\nclass ArchiveService:\n    def other(self):\n        return "source"\n\n    def settle(self):\n        return "new"\n\n# source trailer\n'
        expected=parent.replace(b'return "old"',b'return "new"')
        values=remote_helpers()
        service=values['service']
        source_files={service:source,'backend/archive_backend/settlement_runner.py':b'pass\n',
            'backend/archive_backend/worker_fast.lua':b'return true\n'}
        values.update(expected_service=deploy.sha(parent),
            SOURCE_PINS={name:deploy.sha(raw) for name,raw in source_files.items()},
            SOURCE_METHOD=deploy.sha(values['fragments'](source)[1].encode()),
            DERIVED_SERVICE=deploy.sha(expected))
        payloads,binding,pins=values['derive_payloads'](parent,source_files)
        self.assertEqual(payloads[service],expected)
        self.assertEqual(binding['source_service_sha256'],deploy.sha(source))
        self.assertEqual(binding['parent_service_sha256'],deploy.sha(parent))
        self.assertEqual(binding['output_service_sha256'],pins[service])
        self.assertTrue(binding['outside_method_unchanged'])
        with self.assertRaisesRegex(RuntimeError,'ws4_parent_service_changed'):
            values['derive_payloads'](parent+b'\n',source_files)
        with self.assertRaisesRegex(RuntimeError,'immutable_worker_cache_source_changed'):
            values['derive_payloads'](parent,{**source_files,'unexpected.py':b'pass\n'})

    def test_duplicate_missing_or_non_lf_anchor_is_rejected(self):
        fragments=remote_helpers()['fragments']
        cases=(
            (b'class ArchiveService:\n    pass\n','settlement_method_anchor_invalid'),
            (b'class ArchiveService:\n    def settle(self):pass\n    def settle(self):pass\n','settlement_method_anchor_invalid'),
            (b'class ArchiveService:pass\nclass ArchiveService:pass\n','service_class_anchor_invalid'),
            (b'class ArchiveService:\r\n    def settle(self):pass\r\n','immutable_lf_service_required'),
        )
        for raw,error in cases:
            with self.subTest(error=error):
                with self.assertRaisesRegex(RuntimeError,error):fragments(raw)

    def test_local_preserved_actual_parent_derivation(self):
        # Optional historical evidence is deliberately outside Git/runtime.
        # It cannot replace the fresh production parent hash gate in audit.
        path=deploy.ROOT/'output/ws4_latency_20261104/actual_parent_service_reconstructed.py'
        if not path.exists():self.skipTest('historical local audit not present; remote identity still mandatory')
        raw=path.read_bytes()
        values={name:base64.b64decode(value,validate=True)
            for name,value in deploy.source_payloads(deploy.SOURCE).items()}
        helpers=remote_helpers()
        payloads,binding,pins=helpers['derive_payloads'](raw,values)
        parent=helpers['fragments'](raw)
        result=helpers['fragments'](payloads[helpers['service']])
        self.assertEqual((parent[0],parent[2]),(result[0],result[2]))
        self.assertEqual(pins[helpers['service']],deploy.DERIVED_SERVICE)
        self.assertEqual(binding['source_settle_sha256'],deploy.SOURCE_METHOD)


if __name__=='__main__':unittest.main()
