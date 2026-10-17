param([switch]$CheckOnly)
$ErrorActionPreference = 'Stop'
$ioPortraitRepo = Split-Path -Parent $PSScriptRoot
$ioPortraitEngine = [IO.Path]::GetFullPath((Join-Path $ioPortraitRepo '../../..'))
$ioPortraitSource = Join-Path $PSScriptRoot 'builder_io_portrait.vmap'
$ioPortraitMapName = 'builder_io_companion_v2'
$ioPortraitContent = Join-Path $ioPortraitEngine ('content/dota_addons/Survival/maps/portraits/' + $ioPortraitMapName + '.vmap')
$ioPortraitRuntime = Join-Path $ioPortraitRepo ('maps/portraits/' + $ioPortraitMapName + '.vpk')
$ioPortraitBin = Join-Path $ioPortraitEngine 'game/bin/win64'
$ioPortraitText = [IO.File]::ReadAllText($ioPortraitSource)
foreach ($required in @('models/items/io/io_ti7/io_ti7.vmdl', 'particles/econ/items/wisp/wisp_ambient_ti7.vpcf', 'builder_io_camera')) {
    if (-not $ioPortraitText.Contains($required)) { throw "Io portrait dependency missing: $required" }
}
if ($ioPortraitText.Contains('"local.scales" "string" ""')) { throw 'Io attachment local scales must be explicit' }
foreach ($animationKey in @('StartingAnim', 'IdleAnim')) {
    $animationMatches = [regex]::Matches($ioPortraitText, ('"' + $animationKey + '"\s+"string"\s+"([^"]*)"'))
    if ($animationMatches.Count -ne 1 -or $animationMatches[0].Groups[1].Value -ne 'ti7_io_idle') {
        throw "Io portrait $animationKey must use the model's real ti7_io_idle sequence"
    }
}
if ($CheckOnly) { 'BUILDER_PORTRAIT_MAP_SOURCE_PASS'; return }
$ioPortraitWork = Join-Path $ioPortraitRepo ('output/builder_portrait_map/build_' + (Get-Date -Format 'yyyyMMdd_HHmmss_fff') + '_' + [Guid]::NewGuid().ToString('N').Substring(0, 8))
[void][IO.Directory]::CreateDirectory($ioPortraitWork)
$ioPortraitSourceHash = (Get-FileHash -LiteralPath $ioPortraitSource -Algorithm SHA256).Hash
$ioPortraitPrevious = @{}
foreach ($entry in @(@($ioPortraitContent, 'previous_content.vmap'), @($ioPortraitRuntime, 'previous_runtime.vpk'))) {
    $ioPortraitPrevious[$entry[0]] = Test-Path -LiteralPath $entry[0] -PathType Leaf
    if ($ioPortraitPrevious[$entry[0]]) { Copy-Item -LiteralPath $entry[0] -Destination (Join-Path $ioPortraitWork $entry[1]) }
}
$ioPortraitBinary = Join-Path $ioPortraitWork ($ioPortraitMapName + '.vmap')
$ioPortraitConvertLog = @(& (Join-Path $ioPortraitBin 'dmxconvert.exe') -i $ioPortraitSource -o $ioPortraitBinary -oe binary 2>&1)
$ioPortraitConvertLog | Set-Content -LiteralPath (Join-Path $ioPortraitWork 'convert.log') -Encoding utf8
if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $ioPortraitBinary)) { throw 'Io portrait map conversion failed' }
try {
    [void][IO.Directory]::CreateDirectory((Split-Path -Parent $ioPortraitContent))
    Copy-Item -LiteralPath $ioPortraitBinary -Destination $ioPortraitContent -Force
    $ioPortraitStarted = [DateTime]::UtcNow
    $ioPortraitCompileLog = @(& (Join-Path $ioPortraitBin 'resourcecompiler.exe') -i $ioPortraitContent -game (Join-Path $ioPortraitEngine 'game/dota') -fshallow -nop4 2>&1)
    $ioPortraitCompileExit = $LASTEXITCODE
    $ioPortraitCompileLog | Set-Content -LiteralPath (Join-Path $ioPortraitWork 'compile.log') -Encoding utf8
    if ($ioPortraitCompileExit -ne 0 -or -not ($ioPortraitCompileLog -match '\b0 failed\b') -or ($ioPortraitCompileLog -match '\b[1-9][0-9]* failed\b') -or -not (Test-Path -LiteralPath $ioPortraitRuntime -PathType Leaf)) {
        throw 'Io portrait compiler did not produce a successful map build'
    }
    $ioPortraitRuntimeInfo = Get-Item -LiteralPath $ioPortraitRuntime
    if ($ioPortraitRuntimeInfo.Length -le 0 -or $ioPortraitRuntimeInfo.LastWriteTimeUtc -lt $ioPortraitStarted) { throw 'Io portrait runtime is empty or stale' }
    if ((Get-FileHash -LiteralPath $ioPortraitSource -Algorithm SHA256).Hash -ne $ioPortraitSourceHash) { throw 'Io portrait source changed during compilation' }
    $ioPortraitResult = [pscustomobject]@{
        success=$true; source=$ioPortraitSource; source_sha256=$ioPortraitSourceHash; content=$ioPortraitContent;
        runtime=$ioPortraitRuntime; bytes=$ioPortraitRuntimeInfo.Length; modified_utc=$ioPortraitRuntimeInfo.LastWriteTimeUtc.ToString('o');
        sha256=(Get-FileHash -LiteralPath $ioPortraitRuntime -Algorithm SHA256).Hash; logs=$ioPortraitWork
    }
    $ioPortraitResult | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $ioPortraitWork 'result.json') -Encoding utf8
    $ioPortraitResult | ConvertTo-Json -Compress
} catch {
    foreach ($entry in @(@($ioPortraitContent, 'previous_content.vmap'), @($ioPortraitRuntime, 'previous_runtime.vpk'))) {
        if ($ioPortraitPrevious[$entry[0]]) {
            Copy-Item -LiteralPath (Join-Path $ioPortraitWork $entry[1]) -Destination $entry[0] -Force
        } elseif (Test-Path -LiteralPath $entry[0] -PathType Leaf) {
            Remove-Item -LiteralPath $entry[0] -Force
        }
    }
    throw "Io portrait map compile failed; previous files restored. See $ioPortraitWork. $($_.Exception.Message)"
}
