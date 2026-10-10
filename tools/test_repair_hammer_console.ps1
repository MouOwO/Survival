$ErrorActionPreference = 'Stop'
$checks = 0
function Assert-Console($Value, $Message) {
    if (-not $Value) { throw $Message }
    $script:checks++
}
# Load functions only. Never evaluate the production script's real registry
# path or its entry point in this isolated Windows registry test.
$tokens=$null; $errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile(
    (Join-Path $PSScriptRoot 'repair_hammer_console.ps1'),[ref]$tokens,[ref]$errors)
Assert-Console ($errors.Count -eq 0) 'Repair script must parse in Windows PowerShell.'
$functions=$ast.FindAll({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst]},$false)
foreach ($function in $functions) { Invoke-Expression $function.Extent.Text }
$fixtureName='SurvivalConsoleTest_'+[Guid]::NewGuid().ToString('N')
$fixtureKey='Software\'+$fixtureName
$deviceRoot='HKCU:\'+$fixtureKey+'\Devices'
$repo=Join-Path ([IO.Path]::GetTempPath()) $fixtureName
$guiExe='fixture-vconsole.exe'
$Action='Repair'
$relay=@{relay_available=$true;gui_port=29001}
$originalRelayGuiPort=$env:DOTA2_VCON_GUI_PORT
$env:DOTA2_VCON_GUI_PORT=$null
$guis=@(); $owners=@(); $events=@()
function Get-HammerRelayState { $script:relay }
function Get-HammerGuiProcesses { $script:guis }
function Get-HammerDirectGuiOwners { $script:owners }
function Close-HammerGui($Processes) { $script:events+='close'; $script:guis=@() }
function Start-Process { param($FilePath,$WindowStyle)
    Assert-Console ($FilePath -eq $guiExe -and $WindowStyle -eq 'Normal') 'Restore only the existing GUI.'
    Assert-Console ((Get-HammerDeviceArray).Size -ge 2) 'Persist the array before reopening the GUI.'
    $script:events+='reopen'
}
function Add-Device($Number,$Name,$Auto,$Kind='String',$Type=0) {
    $path=Join-Path $deviceRoot ([string]$Number)
    New-Item -Path $path -Force | Out-Null
    New-ItemProperty -LiteralPath $path -Name deviceName -Value $Name -PropertyType String | Out-Null
    New-ItemProperty -LiteralPath $path -Name deviceType -Value $Type -PropertyType DWord | Out-Null
    if ($null -ne $Auto) {
        New-ItemProperty -LiteralPath $path -Name connectAtStartup -Value $Auto -PropertyType $Kind | Out-Null
    }
}
try {
    Add-Device 1 'Localhost' 'true'
    Add-Device 2 'Localhost:29001' 'true'
    Add-Device 3 '192.168.1.10:29000' 'true'
    Add-Device 4 '127.0.0.1:29009' 'true'
    New-ItemProperty -LiteralPath $deviceRoot -Name size -Value 1 -PropertyType DWord | Out-Null
    $Action='Check'
    $check=Invoke-HammerConsoleRepair
    Assert-Console $check.device_array_repair_needed 'Detect the hidden second Qt array entry.'
    Assert-Console ($check.settings_changes -eq 1) 'Only the direct local startup setting needs changing.'
    Assert-Console ((Get-HammerDeviceArray).Size -eq 1) 'Check must not change registry settings.'
    Assert-Console (-not (Test-Path -LiteralPath $repo)) 'Check must not write backups.'
    $Action='Repair'; $guis=@([pscustomobject]@{Id=123}); $owners=@(123)
    $fixed=Invoke-HammerConsoleRepair
    Assert-Console ($fixed.status -eq 'console_configuration_repaired') 'Repair must complete.'
    Assert-Console (($events -join ',') -eq 'close,reopen') 'Close normally and restore the existing GUI.'
    Assert-Console ((Get-HammerDeviceArray).Size -eq 4) 'Qt must load all existing devices, including remote entries.'
    Assert-Console ((Get-Item -LiteralPath (Join-Path $deviceRoot '1')).GetValue('connectAtStartup') -eq 'false') 'Prevent direct GUI contention.'
    Assert-Console ((Get-Item -LiteralPath (Join-Path $deviceRoot '2')).GetValue('connectAtStartup') -eq 'true') 'Keep shared GUI enabled.'
    Assert-Console ((Get-Item -LiteralPath (Join-Path $deviceRoot '3')).GetValue('connectAtStartup') -eq 'true') 'Preserve remote devices.'
    Assert-Console ((Get-Item -LiteralPath (Join-Path $deviceRoot '4')).GetValue('connectAtStartup') -eq 'true') 'Preserve unrelated local ports.'
    $guis=@(); $owners=@(); $events=@()
    Assert-Console ((Invoke-HammerConsoleRepair).status -eq 'console_configuration_ready') 'Repair should be idempotent.'
    Assert-Console ($events.Count -eq 0) 'An already correct GUI must not restart.'
    Add-Device 5 '127.0.0.1:29000' 1 'DWord'
    Add-Device 6 'localhost:29001' $null
    Invoke-HammerConsoleRepair | Out-Null
    Assert-Console ((Get-Item -LiteralPath (Join-Path $deviceRoot '5')).GetValue('connectAtStartup') -eq 0) 'Handle DWORD settings.'
    Assert-Console ((Get-Item -LiteralPath (Join-Path $deviceRoot '6')).GetValue('connectAtStartup') -eq 'true') 'Handle a missing startup setting.'
    # A vanished daemon left only the enabled 29001 device, exactly as in the
    # live failure. Check must report it, and Repair must preserve other devices.
    $relay=@{relay_available=$false}
    $Action='Check'
    $stale=Invoke-HammerConsoleRepair
    Assert-Console ($stale.mode -eq 'direct_helper' -and $stale.status -eq 'console_repair_needed') 'Detect an enabled endpoint with no relay.'
    Assert-Console ($stale.settings_changes -eq 2) 'Detect both obsolete default relay devices.'
    Assert-Console ((Get-Item -LiteralPath (Join-Path $deviceRoot '2')).GetValue('connectAtStartup') -eq 'true') 'Stale relay Check must not modify settings.'
    $Action='Repair'
    $staleFixed=Invoke-HammerConsoleRepair
    Assert-Console ($staleFixed.settings_changes -eq 2) 'Repair the obsolete relay startup settings.'
    Assert-Console ((Get-Item -LiteralPath (Join-Path $deviceRoot '2')).GetValue('connectAtStartup') -eq 'false') 'Disable the vanished default relay.'
    Assert-Console ((Get-Item -LiteralPath (Join-Path $deviceRoot '6')).GetValue('connectAtStartup') -eq 'false') 'Disable duplicate stale relay devices.'
    Assert-Console ((Get-Item -LiteralPath (Join-Path $deviceRoot '3')).GetValue('connectAtStartup') -eq 'true') 'Stale relay repair preserves remote devices.'
    Assert-Console ((Get-Item -LiteralPath (Join-Path $deviceRoot '4')).GetValue('connectAtStartup') -eq 'true') 'Stale relay repair preserves unrelated local ports.'
    Assert-Console ((Invoke-HammerConsoleRepair).status -eq 'console_configuration_ready') 'Stale relay repair is idempotent.'
    Add-Device 7 'localhost:29011' 1 'DWord'
    $env:DOTA2_VCON_GUI_PORT='29011'
    Invoke-HammerConsoleRepair | Out-Null
    Assert-Console ((Get-Item -LiteralPath (Join-Path $deviceRoot '7')).GetValue('connectAtStartup') -eq 0) 'Disable a vanished configured relay while preserving DWORD type.'
    $relay=@{relay_available=$true;gui_port=29011}
    Invoke-HammerConsoleRepair | Out-Null
    Assert-Console ((Get-Item -LiteralPath (Join-Path $deviceRoot '7')).GetValue('connectAtStartup') -eq 1) 'Enable the live configured relay.'
    Assert-Console ((Get-Item -LiteralPath (Join-Path $deviceRoot '2')).GetValue('connectAtStartup') -eq 'false') 'A live custom relay keeps the old default relay disabled.'
    $env:DOTA2_VCON_GUI_PORT=$null
    # New PC without an MCP installation: create a disconnected GUI default
    # while the existing protocol client remains free to connect directly.
    $deviceRoot='HKCU:\'+$fixtureKey+'\FreshDevices'
    $relay=@{relay_available=$false}
    $fresh=Invoke-HammerConsoleRepair
    Assert-Console ($fresh.mode -eq 'direct_helper' -and $fresh.direct_device_created) 'MCP must be optional.'
    $default=Get-Item -LiteralPath (Join-Path $deviceRoot '1')
    Assert-Console ($default.GetValue('deviceName') -eq 'Localhost' -and $default.GetValue('connectAtStartup') -eq 'false') 'A first GUI launch must not take the helper port.'
    Assert-Console ((Get-HammerDeviceArray).Size -eq 1) 'Persist the new device array size.'
    $relay=@{relay_available=$true;gui_port=29011}
    $shared=Invoke-HammerConsoleRepair
    Assert-Console $shared.relay_device_created 'Create a relay device when missing.'
    Assert-Console ((Get-Item -LiteralPath (Join-Path $deviceRoot '2')).GetValue('deviceName') -eq 'Localhost:29011') 'Respect the configured relay port.'
    Assert-Console ((Get-HammerDeviceArray).Size -eq 2) 'New shared devices must be visible to Qt.'
    Write-Output ('HAMMER_CONSOLE_TESTS_PASSED: '+$checks)
} finally {
    $env:DOTA2_VCON_GUI_PORT=$originalRelayGuiPort
    if ($fixtureKey -notmatch '^Software\\SurvivalConsoleTest_[a-f0-9]{32}$') { throw 'Unsafe fixture key.' }
    [Microsoft.Win32.Registry]::CurrentUser.DeleteSubKeyTree($fixtureKey,$false)
    $resolvedFixture=[IO.Path]::GetFullPath($repo)
    $expectedFixture=[IO.Path]::GetFullPath((Join-Path ([IO.Path]::GetTempPath()) $fixtureName))
    if ($resolvedFixture -ne $expectedFixture) { throw 'Unsafe fixture directory.' }
    if (Test-Path -LiteralPath $resolvedFixture) { Remove-Item -LiteralPath $resolvedFixture -Recurse -Force }
}
