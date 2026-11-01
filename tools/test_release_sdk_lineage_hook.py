"""Offline common-boundary regressions; zero Steam DLL or SDK calls."""
import ctypes as C
import hashlib
import importlib.util
import json
from pathlib import Path
import sys
import tempfile
import types
import unittest
from unittest.mock import patch

TOOLS = Path(__file__).resolve().parent
sys.path.insert(0, str(TOOLS))
import release_sdk_lineage_hook as hook

spec = importlib.util.spec_from_file_location('lineage_hook_test_sdk', TOOLS/'steam_workshop_upload.py')
sdk = importlib.util.module_from_spec(spec)
spec.loader.exec_module(sdk)


class Native:
    def __init__(self): self.calls=[]
    def __call__(self,*values): self.calls.append(values); return 701


class Guard:
    def __init__(self): self.active=False;self.calls=[];self.observed=[]
    def require_sdk_mutation(self,suffix,values,**options):
        if not self.active: raise RuntimeError('lease_required')
        self.calls.append((suffix,values,options))
        return types.SimpleNamespace(observe_result=self.observed.append)
    def before_journal_write(self,path,value,**options):
        if not self.active: raise RuntimeError('lease_required')
        self.calls.append(('journal',path,dict(value)))
    def after_journal_write(self,path,digest,**options):
        self.calls.append(('journal_committed',path,digest))


class BoundaryTests(unittest.TestCase):
    def setUp(self):
        self.guard=Guard();self.native=Native()
        self.patch=patch.object(hook,'AUTHORITY_SHA256','a'*64);self.patch.start();self.addCleanup(self.patch.stop)
        self.import_patch=patch.object(hook.importlib,'import_module',return_value=self.guard)
        self.import_patch.start();self.addCleanup(self.import_patch.stop)

    def test_missing_lease_prevents_every_publication_family(self):
        for suffix in ['CreateItem','StartItemUpdate','SetItemTitle','SetItemDescription',
                       'SetItemContent','SetItemPreview','SetItemVisibility','SetItemTags',
                       'SubmitItemUpdate','DeleteItem','AddItemPreviewFile','UpdateItemPreviewFile',
                       'RemoveItemPreview','AddDependency','RemoveAppDependency','SetUserItemVote',
                       'SetAllowLegacyUpload','AddContentDescriptor','RemoveContentDescriptor',
                       'AddKeyValueTag','RemoveKeyValueTags','FutureUnknownUGCMutation']:
            with self.subTest(suffix=suffix),self.assertRaisesRegex(RuntimeError,'lease_required'):
                hook.wrap_sdk_function('SteamAPI_ISteamUGC_'+suffix,self.native)(111,570,3824360109)
        self.assertEqual(self.native.calls,[])

    def test_uncertain_authority_fails_before_native(self):
        with patch.object(hook,'AUTHORITY_SHA256',None),self.assertRaisesRegex(RuntimeError,'not_configured'):
            hook.wrap_sdk_function('SteamAPI_ISteamUGC_StartItemUpdate',self.native)(111,570,3824360109)
        self.assertEqual(self.native.calls,[])

    def test_missing_or_malformed_guard_permit_never_reaches_native(self):
        for permit in [None,object(),types.SimpleNamespace(observe_result=None)]:
            with patch.object(self.guard,'require_sdk_mutation',return_value=permit):
                with self.assertRaisesRegex(RuntimeError,'unregistered_ugc'):
                    hook.wrap_sdk_function('SteamAPI_ISteamUGC_FutureUnknown',self.native)(111,701)
        self.assertEqual(self.native.calls,[])

    def test_cached_function_checks_live_lease_and_records_actual_result(self):
        saved=hook.wrap_sdk_function('SteamAPI_ISteamUGC_StartItemUpdate',self.native)
        self.guard.active=True
        self.assertEqual(saved(111,570,3824360109),701)
        self.assertEqual(self.guard.calls[0][1],(570,3824360109))
        self.assertEqual(self.guard.observed,[701])
        self.guard.active=False
        with self.assertRaisesRegex(RuntimeError,'lease_required'): saved(111,570,3824360109)
        self.assertEqual(len(self.native.calls),1)

    def test_query_download_and_init_do_not_need_authority(self):
        with patch.object(hook,'AUTHORITY_SHA256',None):
            for name in ['SteamAPI_InitFlat','SteamAPI_ISteamUGC_GetItemState',
                         'SteamAPI_ISteamUGC_CreateQueryUGCDetailsRequest',
                         'SteamAPI_ISteamUGC_SetAllowCachedResponse','SteamAPI_ISteamUGC_SetReturnMetadata',
                         'SteamAPI_ISteamUGC_DownloadItem','SteamAPI_ISteamUGC_SubscribeItem']:
                self.assertIs(hook.wrap_sdk_function(name,self.native),self.native)
        self.assertEqual(self.guard.calls,[])

    def test_actual_common_fn_cannot_bypass_gate(self):
        steam=sdk.Steam();steam.dll=types.SimpleNamespace(SteamAPI_ISteamUGC_StartItemUpdate=self.native)
        saved=steam.fn('SteamAPI_ISteamUGC_StartItemUpdate',C.c_uint64,[C.c_void_p,C.c_uint32,C.c_uint64])
        with self.assertRaisesRegex(RuntimeError,'lease_required'):saved(111,570,3824360109)
        self.assertEqual(self.native.calls,[])

    def test_unleased_canonical_journal_never_creates_or_overwrites_file(self):
        with tempfile.TemporaryDirectory() as directory:
            path=Path(directory)/'canonical.json'
            with patch.object(hook,'CANONICAL_JOURNAL',path):
                with self.assertRaisesRegex(RuntimeError,'lease_required'):sdk.journal(path,{'status':'PENDING'})
                self.assertFalse(path.exists());self.assertFalse(path.with_name('canonical.json.part').exists())
                path.write_bytes(b'ORIGINAL')
                with self.assertRaisesRegex(RuntimeError,'lease_required'):sdk.journal(path,{'status':'PENDING'})
                self.assertEqual(path.read_bytes(),b'ORIGINAL')

    def test_leased_canonical_journal_reports_actual_written_hash(self):
        self.guard.active=True
        with tempfile.TemporaryDirectory() as directory:
            path=Path(directory)/'canonical.json'
            with patch.object(hook,'CANONICAL_JOURNAL',path):sdk.journal(path,{'status':'PENDING'})
            self.assertEqual(self.guard.calls[-1],('journal_committed',path,hashlib.sha256(path.read_bytes()).hexdigest()))
            self.assertEqual(json.loads(path.read_bytes())['status'],'PENDING')

    def test_noncanonical_diagnostic_report_is_not_a_publication(self):
        with tempfile.TemporaryDirectory() as directory,patch.object(hook,'AUTHORITY_SHA256',None):
            path=Path(directory)/'diagnostic.json';sdk.journal(path,{'ok':True})
            self.assertTrue(json.loads(path.read_bytes())['ok'])
        self.assertEqual(self.guard.calls,[])


if __name__=='__main__':unittest.main()
