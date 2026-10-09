param([string]$LogDirectory = 'output/construction_grid_compile')
$ErrorActionPreference = 'Stop'
$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$engine = [IO.Path]::GetFullPath((Join-Path $repo '../../..'))
$content = [IO.Path]::GetFullPath((Join-Path $engine 'content/dota_addons/Survival'))
$compiler = Join-Path $engine 'game/bin/win64/resourcecompiler.exe'
$inspector = Join-Path $engine 'game/bin/win64/resourceinfo.exe'
$sourceRoot = Join-Path $repo 'art/effects/construction_grid/source'
$logRoot = [IO.Path]::GetFullPath((Join-Path $repo $LogDirectory))
if (-not $logRoot.StartsWith(($repo + [IO.Path]::DirectorySeparatorChar), [StringComparison]::OrdinalIgnoreCase)) { throw 'Logs must stay inside this addon workspace' }
$manifest = Get-Content -LiteralPath (Join-Path $repo 'art/effects/construction_grid/manifest.json') -Raw | ConvertFrom-Json
New-Item -ItemType Directory -Force -Path $logRoot | Out-Null
$results = @()
foreach ($entry in $manifest.resources) {
    foreach ($relative in @($entry.texture.Replace('.vtex', '.png'), $entry.texture, $entry.particle)) {
        if ($relative -notmatch '^(materials|particles)/survival_grid/reference_grid_[0-3]\.(png|vtex|vpcf)$') { throw "Unexpected generated path: $relative" }
        $destination = [IO.Path]::GetFullPath((Join-Path $content $relative))
        if (-not $destination.StartsWith(($content + [IO.Path]::DirectorySeparatorChar), [StringComparison]::OrdinalIgnoreCase)) { throw 'Source destination escaped addon content root' }
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $destination) | Out-Null
        Copy-Item -LiteralPath (Join-Path $sourceRoot $relative) -Destination $destination -Force
    }
    foreach ($relative in @($entry.texture, $entry.particle)) {
        $name = [IO.Path]::GetFileName($relative)
        & $compiler -i (Join-Path $content $relative) -game (Join-Path $engine 'game/dota') -fshallow -nop4 2>&1 | Tee-Object -FilePath (Join-Path $logRoot ($name + '.compile.log'))
        if ($LASTEXITCODE -ne 0) { throw "Construction grid compile failed: $relative" }
        $compiled = Join-Path $repo ($relative + '_c')
        if (-not (Test-Path -LiteralPath $compiled)) { throw "Missing compiled output: $compiled" }
        & $inspector -i $compiled -all | Set-Content -LiteralPath (Join-Path $logRoot ($name + '_c.txt')) -Encoding utf8
        if ($LASTEXITCODE -ne 0) { throw "Construction grid resource inspection failed: $relative" }
        $results += [pscustomobject]@{
            resource = $relative
            bytes = (Get-Item -LiteralPath $compiled).Length
            source_sha256 = (Get-FileHash -LiteralPath (Join-Path $sourceRoot $relative) -Algorithm SHA256).Hash.ToLowerInvariant()
            compiled_sha256 = (Get-FileHash -LiteralPath $compiled -Algorithm SHA256).Hash.ToLowerInvariant()
        }
    }
}
$results | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $logRoot 'compiled_manifest.json') -Encoding utf8
& node (Join-Path $repo 'tools/test_construction_grid_resources.cjs')
if ($LASTEXITCODE -ne 0) { throw 'Construction grid texture residency/mip validation failed' }
Write-Output 'CONSTRUCTION_GRID_COMPILE_PASS'
