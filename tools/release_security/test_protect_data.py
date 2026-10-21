import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest import mock

from cryptography.exceptions import InvalidSignature,InvalidTag

spec=importlib.util.spec_from_file_location('protect_data',Path(__file__).with_name('protect_data.py'))
protection=importlib.util.module_from_spec(spec);spec.loader.exec_module(protection)


class ProtectionTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.addCleanup(self.temp.cleanup)
        self.base=Path(self.temp.name);self.source=self.base/'source';self.source.mkdir()
        self.keys=self.base/'keys';protection.initialize_keys(self.keys)
        self.key=self.keys/'data-key.bin';self.vault=self.base/'vault.svault'
        self.name='data/csv/怪物/波次.csv';path=self.source/self.name;path.parent.mkdir(parents=True);path.write_bytes('id,名称,生命\n1,测试怪,2500\n'.encode('utf-8'))
        self.original=path.read_bytes()

    def make(self,target=None):return protection.make_vault(self.source,[self.name],target or self.vault,self.key)

    def test_real_encryption_verification_and_lossless_restore(self):
        result=self.make();self.assertEqual(result['files'],1)
        self.assertNotIn(self.original,self.vault.read_bytes())
        self.assertTrue(protection.verify_vault(self.vault,self.key)['verified'])
        destination=self.base/'restore';protection.verify_vault(self.vault,self.key,destination)
        self.assertEqual((destination/self.name).read_bytes(),self.original)
        self.assertEqual((self.source/self.name).read_bytes(),self.original)

    def test_wrong_key_tamper_and_truncation_never_restore(self):
        self.make();second=self.base/'second_keys';protection.initialize_keys(second)
        with self.assertRaises(ValueError):protection.verify_vault(self.vault,second/'data-key.bin')
        data=self.vault.read_bytes();tampered=self.base/'tampered.svault'
        tampered.write_bytes(data[:-1]+bytes([data[-1]^1]));destination=self.base/'never_created'
        with self.assertRaises(InvalidTag):protection.verify_vault(tampered,self.key,destination)
        self.assertFalse(destination.exists())
        tampered.write_bytes(data[:20])
        with self.assertRaises(Exception):protection.verify_vault(tampered,self.key,destination)
        self.assertFalse(destination.exists())

    def test_independent_nonces_and_no_overwrite(self):
        self.make();second=self.base/'second.svault';self.make(second)
        self.assertNotEqual(self.vault.read_bytes(),second.read_bytes())
        for path in (self.vault,second):self.assertTrue(protection.verify_vault(path,self.key)['verified'])
        with self.assertRaises(ValueError):self.make()
        with self.assertRaises(ValueError):protection.initialize_keys(self.keys)
        with self.assertRaises(ValueError):protection.verify_vault(self.vault,self.key,self.source)

    def test_paths_case_duplicates_and_private_boundary(self):
        for names in (['../outside.csv'],['/absolute.csv'],[self.name,self.name.upper()]):
            with self.subTest(names=names),self.assertRaises(ValueError):protection.make_vault(self.source,names,self.vault,self.key)
        with self.assertRaises(ValueError):protection.external(protection.ROOT/'output/private')
        with self.assertRaises(ValueError):protection.external(self.source/'backup',self.source)
        with self.assertRaises(ValueError):protection.external(Path('relative'))

    def test_authenticated_header_cannot_be_relabelled(self):
        self.make();raw=self.vault.read_bytes();edited=raw.replace(b'source_backup_not_game_runtime',b'FAKE__backup_not_game_runtime',1)
        self.assertNotEqual(raw,edited);path=self.base/'header.svault';path.write_bytes(edited)
        with self.assertRaises(Exception):protection.verify_vault(path,self.key)

    def manifest(self):
        row={'path':'scripts/vscripts/config/generated/monster.lua','bytes':3,'md5':hashlib.md5(b'abc').hexdigest(),'sha256':hashlib.sha256(b'abc').hexdigest()}
        data={'schema':2,'kind':'runtime_release_allowlist','hash_algorithms':['md5','sha256'],'file_count':1,'bytes':3,'files':[row]}
        data['content_sha256']=hashlib.sha256(protection.release_api().manifest_payload(data)).hexdigest()
        path=self.base/'manifest.json';path.write_text(json.dumps(data),encoding='utf-8');return path,data

    def test_signatures_bind_file_inventory_and_pinned_identity(self):
        manifest,data=self.manifest();signature=self.base/'signature.json'
        protection.sign_manifest(manifest,self.keys/'signing-key.pem',signature)
        self.assertTrue(protection.verify_signature(manifest,signature,self.keys/'public-key.pem')['signature_valid'])
        other=self.base/'other_keys';protection.initialize_keys(other)
        with self.assertRaises(ValueError):protection.verify_signature(manifest,signature,other/'public-key.pem')
        # Even recomputing the public digest cannot forge the publisher signature.
        data['files'][0]['path']='scripts/vscripts/config/generated/fake.lua'
        data['content_sha256']=hashlib.sha256(protection.release_api().manifest_payload(data)).hexdigest()
        manifest.write_text(json.dumps(data),encoding='utf-8')
        document=json.loads(signature.read_text());document['content_sha256']=data['content_sha256'];signature.write_text(json.dumps(document),encoding='utf-8')
        with self.assertRaises(InvalidSignature):protection.verify_signature(manifest,signature,self.keys/'public-key.pem')

    def test_public_key_line_endings_do_not_change_identity(self):
        manifest,_=self.manifest();signature=self.base/'signature.json'
        protection.sign_manifest(manifest,self.keys/'signing-key.pem',signature)
        public=self.base/'public_crlf.pem';public.write_bytes((self.keys/'public-key.pem').read_bytes().replace(b'\n',b'\r\n'))
        self.assertTrue(protection.verify_signature(manifest,signature,public)['signature_valid'])

    def test_windows_aliases_are_rejected(self):
        for name in ['data/wave.','data/wave ','data/CON.csv','data/con','data/LPT1.csv','data/AUX.lua','.. /outside.csv']:
            with self.subTest(name=name):self.assertFalse(protection.safe_name(name))

    def test_unreadable_csv_is_not_silently_omitted(self):
        def denied(*args,**kwargs):
            kwargs['onerror'](PermissionError('fixture unreadable CSV'))
            yield
        with mock.patch.object(protection.os,'walk',denied),self.assertRaises(PermissionError):protection.collect_sources(self.source)

    def test_failed_restore_never_publishes_a_partial_tree(self):
        self.make();destination=self.base/'restored'
        with mock.patch.object(protection.shutil,'copyfileobj',side_effect=OSError('fixture disk full')),self.assertRaises(OSError):protection.verify_vault(self.vault,self.key,destination)
        self.assertFalse(destination.exists())
        self.assertTrue(protection.verify_vault(self.vault,self.key,destination)['verified'])

    def test_signed_release_sequence_cannot_be_lowered_or_forged(self):
        manifest,_=self.manifest();signature=self.base/'signature.json'
        protection.sign_manifest(manifest,self.keys/'signing-key.pem',signature,sequence=10)
        with self.assertRaises(ValueError):protection.verify_signature(manifest,signature,self.keys/'public-key.pem',minimum_sequence=11)
        document=json.loads(signature.read_text());document['release_sequence']=11;signature.write_text(json.dumps(document),encoding='utf-8')
        with self.assertRaises(InvalidSignature):protection.verify_signature(manifest,signature,self.keys/'public-key.pem',minimum_sequence=11)


if __name__=='__main__':unittest.main()
