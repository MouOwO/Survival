"""One-file manifest/CAS regression tests; no real install or merchant calls."""
from contextlib import ExitStack
import base64
import json
from pathlib import Path
import struct
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.dont_write_bytecode=True
sys.path.insert(0,str(Path(__file__).resolve().parent))
import patch_helper_policy as p
sys.path.insert(0,str(p.ROOT/'tools/workshop_test'))
from test_web_auth_candidate import manifest


class PolicyPatchTests(unittest.TestCase):
    def fixture(self):
        old=b'old policy';new=b'reviewed new policy'
        before=manifest({p.POLICY:old,'maps/template_map.vpk':b'frozen map','scripts/vscripts/core/release_policy.lua':b'production'})
        return old,new,before

    def projection(self,before,new):
        with patch.object(p,'BASE_SHA',before['content_sha256']),patch.object(p,'COUNT',3),patch.object(p,'OLD_POLICY_SHA',before['files'][next(i for i,row in enumerate(before['files']) if row['path']==p.POLICY)]['sha256']),patch.object(p,'POLICY_SHA',p.web.sha(new)):
            return p.project(before,new)

    def test_fixed_release_identity_is_small_policy_patch(self):
        self.assertEqual((p.BASE_SEQUENCE,p.SEQUENCE,p.COUNT),(2026102701,2026102702,6639))
        self.assertEqual(p.POLICY_SHA,'6da29c9e100c9bb7c591d7a44b7a333dacad2a7895b98fdf4d1c1415e8afe1c2')
        self.assertNotEqual(p.PATCH,p.BASE)

    def test_projection_changes_only_reviewed_policy_and_preserves_inventory(self):
        old,new,before=self.fixture();after=self.projection(before,new)
        a,b=p.rows(before),p.rows(after)
        self.assertEqual(set(a),set(b));self.assertEqual({name for name in a if a[name]!=b[name]},{p.POLICY})
        self.assertEqual(b['maps/template_map.vpk'],a['maps/template_map.vpk'])
        self.assertEqual(b['scripts/vscripts/core/release_policy.lua'],a['scripts/vscripts/core/release_policy.lua'])
        with self.assertRaises(RuntimeError):p.project(before,new)

    def test_actual_reviewed_policy_passes_production_with_all_debug_modules_absent(self):
        raw=p.policy_source()
        fixture=manifest({p.POLICY:raw,'maps/template_map.vpk':b'frozen'})
        p.preflight(raw,fixture)
        bad=raw.replace(b'local offline = package.loaded["debug/offline_logic_test"]',b'local offline = require("debug/offline_logic_test")')
        with patch.object(p,'POLICY_SHA',p.web.sha(bad)),self.assertRaisesRegex(RuntimeError,'optional_debug'):
            p.preflight(bad,fixture)

    def test_crlf_worktree_source_produces_identical_reviewed_lf_patch(self):
        lf=p.policy_source();crlf=lf.replace(b'\n',b'\r\n')
        self.assertEqual(p.web.sha(lf),p.POLICY_SHA)
        with patch.object(Path,'read_bytes',return_value=crlf):normalized=p.policy_source()
        self.assertEqual(normalized,lf);self.assertEqual(p.web.sha(normalized),p.POLICY_SHA)
        _,_,before=self.fixture()
        self.assertEqual(self.projection(before,normalized),self.projection(before,lf))
        self.assertNotEqual(p.web.sha(crlf),p.POLICY_SHA,'Raw signed/base bytes remain sensitive to line endings')

    def test_missing_external_key_and_conflicting_modes_fail_before_base_read(self):
        with patch.object(p,'authenticate_base',side_effect=AssertionError('no baseline read')):
            with self.assertRaises(RuntimeError):p.run(build=True)
            with self.assertRaises(RuntimeError):p.run(build=True,apply=True,signing_key=Path('never-read'))

    def test_cas_conflict_and_game_running_do_not_replace_file(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory=Path(temporary);target=directory/'policy.lua';target.write_bytes(b'foreign')
            with patch.object(p.install,'require_idle'),self.assertRaises(RuntimeError):
                p.cas(target,p.row_bytes(b'old'),b'new',directory/'transaction')
            self.assertEqual(target.read_bytes(),b'foreign')
            with patch.object(p.install,'require_idle',side_effect=RuntimeError('dota_still_running')),self.assertRaises(RuntimeError):
                p.cas(target,p.row_bytes(b'foreign'),b'new',directory/'transaction')
            self.assertEqual(target.read_bytes(),b'foreign')

    def test_cas_stages_and_replaces_only_its_single_file(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory=Path(temporary);target=directory/'policy.lua';target.write_bytes(b'old')
            untouched=directory/'map.vpk';untouched.write_bytes(b'unchanged')
            with patch.object(p.install,'require_idle'):
                p.cas(target,p.row_bytes(b'old'),b'new',directory/'transaction')
            self.assertEqual(target.read_bytes(),b'new');self.assertEqual(untouched.read_bytes(),b'unchanged')
            self.assertEqual(target.stat().st_nlink,1)

    def test_apply_verifies_full_runtime_before_publishing_marker_and_backs_up_both(self):
        self.transaction_check(fail_after_policy=False)

    def test_failed_post_policy_full_verification_restores_exact_policy_and_marker(self):
        self.transaction_check(fail_after_policy=True)

    def transaction_check(self,fail_after_policy):
        old,new,before=self.fixture();after=self.projection(before,new)
        with tempfile.TemporaryDirectory() as temporary,ExitStack() as stack:
            directory=Path(temporary);root=directory/'root';target=directory/'svt_w24';store=root/'output/arcade_payment_link_20261027/policy_patch_transactions'
            for row in before['files']:
                path=target/row['path'];path.parent.mkdir(parents=True,exist_ok=True)
                path.write_bytes(old if row['path']==p.POLICY else b'frozen map' if row['path']=='maps/template_map.vpk' else b'production')
            old_marker=b'original verified v01 marker';(target/p.install.MARKER).write_bytes(old_marker)
            stack.enter_context(patch.object(p,'ROOT',root));stack.enter_context(patch.object(p,'TARGET',target));stack.enter_context(patch.object(p,'STORE',store))
            stack.enter_context(patch.object(p.install,'SHARED',root/'shared'))
            stack.enter_context(patch.object(p.install,'require_idle'));stack.enter_context(patch.object(p,'target_marker',return_value=old_marker))
            stack.enter_context(patch.object(p,'unchanged'));stack.enter_context(patch.object(p,'signature_for'))
            count=[0]
            def verify(folder,manifest,marker):
                count[0]+=1
                if fail_after_policy and count[0]==3:raise RuntimeError('injected_postimage_failure')
                # This tiny fixture intentionally omits native critical assets.
                # Check every actual signed row and metadata instead of relaxing
                # the production selector used by the real transaction.
                self.assertEqual(p.install.inventory(folder),set(p.rows(manifest))|{p.install.MARKER})
                for name,row in p.rows(manifest).items():p.require_row(folder/name,row)
                p.require_row(folder/p.install.MARKER,p.row_bytes(marker))
                return {}
            stack.enter_context(patch.object(p.install,'verify_runtime',side_effect=verify))
            if fail_after_policy:
                with self.assertRaises(p.install.TransactionFailure) as caught:
                    p.apply_patch(before,after,new,{}, {p.pack.handoff.SIGNATURE:b'{}'})
                self.assertEqual(caught.exception.report['recovery']['status'],'V01_RESTORED_FULLY_VERIFIED')
                self.assertEqual((target/p.POLICY).read_bytes(),old);self.assertEqual((target/p.install.MARKER).read_bytes(),old_marker)
            else:
                result=p.apply_patch(before,after,new,{}, {p.pack.handoff.SIGNATURE:b'{}'})
                self.assertTrue(result['full_after_verification']);self.assertEqual((target/p.POLICY).read_bytes(),new)
                marker=json.loads((target/p.install.MARKER).read_bytes())
                self.assertEqual(marker['content_sha256'],after['content_sha256']);self.assertTrue(marker['full_after_verification'])
            transactions=[path for path in store.iterdir() if path.is_dir()]
            self.assertEqual(len(transactions),1);backup=transactions[0]/'backup'
            self.assertEqual(p.install.inventory(backup),{p.POLICY,p.install.MARKER})
            self.assertEqual((backup/p.POLICY).read_bytes(),old);self.assertEqual((backup/p.install.MARKER).read_bytes(),old_marker)

    def test_readonly_plan_never_creates_patch_or_resolves_private_key(self):
        old,new,before=self.fixture();after=self.projection(before,new)
        with ExitStack() as stack:
            for name,value in [('authenticate_base',(before,{},{})),('project',after),('target_marker',b'marker')]:
                stack.enter_context(patch.object(p,name,return_value=value))
            stack.enter_context(patch.object(p,'path_at',return_value=Path('fixture')))
            stack.enter_context(patch.object(Path,'read_bytes',return_value=new))
            for name in ('preflight','unchanged'):stack.enter_context(patch.object(p,name))
            stack.enter_context(patch.object(p.install,'verify_runtime'))
            stack.enter_context(patch.object(p.install,'dota_pids',return_value=[]))
            for owner,name in [(Path,'mkdir'),(p.pack.protect_data,'external'),(p.pack.protect_data,'sign_manifest'),(p,'apply_patch')]:
                stack.enter_context(patch.object(owner,name,side_effect=AssertionError('readonly mutation/key access')))
            result=p.run(signing_key=Path('never-read.pem'))
        self.assertEqual(result['status'],'READ_ONLY_POLICY_PATCH_PLAN')
        self.assertFalse(result['actual_payment_verified'])


if __name__=='__main__':unittest.main(verbosity=2)
