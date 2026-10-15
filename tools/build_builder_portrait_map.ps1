param([switch]$CheckOnly)
$ErrorActionPreference = 'Stop'
$ioPortraitRepo = Split-Path -Parent $PSScriptRoot
$ioPortraitEngine = [IO.Path]::GetFullPath((Join-Path $ioPortraitRepo '../../..'))
$ioPortraitSource = Join-Path $PSScriptRoot 'builder_io_portrait.vmap'
$ioPortraitContent = Join-Path $ioPortraitEngine 'content/dota_addons/Survival/maps/portraits/builder_io_companion_v1.vmap'
$ioPortraitRuntime = Join-Path $ioPortraitRepo 'maps/portraits/builder_io_companion_v1.vpk'
$ioPortraitBin = Join-Path $ioPortraitEngine 'game/bin/win64'
$ioPortraitText = [IO.File]::ReadAllText($ioPortraitSource)
foreach ($required in @('models/items/io/io_ti7/io_ti7.vmdl', 'particles/econ/items/wisp/wisp_ambient_ti7.vpcf', 'builder_io_camera')) {
    if (-not $ioPortraitText.Contains($required)) { throw "Io portrait dependency missing: $required" }
}
if ($ioPortraitText.Contains('"local.scales" "string" ""')) { throw 'Io attachment local scales must be explicit' }
if ($CheckOnly) { 'BUILDER_PORTRAIT_MAP_SOURCE_PASS'; return }
$ioPortraitWork = Join-Path $ioPortraitRepo ('output/builder_portrait_map/build_' + (Get-Date -Format 'yyyyMMdd_HHmmss_fff'))
[void][IO.Directory]::CreateDirectory($ioPortraitWork)
foreach ($entry in @(@($ioPortraitContent, 'previous_content.vmap'), @($ioPortraitRuntime, 'previous_runtime.vpk'))) {
    if (Test-Path -LiteralPath $entry[0]) { Copy-Item -LiteralPath $entry[0] -Destination (Join-Path $ioPortraitWork $entry[1]) }
}
$ioPortraitBinary = Join-Path $ioPortraitWork 'builder_io_companion_v1.vmap'
$ioPortraitConvertLog = @(& (Join-Path $ioPortraitBin 'dmxconvert.exe') -i $ioPortraitSource -o $ioPortraitBinary -oe binary 2>&1)
$ioPortraitConvertLog | Set-Content -LiteralPath (Join-Path $ioPortraitWork 'convert.log') -Encoding utf8
if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $ioPortraitBinary)) { throw 'Io portrait map conversion failed' }
[void][IO.Directory]::CreateDirectory((Split-Path -Parent $ioPortraitContent))
Copy-Item -LiteralPath $ioPortraitBinary -Destination $ioPortraitContent -Force
$ioPortraitStarted = [DateTime]::UtcNow
$ioPortraitCompileLog = @(& (Join-Path $ioPortraitBin 'resourcecompiler.exe') -i $ioPortraitContent -game (Join-Path $ioPortraitEngine 'game/dota') -fshallow -nop4 2>&1)
$ioPortraitCompileLog | Set-Content -LiteralPath (Join-Path $ioPortraitWork 'compile.log') -Encoding utf8
if ($LASTEXITCODE -ne 0 -or -not ($ioPortraitCompileLog -match '0 failed') -or -not (Test-Path -LiteralPath $ioPortraitRuntime) -or (Get-Item -LiteralPath $ioPortraitRuntime).LastWriteTimeUtc -lt $ioPortraitStarted) {
    if (Test-Path -LiteralPath (Join-Path $ioPortraitWork 'previous_content.vmap')) { Copy-Item -LiteralPath (Join-Path $ioPortraitWork 'previous_content.vmap') -Destination $ioPortraitContent -Force }
    if (Test-Path -LiteralPath (Join-Path $ioPortraitWork 'previous_runtime.vpk')) { Copy-Item -LiteralPath (Join-Path $ioPortraitWork 'previous_runtime.vpk') -Destination $ioPortraitRuntime -Force }
    throw "Io portrait map compile failed; see $ioPortraitWork"
}
[pscustomobject]@{ success=$true; source=$ioPortraitSource; runtime=$ioPortraitRuntime; sha256=(Get-FileHash -LiteralPath $ioPortraitRuntime).Hash; logs=$ioPortraitWork } | ConvertTo-Json -Compress
