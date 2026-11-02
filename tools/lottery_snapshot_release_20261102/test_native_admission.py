"""Complete thin-adapter admission with synthetic receipts only;0native/SDK."""
from pathlib import Path
from contextlib import redirect_stdout
from unittest.mock import patch
import copy,importlib.util,io,json,tempfile,unittest

HERE=Path(__file__).resolve().parent
def load(name,path):
    spec=importlib.util.spec_from_file_location(name,path);value=importlib.util.module_from_spec(spec)
    spec.loader.exec_module(value);return value
x=load('snapshot0203_native_contract',HERE/'native_admission.py')
old=load('snapshot0203_private0202_test_fixtures',HERE.parent/'lottery_hotfix_release_20261102/test_native_admission.py')


def fixture(temp):
    with patch.multiple(old.x,SEQUENCE=x.SEQUENCE,KIND=x.KIND,SCOPE=x.SCOPE):f=old.Fixture(temp)
    f.b.PAYLOADS=(*f.b.PAYLOADS,x.ARCHIVE)
    f.package['changed_runtime_paths']=sorted(f.b.PAYLOADS)
    f.package['target_pins'][x.ARCHIVE]={'sha256':x.ARCHIVE_SHA}
    f.package['trusted_review_pins'][x.ARCHIVE]={'sha256':x.ARCHIVE_SHA}
    f.review['runtime_paths']=sorted(f.b.PAYLOADS)
    roles=('n1_gameplay','archive_open')
    captures={role:f.screen('snapshot_'+role,second)for role,second in zip(roles,(65,70))}
    f.review['cold_archive']=dict(kind='COLD_ORDINARY_N1_ARCHIVE_UI',mode_id='standard',difficulty_id='n1',
        fresh_process_no_map_reload=True,opened_via_normal_ui=True,displayed_category_id='clear',captures=captures,
        visual_review=dict(n1_gameplay_confirmed=True,normal_archive_window_open=True,normal_archive_tabs_visible=True,actual_rows_and_values_visible=True,
            not_loading_or_placeholder=True,no_ui_stall=True,
            reviewed_png_sha256=[ref['png']['sha256']for ref in captures.values()]))
    f.log+='ARCHIVE_AUDIT '+json.dumps(dict(open=True,hidden=False,visible=True,category='clear',rows=9,status=''))+'\n'
    f.replace_log(f.log)
    return f


def validate(f):
    f.update()
    with patch.object(x.impl,'environment',return_value=(f.checks,f.b,f.ops)):
        return x.validate_native_release(f.request,f.package,f.manifest,f.signed)


class SnapshotNativeTests(unittest.TestCase):
    def test_complete_positive_scope5_preserves_four_pool_gate_and_adds_cold_archive(self):
        with tempfile.TemporaryDirectory(prefix='snapshot-native-contract-')as temp:
            f=fixture(temp);result=validate(f)
            self.assertTrue(result['ordinary_production_acceptance'])
            self.assertEqual(result['release_sequence'],2026110203)
            self.assertEqual(result['trusted_review_lineage']['final_count'],20)
            self.assertEqual(result['trusted_review_lineage']['unchanged_parent_count'],17)
            self.assertEqual(result['lottery_previews']['cold_archive']['optional_native_audit_rows'],9)
            self.assertFalse(result['native_fps_measured']);self.assertFalse(result['real_player_transaction_performed'])
            f.ops.p.full_vpk.assert_called_once()

    def test_complete_negative_archive_package_and_native_scope(self):
        changes={
            'old0202_signed':lambda f:f.signed.update(release_sequence=2026110202),
            'old_four_scope':lambda f:f.b.__dict__.update(PAYLOADS=f.b.PAYLOADS[:4]),
            'missing_cold_archive':lambda f:f.review.pop('cold_archive'),
            'non_n1':lambda f:f.review['cold_archive'].update(difficulty_id='n2'),
            'not_cold':lambda f:f.review['cold_archive'].update(fresh_process_no_map_reload=False),
            'not_ui_open':lambda f:f.review['cold_archive'].update(opened_via_normal_ui=False),
            'placeholder':lambda f:f.review['cold_archive']['visual_review'].update(actual_rows_and_values_visible=False),
            'wrong_pixel_review':lambda f:f.review['cold_archive']['visual_review'].update(reviewed_png_sha256=['f'*64]*3),
            'missing_tabs':lambda f:f.review['cold_archive']['visual_review'].update(normal_archive_tabs_visible=False),
            'invalid_category':lambda f:f.review['cold_archive'].update(displayed_category_id='../points'),
            'cold_serialize_failure':lambda f:f.replace_log('Failed to serialize CUserMsg_CustomGameEvent [148]\n'+f.log),
            'reliable_oversize':lambda f:f.replace_log(f.log+'SendData reliable data too big\n'),
            'changed_archive_bytes':lambda f:f.package['target_pins'][x.ARCHIVE].update(sha256='e'*64),
            'old_review_drift':lambda f:f.package['trusted_review_pins'].update({'scripts/vscripts/synthetic_review_00.lua':{'sha256':'e'*64}}),
            'missing_pool':lambda f:f.review['lottery_previews'].pop('summer'),
            'real_ticket_spend':lambda f:f.review['lottery_previews']['map'].update(tickets_after=1),
            'fake_exit':lambda f:f.change_receipt('hold_end',lambda row:row['process_lifetime'].update(exit_observed=False)),
            'missing_restore':lambda f:f.change_receipt('restored',lambda row:row.update(original_files=[])),
        }
        for label,change in changes.items():
            with self.subTest(label=label),tempfile.TemporaryDirectory(prefix='snapshot-native-contract-')as temp:
                f=fixture(temp);change(f)
                with self.assertRaises((ValueError,KeyError,TypeError)):validate(f)

    def test_archive_native_footage_must_be_chronological_inside_observations(self):
        for label,change in {
            'before_n1':lambda f:f.review['cold_archive']['captures'].update(archive_open=f.screen('early',64)),
            'after_native_inspection':lambda f:f.review['cold_archive']['captures'].update(archive_open=f.screen('late',95)),
        }.items():
            with self.subTest(label=label),tempfile.TemporaryDirectory(prefix='snapshot-native-contract-')as temp:
                f=fixture(temp);change(f)
                # Bind the altered real fixture captures so chronology is the
                # failing predicate, not a stale reviewed-image digest.
                case=f.review['cold_archive'];case['visual_review']['reviewed_png_sha256']=[case['captures'][role]['png']['sha256']
                    for role in ('n1_gameplay','archive_open')]
                with self.assertRaises(ValueError):validate(f)

    def test_normal_ui_and_full_fatal_log_need_no_tools_or_new_wire_summary(self):
        with tempfile.TemporaryDirectory(prefix='snapshot-native-contract-')as temp:
            f=fixture(temp);f.replace_log(f.log.split('ARCHIVE_AUDIT ')[0]);result=validate(f)
            proof=result['lottery_previews']['cold_archive']
            self.assertIsNone(proof['optional_native_audit_rows'])
            self.assertTrue(proof['actual_rows_and_tabs_root_reviewed'])
            self.assertFalse(proof['tools_page_summary_required'])

    def test_static_default_has_no_package_or_native_actions(self):
        with patch.object(x.impl,'environment',side_effect=AssertionError('No package or native query')),redirect_stdout(io.StringIO())as output:
            self.assertEqual(x.main([]),0)
        self.assertEqual(json.loads(output.getvalue())['native_actions'],0)

    def test_old_capture_generation_cannot_replace_cold_candidate_footage(self):
        with tempfile.TemporaryDirectory(prefix='snapshot-native-contract-')as temp:
            f=fixture(temp);ref=f.review['cold_archive']['captures']['n1_gameplay']['metadata']
            value=json.loads(Path(ref['path']).read_bytes());value['process_created_utc']=old.utc(0)
            f.review['cold_archive']['captures']['n1_gameplay']['metadata']=f.save(Path(ref['path']),value)
            with self.assertRaisesRegex(ValueError,'ordinary screenshot'):validate(f)


if __name__=='__main__':unittest.main()
