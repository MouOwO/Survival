"""Check guest packaging boundaries with a real tiny frozen-file fixture."""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

import build_join_client as guest
import local_host as host


class GuestPackageChecks(unittest.TestCase):
    @unittest.skipUnless(os.name=='nt','Windows PowerShell integration')
    def test_guest_installs_resumes_and_preserves_changed_files_without_launching(self):
        with tempfile.TemporaryDirectory() as temporary:
            folder=Path(temporary);stage=folder/'stage';stage.mkdir()
            file_name='panorama/images/spell icon.vtex_c'
            raw=b'frozen guest installation fixture'
            expected=host.expected_manifest({'files':[]},{file_name:raw})
            source=stage/file_name;source.parent.mkdir(parents=True);source.write_bytes(raw)
            (stage/host.INSTALL_MANIFEST).write_text(json.dumps({'kind':'WS4-LOCAL-1',
                'base_content_sha256':host.BASE_SHA,'runtime':expected}),encoding='utf8')
            destination=folder/'guest'
            with patch.object(host,'STAGE',stage),patch.object(host,'baseline',return_value={}), \
                    patch.object(host,'overlay',return_value={}),patch.object(host,'expected_manifest',return_value=expected):
                guest.build(destination,'26.1.2.3:27015')
            # This fixture contains no real credentials; expose its exception
            # only to the harness so installation failures remain diagnosable.
            fixture_script=destination/'join_client.ps1'
            text=fixture_script.read_text(encoding='utf-8-sig')
            fixture_script.write_text(text.replace('$message = $_.Exception.Message',
                "Write-Output ('FIXTURE_ERROR:' + $_.Exception.Message)\n    $message = $_.Exception.Message"),encoding='utf-8-sig')
            game=folder/'dota 2 beta/game';exe=game/'bin/win64/dota2.exe'
            exe.parent.mkdir(parents=True);exe.write_bytes(b'not executable - process launch is mocked')
            (game/'dota').mkdir()
            capture=folder/'captured_launch.json'
            quote=lambda p:"'"+str(p).replace("'","''")+"'"
            wrapper=folder/'run_fixture.ps1'
            wrapper.write_text("$ErrorActionPreference='Stop'\n"
                "function Get-Process { [CmdletBinding()]param([string]$Name); return $null }\n"
                "function Start-Process { [CmdletBinding()]param([string]$FilePath,[string[]]$ArgumentList,[string]$WorkingDirectory); "
                "@{args=$ArgumentList;exe=$FilePath} | ConvertTo-Json | Set-Content -Encoding UTF8 -LiteralPath "+quote(capture)+" }\n"
                "$global:LASTEXITCODE=0\n& "+quote(destination/'join_client.ps1')+" -GamePath "+quote(game)+"\nexit $LASTEXITCODE\n",encoding='utf-8-sig')
            def run():
                environment=dict(os.environ)
                # A Python child of pwsh inherits its incompatible PowerShell 7
                # module path. Use Windows PowerShell's own standard modules.
                environment['PSModulePath']=';'.join((str(Path(os.environ['ProgramFiles'])/'WindowsPowerShell/Modules'),
                    str(Path(os.environ['SystemRoot'])/'System32/WindowsPowerShell/v1.0/Modules')))
                return subprocess.run(['powershell.exe','-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',str(wrapper)],
                    capture_output=True,text=True,encoding='utf8',errors='replace',timeout=30,env=environment)
            first=run();self.assertEqual(first.returncode,0,first.stdout+first.stderr)
            installed=game/'dota_addons'/host.ADDON/file_name
            self.assertTrue(installed.exists(),first.stdout+first.stderr)
            self.assertEqual(installed.read_bytes(),raw)
            self.assertEqual((game.parent/'content/dota_addons'/host.ADDON/'ws4_local_owner.txt').read_text(),'WS4-LOCAL-1\n')
            launch=json.loads(capture.read_text(encoding='utf-8-sig'))
            self.assertEqual(launch['args'][-2:],['+connect','26.1.2.3:27015'])
            self.assertNotIn('+dota_launch_custom_game',launch['args'])
            installed.unlink();resumed=run()
            self.assertEqual(resumed.returncode,0,resumed.stdout+resumed.stderr)
            self.assertEqual(installed.read_bytes(),raw)
            installed.write_bytes(b'preserve this changed file');capture.unlink()
            changed=run()
            self.assertEqual(changed.returncode,1)
            self.assertIn('client_runtime_bytes_changed',changed.stdout)
            self.assertEqual(installed.read_bytes(),b'preserve this changed file')
            self.assertFalse(capture.exists())

    def test_bundle_uses_allowlist_and_excludes_host_session_and_caches(self):
        with tempfile.TemporaryDirectory() as temporary:
            folder=Path(temporary);stage=folder/'stage';stage.mkdir()
            expected=host.expected_manifest({'files':[]},{'addoninfo.txt':b'frozen fixture'})
            (stage/'addoninfo.txt').write_bytes(b'frozen fixture')
            descriptor={'kind':'WS4-LOCAL-1','base_content_sha256':host.BASE_SHA,'runtime':expected}
            (stage/host.INSTALL_MANIFEST).write_text(json.dumps(descriptor),encoding='utf8')
            private=stage/host.PRIVATE_REL;private.parent.mkdir(parents=True)
            private.write_bytes(b'must-not-be-distributed')
            (stage/'tools_asset_info.bin').write_bytes(b'engine cache')
            destination=folder/'guest'
            with patch.object(host,'STAGE',stage),patch.object(host,'baseline',return_value={}), \
                    patch.object(host,'overlay',return_value={}),patch.object(host,'expected_manifest',return_value=expected):
                result=guest.build(destination,'26.1.2.3:27015')
            self.assertFalse(result['cloud_credentials_in_bundle'])
            self.assertEqual({p.relative_to(destination/host.ADDON).as_posix() for p in (destination/host.ADDON).rglob('*') if p.is_file()},
                {'addoninfo.txt',host.INSTALL_MANIFEST})
            script=(destination/'join_client.ps1').read_text(encoding='utf-8-sig')
            digest=hashlib.sha256((destination/'client_manifest.json').read_bytes()).hexdigest()
            self.assertIn(digest,script)
            self.assertNotIn('__MANIFEST_SHA256__',script)
            self.assertNotIn('dota_launch_custom_game',script)
            self.assertIn("'+connect',$Server",script)
            self.assertFalse(any(b'must-not-be-distributed' in p.read_bytes() for p in destination.rglob('*') if p.is_file()))

    def test_address_must_be_a_single_ipv4_endpoint_before_any_copy(self):
        for address in ('26.1.2.3:27015;quit','26.1.2.3:29003','127.0.0.1:27015/../x'):
            with self.subTest(address=address),patch.object(host,'baseline') as baseline:
                with self.assertRaises((ValueError,host.LocalError)):guest.build(Path('unused-guest-fixture'),address)
                baseline.assert_not_called()


if __name__=='__main__':unittest.main()
