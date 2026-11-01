"""New-family authority integration; no SDK, package scan, process or Git call."""
import copy
import hashlib
from pathlib import Path
import sys
import unittest
from unittest.mock import patch

sys.dont_write_bytecode=True
sys.path.insert(0,str(Path(__file__).resolve().parent))
import release_pipeline as pipeline
from release_lineage_20261101 import guard


class NewAuthorityTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.auth=pipeline.authority()
        cls.validator=guard._validator(cls.auth)

    def test_fixed_new_family_keeps_canonical_lock_and_old_policy_bytes(self):
        auth=self.auth
        self.assertEqual(pipeline.hook.AUTHORITY_FILE.name,'release_authority_20261102.json')
        self.assertEqual(auth.policy['release_sequence'],2026110201)
        self.assertFalse(auth.policy['manual_attach_adopt_allowed'])
        self.assertEqual(auth.policy['native_launch_profiles'],['direct','lobby'])
        self.assertEqual(Path(auth.policy['publication_lock']).resolve(),Path(str(guard.CANONICAL_JOURNAL.resolve())+'.lock'))
        self.assertEqual(Path(auth.policy['canonical_journal']).resolve(),guard.CANONICAL_JOURNAL.resolve())
        old=guard.ROOT/'publishing/workshop/release_authority_20261101.json'
        self.assertEqual(hashlib.sha256(old.read_bytes()).hexdigest(),'06df3c0d9154b2866463a5e525c85997590a0b8d6f71013b98279c36405eaacb')
        for prefix in ('recipe','validator','rehearsal','download'):
            path=Path(auth.policy[prefix+'_path'])
            self.assertEqual(path.parent,guard.ROOT/'tools/portrait_resolution_release_20261102')
            self.assertEqual(hashlib.sha256(path.read_bytes()).hexdigest(),auth.policy[prefix+'_sha256'])

    def test_old1107_and_ready_flags_refused_before_completed_package_or_sdk(self):
        with (patch.object(self.validator.c,'validated_package',side_effect=AssertionError('Old candidate reached package verification')),
                patch.object(pipeline,'_sdk',side_effect=AssertionError('SDK reached'))):
            for sequence in (2026110107,2026110104):
                with self.subTest(sequence=sequence),self.assertRaisesRegex(ValueError,'exact candidate sequence'):
                    self.validator.validate_release({'release_sequence':sequence,'READY':True})

    def test_missing_new_combat_pins_cannot_use_old_artifact_or_begin_git_work(self):
        builder=self.validator.b
        compiled=copy.deepcopy(builder.COMPILED)
        combat=next(key for key,pin in compiled.items() if pin['source'].endswith('/combat_stats.js'))
        for field in ('source_git_sha256','source_sha256','compiled_sha256'):
            changed=copy.deepcopy(compiled);changed[combat][field]=None
            with self.subTest(field=field),patch.object(builder,'COMPILED',changed),patch.object(builder,'blob_at',side_effect=AssertionError('Missing pin reached Git')),self.assertRaisesRegex(ValueError,'PENDING_OFFICIAL_COMPILER_PROOF'):
                builder.compiled_pins_ready()


if __name__=='__main__':unittest.main()
