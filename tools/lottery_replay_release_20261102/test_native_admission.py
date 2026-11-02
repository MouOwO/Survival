"""Synthetic native-evidence contract only, never actual game/FPS acceptance."""
from pathlib import Path
import copy,importlib.util,tempfile,unittest
from unittest.mock import patch
HERE=Path(__file__).resolve().parent
def load(name,path):
    spec=importlib.util.spec_from_file_location(name,path);module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module);return module
x=load('replay0204_native_contract',HERE/'native_admission.py')
old=load('replay0204_old_fixture',HERE.parent/'lottery_snapshot_release_20261102/test_native_admission.py')


def fixture(folder):
    with patch.object(old.x.impl,'SEQUENCE',2026110204):f=old.fixture(folder)
    extras=('scripts/vscripts/systems/archive_http_adapter.lua','scripts/vscripts/systems/lottery_http_service.lua')
    f.b.PAYLOADS=(*f.b.PAYLOADS,*extras)
    f.package['changed_runtime_paths']=sorted(f.b.PAYLOADS);f.review['runtime_paths']=sorted(f.b.PAYLOADS)
    for name in extras:
        f.package['target_pins'][name]={'sha256':'a'*64};f.package['trusted_review_pins'][name]={'sha256':'a'*64}
    f.review['repeat_previews']=[]
    for index in range(3):
        roles=('animation_a','animation_b','window_after')
        captures={role:f.screen('repeat_'+str(index)+'_'+role,72+index*5+j) for j,role in enumerate(roles)}
        f.review['repeat_previews'].append(dict(pool='map',mode='NO_CONSUMPTION_PREVIEW',captures=captures,
            visual_review=dict(animation_progressed=True,returned_to_lottery_window=True,
                               reviewed_png_sha256=[v['png']['sha256'] for v in captures.values()])))
    f.log+=('[LOTTERY_CINEMATIC] stage=preview pool=map\n[LOTTERY_CINEMATIC] stage=complete pool=map preview=true\n')*3
    f.replace_log(f.log);return f


def validate(f):
    f.update()
    with patch.object(x.impl,'environment',return_value=(f.checks,f.b,f.ops)):
        return x.validate_native_release(f.request,f.package,f.manifest,f.signed)


class RepeatAdmissionTests(unittest.TestCase):
    def test_three_repeats_and_seven_scope_required(self):
        with tempfile.TemporaryDirectory(prefix='replay-admission-contract-') as folder:
            result=validate(fixture(folder))
            self.assertEqual(result['release_sequence'],2026110204)
            self.assertEqual(result['trusted_review_lineage']['final_count'],22)
            self.assertEqual(result['lottery_previews']['same_pool_consecutive_presentations'],3)

    def test_missing_repeat_fake_static_pixel_and_old_scope_rejected(self):
        for kind in ('missing','static','old_scope'):
            with self.subTest(kind=kind),tempfile.TemporaryDirectory(prefix='replay-admission-contract-') as folder:
                f=fixture(folder)
                if kind=='missing':f.review['repeat_previews'].pop()
                elif kind=='static':
                    case=f.review['repeat_previews'][1];case['captures']['animation_b']=copy.deepcopy(case['captures']['animation_a'])
                else:f.b.PAYLOADS=f.b.PAYLOADS[:5]
                with self.assertRaises(ValueError):validate(f)


if __name__=='__main__':unittest.main()
