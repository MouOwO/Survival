param([ValidateSet('survival_c6','template_map')][string]$MapName = 'survival_c6')
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$engine = (Resolve-Path (Join-Path $repo '../../..')).Path
$bin = Join-Path $engine 'game/bin/win64'
$node = 'C:/Program Files/nodejs/node.exe'
$out = Join-Path $repo $(if ($MapName -eq 'template_map') { 'output/map_main_merge_20260919' } else { 'output/map_build_c6' })
New-Item -ItemType Directory -Force -Path $out | Out-Null
# Windows PowerShell 5.1 treats redirected native stderr as ErrorRecords.
# Redirect at process creation and use ExitCode; relay diagnostics are normal.
function Invoke-PreviewClient([string]$Requests, [string]$Expect = '') {
    $clientArgs = @(('"{0}"' -f (Join-Path $PSScriptRoot 'mcp-client.cjs')), ('"{0}"' -f $Requests))
    if ($Expect) { $clientArgs += @('--expect', ('"{0}"' -f $Expect)) }
    $child = Start-Process -FilePath $node -ArgumentList $clientArgs -WindowStyle Hidden -Wait -PassThru -RedirectStandardOutput (Join-Path $out 'launcher.log') -RedirectStandardError (Join-Path $out 'launcher.stderr.log')
    return $child.ExitCode
}
if (-not (Test-Path -LiteralPath (Join-Path $repo "maps/$MapName.vpk"))) { throw "$MapName.vpk not found." }
$games = @(Get-CimInstance Win32_Process -Filter "name='dota2.exe'" | Where-Object {
    $live = Get-Process -Id $_.ProcessId -ErrorAction SilentlyContinue
    $live -and -not $live.HasExited
})
if ($games | Where-Object { $_.CommandLine -notmatch '-addon\s+survival(?:\s|$)' }) {
    throw 'Another Dota instance is running. Close it, then run this launcher again.'
}
if ($games.Count -eq 0) {
    Start-Process (Join-Path $bin 'dota2.exe') -ArgumentList "-tools -noassetbrowser -addon survival -dev -condebug -novid -windowed -w 1600 -h 900 +dota_launch_custom_game survival $MapName" -WorkingDirectory (Join-Path $engine 'game/dota') -WindowStyle Normal
}
if (-not (Get-Process vconsole2 -ErrorAction SilentlyContinue)) {
    Start-Process (Join-Path $bin 'vconsole2.exe') -WorkingDirectory (Join-Path $engine 'game/dota') -WindowStyle Hidden
}
$launchFile = Join-Path $PSScriptRoot 'launch.json'
$previewFile = Join-Path $PSScriptRoot 'preview.json'
if ($MapName -eq 'template_map') {
    $launchFile = Join-Path $out 'launcher-launch.json'
    $previewFile = Join-Path $out 'launcher-preview.json'
    $launchText = (Get-Content -LiteralPath (Join-Path $PSScriptRoot 'launch.json') -Raw).Replace('survival survival_c6', 'survival template_map')
    $previewText = (Get-Content -LiteralPath (Join-Path $PSScriptRoot 'preview.json') -Raw).Replace('700 6250', '700 874').Replace('-1024 5376', '-1024 0')
    $previewRequests = ConvertFrom-Json $previewText
    $previewRequests[0].arguments.commands = $previewRequests[0].arguments.commands.Replace("`nc6_preview_z3200`n", "`nc6_preview_z1800`n")
    [IO.File]::WriteAllText($launchFile, $launchText)
    [IO.File]::WriteAllText($previewFile, (ConvertTo-Json -InputObject @($previewRequests) -Depth 5))
}
Write-Host "Loading $MapName map preview..."
$loaded = $false
for ($attempt = 0; $attempt -lt 12; $attempt++) {
    if ((Invoke-PreviewClient $launchFile) -eq 0) { $loaded = $true; break }
    Start-Sleep -Seconds 3
}
if (-not $loaded) { throw "Could not send map launch command. See $out/launcher.log and ensure VConsole connects to Localhost:29001." }
# Check the actual Lua map identity, not MCP's incompatible status_json parser.
$token = 'C6_PREVIEW_READY_' + [Guid]::NewGuid().ToString('N')
$readyFile = Join-Path $out 'launcher-ready.json'
$lua = "if GetMapName() == '$MapName' then DoIncludeScript('tests/map_c6_preview', getfenv(0)); print('$token') end"
$readyRequests = @(
    @{ name='console_send'; arguments=@{ commands='sv_cheats 1' } },
    @{ name='dota_run_lua'; arguments=@{ code=$lua } }
)
[IO.File]::WriteAllText($readyFile, (ConvertTo-Json -InputObject $readyRequests -Depth 5 -Compress))
$ready = $false
for ($attempt = 0; $attempt -lt 8; $attempt++) {
    if ((Invoke-PreviewClient $readyFile $token) -eq 0) { $ready = $true; break }
    Start-Sleep -Seconds 2
}
if (-not $ready) { throw "$MapName did not finish loading. See $out/launcher.stderr.log." }
# Let hero setup finish before applying the overview camera; addon UI also
# adjusts the camera during setup. Preview has no difficulty selection or HUD.
Start-Sleep -Seconds 8
if ((Invoke-PreviewClient $previewFile) -ne 0) { throw 'Could not enable the map preview camera.' }
& (Join-Path $PSScriptRoot 'window.ps1') -Show -PreviewOnly -CenterPointer | Out-Null
Write-Host 'Map preview ready. F7: close view; F8: overview; mouse wheel: zoom; move mouse to window edges to pan.'
