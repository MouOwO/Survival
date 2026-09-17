[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$GameRoot = "",
    [string]$ContentRoot = "",
    [string]$ResourceCompiler = "",
    [switch]$SyncRepositories
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($GameRoot)) {
    $GameRoot = Split-Path -Parent $PSScriptRoot
}
if ([string]::IsNullOrWhiteSpace($ContentRoot)) {
    $ContentRoot = $GameRoot -replace '\\game\\dota_addons\\Survival$', '\content\dota_addons\Survival'
}

function Check($condition, [string]$message) {
    if (-not $condition) { throw $message }
}

function Invoke-Git([string]$root, [string[]]$arguments) {
    $output = @(& git -C $root @arguments 2>&1)
    if ($LASTEXITCODE -ne 0) {
        $detail = ($output | ForEach-Object { $_.ToString() }) -join " | "
        throw "GIT_COMMAND_FAILED: git -C $root $($arguments -join ' '): $detail"
    }
    return $output
}

$game = (Resolve-Path -LiteralPath $GameRoot).Path
$content = (Resolve-Path -LiteralPath $ContentRoot).Path
$verifyScript = Join-Path $game "tools\verify_minimap_sync.ps1"

Check (Test-Path -LiteralPath (Join-Path $game ".git")) "GAME_REPOSITORY_NOT_FOUND: $game"
Check (Test-Path -LiteralPath (Join-Path $content ".git")) "CONTENT_REPOSITORY_NOT_FOUND: $content"
Check (Test-Path -LiteralPath $verifyScript -PathType Leaf) "VERIFY_SCRIPT_NOT_FOUND: $verifyScript"

if (-not $WhatIfPreference) {
    $runningDota = @(Get-Process -Name "dota2" -ErrorAction SilentlyContinue)
    Check ($runningDota.Count -eq 0) "DOTA2_IS_RUNNING: fully exit Dota 2 and Workshop Tools before repair"
}

$gamePaths = @(
    "resource/overviews/template_map.txt",
    "materials/overviews/survival_minimap.vmat_c",
    "materials/overviews/survival_minimap_tga_81334029.vtex_c",
    "maps/template_map.vpk"
)
$contentPaths = @(
    "materials/overviews/survival_minimap.tga",
    "materials/overviews/survival_minimap.vmat",
    "materials/overviews/survival_minimap.txt"
)

if ($SyncRepositories) {
    $gameStatus = @(Invoke-Git $game @("status", "--porcelain"))
    $contentStatus = @(Invoke-Git $content @("status", "--porcelain"))
    Check ($gameStatus.Count -eq 0) "GAME_REPOSITORY_DIRTY: commit or stash changes before -SyncRepositories"
    Check ($contentStatus.Count -eq 0) "CONTENT_REPOSITORY_DIRTY: commit or stash changes before -SyncRepositories"

    if ($PSCmdlet.ShouldProcess($content, "git pull --ff-only")) {
        Invoke-Git $content @("pull", "--ff-only") | ForEach-Object { Write-Host $_ }
    }
    if ($PSCmdlet.ShouldProcess($game, "git pull --ff-only")) {
        Invoke-Git $game @("pull", "--ff-only") | ForEach-Object { Write-Host $_ }
    }
}

$untrackedOverviewFiles = @(
    Invoke-Git $game @(
        "ls-files", "--others", "--exclude-standard", "--",
        "materials/overviews/template_map*",
        "materials/overviews/survival_minimap*"
    )
)
$staleFiles = @(
    $untrackedOverviewFiles | Where-Object {
        $_ -match '^materials/overviews/(template_map|survival_minimap).*\.(vmat_c|vtex_c)$'
    }
)

if ($staleFiles.Count -gt 0) {
    $backupRoot = Join-Path $env:TEMP ("Survival-minimap-stale-" + (Get-Date -Format "yyyyMMdd-HHmmss"))
    foreach ($relativePath in $staleFiles) {
        $source = Join-Path $game $relativePath
        $destination = Join-Path $backupRoot $relativePath
        if ($PSCmdlet.ShouldProcess($source, "move stale untracked minimap output to $destination")) {
            $destinationDirectory = Split-Path -Parent $destination
            New-Item -ItemType Directory -Path $destinationDirectory -Force | Out-Null
            Move-Item -LiteralPath $source -Destination $destination -Force
        }
    }
    Write-Host "STALE_MINIMAP_BACKUP=$backupRoot"
}

if ($PSCmdlet.ShouldProcess($content, "restore tracked minimap source files from HEAD")) {
    Invoke-Git $content (@("restore", "--source=HEAD", "--worktree", "--") + $contentPaths) | Out-Null
}
if ($PSCmdlet.ShouldProcess($game, "restore tracked minimap runtime files from HEAD")) {
    Invoke-Git $game (@("restore", "--source=HEAD", "--worktree", "--") + $gamePaths) | Out-Null
}

if (-not $WhatIfPreference) {
    & $verifyScript -GameRoot $game -ContentRoot $content `
        -ResourceCompiler $ResourceCompiler -RequireCleanGit
    if ($LASTEXITCODE -ne 0) { throw "MINIMAP_VERIFY_FAILED: exit=$LASTEXITCODE" }
}

$gameCommit = (Invoke-Git $game @("rev-parse", "HEAD") | Select-Object -First 1)
$contentCommit = (Invoke-Git $content @("rev-parse", "HEAD") | Select-Object -First 1)
if ($WhatIfPreference) {
    Write-Host "MINIMAP_CLIENT_REPAIR_PREVIEW"
} else {
    Write-Host "MINIMAP_CLIENT_REPAIR_PASS"
}
Write-Host "GAME_COMMIT=$gameCommit"
Write-Host "CONTENT_COMMIT=$contentCommit"