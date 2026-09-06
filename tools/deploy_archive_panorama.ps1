param([switch]$CheckOnly)
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$gameRoot = Split-Path -Parent (Split-Path -Parent $repo)
$engineRoot = Split-Path -Parent $gameRoot
$contentRoot = Join-Path $engineRoot 'content/dota_addons/Survival'
$source = Join-Path $repo 'panorama/src'
$manifest = Join-Path $contentRoot 'panorama/layout/custom_game/custom_ui_manifest.xml'
$compiler = Join-Path $gameRoot 'bin/win64/resourcecompiler.exe'
$files = @('layout/custom_game/archive.xml', 'scripts/custom_game/archive.js', 'styles/custom_game/archive.css', 'styles/custom_game/archive_difficulty.css')
$files += @('scripts/custom_game/reward_presentation.js', 'scripts/custom_game/lottery_ui.js')
$files += @('scripts/custom_game/combat_stats.js')
$files += @('scripts/custom_game/daily_rewards.js', 'styles/custom_game/daily_rewards.css')
$files += @('scripts/custom_game/treasure_history.js')
$hudPath = Join-Path $contentRoot 'panorama/layout/custom_game/survival_hud.xml'
$hudText = [IO.File]::ReadAllText($hudPath)
$sharedScript = 'file://{resources}/scripts/custom_game/reward_presentation.js'
if (-not $hudText.Contains($sharedScript)) {
    $hudText = $hudText.Replace('<scripts>', ('<scripts>' + "`r`n" + '        <include src="' + $sharedScript + '" />'))
}
$difficultyStyle = 'file://{resources}/styles/custom_game/archive_difficulty.css'
if (-not $hudText.Contains($difficultyStyle)) {
    if (-not $hudText.Contains('</styles>')) { throw 'HUD styles section missing' }
    $hudText = $hudText.Replace('</styles>', ('    <include src="' + $difficultyStyle + '" />' + "`r`n    </styles>"))
}
foreach ($relative in $files) {
    if (-not (Test-Path (Join-Path $source $relative))) { throw "Missing source: $relative" }
}
if (-not (Test-Path $manifest)) { throw "Missing manifest: $manifest" }
[xml]$xml = Get-Content $manifest -Raw
$layout = 'file://{resources}/layout/custom_game/archive.xml'
if (-not ($xml.root.Panel.CustomUIElement | Where-Object { $_.layoutfile -eq $layout })) {
    $node = $xml.CreateElement('CustomUIElement')
    $node.SetAttribute('type', 'Hud'); $node.SetAttribute('layoutfile', $layout)
    $xml.root.Panel.AppendChild($node) | Out-Null
}
if ($CheckOnly) {
    Write-Host "ARCHIVE_DEPLOY_CHECK_PASS: 4 sources; archive Hud and difficulty layout; target $contentRoot"
    exit 0
}
foreach ($relative in $files) {
    Copy-Item -LiteralPath (Join-Path $source $relative) -Destination (Join-Path $contentRoot ('panorama/' + $relative)) -Force
}
$settings = [Xml.XmlWriterSettings]::new()
$settings.Indent = $true; $settings.Encoding = [Text.UTF8Encoding]::new($false)
$writer = [Xml.XmlWriter]::Create($manifest, $settings)
try { $xml.Save($writer) } finally { $writer.Dispose() }
[IO.File]::WriteAllText($hudPath, $hudText, [Text.UTF8Encoding]::new($false))
foreach ($file in (@($files | ForEach-Object { Join-Path $contentRoot ('panorama/' + $_) }) + @($manifest, $hudPath))) {
    & $compiler -i $file -game (Join-Path $gameRoot 'dota') -f
    if ($LASTEXITCODE -ne 0) { throw "Panorama compile failed: $file" }
}
Write-Host 'ARCHIVE_PANORAMA_DEPLOY_PASS'
