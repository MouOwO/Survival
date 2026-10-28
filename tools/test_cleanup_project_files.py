import hashlib
import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('cleanup', Path(__file__).with_name('cleanup_project_files.py'))
tool = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tool)


class CleanupTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name) / 'project'
        self.root.mkdir()
        subprocess.run(['git', 'init', '-q', str(self.root)], check=True)
        subprocess.run(['git', '-C', str(self.root), '-c', 'user.name=Test', '-c', 'user.email=test@example.invalid', 'commit', '--allow-empty', '-qm', 'fixture'], check=True)
        self.path = self.root / 'output/old_preview/preview/image.png'
        self.path.parent.mkdir(parents=True)
        self.path.write_bytes(b'historical generated image')
        self.plan = {'schema': 1, 'action': 'archive_verify_then_delete_exact_files', 'root': str(self.root),
                     'head': subprocess.check_output(['git', '-C', str(self.root), 'rev-parse', 'HEAD'], text=True).strip(),
                     'bytes': self.path.stat().st_size,
                     'files': [{'path': self.path.relative_to(self.root).as_posix(), 'bytes': self.path.stat().st_size,
                                'sha256': tool.sha(self.path), 'reason': 'regenerated fixture'}]}
        self.archive = Path(self.tmp.name) / 'external/history.zip'

    def test_default_is_read_only(self):
        self.assertFalse(tool.cleanup(self.root, self.plan, self.archive)['applied'])
        self.assertTrue(self.path.exists())
        self.assertFalse(self.archive.exists())

    def test_archive_bytes_recover_deleted_file(self):
        result = tool.cleanup(self.root, self.plan, self.archive, apply=True)
        self.assertTrue(result['archive_fully_verified'])
        self.assertFalse(self.path.exists())
        with tool.zipfile.ZipFile(self.archive) as archive:
            self.assertEqual(archive.read(self.plan['files'][0]['path']), b'historical generated image')
            self.assertEqual(json.loads(archive.read('_cleanup_manifest.json')), self.plan)

    def test_changed_source_is_not_deleted(self):
        self.path.write_bytes(b'new authored work')
        with self.assertRaises(ValueError): tool.cleanup(self.root, self.plan, self.archive, apply=True)
        self.assertTrue(self.path.exists())
        self.assertFalse(self.archive.exists())

    def test_source_change_during_archiving_preserves_files(self):
        original = tool.zipfile.ZipFile.write
        def changing(archive, *args, **kwargs):
            result = original(archive, *args, **kwargs)
            self.path.write_bytes(b'changed during archive')
            return result
        with patch.object(tool.zipfile.ZipFile, 'write', changing):
            with self.assertRaises(ValueError): tool.cleanup(self.root, self.plan, self.archive, apply=True)
        self.assertTrue(self.path.exists())

    def test_traversal_protected_evidence_and_credentials_rejected(self):
        for name in ['../outside.txt', 'output/../scripts/main.lua', 'output/map_resources_20261028/compile.log',
                     'output/workshop_web_auth_20261024/steam_tls_relay_process.json',
                     'output/ui_qa_20261025/release/package.json', 'output/old/.env',
                     'output/old/.git/objects/pack/a.pack', 'output/old/before/source.lua',
                     'scripts/vscripts/main.lua']:
            with self.subTest(name=name): self.assertFalse(tool.eligible(name))

    def test_existing_archive_and_inside_root_rejected(self):
        with self.assertRaises(ValueError): tool.cleanup(self.root, self.plan, self.root / 'backup.zip')
        self.archive.parent.mkdir()
        self.archive.write_bytes(b'previous backup')
        with self.assertRaises(ValueError): tool.cleanup(self.root, self.plan, self.archive)
        self.assertEqual(self.archive.read_bytes(), b'previous backup')

    def test_duplicate_targets_rejected(self):
        self.plan['files'].append(dict(self.plan['files'][0]))
        self.plan['bytes'] *= 2
        with self.assertRaises(ValueError): tool.cleanup(self.root, self.plan, self.archive)

    def test_archive_error_never_deletes_source(self):
        with patch.object(tool.zipfile.ZipFile, 'write', side_effect=OSError('archive failed')):
            with self.assertRaises(OSError): tool.cleanup(self.root, self.plan, self.archive, apply=True)
        self.assertTrue(self.path.exists())


if __name__ == '__main__':
    unittest.main()
