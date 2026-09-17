param([switch]$CheckOnly)
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$gameRoot = Split-Path -Parent (Split-Path -Parent $repo)
$engineRoot = Split-Path -Parent $gameRoot
$contentRoot = Join-Path $engineRoot 'content/dota_addons/Survival/panorama'
$hud = Join-Path $contentRoot 'layout/custom_game/survival_hud.xml'
$source = Join-Path $repo 'panorama/src'
$files = @('scripts/custom_game/ui_layers.js', 'scripts/custom_game/lottery_ui.js', 'styles/custom_game/lottery_celestial.css', 'images/custom_game/lottery_celestial/home.png', 'images/custom_game/lottery_celestial/results.png')
$handoff = Join-Path $source 'images/custom_game/lottery_handoff'
$files += Get-ChildItem -LiteralPath $handoff -File -Recurse | ForEach-Object { 'images/custom_game/lottery_handoff/' + $_.FullName.Substring($handoff.Length + 1).Replace('\', '/') }
foreach ($relative in $files) { if (-not (Test-Path -LiteralPath (Join-Path $source $relative))) { throw "Missing: $relative" } }
$fragment = [IO.File]::ReadAllText((Join-Path $source 'layout/custom_game/lottery_window.xml'))
[xml]$validFragment = $fragment
$text = [IO.File]::ReadAllText($hud)
$pattern = '(?s)<Panel id="LotteryWindow".*?(?=<Panel id="LotteryItemTooltip")'
if ([regex]::Matches($text, $pattern).Count -ne 1) { throw 'Expected exactly one existing lottery window before tooltip' }
$text = [regex]::Replace($text, $pattern, [System.Text.RegularExpressions.MatchEvaluator]{ param($match) $fragment + "`r`n        " })
$include = '<include src="file://{resources}/styles/custom_game/lottery_celestial.css" />'
if (-not $text.Contains($include)) { $text = $text.Replace('</styles>', ('    ' + $include + "`r`n    </styles>")) }
$layerInclude = '<include src="file://{resources}/scripts/custom_game/ui_layers.js" />'
if (-not $text.Contains($layerInclude)) { $text = $text.Replace('<scripts>', ('<scripts>' + "`r`n        " + $layerInclude)) }
[xml]$validHud = $text
foreach ($id in @('LotteryWindow','LotterySingleButton','LotteryTenButton','LotteryAgain','LotteryItemTooltip')) {
    if ($validHud.SelectNodes("//*[@id='$id']").Count -ne 1) { throw "Missing or duplicated panel: $id" }
}
if ($CheckOnly) { Write-Output 'LOTTERY_DEPLOY_CHECK_PASS'; exit 0 }
# Preserve the live HUD before the scoped replacement, including unrelated user edits.
$backupDir = Join-Path $repo 'ui/lottery_celestial/backups'
New-Item -ItemType Directory -Force -Path $backupDir | Out-Null
Copy-Item -LiteralPath $hud -Destination (Join-Path $backupDir ((Get-Date -Format 'yyyyMMdd_HHmmss_fff') + '_survival_hud.xml'))
foreach ($relative in $files) {
    $destination = Join-Path $contentRoot $relative
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $destination) | Out-Null
    Copy-Item -LiteralPath (Join-Path $source $relative) -Destination $destination -Force
}
[IO.File]::WriteAllText($hud, $text, [Text.UTF8Encoding]::new($false))
$compiler = Join-Path $gameRoot 'bin/win64/resourcecompiler.exe'
foreach ($file in @((Join-Path $contentRoot 'scripts/custom_game/ui_layers.js'), (Join-Path $contentRoot 'styles/custom_game/lottery_celestial.css'), (Join-Path $contentRoot 'scripts/custom_game/lottery_ui.js'), $hud)) {
    & $compiler -i $file -game (Join-Path $gameRoot 'dota') -f
    if ($LASTEXITCODE -ne 0) { throw "Compile failed: $file" }
}
# Dynamic JS image paths are not automatically discovered by the layout compiler.
foreach ($icon in (Get-ChildItem -LiteralPath (Join-Path $contentRoot 'images/custom_game/lottery_handoff/icons') -Filter '*.svg' -File)) {
    & $compiler -i $icon.FullName -game (Join-Path $gameRoot 'dota') -f
    if ($LASTEXITCODE -ne 0) { throw "Icon compile failed: $($icon.Name)" }
}
Write-Output 'LOTTERY_PANORAMA_DEPLOY_PASS'
