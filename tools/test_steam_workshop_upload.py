"""Offline SDK ABI and publication/recovery guard tests; no Steam is loaded."""
import ctypes as C
import hashlib
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parent))
import steam_workshop_upload as api


class FakeSteam:
    owner = api.OWNER

    def __init__(self, items=None, legal=False):
        self.items = [{'visibility': 2, **item} for item in (items or [])]
        self.calls = []
        self.legal = legal

    def owned(self):
        return self.items

    def ug(self, name, result, types, *args):
        self.calls.append((name, args))
        if name == 'CreateItem':
            return 123
        raise RuntimeError('Stop before update/content transfer')

    def wait(self, call, cls, callback_id):
        assert cls is api.Created and callback_id == 3403
        response = cls()
        response.result, response.item, response.legal = 1, 9876543210, self.legal
        return response


class UploadGuards(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        self.folder = self.root / 'content'
        self.folder.mkdir()
        self.vpk = self.folder / '1.vpk'
        self.vpk.write_bytes(b'small verified-package fixture')
        self.state = self.root / 'journal.json'
        self.facts = {'content_sha256': 'a' * 64, 'vpk_sha256': api.pack.runtime.digest(self.vpk)}

    def tearDown(self):
        self.tmp.cleanup()

    def invoke(self, steam, *, apply=True):
        with patch.object(api, 'emit'):
            return api.publish(steam, {}, self.root / 'cover.jpg', self.vpk,
                               self.facts, self.state, apply=apply)

    def test_official_win64_struct_layouts(self):
        self.assertEqual((C.sizeof(api.Created), api.Created.item.offset, api.Created.legal.offset), (24, 8, 16))
        self.assertEqual((C.sizeof(api.Submitted), api.Submitted.item.offset, api.Submitted.legal.offset), (16, 8, 4))
        self.assertEqual((C.sizeof(api.Queried), api.Queried.cursor.offset), (280, 21))
        self.assertEqual((C.sizeof(api.Strings), api.Strings.count.offset), (16, 8))

    def test_default_only_reads_even_with_owned_items(self):
        steam = FakeSteam([{'id': '456'}])
        self.assertEqual(self.invoke(steam, apply=False)['status'], 'VERIFIED_NO_PUBLICATION')
        self.assertFalse(steam.calls)
        self.assertFalse(self.state.exists())

    def test_existing_owner_items_prevent_duplicate_create(self):
        steam = FakeSteam([{'id': '456'}])
        with self.assertRaisesRegex(ValueError, 'Existing owned'):
            self.invoke(steam)
        self.assertFalse(steam.calls)

    def test_unknown_pending_create_must_be_recovered(self):
        api.journal(self.state, {'owner': api.OWNER, 'app_id': api.APP,
                    **self.facts, 'workshop_id': None, 'status': 'CREATE_REQUEST_PENDING'})
        steam = FakeSteam()
        with self.assertRaisesRegex(ValueError, 'no confirmed ID'):
            self.invoke(steam)
        self.assertFalse(steam.calls)

    def test_created_id_saved_before_legal_stop(self):
        steam = FakeSteam(legal=True)
        with self.assertRaisesRegex(ValueError, 'accept its Workshop agreement'):
            self.invoke(steam)
        state = json.loads(self.state.read_text(encoding='utf8'))
        self.assertEqual(state['workshop_id'], '9876543210')
        self.assertTrue(state['legal_agreement_required'])
        self.assertEqual([name for name, _ in steam.calls], ['CreateItem'])
        self.assertTrue(self.vpk.exists())

    def test_created_id_survives_update_failure(self):
        steam = FakeSteam()
        with self.assertRaisesRegex(RuntimeError, 'Stop before update'):
            self.invoke(steam)
        self.assertEqual(json.loads(self.state.read_text(encoding='utf8'))['workshop_id'], '9876543210')
        self.assertTrue((self.folder / '9876543210.vpk').exists())
        self.assertEqual([name for name, _ in steam.calls], ['CreateItem', 'StartItemUpdate'])

    def test_resume_requires_owned_confirmed_id(self):
        api.journal(self.state, {'owner': api.OWNER, 'app_id': api.APP,
                    **self.facts, 'workshop_id': '9876543210', 'status': 'PRIVATE_ITEM_CREATED'})
        steam = FakeSteam()
        with self.assertRaisesRegex(ValueError, 'current owner list'):
            self.invoke(steam)
        self.assertFalse(steam.calls)

    def test_recovery_journal_never_in_content(self):
        self.state = self.folder / 'journal.json'
        steam = FakeSteam()
        with self.assertRaisesRegex(ValueError, 'outside the uploaded'):
            self.invoke(steam)
        self.assertFalse(steam.calls)

    def test_os_lock_blocks_concurrent_publication_and_releases(self):
        if sys.platform != 'win32':
            self.skipTest('Reviewed uploader targets Windows x64')
        with api.publication_lock(self.state):
            with self.assertRaises(OSError):
                with api.publication_lock(self.state):
                    self.fail('Second publisher obtained the same state lock')
        with api.publication_lock(self.state):
            pass

    def test_unknown_submit_result_never_resubmits_automatically(self):
        api.journal(self.state, {'owner': api.OWNER, 'app_id': api.APP,
                    **self.facts, 'workshop_id': '9876543210', 'status': 'SUBMIT_REQUEST_PENDING'})
        steam = FakeSteam([{'id': '9876543210', 'owner': api.OWNER}])
        with self.assertRaisesRegex(ValueError, 'Prior submit result is unknown'):
            self.invoke(steam)
        self.assertFalse(steam.calls)

    def test_changed_uploaded_package_requires_explicit_update_and_reuses_confirmed_id(self):
        initial = {'owner': api.OWNER, 'app_id': api.APP, **self.facts,
                   'vpk_sha256': 'old', 'workshop_id': '9876543210',
                   'download_manifest': 'old-manifest', 'download_verified': True,
                   'native_four_archive_reads_verified': True,
                   'status': 'SUBMITTED_PRIVATE_PENDING_DOWNLOAD_AND_NATIVE_TEST', 'uploaded': True}
        api.journal(self.state, initial)
        steam = FakeSteam([{'id': '9876543210', 'owner': api.OWNER}])
        with self.assertRaisesRegex(ValueError, 'update-existing'):
            self.invoke(steam)
        self.assertFalse(steam.calls)
        with patch.object(api, 'emit'), self.assertRaisesRegex(RuntimeError, 'Stop before update'):
            api.publish(steam, {}, self.root / 'cover.jpg', self.vpk,
                        self.facts, self.state, apply=True, update_existing=True)
        state = json.loads(self.state.read_text(encoding='utf8'))
        self.assertEqual(state['workshop_id'], '9876543210')
        self.assertEqual(state['vpk_sha256'], self.facts['vpk_sha256'])
        self.assertFalse(state['uploaded'])
        self.assertNotIn('download_manifest', state)
        self.assertNotIn('download_verified', state)
        self.assertNotIn('native_four_archive_reads_verified', state)
        self.assertEqual([name for name, _ in steam.calls], ['StartItemUpdate'])

    def test_unlisted_requires_existing_explicit_visibility_approval(self):
        steam=FakeSteam()
        listing={'visibility_requested':'unlisted','workshop_id':'9876543210'}
        with patch.object(api,'emit'), self.assertRaisesRegex(ValueError,'Unlisted requires'):
            api.publish(steam,listing,self.root/'cover.jpg',self.vpk,self.facts,self.state,apply=True)
        self.assertFalse(steam.calls)
        api.journal(self.state,{'owner':api.OWNER,'app_id':api.APP,**self.facts,
            'workshop_id':'9876543210','visibility_requested':2,'uploaded':True})
        with patch.object(api,'emit'), self.assertRaisesRegex(ValueError,'explicitly approved visibility'):
            api.publish(steam,listing,self.root/'cover.jpg',self.vpk,self.facts,self.state,apply=True)
        self.assertFalse(steam.calls)

    def test_update_preparation_archives_old_acceptance_before_any_sdk_failure(self):
        older = {'content_sha256': 'earlier-release', 'native_test': 'EARLIER_PASS'}
        evidence = {'native_test': 'VERIFIED_SINGLE_PLAYER_LOGIN_PROFILE_GAMEPLAY',
                    'ordinary_workshop_match': 'VERIFIED_SINGLE_PLAYER_LOGIN_PROFILE_GAMEPLAY',
                    'native_four_archive_reads_verified': True, 'ready_for_public_release': True,
                    'download_verified': True, 'download_manifest': 'old-manifest',
                    'remote_manifest': 'old-remote-manifest', 'reconciliation': {'verified': True},
                    'failed_attempts': [{'release_sequence': 1}], 'multiplayer_acceptance': 'PASS'}
        initial = {'owner': api.OWNER, 'app_id': api.APP, **self.facts, **evidence,
                   'vpk_sha256': 'old-package', 'workshop_id': '9876543210', 'uploaded': True,
                   'status': 'OLD_ACCEPTED_RELEASE', 'previous_release': older,
                   'historical_acceptance': {'native_test': 'EXPLICITLY_HISTORICAL_PASS'}}
        api.journal(self.state, initial)
        steam = FakeSteam([{'id': '9876543210', 'owner': api.OWNER}])
        with patch.object(api, 'emit'), self.assertRaisesRegex(RuntimeError, 'Stop before update'):
            api.publish(steam, {}, self.root / 'cover.jpg', self.vpk,
                        self.facts, self.state, apply=True, update_existing=True)
        state = json.loads(self.state.read_text(encoding='utf8'))
        self.assertEqual(state['status'], 'PRIVATE_ITEM_UPDATE_PREPARED')
        self.assertEqual(state['native_test'], 'NOT_RUN')
        self.assertEqual(state['ordinary_workshop_match'], 'NOT_RUN')
        self.assertFalse(state['ready_for_public_release'])
        self.assertEqual(state['release_history'], [older])
        for name, value in evidence.items():
            self.assertEqual(state['previous_release'][name], value)
            if name not in ('native_test', 'ordinary_workshop_match', 'ready_for_public_release'):
                self.assertNotIn(name, state)
        self.assertEqual(state['previous_release']['vpk_sha256'], 'old-package')
        self.assertEqual(state['historical_acceptance'], initial['historical_acceptance'])
        self.assertEqual([name for name, _ in steam.calls], ['StartItemUpdate'])

    def test_new_signature_sequence_cannot_reuse_same_package_acceptance(self):
        initial = {'owner': api.OWNER, 'app_id': api.APP, **self.facts, 'release_sequence': 1,
                   'workshop_id': '9876543210', 'uploaded': True, 'native_test': 'PASS',
                   'ordinary_workshop_match': 'PASS'}
        api.journal(self.state, initial)
        steam = FakeSteam([{'id': '9876543210', 'owner': api.OWNER}])
        facts = {**self.facts, 'release_sequence': 2}
        with patch.object(api, 'emit'), self.assertRaisesRegex(ValueError, 'new signed release'):
            api.publish(steam, {}, self.root / 'cover.jpg', self.vpk, facts, self.state, apply=True)
        self.assertEqual(json.loads(self.state.read_text(encoding='utf8'))['native_test'], 'PASS')
        with patch.object(api, 'emit'), self.assertRaisesRegex(RuntimeError, 'Stop before update'):
            api.publish(steam, {'workshop_id': '9876543210'}, self.root / 'cover.jpg', self.vpk,
                        facts, self.state, apply=True, update_existing=True)
        state = json.loads(self.state.read_text(encoding='utf8'))
        self.assertEqual(state['release_sequence'], 2)
        self.assertEqual(state['native_test'], 'NOT_RUN')
        self.assertEqual(state['ordinary_workshop_match'], 'NOT_RUN')
        self.assertEqual(state['previous_release']['release_sequence'], 1)
        self.assertEqual(state['previous_release']['native_test'], 'PASS')
    def test_approved_unlisted_never_silently_reverts_to_private_or_public(self):
        api.journal(self.state,{'owner':api.OWNER,'app_id':api.APP,**self.facts,
            'workshop_id':'9876543210','visibility_requested':3,'uploaded':True})
        steam=FakeSteam([{'id':'9876543210','owner':api.OWNER,'visibility':3}])
        for requested in ('private','public','friends_only'):
            with patch.object(api,'emit'), self.assertRaises(ValueError):
                api.publish(steam,{'visibility_requested':requested,'workshop_id':'9876543210'},
                    self.root/'cover.jpg',self.vpk,self.facts,self.state,apply=True)
        self.assertFalse(steam.calls)
        with patch.object(api,'emit'):
            result=api.publish(steam,{'visibility_requested':'unlisted','workshop_id':'9876543210'},
                self.root/'cover.jpg',self.vpk,self.facts,self.state,apply=True)
        self.assertTrue(result['uploaded'])
        self.assertFalse(steam.calls,'same bytes and approved visibility must be idempotent')
        steam.items[0]['visibility']=0
        with patch.object(api,'emit'), self.assertRaisesRegex(ValueError,'Remote visibility differs'):
            api.publish(steam,{'visibility_requested':'unlisted','workshop_id':'9876543210'},
                self.root/'cover.jpg',self.vpk,self.facts,self.state,apply=True)

    def test_approved_unlisted_package_update_preserves_visibility_three(self):
        class UpdatingSteam(FakeSteam):
            def ug(self,name,result,types,*args):
                self.calls.append((name,args))
                if name=='StartItemUpdate': return 99
                if name.startswith('SetItem'): return True
                if name=='SubmitItemUpdate': raise RuntimeError('Stop before submit')
                raise AssertionError(name)
        api.journal(self.state,{'owner':api.OWNER,'app_id':api.APP,**self.facts,
            'vpk_sha256':'old','workshop_id':'9876543210','visibility_requested':3,'uploaded':True})
        steam=UpdatingSteam([{'id':'9876543210','owner':api.OWNER,'visibility':3}])
        listing={'visibility_requested':'unlisted','workshop_id':'9876543210','title':'test','description':'test'}
        with patch.object(api,'emit'), self.assertRaisesRegex(RuntimeError,'Stop before submit'):
            api.publish(steam,listing,self.root/'cover.jpg',self.vpk,{**self.facts,'release_sequence':1},
                self.state,apply=True,update_existing=True)
        visibility_calls=[args for name,args in steam.calls if name=='SetItemVisibility']
        self.assertEqual(visibility_calls,[(99,3)])
        state=json.loads(self.state.read_text(encoding='utf8'))
        self.assertEqual(state['visibility_requested'],3)
        self.assertEqual(state['status'],'SUBMIT_REQUEST_PENDING')

    def test_download_check_requires_approved_visibility(self):
        import verify_workshop_download as verify
        state={'owner':api.OWNER,'app_id':api.APP,'workshop_id':'9876543210',
               'visibility_requested':3,'uploaded':True}
        steam=FakeSteam([{'id':'9876543210','owner':api.OWNER,'visibility':3,'tags':'Custom Game'}])
        self.assertEqual(verify.check(steam,state)['status'],'UNLISTED_ITEM_READ_ONLY_VERIFIED')
        for visibility in (0,2):
            with self.assertRaises(ValueError):verify.check(steam,{**state,'visibility_requested':visibility})
        self.assertFalse(steam.calls,'read-only verification must not alter subscriptions or publish')

    def test_multipart_cannot_create_unknown_item(self):
        self.facts['package_files'] = [{'name': '1.vpk'}, {'name': '1_000.vpk'}]
        steam = FakeSteam()
        with self.assertRaisesRegex(ValueError, 'confirmed existing'):
            self.invoke(steam)
        self.assertFalse(steam.calls)

    def test_new_signed_release_requires_explicit_update_and_exact_listing_id(self):
        api.journal(self.state, {'owner': api.OWNER, 'app_id': api.APP,
            'content_sha256': 'old-release', 'vpk_sha256': 'old-package',
            'workshop_id': '9876543210', 'uploaded': True, 'status': 'SUBMITTED'})
        steam=FakeSteam([{'id':'9876543210','owner':api.OWNER}])
        with self.assertRaisesRegex(ValueError, 'new signed release'):
            self.invoke(steam)
        with patch.object(api,'emit'), self.assertRaisesRegex(ValueError, 'new signed release'):
            api.publish(steam,{'workshop_id':'different'},self.root/'cover.jpg',self.vpk,
                self.facts,self.state,apply=True,update_existing=True)
        self.assertFalse(steam.calls)
        with patch.object(api,'emit'), self.assertRaisesRegex(RuntimeError,'Stop before update'):
            api.publish(steam,{'workshop_id':'9876543210'},self.root/'cover.jpg',self.vpk,
                self.facts,self.state,apply=True,update_existing=True)
        state=json.loads(self.state.read_text(encoding='utf8'))
        self.assertEqual(state['previous_release']['content_sha256'],'old-release')
        self.assertEqual(state['content_sha256'],self.facts['content_sha256'])
        self.assertEqual([name for name,_ in steam.calls],['StartItemUpdate'])

    def test_multipart_archive_tamper_and_extra_file_stop_before_sdk_update(self):
        tree, ordered, _ = api.pack.make_tree([{'path': 'sample.txt', 'bytes': 4}])
        import struct
        import zlib
        struct.pack_into('<IHHIIH', tree, ordered[0]['crc_position'], zlib.crc32(b'data'),
                         0, 0, 0, 4, 0xFFFF)
        prefix = (api.pack.HEADER.pack(api.pack.MAGIC, 2, len(tree), 0, 0, 48, 0) + tree
                  + hashlib.md5(tree).digest() + hashlib.md5(b'').digest())
        self.vpk.write_bytes(prefix + hashlib.md5(prefix).digest())
        volume = self.folder / '1_000.vpk'
        volume.write_bytes(b'data')
        self.facts.update(vpk_sha256=api.pack.runtime.digest(self.vpk),
                          package_files=api.pack.package_inventory(self.vpk))
        api.journal(self.state, {'owner': api.OWNER, 'app_id': api.APP, **self.facts,
                                'workshop_id': '1', 'status': 'PRIVATE_ITEM_UPDATE_PREPARED'})
        steam = FakeSteam([{'id': '1', 'owner': api.OWNER}])
        volume.write_bytes(b'edit')
        with self.assertRaisesRegex(ValueError, 'archives changed'):
            self.invoke(steam)
        self.assertFalse(steam.calls)
        volume.write_bytes(b'data')
        (self.folder / 'extra.txt').write_text('unreviewed')
        with self.assertRaisesRegex(ValueError, 'archives changed'):
            self.invoke(steam)
        self.assertFalse(steam.calls)


if __name__ == '__main__':
    unittest.main()
