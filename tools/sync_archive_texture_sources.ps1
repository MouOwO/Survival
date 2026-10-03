[CmdletBinding()]
param([switch]$CheckOnly, [string]$GameRoot = '', [string]$ContentRoot = '')
$ErrorActionPreference = 'Stop'
if (-not $GameRoot) { $GameRoot = Join-Path $PSScriptRoot '..' }
$repo = [IO.Path]::GetFullPath($GameRoot)
if (-not $ContentRoot) { $ContentRoot = Join-Path $repo '../../../content/dota_addons/survival' }
$content = [IO.Path]::GetFullPath($ContentRoot)
$masters = Join-Path $repo 'art/ui/sources'
$mirror = Join-Path $repo 'panorama/src/images'
$utf8 = [Text.UTF8Encoding]::new($false, $true)
$writes = [Collections.Generic.List[object]]::new()
$images = @{}
$recipes = 0
function Read-Recipe([string]$file) {
    $text = $utf8.GetString([IO.File]::ReadAllBytes($file))
    if ($text.StartsWith([string][char]0xFEFF, [StringComparison]::Ordinal) -or $text.Replace("`r`n", "").Contains("`r")) {
        throw "Unexpected recipe encoding; inspect before changing: $file"
    }
    return $text
}
function Plan-Write([string]$path, [byte[]]$bytes, [string]$backupName) {
    if (Test-Path -LiteralPath $path) {
        if ([Convert]::ToBase64String([IO.File]::ReadAllBytes($path)) -eq [Convert]::ToBase64String($bytes)) { return }
    }
    $writes.Add(@{ path=$path; bytes=$bytes; backup=$backupName })
}
# Preflight every recipe and image before any writes. Real artwork/content edits
# must be reconciled explicitly; only line-ending differences are auto-repaired.
foreach ($group in @('archive_gpu_regular', 'archive_gpu_small')) {
    $files = @(Get-ChildItem -LiteralPath (Join-Path $masters "custom_game/$group") -Filter '*.vtex' -File)
    if (-not $files.Count) { throw "No texture recipes found: $group" }
    foreach ($source in $files) {
        $relative = "custom_game/$group/$($source.Name)"
        $text = Read-Recipe $source.FullName
        $canonical = $text.Replace("`r`n", "`n")
        $bytes = $utf8.GetBytes($canonical)
        foreach ($target in @(@{root=$masters;name='masters'}, @{root=$mirror;name='mirror'}, @{root=(Join-Path $content 'panorama/images');name='content'})) {
            $path = Join-Path $target.root $relative
            if ((Test-Path -LiteralPath $path) -and (Read-Recipe $path).Replace("`r`n", "`n") -cne $canonical) {
                throw "Recipe content differs beyond line endings; nothing changed: $path"
            }
            Plan-Write $path $bytes ($target.name+'/'+$relative)
        }
        $inputs = [regex]::Matches($canonical, '"m_fileName"\s+"string"\s+"([^"\r\n]+)"')
        if (-not $inputs.Count) { throw "Recipe has no image dependency: $relative" }
        foreach ($inputImage in $inputs) {
            $name = $inputImage.Groups[1].Value
            if ($name -notmatch '^panorama/images/custom_game/[A-Za-z0-9_/-]+\.png$') { throw "Unsafe image dependency: $relative" }
            $images[$name.Substring('panorama/images/'.Length)] = $true
        }
        $recipes++
    }
}
foreach ($relative in $images.Keys) {
    $source = Join-Path $masters $relative
    $bytes = [IO.File]::ReadAllBytes($source)
    foreach ($target in @(@{root=$mirror;name='mirror'}, @{root=(Join-Path $content 'panorama/images');name='content'})) {
        $path = Join-Path $target.root $relative
        if ((Test-Path -LiteralPath $path) -and (Get-FileHash -LiteralPath $source).Hash -ne (Get-FileHash -LiteralPath $path).Hash) {
            throw "Image content differs; nothing changed: $path"
        }
        Plan-Write $path $bytes ($target.name+'/'+$relative)
    }
}
if ($CheckOnly) {
    if ($writes.Count) { throw "$($writes.Count) inputs need LF normalization or synchronization. Run repair_archive_textures.cmd with Dota closed." }
} elseif ($writes.Count) {
    $backup = Join-Path $repo ('output/archive_texture_fix/source_backup_'+[Guid]::NewGuid().ToString('N'))
    foreach ($item in $writes) {
        if (Test-Path -LiteralPath $item.path) {
            $saved = Join-Path $backup $item.backup
            $null = New-Item -ItemType Directory -Force -Path (Split-Path -Parent $saved)
            Copy-Item -LiteralPath $item.path -Destination $saved
        }
    }
    foreach ($item in $writes) {
        $null = New-Item -ItemType Directory -Force -Path (Split-Path -Parent $item.path)
        [IO.File]::WriteAllBytes($item.path, $item.bytes)
    }
    Write-Output "ARCHIVE_SOURCES_REPAIRED: $($writes.Count) inputs; backup=$backup"
}
Write-Output "ARCHIVE_SOURCES_READY: $recipes LF recipes and $($images.Count) image dependencies checked."
