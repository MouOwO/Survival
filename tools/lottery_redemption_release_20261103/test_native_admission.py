"""Synthetic policy checks; no native acceptance or ticket consumption."""
from pathlib import Path
import importlib.util,tempfile,unittest
from unittest.mock import patch
HERE=Path(__file__).resolve().parent
def load(name,path):
    spec=importlib.util.spec_from_file_location(name,path);m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m);return m
x=load('redemption0301_gate',HERE/'native_admission.py')
old=load('redemption0301_fixture',HERE.parent/'lottery_replay_release_20261102/test_native_admission.py')
CACHE='panorama/scripts/custom_game/common/lottery_cache.vjs_c'
SOURCE='panorama/src/scripts/custom_game/common/lottery_cache.js'
def fixture(folder):
    f=old.fixture(folder)
    f.b.SEQUENCE=2026110301
    f.b.PAYLOADS=(*f.b.PAYLOADS[:2],CACHE,*f.b.PAYLOADS[2:])
    f.b.COMPILED[CACHE]={'source':SOURCE}
    f.package['source_artifact_pins'][SOURCE]={}
    f.package['target_pins'][CACHE]={'sha256':'a'*64}
    for v in (f.package,f.signed,f.review):v['release_sequence']=2026110301
    f.change_receipt('transaction',lambda v:v.update(release_sequence=2026110301))
    f.package['changed_runtime_paths']=sorted(f.b.PAYLOADS);f.review['runtime_paths']=sorted(f.b.PAYLOADS)
    return f
def validate(f):
    f.update()
    with patch.object(x.impl,'environment',return_value=(f.checks,f.b,f.ops)):
        return x.validate_native_release(f.request,f.package,f.manifest,f.signed)
class AdmissionTests(unittest.TestCase):
    def test_complete_eight_resource_three_binding_gate(self):
        with tempfile.TemporaryDirectory() as d:
            result=validate(fixture(d))
            self.assertEqual(result['release_sequence'],2026110301)
            self.assertEqual(result['trusted_review_lineage']['final_count'],22)
            self.assertFalse(result['real_player_transaction_performed'])
    def test_missing_cache_binding_rejected(self):
        with tempfile.TemporaryDirectory() as d:
            f=fixture(d);del f.package['source_artifact_pins'][SOURCE]
            with self.assertRaises(ValueError):validate(f)
if __name__=='__main__':unittest.main()
