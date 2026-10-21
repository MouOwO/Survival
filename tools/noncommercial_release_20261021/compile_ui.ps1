$ErrorActionPreference = 'Stop'
$taskRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$engineRoot = [IO.Path]::GetFullPath((Join-Path $taskRoot '../../..'))
$contentRoot = Join-Path $engineRoot 'content/dota_addons/Survival/panorama'
$compiler = Join-Path $engineRoot 'game/bin/win64/resourcecompiler.exe'
$taskBackup = Join-Path $taskRoot ('output/noncommercial_release_20261021/ui_' + (Get-Date -Format 'yyyyMMdd_HHmmss_fff'))
$sources = @(
    'payment_test.js', 'commerce_remaining_5d5c1152eb.js', 'black_lion_market_model.js',
    'black_lion_market.js', 'common/commerce_components.js', 'vip_window.js',
    'topnav_remaining_5d5c1152eb.js', 'daily_remaining_5d5c1152eb.js'
)
function Get-TaskHash($path) {
    if (Test-Path -LiteralPath $path -PathType Leaf) { return (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() }
    return $null
}
function Assert-TaskPath($path, $root) {
    $absolute = [IO.Path]::GetFullPath($path)
    $prefix = [IO.Path]::GetFullPath($root).TrimEnd('\') + '\'
    if (-not $absolute.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) { throw "Path outside intended root: $absolute" }
}
$records = @()
foreach ($relative in $sources) {
    $source = Join-Path $taskRoot ('panorama/src/scripts/custom_game/' + $relative)
    $content = Join-Path $contentRoot ('scripts/custom_game/' + $relative)
    $runtimeRelative = 'panorama/scripts/custom_game/' + $relative.Replace('.js', '.vjs_c')
    $runtime = Join-Path $taskRoot $runtimeRelative
    Assert-TaskPath $source $taskRoot
    Assert-TaskPath $content $contentRoot
    Assert-TaskPath $runtime $taskRoot
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { throw "Missing source: $relative" }
    $record = [ordered]@{relative=$relative;source=$source;content=$content;runtime=$runtime;
        sourceHash=(Get-TaskHash $source);contentBefore=(Get-TaskHash $content);runtimeBefore=(Get-TaskHash $runtime);
        contentBackup=(Join-Path $taskBackup ('content/' + $relative));runtimeBackup=(Join-Path $taskBackup ('runtime/' + $relative + '.vjs_c'));
        compilerLog=(Join-Path $taskBackup ($relative.Replace('/','_') + '.log'));compiledHash=$null;written=$false;compiled=$false}
    foreach ($backup in @($record.contentBackup,$record.runtimeBackup)) { New-Item -ItemType Directory -Force -Path (Split-Path -Parent $backup) | Out-Null }
    if ($record.contentBefore) { Copy-Item -LiteralPath $content -Destination $record.contentBackup }
    if ($record.runtimeBefore) { Copy-Item -LiteralPath $runtime -Destination $record.runtimeBackup }
    $records += $record
}
$failure = $null
try {
    foreach ($record in $records) {
        if ((Get-TaskHash $record.source) -ne $record.sourceHash -or (Get-TaskHash $record.content) -ne $record.contentBefore -or (Get-TaskHash $record.runtime) -ne $record.runtimeBefore) { throw "Concurrent edit before compilation: $($record.relative)" }
        Copy-Item -LiteralPath $record.source -Destination $record.content -Force
        $record.written = $true
        $started = (Get-Date).ToUniversalTime()
        $log = @(& $compiler -i $record.content -game (Join-Path $engineRoot 'game/dota') -fshallow -nop4 2>&1)
        $compileExit = $LASTEXITCODE
        $record.compiledHash = Get-TaskHash $record.runtime
        $record.compiled = $true
        $log | Set-Content -LiteralPath $record.compilerLog -Encoding utf8
        if ($compileExit -ne 0 -or -not ($log -match 'OK: [1-9][0-9]* compiled, 0 failed,') -or -not $record.compiledHash) { throw "Compilation failed: $($record.relative)" }
        if ((Get-Item -LiteralPath $record.runtime).LastWriteTimeUtc -lt $started) { throw "Stale compiled resource: $($record.relative)" }
        if ((Get-TaskHash $record.content) -ne $record.sourceHash -or (Get-TaskHash $record.source) -ne $record.sourceHash) { throw "Source changed while compiling: $($record.relative)" }
        Write-Output ('NONCOMMERCIAL_UI_COMPILED ' + $record.relative)
    }
} catch { $failure = $_.Exception.Message }
if ($failure) {
    foreach ($record in $records) {
        if ($record.written -and (Get-TaskHash $record.content) -eq $record.sourceHash) {
            if ($record.contentBefore) { Copy-Item -LiteralPath $record.contentBackup -Destination $record.content -Force }
        }
        if ($record.compiled -and $record.runtimeBefore -and (Get-TaskHash $record.runtime) -eq $record.compiledHash) {
            Copy-Item -LiteralPath $record.runtimeBackup -Destination $record.runtime -Force
        }
    }
}
@{success=($null -eq $failure);failure=$failure;files=$records} | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $taskBackup 'report.json') -Encoding utf8
if ($failure) { throw $failure }
Write-Output ('NONCOMMERCIAL_UI_COMPILE_PASS ' + $taskBackup)
