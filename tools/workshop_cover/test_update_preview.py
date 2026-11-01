from pathlib import Path
from types import SimpleNamespace
from unittest import TestCase,main,mock
import json,sys,tempfile
sys.path.insert(0,str(Path(__file__).resolve().parent))
import update_preview as app

class FakeSteam:
    def __init__(self,path):self.path=path;self.calls=[];self.timeout=False
    def ug(self,name,*args):
        self.calls.append(name)
        if name=='SubmitItemUpdate':
            assert json.loads(self.path.read_bytes())['status']=='SUBMIT_REQUEST_PENDING'
            return 11
        return 10 if name=='StartItemUpdate' else True
    def wait(self,*args,**kwargs):
        if self.timeout:raise TimeoutError('simulated unknown result')
        return SimpleNamespace(item=app.ITEM,legal=False)

class PreviewTests(TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.addCleanup(self.temp.cleanup)
        self.path=Path(self.temp.name)/'state.json';self.steam=FakeSteam(self.path)
        self.before={key:'same' for key in app.PROTECTED};self.before['visibility']=3
        self.after=dict(self.before,preview_url='new')
        self.facts={'sha256':'a'*64,'bytes':1,'width':1672,'height':941}
    def submit(self):return app.submit_preview(self.steam,Path('approved.jpg'),self.path)
    def patches(self):
        return mock.patch.object(app,'image_facts',return_value=self.facts),mock.patch.object(app,'fresh_item',side_effect=[self.before,self.after])
    def test_only_preview_setter_and_no_content_or_visibility_changes(self):
        image,query=self.patches()
        with image,query:result=self.submit()
        self.assertEqual(self.steam.calls,['StartItemUpdate','SetItemPreview','SubmitItemUpdate'])
        self.assertEqual(result['protected_fields_changed'],[])
        self.assertEqual(result['status'],'PREVIEW_SUBMITTED_VERIFY_IMAGE')
    def test_pending_is_journaled_and_never_automatically_resubmitted(self):
        self.steam.timeout=True;image,query=self.patches()
        with image,query:
            with self.assertRaises(TimeoutError):self.submit()
            self.assertEqual(json.loads(self.path.read_bytes())['status'],'SUBMIT_REQUEST_PENDING')
            calls=list(self.steam.calls)
            with self.assertRaisesRegex(RuntimeError,'verification_not_resubmit'):self.submit()
            self.assertEqual(self.steam.calls,calls)
    def test_completed_submission_also_cannot_be_repeated(self):
        image,query=self.patches()
        with image,query:
            self.submit();calls=list(self.steam.calls)
            with self.assertRaisesRegex(RuntimeError,'verification_not_resubmit'):self.submit()
            self.assertEqual(self.steam.calls,calls)
    def test_unexpected_metadata_change_is_retained_and_reported(self):
        self.after['total_files_bytes']='changed';image,query=self.patches()
        with image,query:
            with self.assertRaisesRegex(RuntimeError,'unexpected_workshop_content'):self.submit()
        self.assertEqual(json.loads(self.path.read_bytes())['protected_fields_changed'],['total_files_bytes'])
    def test_other_visibility_is_rejected_before_mutation(self):
        self.before['visibility']=0;image,query=self.patches()
        with image,query:
            with self.assertRaisesRegex(RuntimeError,'unlisted_visibility'):self.submit()
        self.assertEqual(self.steam.calls,[])
    def test_real_approved_jpeg_and_size_guard(self):
        facts=app.image_facts(app.COVER)
        self.assertEqual((facts['width'],facts['height']),(1672,941))
        self.assertLess(facts['bytes'],1_000_000)
        oversized=Path(self.temp.name)/'large.jpg';oversized.write_bytes(b'0'*1_000_000)
        with self.assertRaisesRegex(ValueError,'below_one_megabyte'):app.image_facts(oversized)
    def test_verification_downloads_exact_approved_bytes_without_remote_mutation(self):
        self.facts=app.image_facts(app.COVER);image,query=self.patches()
        with image,query:self.submit()
        self.steam.calls.clear()
        with mock.patch.object(app,'fresh_item',return_value=self.after),mock.patch.object(app,'download_preview',return_value=app.COVER.read_bytes()):
            result=app.verify_preview(self.steam,self.path)
        self.assertEqual(self.steam.calls,[])
        self.assertTrue(result['remote_preview_verified'])
        self.assertEqual(result['status'],'PREVIEW_VERIFIED_CDN')
    def test_wrong_cdn_and_wrong_remote_bytes_are_rejected(self):
        with self.assertRaisesRegex(ValueError,'official_preview_cdn'):app.download_preview('https://example.com/a.jpg')
        self.facts=app.image_facts(app.COVER);image,query=self.patches()
        with image,query:self.submit()
        with mock.patch.object(app,'fresh_item',return_value=self.after),mock.patch.object(app,'download_preview',return_value=b'old'):
            with self.assertRaisesRegex(RuntimeError,'do_not_match'):app.verify_preview(self.steam,self.path)

if __name__=='__main__':main()
