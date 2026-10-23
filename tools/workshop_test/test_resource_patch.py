"""Verify audit-driven patches accept only pinned, exact frozen resources."""
import hashlib
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import zipfile

import build_resource_patch as repair
import local_host as host


class ResourcePatchChecks(unittest.TestCase):
    def test_patch_verifies_all_bytes_and_rejects_unknown_or_incomplete_audits(self):
        with tempfile.TemporaryDirectory() as temporary:
            root=Path(temporary);bundle=root/'bundle';source=bundle/host.ADDON;source.mkdir(parents=True)
            files={'addoninfo.txt':b'frozen addon','one.txt':b'correct frozen payload'}
            runtime=host.expected_manifest({'files':[]},files)
            for name,raw in files.items():(source/name).write_bytes(raw)
            marker=json.dumps({'kind':'WS4-LOCAL-1','base_content_sha256':host.BASE_SHA,'runtime':runtime}).encode()
            (bundle/'client_manifest.json').write_bytes(marker)
            audit=root/'audit.json'
            report={'status':'CLIENT_RESOURCE_AUDIT_COMPLETE','files':2,'issue_count':1,'issues':[{'path':'one.txt'}]}
            audit.write_text(json.dumps(report),encoding='utf8')
            with patch.object(repair,'MANIFEST_SHA256',hashlib.sha256(marker).hexdigest()):
                archive=root/'repair.zip'
                result=repair.build(bundle,audit,archive,('addoninfo.txt',))
                self.assertEqual(result['resources'],2)
                self.assertTrue(result['all_entry_hashes_verified'])
                self.assertTrue(result['legacy_zip_without_zip64'])
                with zipfile.ZipFile(archive) as z:
                    self.assertEqual(z.read(host.ADDON+'/one.txt'),files['one.txt'])
                    self.assertEqual(z.read(host.ADDON+'/addoninfo.txt'),files['addoninfo.txt'])
                    self.assertIn('check_resources.cmd',z.namelist())
                    self.assertIn(hashlib.sha256(marker).hexdigest(),z.read('join_client.ps1').decode('utf-8-sig'))
                report['issues']=[{'path':'../private.txt'}];audit.write_text(json.dumps(report),encoding='utf8')
                rejected=root/'unknown.zip'
                with self.assertRaisesRegex(host.LocalError,'patch_unknown_resource'):repair.build(bundle,audit,rejected)
                self.assertFalse(rejected.exists())
                report['issue_count']=2;audit.write_text(json.dumps(report),encoding='utf8')
                with self.assertRaisesRegex(host.LocalError,'patch_audit_incomplete'):repair.build(bundle,audit,rejected)
                self.assertFalse(rejected.exists())
                report['issue_count']=1;report['issues']=[{'path':'one.txt'}]
                audit.write_text(json.dumps(report),encoding='utf8')
                (source/'one.txt').write_bytes(b'do not distribute this changed file')
                with self.assertRaisesRegex(host.LocalError,'patch_source_bytes_changed'):
                    repair.build(bundle,audit,root/'changed.zip')
                self.assertEqual((source/'one.txt').read_bytes(),b'do not distribute this changed file')


if __name__=='__main__':unittest.main()
