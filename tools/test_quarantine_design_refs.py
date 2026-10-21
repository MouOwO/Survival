"""Behavioral tests for reversible external design_refs quarantine."""
import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest import mock

spec=importlib.util.spec_from_file_location('quarantine_design_refs', Path(__file__).with_name('quarantine_design_refs.py'))
q=importlib.util.module_from_spec(spec)
spec.loader.exec_module(q)


class QuarantineTests(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory(prefix='survival_quarantine_test_')
        self.base=Path(self.tmp.name)
        self.roots={'game':self.base/'game/survival','content':self.base/'content/Survival'}
        for root in self.roots.values(): root.mkdir(parents=True)
        self.batch=self.base/'outside/batch'
        self.manifest=self.base/'audit.json'

    def tearDown(self): self.tmp.cleanup()

    def file(self, path='design_refs/concept/unused.png', content=b'authored image bytes', repo='game'):
        p=self.roots[repo]/path
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_bytes(content)
        return {'repo':repo,'path':path,'bytes':len(content),'sha256':hashlib.sha256(content).hexdigest(),'reason':'no incoming references'}

    def plan(self, rows):
        self.manifest.write_text(json.dumps({'schema_version':1,'action':'move_to_external_quarantine_only','files':rows}), 'utf-8')
        return q.load_plan(self.manifest, self.roots)

    def test_default_review_does_not_create_backup_or_remove_source(self):
        row=self.file()
        result=q.quarantine(self.plan([row]), self.batch)
        self.assertFalse(result['applied'])
        self.assertTrue((self.roots['game']/row['path']).is_file())
        self.assertFalse(self.batch.exists())

    def test_move_and_copy_restore_are_verified_and_idempotent(self):
        row=self.file(); original=self.roots['game']/row['path']
        result=q.quarantine(self.plan([row]), self.batch, apply=True)
        self.assertEqual(result['moved_files'],1)
        self.assertFalse(original.exists())
        backup=self.batch/'game'/row['path']
        self.assertEqual(q.digest(backup),row['sha256'])
        self.assertFalse(q.restore(self.batch/q.MANIFEST_NAME,self.roots)['applied'])
        self.assertFalse(original.exists())
        restored=q.restore(self.batch/q.MANIFEST_NAME,self.roots,apply=True)
        self.assertEqual(restored['restored_files'],1)
        self.assertEqual(original.read_bytes(),backup.read_bytes())
        self.assertTrue(backup.exists())
        again=q.restore(self.batch/q.MANIFEST_NAME,self.roots,apply=True)
        self.assertEqual(again['already_present'],1)
        self.assertEqual(again['restored_files'],0)
        events=[json.loads(x)['state'] for x in (self.batch/q.JOURNAL_NAME).read_text('utf-8').splitlines()]
        self.assertIn('planned',events); self.assertIn('moved_verified',events); self.assertIn('restored_verified',events)

    def test_all_rows_validated_before_any_move(self):
        first=self.file('design_refs/a.png',b'a'); second=self.file('design_refs/b.png',b'b')
        plan=self.plan([first,second])
        (self.roots['game']/second['path']).write_bytes(b'changed')
        with self.assertRaises(q.QuarantineError): q.quarantine(plan,self.batch,apply=True)
        self.assertTrue((self.roots['game']/first['path']).exists())
        self.assertFalse(self.batch.exists())

    def test_rejects_non_design_refs_traversal_git_and_duplicate_paths(self):
        valid=self.file()
        for path in ['../outside','/design_refs/a','design_refs/../../secret','panorama/a.png','design_refs/.git/config','design_refs/x/../a','design_refs//a','design_refs\\a','C:/outside']:
            with self.subTest(path=path),self.assertRaises(q.QuarantineError): self.plan([{**valid,'path':path}])
        with self.assertRaises(q.QuarantineError): self.plan([valid,valid])
        with self.assertRaises(q.QuarantineError): self.plan([{**valid,'reference_count':1}])

    def test_backup_must_be_outside_both_addons_and_new(self):
        row=self.file(); plan=self.plan([row])
        for target in [self.roots['game']/'pending',self.roots['content']/'pending']:
            with self.subTest(target=target),self.assertRaises(q.QuarantineError): q.quarantine(plan,target,apply=True)
        self.batch.mkdir(parents=True)
        with self.assertRaises(q.QuarantineError): q.quarantine(plan,self.batch,apply=True)
        with self.assertRaises(OSError): q.quarantine(plan,self.batch,apply=True,resume=True)

    def test_restore_never_overwrites_changed_source(self):
        first=self.file('design_refs/a.png',b'a'); second=self.file('design_refs/b.png',b'b')
        q.quarantine(self.plan([first,second]),self.batch,apply=True)
        original=self.roots['game']/first['path']; original.write_bytes(b'new work')
        result=q.restore(self.batch/q.MANIFEST_NAME,self.roots,apply=True)
        self.assertEqual(original.read_bytes(),b'new work')
        self.assertEqual(result['restored_files'],1)
        self.assertEqual(len(result['conflicts']),1)
        self.assertEqual((self.roots['game']/second['path']).read_bytes(),b'b')

    def test_resume_after_backup_published_before_source_removed(self):
        row=self.file(); plan=self.plan([row]); original_publish=q._publish_copy
        def publish_then_interrupt(*args):
            original_publish(*args)
            raise OSError('simulated interruption after backup verification')
        with mock.patch.object(q,'_publish_copy',side_effect=publish_then_interrupt):
            with self.assertRaises(OSError): q.quarantine(plan,self.batch,apply=True)
        self.assertTrue((self.roots['game']/row['path']).exists())
        self.assertTrue((self.batch/'game'/row['path']).exists())
        result=q.quarantine(plan,self.batch,apply=True,resume=True)
        self.assertEqual(result['moved_files'],1)
        self.assertFalse((self.roots['game']/row['path']).exists())

    def test_resume_after_source_removed_before_receipt(self):
        row=self.file(); plan=self.plan([row]); original_append=q._append
        def append_with_interruption(batch,event):
            if event.get('state')=='moved_verified': raise OSError('simulated receipt interruption')
            return original_append(batch,event)
        with mock.patch.object(q,'_append',side_effect=append_with_interruption):
            with self.assertRaises(OSError): q.quarantine(plan,self.batch,apply=True)
        self.assertFalse((self.roots['game']/row['path']).exists())
        result=q.quarantine(plan,self.batch,apply=True,resume=True)
        self.assertEqual(result['already_moved'],1)

    def test_producer_change_during_copy_preserves_new_work_and_verified_backup(self):
        row=self.file(); plan=self.plan([row]); original_publish=q._publish_copy
        source=self.roots['game']/row['path']
        def publish_then_edit(*args):
            original_publish(*args)
            source.write_bytes(b'concurrent new work')
        with mock.patch.object(q,'_publish_copy',side_effect=publish_then_edit):
            with self.assertRaises(q.QuarantineError): q.quarantine(plan,self.batch,apply=True)
        self.assertEqual(source.read_bytes(),b'concurrent new work')
        self.assertEqual(q.digest(self.batch/'game'/row['path']),row['sha256'])
        result=q.restore(self.batch/q.MANIFEST_NAME,self.roots,apply=True)
        self.assertEqual(len(result['conflicts']),1)
        self.assertEqual(source.read_bytes(),b'concurrent new work')

    def test_resume_requires_exact_original_audit_and_backup(self):
        row=self.file(); plan=self.plan([row]); q.quarantine(plan,self.batch,apply=True)
        self.manifest.write_text(self.manifest.read_text('utf-8')+'\n','utf-8')
        different=q.load_plan(self.manifest,self.roots)
        with self.assertRaises(q.QuarantineError): q.quarantine(different,self.batch,apply=True,resume=True)
        (self.batch/'game'/row['path']).write_bytes(b'corrupt')
        with self.assertRaises(q.QuarantineError): q.restore(self.batch/q.MANIFEST_NAME,self.roots,apply=True)
        self.assertFalse((self.roots['game']/row['path']).exists())

    def test_backup_manifest_cannot_be_edited_unnoticed(self):
        row=self.file(); q.quarantine(self.plan([row]),self.batch,apply=True)
        p=self.batch/q.MANIFEST_NAME; p.write_text(p.read_text('utf-8')+'\n','utf-8')
        with self.assertRaises(q.QuarantineError): q.restore(p,self.roots,apply=True)

    def test_links_are_rejected_without_touching_their_targets(self):
        external=self.base/'external'; external.mkdir(); (external/'x.png').write_bytes(b'outside')
        link=self.roots['game']/'design_refs/link'; link.parent.mkdir(parents=True)
        try: link.symlink_to(external,target_is_directory=True)
        except (OSError,NotImplementedError):
            try:
                import _winapi
                _winapi.CreateJunction(str(external),str(link))
            except (ImportError,OSError,AttributeError): self.skipTest('link creation unavailable')
        row={'repo':'game','path':'design_refs/link/x.png','bytes':7,'sha256':hashlib.sha256(b'outside').hexdigest()}
        with self.assertRaises(q.QuarantineError): self.plan([row])
        self.assertEqual((external/'x.png').read_bytes(),b'outside')

    def test_content_files_use_separate_payload_and_root(self):
        rows=[self.file(content=b'game'),self.file(content=b'content',repo='content')]
        q.quarantine(self.plan(rows),self.batch,apply=True)
        self.assertEqual((self.batch/'game'/rows[0]['path']).read_bytes(),b'game')
        self.assertEqual((self.batch/'content'/rows[1]['path']).read_bytes(),b'content')
        result=q.restore(self.batch/q.MANIFEST_NAME,self.roots,apply=True)
        self.assertEqual(result['restored_files'],2)


if __name__=='__main__': unittest.main()
