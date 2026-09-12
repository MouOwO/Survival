$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$engineRoot = [IO.Path]::GetFullPath((Join-Path $repoRoot '../../..'))
$contentRoot = Join-Path $engineRoot 'content/dota_addons/Survival'
$allowedRoots = @((Join-Path $repoRoot 'art/ui'), (Join-Path $contentRoot '美术索引'))
$entries = Get-Content -LiteralPath (Join-Path $repoRoot 'art/shortcuts.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$shell = New-Object -ComObject WScript.Shell
$count = 0
foreach ($entry in $entries) {
    $linkPath = [IO.Path]::GetFullPath($entry.link)
    $allowed = $false
    foreach ($root in $allowedRoots) {
        if ($linkPath.StartsWith([IO.Path]::GetFullPath($root) + '\', [StringComparison]::OrdinalIgnoreCase)) {$allowed = $true}
    }
    if (-not $allowed -or [IO.Path]::GetExtension($linkPath) -ne '.lnk') {throw "Invalid link target: $linkPath"}
    if (-not (Test-Path -LiteralPath $entry.target -PathType Leaf)) {throw "Missing source: $($entry.target)"}
    New-Item -ItemType Directory -Path (Split-Path -Parent $linkPath) -Force | Out-Null
    $link = $shell.CreateShortcut($linkPath)
    $link.TargetPath = $entry.target
    $link.WorkingDirectory = Split-Path -Parent $entry.target
    $link.Description = '美术源文件快捷方式；编辑会修改原始素材，运行路径不变。'
    $link.Save()
    if ($shell.CreateShortcut($linkPath).TargetPath -ne $entry.target) {throw "Link verification failed: $linkPath"}
    $count++
}
Copy-Item -LiteralPath (Join-Path $repoRoot 'art/index.html') -Destination (Join-Path $contentRoot '美术索引/index.html') -Force
Copy-Item -LiteralPath (Join-Path $repoRoot 'art/Content文件总表.csv') -Destination (Join-Path $contentRoot '美术索引/Content文件总表.csv') -Force
Copy-Item -LiteralPath (Join-Path $repoRoot 'art/README.md') -Destination (Join-Path $contentRoot '美术索引/README.md') -Force
Write-Output "Created and verified $count shortcuts. No source asset renamed or copied."
