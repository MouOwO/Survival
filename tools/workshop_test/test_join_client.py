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
    @unittest.skipUnless(os.name=='nt','Windows PowerShell diagnostics')
    def test_guest_diagnostics_identify_missing_asset_and_sanitize_parser_failures(self):
        with tempfile.TemporaryDirectory() as temporary:
            folder=Path(temporary)
            (folder/host.ADDON).mkdir()
            expected=host.expected_manifest({'files':[]},{'addoninfo.txt':b'frozen'})
            marker=json.dumps({'kind':'WS4-LOCAL-1','base_content_sha256':host.BASE_SHA,'runtime':expected}).encode()
            template=(host.HERE/'join_client.ps1').read_text(encoding='utf8')
            def run(raw,listed_path=None):
                (folder/'client_manifest.json').write_bytes(raw)
                (folder/'join_client.ps1').write_text(template.replace('__MANIFEST_SHA256__',hashlib.sha256(raw).hexdigest()),encoding='utf-8-sig')
                environment=dict(os.environ)
                environment['PSModulePath']=';'.join((str(Path(os.environ['ProgramFiles'])/'WindowsPowerShell/Modules'),
                    str(Path(os.environ['SystemRoot'])/'System32/WindowsPowerShell/v1.0/Modules')))
                command=['powershell.exe','-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',
                    str(folder/'join_client.ps1'),'-Server','26.1.2.3:27015','-CheckOnly']
                if listed_path:
                    quote=lambda value:"'"+str(value).replace("'","''")+"'"
                    wrapper=folder/'layout_fixture.ps1'
                    wrapper.write_text('function Get-ChildItem { [CmdletBinding()]param([string]$LiteralPath,[switch]$Force,[switch]$Recurse); '
                        '[pscustomobject]@{FullName='+quote(folder/host.ADDON/listed_path)+';PSIsContainer=$false} }\n'
                        '$global:LASTEXITCODE=0\n& '+quote(folder/'join_client.ps1')+
                        ' -Server 26.1.2.3:27015 -CheckOnly\nexit $LASTEXITCODE\n',encoding='utf-8-sig')
                    command=['powershell.exe','-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',str(wrapper)]
                result=subprocess.run(command,capture_output=True,
                    text=True,encoding='utf8',errors='replace',timeout=10,env=environment)
                self.assertEqual(result.returncode,1,result.stdout+result.stderr)
                return result,json.loads((folder/'join_diagnostic.json').read_text(encoding='utf8'))
            missing,data=run(marker)
            self.assertEqual((data['error'],data['stage'],data['file']),('guest_file_missing','check_resources','addoninfo.txt'))
            self.assertEqual(data['revision'],'WS4-JOIN-05')
            private='must-never-print-parser-input'
            failed,data=run(('{"example":"'+private+'", broken').encode())
            self.assertEqual(data['stage'],'read_manifest')
            self.assertIn('exception_type',data)
            self.assertNotIn(private,failed.stdout+failed.stderr+json.dumps(data))
            self.assertNotIn(str(folder),json.dumps(data))
            for name,code in (('missing.vtex_c','guest_file_missing'),('x'*180+'.vtex_c','guest_path_too_long')):
                relative='panorama/images/'+name
                failed,data=run(marker,relative)
                self.assertEqual((data['error'],data['stage'],data['file']),(code,'check_layout',relative))
                self.assertEqual(data['path_chars'],len(str(folder/host.ADDON/relative)))

    @unittest.skipUnless(os.name=='nt','Windows CMD integration')
    def test_cmd_reports_missing_or_empty_script_without_starting_game(self):
        with tempfile.TemporaryDirectory() as temporary:
            folder=Path(temporary)
            launcher=folder/'join_game.cmd'
            launcher.write_bytes((host.HERE/'launch_join.cmd').read_bytes())
            for empty in (False,True):
                if empty:(folder/'join_client.ps1').write_bytes(b'')
                result=subprocess.run(['cmd.exe','/d','/c',str(launcher)],input='\n',capture_output=True,
                    text=True,encoding='utf8',errors='replace',timeout=10)
                self.assertEqual(result.returncode,1,result.stdout+result.stderr)
                self.assertIn('guest_files_missing_or_empty',result.stdout)

    @unittest.skipUnless(os.name=='nt','Windows PowerShell integration')
    def test_repo_guest_entry_rejects_missing_package_and_changed_script(self):
        with tempfile.TemporaryDirectory() as temporary:
            folder=Path(temporary)
            def run():
                return subprocess.run(['powershell.exe','-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass',
                    '-File',str(host.HERE/'launch_guest.ps1'),'-PackagePath',str(folder),'-CheckOnly'],
                    capture_output=True,text=True,encoding='utf8',errors='replace',timeout=30)
            missing=run()
            self.assertEqual(missing.returncode,1)
            self.assertIn('guest_package_missing',missing.stdout)
            sentinel=folder/'should_not_run.txt'
            (folder/'join_client.ps1').write_text("Set-Content -LiteralPath '"+
                str(sentinel).replace("'","''")+"' -Value 'unexpected'",encoding='utf-8-sig')
            changed=run()
            self.assertEqual(changed.returncode,1)
            self.assertIn('guest_entrypoint_changed',changed.stdout)
            self.assertFalse(sentinel.exists())

    @unittest.skipUnless(os.name=='nt','Windows PowerShell integration')
    def test_guest_installs_resumes_and_preserves_changed_files_without_launching(self):
        with tempfile.TemporaryDirectory() as temporary:
            folder=Path(temporary);stage=folder/'stage';stage.mkdir()
            file_name='panorama/images/spell icon.vtex_c'
            raw=b'frozen guest installation fixture'
            expected=host.expected_manifest({'files':[]},{file_name:raw,'addoninfo.txt':b'frozen fixture addon'})
            source=stage/file_name;source.parent.mkdir(parents=True);source.write_bytes(raw)
            (stage/'addoninfo.txt').write_bytes(b'frozen fixture addon')
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
            game=folder/'library/steamapps/common/dota 2 beta/game';exe=game/'bin/win64/dota2.exe'
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
            def run(command=None):
                environment=dict(os.environ)
                # A Python child of pwsh inherits its incompatible PowerShell 7
                # module path. Use Windows PowerShell's own standard modules.
                environment['PSModulePath']=';'.join((str(Path(os.environ['ProgramFiles'])/'WindowsPowerShell/Modules'),
                    str(Path(os.environ['SystemRoot'])/'System32/WindowsPowerShell/v1.0/Modules')))
                return subprocess.run(command or ['powershell.exe','-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',str(wrapper)],
                    capture_output=True,text=True,encoding='utf8',errors='replace',timeout=30,env=environment)
            for entry in ('加入测试.cmd','join_game.cmd'):
                checked=run(['cmd.exe','/d','/c','call',str(destination/entry),'-CheckOnly','-GamePath',str(game)])
                self.assertEqual(checked.returncode,0,checked.stdout+checked.stderr)
                self.assertIn('CLIENT_PACKAGE_CHECKED_NO_GAME_STARTED',checked.stdout)
                self.assertFalse(capture.exists())
            first=run();self.assertEqual(first.returncode,0,first.stdout+first.stderr)
            installed=game/'dota_addons'/host.ADDON/file_name
            self.assertTrue(installed.exists(),first.stdout+first.stderr)
            self.assertEqual(installed.read_bytes(),raw)
            self.assertEqual((game.parent/'content/dota_addons'/host.ADDON/'ws4_local_owner.txt').read_text(),'WS4-LOCAL-1\n')
            launch=json.loads(capture.read_text(encoding='utf-8-sig'))
            self.assertEqual(launch['args'][-2:],['+connect','26.1.2.3:27015'])
            self.assertNotIn('+dota_launch_custom_game',launch['args'])
            # Without a Steam registry value only one initial library remains.
            # Preserve array semantics while appending libraries from the VDF.
            config=folder/'programfiles/Steam/steamapps/libraryfolders.vdf'
            config.parent.mkdir(parents=True)
            config.write_text('"libraryfolders" { "0" { "path" "'+
                str(folder/'library').replace('\\','\\\\')+'" } }',encoding='utf8')
            original_wrapper=wrapper.read_text(encoding='utf-8-sig')
            wrapper.write_text("${env:ProgramFiles(x86)}="+quote(folder/'programfiles')+"\n"
                "function Get-ItemProperty { [CmdletBinding()]param([string]$LiteralPath); return $null }\n"+
                original_wrapper.replace(' -GamePath '+quote(game),''),encoding='utf-8-sig')
            fallback=run()
            self.assertEqual(fallback.returncode,0,fallback.stdout+fallback.stderr)
            wrapper.write_text(original_wrapper,encoding='utf-8-sig')
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
