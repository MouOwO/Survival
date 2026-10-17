param(
    [string]$Report = 'output/collection_rarity_20261016/ui_compile.json',
    [string]$ExpectedSourceManifest = '',
    [switch]$CheckOnly
)
$ErrorActionPreference = 'Stop'
$rarityRepo = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$rarityEngine = (Resolve-Path (Join-Path $rarityRepo '../../..')).Path
$raritySource = Join-Path $rarityRepo 'panorama/src'
$rarityContent = (Get-Item -LiteralPath (Join-Path $rarityEngine 'content/dota_addons/Survival/panorama')).FullName
$rarityRuntime = Join-Path $rarityRepo 'panorama'
$rarityCompiler = Join-Path $rarityEngine 'game/bin/win64/resourcecompiler.exe'
$rarityScope = @(
    'scripts/custom_game/collection_gw2.js',
    'scripts/custom_game/common/archive_tooltip.js',
    'styles/custom_game/collection_gw2.css'
)

function Get-RarityChild([string]$Root, [string]$Relative) {
    $path = [IO.Path]::GetFullPath((Join-Path $Root $Relative))
    if (-not $path.StartsWith($Root + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Path escaped its named root: $Relative"
    }
    $cursor = $path
    while (-not (Test-Path -LiteralPath $cursor)) { $cursor = Split-Path -Parent $cursor }
    $item = Get-Item -LiteralPath $cursor -Force
    while ($item) {
        if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "Unexpected link: $path" }
        if ($item.FullName.Equals($Root, [StringComparison]::OrdinalIgnoreCase)) { return $path }
        $item = if ($item -is [IO.DirectoryInfo]) { $item.Parent } else { $item.Directory }
    }
    throw "Path did not reach its named root: $path"
}

function Get-RarityHash([string]$Path) {
    if (Test-Path -LiteralPath $Path -PathType Leaf) { return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash }
    return $null
}

if (-not (Test-Path -LiteralPath $rarityCompiler -PathType Leaf)) { throw 'Native resourcecompiler is missing.' }
$rarityReport = Get-RarityChild $rarityRepo $Report
$rarityOutput = Join-Path $rarityRepo 'output'
if (-not $rarityReport.StartsWith($rarityOutput + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase) -or
    -not $rarityReport.EndsWith('.json', [StringComparison]::OrdinalIgnoreCase)) { throw 'Report must be JSON under output/.' }

# Confirm every selected script/style is already loaded. No layout or HUD changes are required.
$rarityConsumers = @()
foreach ($file in Get-ChildItem -LiteralPath (Join-Path $raritySource 'layout/custom_game') -Filter '*.xml' -File -Recurse) {
    [xml]$layout = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8
    foreach ($relative in $rarityScope) {
        $uri = 'file://{resources}/' + $relative
        $nodes = @($layout.SelectNodes('//scripts/include | //styles/include') | Where-Object { $_.GetAttribute('src') -eq $uri })
        if ($nodes.Count -gt 1) { throw "Duplicate script consumer: $relative in $($file.Name)" }
        if ($nodes.Count) { $rarityConsumers += [pscustomobject]@{ relative = $relative; layout = $file.FullName; count = $nodes.Count } }
    }
}
foreach ($relative in $rarityScope) {
    if (-not @($rarityConsumers | Where-Object { $_.relative -eq $relative }).Count) { throw "Script has no active XML consumer: $relative" }
}

$rarityBackup = Get-RarityChild $rarityRepo ('output/collection_rarity_20261016/ui_compile_' + (Get-Date -Format 'yyyyMMdd_HHmmss_fff') + '_' + [guid]::NewGuid().ToString('N').Substring(0,8))
$rarityRecords = foreach ($relative in $rarityScope) {
    $source = Get-RarityChild $raritySource $relative
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { throw "Source missing: $relative" }
    $content = Get-RarityChild $rarityContent $relative
    $artifactRelative = ($relative -replace '\.js$', '.vjs_c') -replace '\.css$', '.vcss_c'
    $artifact = Get-RarityChild $rarityRuntime $artifactRelative
    [pscustomobject]@{
        relative = $relative; source = $source; content = $content; artifact = $artifact
        sourceHash = Get-RarityHash $source
        contentExisted = (Test-Path -LiteralPath $content -PathType Leaf)
        artifactExisted = (Test-Path -LiteralPath $artifact -PathType Leaf)
        contentBeforeHash = Get-RarityHash $content; artifactBeforeHash = Get-RarityHash $artifact
        sourceBackup = Join-Path $rarityBackup ('source/' + $relative)
        contentBackup = Join-Path $rarityBackup ('content/' + $relative)
        artifactBackup = Join-Path $rarityBackup ('runtime/' + $artifactRelative)
        compileStartedUtc = $null; compileExitCode = $null; log = $null
        compiledHash = $null; artifactBytes = $null; artifactWriteUtc = $null; verified = $false
    }
}
if ($ExpectedSourceManifest) {
    $expected = Get-Content -LiteralPath (Get-RarityChild $rarityRepo $ExpectedSourceManifest) -Raw -Encoding UTF8 | ConvertFrom-Json
    if (@($expected.records).Count -ne $rarityScope.Count) { throw 'Expected manifest scope differs from the exact two JS and one CSS sources.' }
    foreach ($record in $rarityRecords) {
        $match = @($expected.records | Where-Object { $_.relative -eq $record.relative })
        if ($match.Count -ne 1 -or $match[0].sourceHash -ne $record.sourceHash) { throw "Frozen source hash differs: $($record.relative)" }
    }
}

# All unrelated files retain their mtime and size. Script/style/layout resources also retain SHA-256.
# Existing images are read only and are never passed to the compiler.
$raritySelectedPaths = @{}
foreach ($record in $rarityRecords) { foreach ($path in @($record.source, $record.content, $record.artifact)) { $raritySelectedPaths[$path] = $true } }
$rarityProtected = foreach ($root in @($raritySource, $rarityContent, $rarityRuntime)) {
    foreach ($file in Get-ChildItem -LiteralPath $root -Recurse -File -Force) {
        if ($root -eq $rarityRuntime -and $file.FullName.StartsWith($raritySource + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { continue }
        if ($raritySelectedPaths.ContainsKey($file.FullName)) { continue }
        $relative = $file.FullName.Substring($root.Length + 1).Replace('\','/')
        $hash = if ($relative -match '^(scripts|styles|layout)/') { Get-RarityHash $file.FullName } else { $null }
        [pscustomobject]@{ root = $root; relative = $relative; path = $file.FullName; bytes = $file.Length; writeUtc = $file.LastWriteTimeUtc.ToString('o'); hash = $hash }
    }
}

function Get-RarityProtectedChanges {
    $changes = @()
    $knownPaths = @{}
    foreach ($record in $rarityProtected) {
        $knownPaths[$record.path] = $true
        if (-not (Test-Path -LiteralPath $record.path -PathType Leaf)) { $changes += $record.path; continue }
        $file = Get-Item -LiteralPath $record.path
        if ($file.Length -ne $record.bytes -or $file.LastWriteTimeUtc.ToString('o') -ne $record.writeUtc -or
            ($record.hash -and (Get-RarityHash $record.path) -ne $record.hash)) { $changes += $record.path }
    }
    foreach ($root in @($raritySource, $rarityContent, $rarityRuntime)) {
        foreach ($file in Get-ChildItem -LiteralPath $root -Recurse -File -Force) {
            if ($root -eq $rarityRuntime -and $file.FullName.StartsWith($raritySource + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { continue }
            if (-not $knownPaths.ContainsKey($file.FullName) -and -not $raritySelectedPaths.ContainsKey($file.FullName)) { $changes += $file.FullName }
        }
    }
    return $changes
}

if ($CheckOnly) {
    [pscustomobject]@{ success = $true; checkOnly = $true; scope = $rarityScope; records = $rarityRecords; consumers = $rarityConsumers;
        protectedFiles = @($rarityProtected).Count; backup = $rarityBackup; report = $rarityReport; nativeFlags = @('-fshallow','-nop4');
        imagesCompiled = 0; jsCompiled = 2; cssCompiled = 1; xmlCompiled = 0 } | ConvertTo-Json -Depth 8
    return
}

New-Item -ItemType Directory -Path $rarityBackup -Force | Out-Null
foreach ($record in $rarityRecords) {
    foreach ($path in @($record.sourceBackup, $record.contentBackup, $record.artifactBackup)) { New-Item -ItemType Directory -Path (Split-Path -Parent $path) -Force | Out-Null }
    Copy-Item -LiteralPath $record.source -Destination $record.sourceBackup
    if ($record.contentExisted) { Copy-Item -LiteralPath $record.content -Destination $record.contentBackup }
    if ($record.artifactExisted) { Copy-Item -LiteralPath $record.artifact -Destination $record.artifactBackup }
}
@{ records = $rarityRecords; protected = $rarityProtected } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $rarityBackup 'manifest_before.json') -Encoding UTF8
try {
    foreach ($record in $rarityRecords) {
        if ((Get-RarityHash $record.source) -ne $record.sourceHash) { throw "Source changed before copy: $($record.relative)" }
        New-Item -ItemType Directory -Path (Split-Path -Parent $record.content) -Force | Out-Null
        Copy-Item -LiteralPath $record.source -Destination $record.content -Force
        if ((Get-RarityHash $record.content) -ne $record.sourceHash) { throw "Content hash differs: $($record.relative)" }
    }
    foreach ($record in $rarityRecords) {
        $record.compileStartedUtc = (Get-Date).ToUniversalTime().ToString('o')
        $record.log = Join-Path $rarityBackup (($record.relative -replace '/', '_') + '.log')
        $log = @(& $rarityCompiler -i $record.content -game (Join-Path $rarityEngine 'game/dota') -fshallow -nop4 2>&1)
        $record.compileExitCode = $LASTEXITCODE
        $log | Set-Content -LiteralPath $record.log -Encoding UTF8
        if ($record.compileExitCode -ne 0 -or -not ($log -match '\b0 failed\b')) { throw "Native compiler failed: $($record.relative)" }
        Write-Output ('COLLECTION_RARITY_COMPILE_PASS ' + $record.relative)
    }
    foreach ($record in $rarityRecords) {
        if ((Get-RarityHash $record.source) -ne $record.sourceHash -or (Get-RarityHash $record.content) -ne $record.sourceHash) { throw "Source/Content changed during compile: $($record.relative)" }
        if (-not (Test-Path -LiteralPath $record.artifact -PathType Leaf)) { throw "Compiled artifact missing: $($record.relative)" }
        $file = Get-Item -LiteralPath $record.artifact
        if ($file.Length -le 0 -or $file.LastWriteTimeUtc -lt [datetime]::Parse($record.compileStartedUtc).ToUniversalTime()) { throw "Compiled artifact is stale or empty: $($record.relative)" }
        $record.compiledHash = Get-RarityHash $record.artifact; $record.artifactBytes = $file.Length
        $record.artifactWriteUtc = $file.LastWriteTimeUtc.ToString('o'); $record.verified = $true
    }
    $rarityChanges = @(Get-RarityProtectedChanges)
    if ($rarityChanges.Count) { throw ('Unrelated Panorama resources changed: ' + ($rarityChanges -join ', ')) }
    New-Item -ItemType Directory -Path (Split-Path -Parent $rarityReport) -Force | Out-Null
    @{ at = (Get-Date -Format o); success = $true; backup = $rarityBackup; records = $rarityRecords; consumers = $rarityConsumers;
        protectedFiles = @($rarityProtected).Count; protectedChanges = @(); nativeFlags = @('-fshallow','-nop4');
        imagesCompiled = 0; jsCompiled = 2; cssCompiled = 1; xmlCompiled = 0 } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $rarityReport -Encoding UTF8
} catch {
    $rarityFailure = $_; $rarityRollbackErrors = @()
    foreach ($record in $rarityRecords) {
        try {
            if ($record.contentExisted) { Copy-Item -LiteralPath $record.contentBackup -Destination $record.content -Force }
            elseif (Test-Path -LiteralPath $record.content -PathType Leaf) { Remove-Item -LiteralPath $record.content }
            if ($record.artifactExisted) { Copy-Item -LiteralPath $record.artifactBackup -Destination $record.artifact -Force }
            elseif (Test-Path -LiteralPath $record.artifact -PathType Leaf) { Remove-Item -LiteralPath $record.artifact }
            if ((Get-RarityHash $record.content) -ne $record.contentBeforeHash -or (Get-RarityHash $record.artifact) -ne $record.artifactBeforeHash) { throw "Rollback hash mismatch: $($record.relative)" }
        } catch { $rarityRollbackErrors += $_.ToString() }
    }
    @{ at = (Get-Date -Format o); success = $false; error = $rarityFailure.ToString(); rolledBack = ($rarityRollbackErrors.Count -eq 0);
        rollbackErrors = $rarityRollbackErrors; records = $rarityRecords; protectedChanges = @(Get-RarityProtectedChanges) } |
        ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $rarityBackup 'failure.json') -Encoding UTF8
    throw $rarityFailure
}
