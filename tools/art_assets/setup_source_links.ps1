# Run after relocating a checkout. Never replaces an existing real source directory.
$ErrorActionPreference='Stop'
$repoRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$engineRoot=[IO.Path]::GetFullPath((Join-Path $repoRoot '../../..'))
$source=Join-Path $repoRoot 'art/ui/sources'
if (-not (Test-Path -LiteralPath $source -PathType Container)) {throw 'Missing art/ui/sources'}
foreach ($path in @((Join-Path $repoRoot 'panorama/src/images'),(Join-Path $engineRoot 'content/dota_addons/Survival/panorama/images'))) {
    if (Test-Path -LiteralPath $path) {
        $item=Get-Item -LiteralPath $path
        if ($item.LinkType -ne 'Junction' -or $item.Target -ne $source) {throw "Existing directory must be reconciled first: $path"}
    } else {
        New-Item -ItemType Directory -Path (Split-Path -Parent $path) -Force | Out-Null
        New-Item -ItemType Junction -Path $path -Target $source | Out-Null
    }
}
Write-Output 'Source junctions verified.'
