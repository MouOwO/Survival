param([ValidateSet('Check','Repair')][string]$Action = 'Check')
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$deviceRoot = 'HKCU:\Software\Valve\VConsole2 SDK\Devices'
$guiExe = [IO.Path]::GetFullPath((Join-Path $repo '../../bin/win64/vconsole2.exe'))

function Get-HammerRelayState {
    $node = Get-Command node.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $node) { return @{relay_available=$false} }
    $adapter = Join-Path $PSScriptRoot 'map_c6/console-relay.cjs'
    $code = 'require(process.argv[1]).relayStatus().then(v=>process.stdout.write(JSON.stringify(v)))'
    $value = & $node.Source -e $code $adapter
    if ($LASTEXITCODE -ne 0) { return @{relay_available=$false} }
    try { return ($value | ConvertFrom-Json) } catch { return @{relay_available=$false} }
}
function Get-HammerDevices {
    foreach ($entry in @(Get-ChildItem -LiteralPath $deviceRoot -ErrorAction SilentlyContinue)) {
        $key = Get-Item -LiteralPath $entry.PSPath
        $name = $key.GetValue('deviceName')
        if ($key.GetValue('deviceType') -ne 0 -or $name -isnot [string]) { continue }
        $address = $name.Trim()
        $port = 29000
        if ($address -match '^(?:localhost|127\.0\.0\.1)(?::([0-9]+))?$') {
            if ($Matches[1]) { $port = [int]$Matches[1] }
        } else { continue }
        $kind = if ('connectAtStartup' -in $key.GetValueNames()) { $key.GetValueKind('connectAtStartup') }
            else { [Microsoft.Win32.RegistryValueKind]::String }
        [pscustomobject]@{Key=$entry.PSChildName;Path=$entry.PSPath;Name=$name;Port=$port;
            Auto=([string]$key.GetValue('connectAtStartup')).ToLowerInvariant();
            Kind=$kind}
    }
}
function Get-HammerDeviceArray {
    $size = 0
    if (Test-Path -LiteralPath $deviceRoot) {
        $size = [int](Get-Item -LiteralPath $deviceRoot).GetValue('size', 0)
    }
    $indices = @(Get-ChildItem -LiteralPath $deviceRoot -ErrorAction SilentlyContinue |
        Where-Object {$_.PSChildName -match '^[1-9][0-9]*$'} | ForEach-Object {[int]$_.PSChildName})
    $maximum = if ($indices.Count) { [int]($indices | Measure-Object -Maximum).Maximum } else { 0 }
    [pscustomobject]@{Size=$size;Maximum=$maximum}
}
function Get-HammerConsolePlan($Devices, $Relay) {
    $changes = @()
    $target = if ($Relay.relay_available) { [int]$Relay.gui_port } else { 0 }
    # The standard relay endpoint can remain enabled after its daemon exits.
    # Recognize our configured relay port too, without changing unrelated local
    # devices. A live custom relay replaces the standard endpoint.
    $relayPorts = @(29001)
    $configuredRelayPort = 0
    if ([int]::TryParse($env:DOTA2_VCON_GUI_PORT, [ref]$configuredRelayPort) -and
        $configuredRelayPort -gt 0 -and $configuredRelayPort -le 65535 -and
        $configuredRelayPort -ne 29000) { $relayPorts += $configuredRelayPort }
    foreach ($device in @($Devices)) {
        $desired = if ($device.Port -eq 29000) { 'false' }
            elseif ($target -gt 0 -and $device.Port -eq $target) { 'true' }
            elseif ($device.Port -in $relayPorts) { 'false' } else { $null }
        if ($null -ne $desired -and $device.Auto -ne $desired -and
            -not ($desired -eq 'false' -and $device.Auto -eq '0') -and
            -not ($desired -eq 'true' -and $device.Auto -eq '1')) {
            $changes += [pscustomobject]@{Device=$device;Desired=$desired}
        }
    }
    [pscustomobject]@{Changes=$changes;Target=$target;
        Create=($target -gt 0 -and @($Devices | Where-Object {$_.Port -eq $target}).Count -eq 0);
        CreateDirect=($target -eq 0 -and @($Devices | Where-Object {$_.Port -eq 29000}).Count -eq 0)}
}
function Get-HammerGuiProcesses {
    @(Get-Process vconsole2 -ErrorAction SilentlyContinue | Where-Object {
        # Restrict GUI restart to the VConsole executable belonging to this Dota installation.
        try { $_.Path -eq $guiExe } catch { $false }
    })
}
function Get-HammerDirectGuiOwners {
    $guiIds = @(Get-HammerGuiProcesses | ForEach-Object {$_.Id})
    if ($guiIds.Count -eq 0) { return @() }
    @(& (Join-Path $env:SystemRoot 'System32/netstat.exe') -ano -p TCP | ForEach-Object {
        $fields = $_.Trim() -split '\s+'
        if ($fields.Count -ge 5 -and $fields[0] -eq 'TCP' -and
            $fields[2] -eq '127.0.0.1:29000' -and $fields[3] -eq 'ESTABLISHED' -and
            [int]$fields[4] -in $guiIds) { [int]$fields[4] }
    } | Select-Object -Unique)
}
function Close-HammerGui($Processes) {
    foreach ($process in @($Processes)) {
        if (-not $process.CloseMainWindow()) { throw 'VConsole could not close normally. Close its dialog and rerun Setup; the game was preserved.' }
        if (-not $process.WaitForExit(8000)) { throw 'VConsole is still closing. Finish its dialog and rerun Setup; no process was killed.' }
    }
}
function Set-HammerConsolePlan($Plan) {
    foreach ($change in @($Plan.Changes)) {
        $kind = $change.Device.Kind
        if ($kind -eq [Microsoft.Win32.RegistryValueKind]::DWord) {
            Set-ItemProperty -LiteralPath $change.Device.Path -Name 'connectAtStartup' -Value ([int]($change.Desired -eq 'true')) -Type DWord
        } elseif ($kind -eq [Microsoft.Win32.RegistryValueKind]::String) {
            Set-ItemProperty -LiteralPath $change.Device.Path -Name 'connectAtStartup' -Value $change.Desired -Type String
        } else { throw 'Unsupported VConsole setting type; original value was preserved.' }
    }
    if ($Plan.Create -or $Plan.CreateDirect) {
        if (-not (Test-Path -LiteralPath $deviceRoot)) {
            New-Item -Path $deviceRoot | Out-Null
        }
        $number = (Get-HammerDeviceArray).Maximum + 1
        $createdPath = Join-Path $deviceRoot ([string]$number)
        New-Item -Path $createdPath | Out-Null
        $name = if ($Plan.Create) { 'Localhost:'+$Plan.Target } else { 'Localhost' }
        $auto = if ($Plan.Create) { 'true' } else { 'false' }
        New-ItemProperty -LiteralPath $createdPath -Name 'deviceName' -Value $name -PropertyType String | Out-Null
        New-ItemProperty -LiteralPath $createdPath -Name 'deviceType' -Value 0 -PropertyType DWord | Out-Null
        New-ItemProperty -LiteralPath $createdPath -Name 'connectAtStartup' -Value $auto -PropertyType String | Out-Null
    }
}
function Invoke-HammerConsoleRepair {
    $relay = Get-HammerRelayState
    $devices = @(Get-HammerDevices)
    $plan = Get-HammerConsolePlan $devices $relay
    $array = Get-HammerDeviceArray
    # VConsole uses a Qt settings array: an existing device above "size" is
    # silently ignored even when connectAtStartup=true.
    $arrayRepair = $array.Maximum -gt $array.Size
    $owners = @(Get-HammerDirectGuiOwners)
    $needed = $plan.Changes.Count -gt 0 -or $plan.Create -or $plan.CreateDirect -or $owners.Count -gt 0 -or $arrayRepair
    $mode = if ($relay.relay_available) {'shared_relay'} else {'direct_helper'}
    if ($Action -eq 'Check' -or -not $needed) {
        return [pscustomobject]@{ok=$true;status=if($needed){'console_repair_needed'}else{'console_configuration_ready'};
            mode=$mode;direct_gui_connected=($owners.Count -gt 0);settings_changes=$plan.Changes.Count;
            relay_device_needed=$plan.Create;direct_device_needed=$plan.CreateDirect;device_array_repair_needed=$arrayRepair}
    }
    $backupFolder = Join-Path $repo 'output/hammer_backend/console_backups'
    New-Item -ItemType Directory -Path $backupFolder -Force | Out-Null
    $backup = Join-Path $backupFolder ('devices_'+[Guid]::NewGuid().ToString('N')+'.json')
    # Only the affected auto-connect values are backed up; no credentials or console history.
    foreach ($change in @($plan.Changes)) {
        if ($change.Device.Kind -notin @([Microsoft.Win32.RegistryValueKind]::DWord,
            [Microsoft.Win32.RegistryValueKind]::String)) {
            throw 'Unsupported VConsole setting type; original values were preserved.'
        }
    }
    $settings = @($plan.Changes | ForEach-Object {[pscustomobject]@{Key=$_.Device.Key;Name=$_.Device.Name;
        ConnectAtStartup=$_.Device.Auto;ValueKind=[string]$_.Device.Kind}})
    [pscustomobject]@{Devices=$settings;ArraySize=$array.Size} |
        ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $backup -Encoding UTF8
    $guis = @(Get-HammerGuiProcesses)
    $reopen = $guis.Count -gt 0
    if ($reopen) { Close-HammerGui $guis }
    try {
        # Apply after GUI shutdown; Qt writes its cached settings when it exits.
        Set-HammerConsolePlan $plan
        $after = Get-HammerDeviceArray
        if ($after.Maximum -gt $after.Size) {
            Set-ItemProperty -LiteralPath $deviceRoot -Name 'size' -Value $after.Maximum -Type DWord
        }
    } finally {
        if ($reopen -and @(Get-HammerGuiProcesses).Count -eq 0) {
            # Restore the interactive window the user already had open.
            Start-Process -FilePath $guiExe -WindowStyle Normal
        }
    }
    [pscustomobject]@{ok=$true;status='console_configuration_repaired';mode=$mode;
        gui_reopened=$reopen;settings_changes=$plan.Changes.Count;relay_device_created=$plan.Create;
        direct_device_created=$plan.CreateDirect;device_array_repaired=$arrayRepair}
}
Invoke-HammerConsoleRepair | ConvertTo-Json -Compress
