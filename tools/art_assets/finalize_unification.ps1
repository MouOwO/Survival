$ErrorActionPreference='Stop'
$repoRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$engineRoot=[IO.Path]::GetFullPath((Join-Path $repoRoot '../../..'))
$source=Join-Path $repoRoot 'art/ui/sources'
$manifest=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'unification.json') -Raw -Encoding UTF8 | ConvertFrom-Json
foreach ($row in $manifest.files) {
    $dest=Join-Path $repoRoot $row.destination
    if ((Get-FileHash -LiteralPath $dest -Algorithm SHA256).Hash.ToLowerInvariant() -ne $row.destination_sha256) {throw "Changed destination: $dest"}
}
$targets=@((Join-Path $repoRoot 'ui'),(Join-Path $repoRoot 'panorama/src/images'),(Join-Path $engineRoot 'content/dota_addons/Survival/panorama/images'))
foreach ($entry in $targets) {
    $target=[IO.Path]::GetFullPath($entry)
    $expected=@([IO.Path]::GetFullPath((Join-Path $repoRoot 'ui')),[IO.Path]::GetFullPath((Join-Path $repoRoot 'panorama/src/images')),[IO.Path]::GetFullPath((Join-Path $engineRoot 'content/dota_addons/Survival/panorama/images')))
    if ($target -notin $expected) {throw 'Invalid deletion scope'}
    if ((Get-Item -LiteralPath $target).Attributes -band [IO.FileAttributes]::ReparsePoint) {throw 'Source already redirected; do not rerun migration'}
    if (Get-ChildItem -LiteralPath $target -Recurse -Force -Attributes ReparsePoint) {throw 'Unexpected reparse point'}
}
# Verify original artwork immediately before removing the duplicated source trees.
foreach ($target in $targets[1..2]) {
    Get-ChildItem -LiteralPath $target -File -Recurse -Force | ForEach-Object {
        $relative=$_.FullName.Substring($target.Length).TrimStart('\')
        if ((Get-FileHash -LiteralPath $_.FullName).Hash -ne (Get-FileHash -LiteralPath (Join-Path $source $relative)).Hash) {throw "Artwork mismatch: $relative"}
    }
}
foreach ($target in $targets) {
    Get-ChildItem -LiteralPath $target -File -Recurse -Force | ForEach-Object {Remove-Item -LiteralPath $_.FullName -Force}
    Get-ChildItem -LiteralPath $target -Directory -Recurse -Force | Sort-Object {$_.FullName.Length} -Descending | ForEach-Object {Remove-Item -LiteralPath $_.FullName -Force}
    Remove-Item -LiteralPath $target -Force
}
foreach ($target in $targets[1..2]) {New-Item -ItemType Junction -Path $target -Target $source | Out-Null}
Write-Output 'Old UI directory removed; both engine source paths now point to art/ui/sources.'
