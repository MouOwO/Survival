param([string]$AddonPath)
$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($AddonPath)) {
    $AddonPath = Read-Host 'Paste the game/dota_addons/survival folder path'
}
$repo = (Resolve-Path -LiteralPath $AddonPath.Trim().Trim('"')).Path
if (-not (Test-Path -LiteralPath (Join-Path $repo 'addoninfo.txt'))) {
    throw 'Not a game addon folder.'
}
$gameRoot = (Resolve-Path -LiteralPath (Join-Path $repo '../..')).Path
# Only emit selected metadata, never raw minidump memory or arbitrary logs.
$report = [Collections.Generic.List[string]]::new()
$report.Add('LAN_LOADING_DIAGNOSTICS_V1')
$report.Add('Collected: ' + (Get-Date -Format o))
$info = Join-Path $gameRoot 'dota/steam.inf'
if (Test-Path -LiteralPath $info) {
    foreach ($line in Get-Content -LiteralPath $info) {
        if ($line -match '^(ClientVersion|ServerVersion|SourceRevision)=') { $report.Add($line) }
    }
}
foreach ($relative in @('scripts/custom_game/startup_loading.vjs_c','layout/custom_game/startup_loading.vxml_c','layout/custom_game/custom_loading_screen.vxml_c','layout/custom_game/custom_ui_manifest.vxml_c')) {
    $path = Join-Path (Join-Path $repo 'panorama') $relative
    if (Test-Path -LiteralPath $path) { $report.Add($relative + ' SHA256=' + (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash) }
    else { $report.Add($relative + ' MISSING') }
}
$dump = Get-ChildItem -LiteralPath (Join-Path $gameRoot 'bin/win64') -Filter 'dota2*.mdmp' |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ($dump) {
    $report.Add('Dump: ' + $dump.Name + ' Modified: ' + $dump.LastWriteTime.ToString('o'))
    try {
        if ($dump.Length -gt 67108864) { throw 'Dump too large for this metadata probe' }
        $b = [IO.File]::ReadAllBytes($dump.FullName)
        if ($b.Length -lt 32 -or [BitConverter]::ToUInt32($b,0) -ne 0x504D444D) { throw 'Invalid minidump header' }
        $n = [BitConverter]::ToUInt32($b,8); $r = [BitConverter]::ToUInt32($b,12)
        if ($n -gt 1024 -or ([long]$r+12*$n) -gt $b.Length) { throw 'Invalid stream directory' }
        $ex = 0; $mods = 0
        for ($i=0; $i -lt $n; $i++) {
            $p=$r+12*$i; $t=[BitConverter]::ToUInt32($b,$p); $o=[BitConverter]::ToUInt32($b,$p+8)
            if ($t -eq 6) { $ex=$o }; if ($t -eq 4) { $mods=$o }
        }
        if (!$ex -or !$mods) { throw 'Missing exception/module streams' }
        $a=[BitConverter]::ToUInt64($b,$ex+24)
        $report.Add(('Exception: 0x{0:X}' -f [BitConverter]::ToUInt32($b,$ex+8)))
        $count=[BitConverter]::ToUInt32($b,$mods)
        if ($count -gt 4096 -or ([long]$mods+4+108*$count) -gt $b.Length) { throw 'Invalid module stream' }
        for ($i=0; $i -lt $count; $i++) {
            $p=$mods+4+108*$i; $base=[BitConverter]::ToUInt64($b,$p); $size=[BitConverter]::ToUInt32($b,$p+8)
            if ($a -ge $base -and ($a-$base) -lt $size) {
                $s=[BitConverter]::ToUInt32($b,$p+20); $len=[BitConverter]::ToUInt32($b,$s)
                $name=[Text.Encoding]::Unicode.GetString($b,$s+4,$len)
                $report.Add('Module: ' + [IO.Path]::GetFileName($name))
                $report.Add(('Offset: 0x{0:X}' -f ($a-$base)))
                $report.Add(('Dump module timestamp: 0x{0:X}' -f [BitConverter]::ToUInt32($b,$p+16)))
            }
        }
    } catch { $report.Add('DUMP_METADATA_UNAVAILABLE: ' + $_.Exception.GetType().Name) }
} else { $report.Add('NO_DOTA_CRASH_DUMP') }
$log = Join-Path $gameRoot 'dota/console.log'
if (Test-Path -LiteralPath $log) {
    $report.Add('Console modified: ' + (Get-Item -LiteralPath $log).LastWriteTime.ToString('o'))
    $lines = Get-Content -LiteralPath $log -Tail 6000 |
        Where-Object { $_ -match '\[STARTUP_|JS Exception|TypeError|ReferenceError|SyntaxError|DOTA_GAMERULES_STATE|SIGNONSTATE|startup_loading\.(js|vjs)|FATAL ERROR|accessviolation' } |
        Where-Object { $_ -notmatch '(?i)token|password|secret|authorization|credential|private.?key|https?://' } |
        Select-Object -Last 65
    foreach ($line in $lines) { $report.Add(($line -replace '\b[0-9]{17}\b','<account-redacted>')) }
} else { $report.Add('NO_CONSOLE_LOG') }
$outputDir = Join-Path $repo 'output/lan_diagnostics'
New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
$outputPath = Join-Path $outputDir ('loading_' + (Get-Date -Format 'yyyyMMddHHmmss') + '_' + [Guid]::NewGuid().ToString('N') + '.txt')
$report | Set-Content -LiteralPath $outputPath -Encoding UTF8
$report | Write-Output
Write-Output ('REPORT_SAVED: ' + $outputPath)
