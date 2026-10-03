$ErrorActionPreference = 'Stop'
$sync = Join-Path $PSScriptRoot 'sync_archive_texture_sources.ps1'
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('survival_texture_sync_'+[Guid]::NewGuid().ToString('N'))
$game = Join-Path $fixture 'game'
$content = Join-Path $fixture 'content'
$utf8 = [Text.UTF8Encoding]::new($false)
function Write-File([string]$path, [string]$text) {
    $null = New-Item -ItemType Directory -Path (Split-Path -Parent $path) -Force
    [IO.File]::WriteAllText($path, $text, $utf8)
}
function Assert($value, [string]$message) { if (-not $value) { throw "TEST_FAILED: $message" } }
function Fails([scriptblock]$action, [string]$message) {
    try { $null = & $action } catch {
        Assert ($_.Exception.Message.Contains($message)) $_.Exception.Message
        return
    }
    throw "TEST_FAILED: expected $message"
}
$roots = @((Join-Path $game 'art/ui/sources'),(Join-Path $game 'panorama/src/images'),(Join-Path $content 'panorama/images'))
$recipe = "header`n`"m_fileName`" `"string`" `"panorama/images/custom_game/archive_items_v2/icon.png`"`n"
foreach ($root in $roots) {
    foreach ($group in @('archive_gpu_regular','archive_gpu_small')) {
        Write-File (Join-Path $root "custom_game/$group/icon.vtex") ($recipe.Replace("`n","`r`n"))
    }
}
# Missing mirror/content image dependencies should be copied from the master.
Write-File (Join-Path $roots[0] 'custom_game/archive_items_v2/icon.png') 'fixture image bytes'
Fails { & $sync -GameRoot $game -ContentRoot $content -CheckOnly } 'need LF normalization'
$changedContent = Join-Path $roots[2] 'custom_game/archive_gpu_small/icon.vtex'
Write-File $changedContent ($recipe+'real edit')
Fails { & $sync -GameRoot $game -ContentRoot $content } 'differs beyond line endings'
Assert ([IO.File]::ReadAllText((Join-Path $roots[0] 'custom_game/archive_gpu_regular/icon.vtex')).Contains("`r`n")) 'preflight failure must not change any input'
Write-File $changedContent $recipe
$null = & $sync -GameRoot $game -ContentRoot $content
$null = & $sync -GameRoot $game -ContentRoot $content -CheckOnly
$before = (Get-Item -LiteralPath $changedContent).LastWriteTimeUtc
$result = & $sync -GameRoot $game -ContentRoot $content
Assert (-not ($result -match 'REPAIRED')) 'second run must be a no-op'
Assert ((Get-Item -LiteralPath $changedContent).LastWriteTimeUtc -eq $before) 'do not touch an unchanged source'
foreach ($root in $roots) {
    Assert ([IO.File]::ReadAllText((Join-Path $root 'custom_game/archive_gpu_regular/icon.vtex')) -ceq $recipe) 'all roots must contain exact LF bytes'
    Assert ([IO.File]::ReadAllText((Join-Path $root 'custom_game/archive_items_v2/icon.png')) -ceq 'fixture image bytes') 'missing image copied'
}
Write-File (Join-Path $roots[2] 'custom_game/archive_items_v2/icon.png') 'artist edit'
Fails { & $sync -GameRoot $game -ContentRoot $content } 'Image content differs'
Write-Output 'ARCHIVE_TEXTURE_SYNC_PASS: LF normalization, dependency copying, no-op rerun, preflight preserves real edits.'
