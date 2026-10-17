param(
    [string]$Report = 'output/wife_video_20261016/ui_compile.json',
    [string]$ExpectedSourceManifest = '',
    [switch]$CheckOnly
)
$ErrorActionPreference = 'Stop'
$wifeRepo = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$wifeEngine = (Resolve-Path (Join-Path $wifeRepo '../../..')).Path
$wifeSource = Join-Path $wifeRepo 'panorama/src'
$wifeContent = (Get-Item -LiteralPath (Join-Path $wifeEngine 'content/dota_addons/Survival/panorama')).FullName
$wifeRuntime = Join-Path $wifeRepo 'panorama'
$wifeCompiler = Join-Path $wifeEngine 'game/bin/win64/resourcecompiler.exe'
$wifeScope = @(
    'scripts/custom_game/icons_remaining_5d5c1152eb.js',
    'scripts/custom_game/common/archive_tooltip.js',
    'scripts/custom_game/archive_v10.js',
    'scripts/custom_game/archive_180de7e38b_titles_compact_v6.js',
    'scripts/custom_game/collection_gw2.js'
)

function Get-WifeChild([string]$Root, [string]$Relative) {
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

function Get-WifeHash([string]$Path) {
    if (Test-Path -LiteralPath $Path -PathType Leaf) { return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash }
    return $null
}

if (-not (Test-Path -LiteralPath $wifeCompiler -PathType Leaf)) { throw 'Native resourcecompiler is missing.' }
$wifeReport = Get-WifeChild $wifeRepo $Report
$wifeOutput = Join-Path $wifeRepo 'output'
if (-not $wifeReport.StartsWith($wifeOutput + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase) -or
    -not $wifeReport.EndsWith('.json', [StringComparison]::OrdinalIgnoreCase)) { throw 'Report must be JSON under output/.' }

# Confirm every selected script is already loaded. No layout or HUD changes are required.
$wifeConsumers = @()
foreach ($file in Get-ChildItem -LiteralPath (Join-Path $wifeSource 'layout/custom_game') -Filter '*.xml' -File -Recurse) {
    [xml]$layout = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8
    foreach ($relative in $wifeScope) {
        $uri = 'file://{resources}/' + $relative
        $nodes = @($layout.SelectNodes('//scripts/include') | Where-Object { $_.GetAttribute('src') -eq $uri })
        if ($nodes.Count -gt 1) { throw "Duplicate script consumer: $relative in $($file.Name)" }
        if ($nodes.Count) { $wifeConsumers += [pscustomobject]@{ relative = $relative; layout = $file.FullName; count = $nodes.Count } }
    }
}
foreach ($relative in $wifeScope) {
    if (-not @($wifeConsumers | Where-Object { $_.relative -eq $relative }).Count) { throw "Script has no active XML consumer: $relative" }
}

$wifeBackup = Get-WifeChild $wifeRepo ('output/wife_video_20261016/ui_compile_' + (Get-Date -Format 'yyyyMMdd_HHmmss_fff') + '_' + [guid]::NewGuid().ToString('N').Substring(0,8))
$wifeRecords = foreach ($relative in $wifeScope) {
    $source = Get-WifeChild $wifeSource $relative
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { throw "Source missing: $relative" }
    $content = Get-WifeChild $wifeContent $relative
    $artifactRelative = $relative -replace '\.js$', '.vjs_c'
    $artifact = Get-WifeChild $wifeRuntime $artifactRelative
    [pscustomobject]@{
        relative = $relative; source = $source; content = $content; artifact = $artifact
        sourceHash = Get-WifeHash $source
        contentExisted = (Test-Path -LiteralPath $content -PathType Leaf)
        artifactExisted = (Test-Path -LiteralPath $artifact -PathType Leaf)
        contentBeforeHash = Get-WifeHash $content; artifactBeforeHash = Get-WifeHash $artifact
        sourceBackup = Join-Path $wifeBackup ('source/' + $relative)
        contentBackup = Join-Path $wifeBackup ('content/' + $relative)
        artifactBackup = Join-Path $wifeBackup ('runtime/' + $artifactRelative)
        compileStartedUtc = $null; compileExitCode = $null; log = $null
        compiledHash = $null; artifactBytes = $null; artifactWriteUtc = $null; verified = $false
    }
}
if ($ExpectedSourceManifest) {
    $expected = Get-Content -LiteralPath (Get-WifeChild $wifeRepo $ExpectedSourceManifest) -Raw -Encoding UTF8 | ConvertFrom-Json
    if (@($expected.records).Count -ne $wifeScope.Count) { throw 'Expected manifest scope differs from the exact five JS sources.' }
    foreach ($record in $wifeRecords) {
        $match = @($expected.records | Where-Object { $_.relative -eq $record.relative })
        if ($match.Count -ne 1 -or $match[0].sourceHash -ne $record.sourceHash) { throw "Frozen source hash differs: $($record.relative)" }
    }
}

# All unrelated files retain their mtime and size. Script/style/layout resources also retain SHA-256.
# Existing images are read only and are never passed to the compiler.
$wifeSelectedPaths = @{}
foreach ($record in $wifeRecords) { foreach ($path in @($record.source, $record.content, $record.artifact)) { $wifeSelectedPaths[$path] = $true } }
$wifeProtected = foreach ($root in @($wifeSource, $wifeContent, $wifeRuntime)) {
    foreach ($file in Get-ChildItem -LiteralPath $root -Recurse -File -Force) {
        if ($root -eq $wifeRuntime -and $file.FullName.StartsWith($wifeSource + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { continue }
        if ($wifeSelectedPaths.ContainsKey($file.FullName)) { continue }
        $relative = $file.FullName.Substring($root.Length + 1).Replace('\','/')
        $hash = if ($relative -match '^(scripts|styles|layout)/') { Get-WifeHash $file.FullName } else { $null }
        [pscustomobject]@{ root = $root; relative = $relative; path = $file.FullName; bytes = $file.Length; writeUtc = $file.LastWriteTimeUtc.ToString('o'); hash = $hash }
    }
}

function Get-WifeProtectedChanges {
    $changes = @()
    $knownPaths = @{}
    foreach ($record in $wifeProtected) {
        $knownPaths[$record.path] = $true
        if (-not (Test-Path -LiteralPath $record.path -PathType Leaf)) { $changes += $record.path; continue }
        $file = Get-Item -LiteralPath $record.path
        if ($file.Length -ne $record.bytes -or $file.LastWriteTimeUtc.ToString('o') -ne $record.writeUtc -or
            ($record.hash -and (Get-WifeHash $record.path) -ne $record.hash)) { $changes += $record.path }
    }
    foreach ($root in @($wifeSource, $wifeContent, $wifeRuntime)) {
        foreach ($file in Get-ChildItem -LiteralPath $root -Recurse -File -Force) {
            if ($root -eq $wifeRuntime -and $file.FullName.StartsWith($wifeSource + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { continue }
            if (-not $knownPaths.ContainsKey($file.FullName) -and -not $wifeSelectedPaths.ContainsKey($file.FullName)) { $changes += $file.FullName }
        }
    }
    return $changes
}

if ($CheckOnly) {
    [pscustomobject]@{ success = $true; checkOnly = $true; scope = $wifeScope; records = $wifeRecords; consumers = $wifeConsumers;
        protectedFiles = @($wifeProtected).Count; backup = $wifeBackup; report = $wifeReport; nativeFlags = @('-fshallow','-nop4');
        imagesCompiled = 0; cssCompiled = 0; xmlCompiled = 0 } | ConvertTo-Json -Depth 8
    return
}

New-Item -ItemType Directory -Path $wifeBackup -Force | Out-Null
foreach ($record in $wifeRecords) {
    foreach ($path in @($record.sourceBackup, $record.contentBackup, $record.artifactBackup)) { New-Item -ItemType Directory -Path (Split-Path -Parent $path) -Force | Out-Null }
    Copy-Item -LiteralPath $record.source -Destination $record.sourceBackup
    if ($record.contentExisted) { Copy-Item -LiteralPath $record.content -Destination $record.contentBackup }
    if ($record.artifactExisted) { Copy-Item -LiteralPath $record.artifact -Destination $record.artifactBackup }
}
@{ records = $wifeRecords; protected = $wifeProtected } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $wifeBackup 'manifest_before.json') -Encoding UTF8
try {
    foreach ($record in $wifeRecords) {
        if ((Get-WifeHash $record.source) -ne $record.sourceHash) { throw "Source changed before copy: $($record.relative)" }
        New-Item -ItemType Directory -Path (Split-Path -Parent $record.content) -Force | Out-Null
        Copy-Item -LiteralPath $record.source -Destination $record.content -Force
        if ((Get-WifeHash $record.content) -ne $record.sourceHash) { throw "Content hash differs: $($record.relative)" }
    }
    foreach ($record in $wifeRecords) {
        $record.compileStartedUtc = (Get-Date).ToUniversalTime().ToString('o')
        $record.log = Join-Path $wifeBackup (($record.relative -replace '/', '_') + '.log')
        $log = @(& $wifeCompiler -i $record.content -game (Join-Path $wifeEngine 'game/dota') -fshallow -nop4 2>&1)
        $record.compileExitCode = $LASTEXITCODE
        $log | Set-Content -LiteralPath $record.log -Encoding UTF8
        if ($record.compileExitCode -ne 0 -or -not ($log -match '\b0 failed\b')) { throw "Native compiler failed: $($record.relative)" }
        Write-Output ('WIFE_UI_COMPILE_PASS ' + $record.relative)
    }
    foreach ($record in $wifeRecords) {
        if ((Get-WifeHash $record.source) -ne $record.sourceHash -or (Get-WifeHash $record.content) -ne $record.sourceHash) { throw "Source/Content changed during compile: $($record.relative)" }
        if (-not (Test-Path -LiteralPath $record.artifact -PathType Leaf)) { throw "Compiled artifact missing: $($record.relative)" }
        $file = Get-Item -LiteralPath $record.artifact
        if ($file.Length -le 0 -or $file.LastWriteTimeUtc -lt [datetime]::Parse($record.compileStartedUtc).ToUniversalTime()) { throw "Compiled artifact is stale or empty: $($record.relative)" }
        $record.compiledHash = Get-WifeHash $record.artifact; $record.artifactBytes = $file.Length
        $record.artifactWriteUtc = $file.LastWriteTimeUtc.ToString('o'); $record.verified = $true
    }
    $wifeChanges = @(Get-WifeProtectedChanges)
    if ($wifeChanges.Count) { throw ('Unrelated Panorama resources changed: ' + ($wifeChanges -join ', ')) }
    New-Item -ItemType Directory -Path (Split-Path -Parent $wifeReport) -Force | Out-Null
    @{ at = (Get-Date -Format o); success = $true; backup = $wifeBackup; records = $wifeRecords; consumers = $wifeConsumers;
        protectedFiles = @($wifeProtected).Count; protectedChanges = @(); nativeFlags = @('-fshallow','-nop4');
        imagesCompiled = 0; cssCompiled = 0; xmlCompiled = 0 } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $wifeReport -Encoding UTF8
} catch {
    $wifeFailure = $_; $wifeRollbackErrors = @()
    foreach ($record in $wifeRecords) {
        try {
            if ($record.contentExisted) { Copy-Item -LiteralPath $record.contentBackup -Destination $record.content -Force }
            elseif (Test-Path -LiteralPath $record.content -PathType Leaf) { Remove-Item -LiteralPath $record.content }
            if ($record.artifactExisted) { Copy-Item -LiteralPath $record.artifactBackup -Destination $record.artifact -Force }
            elseif (Test-Path -LiteralPath $record.artifact -PathType Leaf) { Remove-Item -LiteralPath $record.artifact }
            if ((Get-WifeHash $record.content) -ne $record.contentBeforeHash -or (Get-WifeHash $record.artifact) -ne $record.artifactBeforeHash) { throw "Rollback hash mismatch: $($record.relative)" }
        } catch { $wifeRollbackErrors += $_.ToString() }
    }
    @{ at = (Get-Date -Format o); success = $false; error = $wifeFailure.ToString(); rolledBack = ($wifeRollbackErrors.Count -eq 0);
        rollbackErrors = $wifeRollbackErrors; records = $wifeRecords; protectedChanges = @(Get-WifeProtectedChanges) } |
        ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $wifeBackup 'failure.json') -Encoding UTF8
    throw $wifeFailure
}
