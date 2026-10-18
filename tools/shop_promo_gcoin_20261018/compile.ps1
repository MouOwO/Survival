[CmdletBinding()]
param(
    [switch]$CheckOnly,
    [string]$SourceRoot = 'panorama/src',
    [string]$Report = 'output/shop_promo_gcoin_20261018/compile.json'
)
$ErrorActionPreference = 'Stop'
$shopPromoRepo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$shopPromoEngine = [IO.Path]::GetFullPath((Join-Path $shopPromoRepo '../../..'))
$shopPromoContent = Join-Path $shopPromoEngine 'content/dota_addons/Survival/panorama'
$shopPromoRuntime = Join-Path $shopPromoRepo 'panorama'
$shopPromoCompiler = Join-Path $shopPromoEngine 'game/bin/win64/resourcecompiler.exe'
$shopPromoSourceRoot = [IO.Path]::GetFullPath((Join-Path $shopPromoRepo $SourceRoot))
$shopPromoReport = [IO.Path]::GetFullPath((Join-Path $shopPromoRepo $Report))
$shopPromoBackup = Join-Path $shopPromoRepo ('output/shop_promo_gcoin_20261018/compile_' + (Get-Date -Format yyyyMMdd_HHmmss_fff) + '_' + [guid]::NewGuid().ToString('N').Substring(0,8))
$shopPromoFiles = @(
    'scripts/custom_game/black_lion_market.js',
    'scripts/custom_game/black_lion_market_model.js',
    'scripts/custom_game/archive_void_v1.js',
    'scripts/custom_game/commerce_remaining_5d5c1152eb.js',
    'scripts/custom_game/commerce_wallet.js',
    'scripts/custom_game/payment_test.js',
    'scripts/custom_game/video_shop_bundles.js',
    'scripts/custom_game/common/commerce_components.js',
    'scripts/custom_game/common/menu_v10.js',
    'scripts/custom_game/common/ui_components.js',
    'scripts/custom_game/common/item_resources.js',
    'styles/custom_game/black_lion_market.css'
)
$shopPromoRecords = @()
$shopPromoSuccess = $false
$shopPromoFailure = $null
$shopPromoRestoreErrors = @()

function Assert-ShopPromoPath([string]$Path, [string]$Root) {
    $resolved = [IO.Path]::GetFullPath($Path)
    $prefix = [IO.Path]::GetFullPath($Root).TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
    if (-not $resolved.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Path is outside the intended directory: $resolved"
    }
}

function Get-ShopPromoHash([string]$Path) {
    if (Test-Path -LiteralPath $Path -PathType Leaf) {
        return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
    }
    return $null
}

function Assert-ShopPromoHash([string]$Path, $Expected, [string]$Stage) {
    if ((Get-ShopPromoHash $Path) -ne $Expected) {
        throw "File changed during ${Stage}: $Path; snapshots remain in $shopPromoBackup"
    }
}

function Save-ShopPromoReport {
    $value = @{
        at = (Get-Date -Format o); success = $shopPromoSuccess; failure = $shopPromoFailure
        sourceRoot = $shopPromoSourceRoot; backup = $shopPromoBackup
        restoreErrors = @($shopPromoRestoreErrors); records = @($shopPromoRecords)
    }
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $shopPromoReport) | Out-Null
    $value | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $shopPromoReport -Encoding utf8
    $value | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $shopPromoBackup 'report.json') -Encoding utf8
}

Assert-ShopPromoPath $shopPromoSourceRoot $shopPromoRepo
Assert-ShopPromoPath $shopPromoReport $shopPromoRepo
if (-not (Test-Path -LiteralPath $shopPromoCompiler -PathType Leaf)) { throw 'Dota2 resource compiler is missing.' }
foreach ($relative in $shopPromoFiles) {
    $source = Join-Path $shopPromoSourceRoot $relative
    $content = Join-Path $shopPromoContent $relative
    $runtimeRelative = $relative -replace '\.js$', '.vjs_c' -replace '\.css$', '.vcss_c'
    $artifact = Join-Path $shopPromoRuntime $runtimeRelative
    Assert-ShopPromoPath $source $shopPromoSourceRoot
    Assert-ShopPromoPath $content $shopPromoContent
    Assert-ShopPromoPath $artifact $shopPromoRuntime
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { throw "Missing source: $relative" }
    $shopPromoRecords += [pscustomobject]@{
        relative = $relative; runtimeRelative = $runtimeRelative
        source = $source; content = $content; artifact = $artifact
        sourceHash = Get-ShopPromoHash $source
        contentBeforeHash = Get-ShopPromoHash $content; runtimeBeforeHash = Get-ShopPromoHash $artifact
        sourceBackup = Join-Path $shopPromoBackup ('source/' + $relative)
        contentBackup = Join-Path $shopPromoBackup ('content/' + $relative)
        runtimeBackup = Join-Path $shopPromoBackup ('runtime/' + $runtimeRelative)
        compiledBackup = Join-Path $shopPromoBackup ('compiled/' + $runtimeRelative)
        compilerLog = Join-Path $shopPromoBackup (([IO.Path]::GetFileName($source)) + '.log')
        contentWritten = $false; runtimeAttempted = $false
        contentOwnedHash = $null; runtimeOwnedHash = $null; compiledHash = $null
        contentRestored = $false; runtimeRestored = $false
    }
}
if ($CheckOnly) { Write-Output 'SHOP_PROMO_GCOIN_PANORAMA_CHECK_PASS 12 sources'; return }

try {
    foreach ($record in $shopPromoRecords) {
        foreach ($target in @($record.sourceBackup, $record.contentBackup, $record.runtimeBackup, $record.compiledBackup)) {
            New-Item -ItemType Directory -Force -Path (Split-Path -Parent $target) | Out-Null
        }
        Copy-Item -LiteralPath $record.source -Destination $record.sourceBackup
        Assert-ShopPromoHash $record.sourceBackup $record.sourceHash 'source snapshot'
        Assert-ShopPromoHash $record.source $record.sourceHash 'source snapshot'
        if ($record.contentBeforeHash) { Copy-Item -LiteralPath $record.content -Destination $record.contentBackup }
        if ($record.runtimeBeforeHash) { Copy-Item -LiteralPath $record.artifact -Destination $record.runtimeBackup }
        Assert-ShopPromoHash $record.content $record.contentBeforeHash 'Content snapshot'
        Assert-ShopPromoHash $record.artifact $record.runtimeBeforeHash 'runtime snapshot'
        if ($record.contentBeforeHash) { Assert-ShopPromoHash $record.contentBackup $record.contentBeforeHash 'Content backup' }
        if ($record.runtimeBeforeHash) { Assert-ShopPromoHash $record.runtimeBackup $record.runtimeBeforeHash 'runtime backup' }
    }
    Save-ShopPromoReport
    foreach ($record in $shopPromoRecords) {
        Assert-ShopPromoHash $record.source $record.sourceHash 'before compilation'
        Assert-ShopPromoHash $record.content $record.contentBeforeHash 'before Content write'
        Assert-ShopPromoHash $record.artifact $record.runtimeBeforeHash 'before compilation'
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $record.content) | Out-Null
        Copy-Item -LiteralPath $record.sourceBackup -Destination $record.content -Force
        $record.contentWritten = $true; $record.contentOwnedHash = $record.sourceHash
        $started = (Get-Date).ToUniversalTime()
        $record.runtimeAttempted = $true
        $log = @(& $shopPromoCompiler -i $record.content -game (Join-Path $shopPromoEngine 'game/dota') -fshallow -nop4 2>&1)
        $compilerExit = $LASTEXITCODE
        $record.runtimeOwnedHash = Get-ShopPromoHash $record.artifact
        $log | Set-Content -LiteralPath $record.compilerLog -Encoding utf8
        Save-ShopPromoReport
        if ($compilerExit -ne 0 -or -not ($log -match 'OK: [1-9][0-9]* compiled, 0 failed,')) {
            throw "Compile failed: $($record.relative); see $($record.compilerLog)"
        }
        if (-not (Test-Path -LiteralPath $record.artifact -PathType Leaf)) { throw "Missing output: $($record.runtimeRelative)" }
        $built = Get-Item -LiteralPath $record.artifact
        if ($built.Length -le 0 -or $built.LastWriteTimeUtc -lt $started) { throw "Empty or stale output: $($record.runtimeRelative)" }
        Assert-ShopPromoHash $record.source $record.sourceHash 'after compilation'
        Assert-ShopPromoHash $record.content $record.sourceHash 'after compilation'
        $record.compiledHash = $record.runtimeOwnedHash
        Copy-Item -LiteralPath $record.artifact -Destination $record.compiledBackup
        Assert-ShopPromoHash $record.compiledBackup $record.compiledHash 'compiled snapshot'
        Write-Output ('SHOP_PROMO_GCOIN_PANORAMA_COMPILED ' + $record.relative)
    }
    foreach ($record in $shopPromoRecords) {
        Assert-ShopPromoHash $record.source $record.sourceHash 'final source verification'
        Assert-ShopPromoHash $record.content $record.sourceHash 'final Content verification'
        Assert-ShopPromoHash $record.artifact $record.compiledHash 'final runtime verification'
    }
    $shopPromoSuccess = $true
} catch {
    $shopPromoFailure = $_.Exception.Message
} finally {
    if (-not $shopPromoSuccess) {
        foreach ($record in $shopPromoRecords) {
            foreach ($kind in @('content', 'runtime')) {
                $attempted = if ($kind -eq 'content') { $record.contentWritten } else { $record.runtimeAttempted }
                if (-not $attempted) { continue }
                try {
                    $target = if ($kind -eq 'content') { $record.content } else { $record.artifact }
                    $root = if ($kind -eq 'content') { $shopPromoContent } else { $shopPromoRuntime }
                    Assert-ShopPromoPath $target $root
                    $ownedHash = $record.($kind + 'OwnedHash')
                    Assert-ShopPromoHash $target $ownedHash "before $kind recovery"
                    $beforeHash = $record.($kind + 'BeforeHash')
                    if ($beforeHash) {
                        $saved = $record.($kind + 'Backup')
                        Assert-ShopPromoHash $saved $beforeHash "$kind backup verification"
                        Copy-Item -LiteralPath $saved -Destination $target -Force
                    } elseif (Test-Path -LiteralPath $target -PathType Leaf) {
                        Remove-Item -LiteralPath $target -Force
                    }
                    Assert-ShopPromoHash $target $beforeHash "after $kind recovery"
                    $record.($kind + 'Restored') = $true
                } catch { $shopPromoRestoreErrors += $_.Exception.Message }
            }
        }
    }
    New-Item -ItemType Directory -Force -Path $shopPromoBackup | Out-Null
    Save-ShopPromoReport
}
if ($shopPromoRestoreErrors.Count) { throw ($shopPromoRestoreErrors -join [Environment]::NewLine) }
if ($shopPromoFailure) { throw $shopPromoFailure }
Write-Output ('SHOP_PROMO_GCOIN_PANORAMA_PASS report=' + $shopPromoReport)
