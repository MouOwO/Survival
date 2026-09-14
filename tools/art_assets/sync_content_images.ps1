# Artist masters stay under art/ui; Source 2 must see physical content inputs.
$ErrorActionPreference='Stop'
$repoRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$engineRoot=[IO.Path]::GetFullPath((Join-Path $repoRoot '../../..'))
$source=Join-Path $repoRoot 'art/ui/sources'
$destination=[IO.Path]::GetFullPath((Join-Path $engineRoot 'content/dota_addons/Survival/panorama/images'))
if (-not (Test-Path -LiteralPath $source -PathType Container)) {throw 'Missing master images'}
$isJunction=$false
if (Test-Path -LiteralPath $destination) {
    $entry=Get-Item -LiteralPath $destination
    if ($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) {
        if ($entry.LinkType -ne 'Junction' -or $entry.Target -ne $source) {throw 'Unexpected content junction target'}
        $isJunction=$true
    }
}
$writeRoot=$destination
if ($isJunction) {
    $writeRoot=$destination+'.physical_stage'
    if (Test-Path -LiteralPath $writeRoot) {throw 'Staging directory exists; inspect before retry'}
}
New-Item -ItemType Directory -Path $writeRoot -Force | Out-Null
$count=0
$cleanupPlan=Join-Path $PSScriptRoot 'content_cleanup_plan.json'
$excludedImageRoots=@()
if (Test-Path -LiteralPath $cleanupPlan) {
    $cleanup=Get-Content -LiteralPath $cleanupPlan -Raw | ConvertFrom-Json
    $excludedImageRoots=@($cleanup.remove | Where-Object {$_.relative.StartsWith('panorama/images/')} | ForEach-Object {$_.relative.Substring(16).Replace('/','\')+'\'})
}
Get-ChildItem -LiteralPath $source -Recurse -File | ForEach-Object {
    $relative=$_.FullName.Substring($source.Length).TrimStart('\')
    $excluded=$false
    foreach($prefix in $excludedImageRoots) {if($relative.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase)){$excluded=$true;break}}
    if($excluded){return}
    $target=Join-Path $writeRoot $relative
    New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force | Out-Null
    Copy-Item -LiteralPath $_.FullName -Destination $target -Force
    if ((Get-FileHash -LiteralPath $_.FullName).Hash -ne (Get-FileHash -LiteralPath $target).Hash) {throw "Copy mismatch: $relative"}
    $count++
}
if ($isJunction) {
    # Remove only the verified junction itself, never recurse into the artist masters.
    $entry=Get-Item -LiteralPath $destination
    if ($entry.LinkType -ne 'Junction' -or $entry.Target -ne $source) {throw 'Junction changed during copy'}
    [IO.Directory]::Delete($destination)
    Move-Item -LiteralPath $writeRoot -Destination $destination
}
if ((Get-Item -LiteralPath $destination).Attributes -band [IO.FileAttributes]::ReparsePoint) {throw 'Content images must be physical'}
@{files=$count;content=$destination;physical=$true;time=(Get-Date -Format o)} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $PSScriptRoot 'content_sync.json') -Encoding UTF8
Write-Output "Verified $count physical Source 2 image inputs."
