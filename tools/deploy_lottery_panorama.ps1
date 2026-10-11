param([switch]$CheckOnly)
$ErrorActionPreference = 'Stop'
# The active lottery lives inside survival_hud.xml and the V10 shared shell.
# Keep this historical entry point compatible without restoring retired skins.
$lotteryRepo = Split-Path -Parent $PSScriptRoot
$lotteryScope = Join-Path $lotteryRepo 'tools/menus_v10/compile_scope.json'
$lotteryCompiler = Join-Path $lotteryRepo 'tools/menus_v10/compile.ps1'
$lotteryLayout = Join-Path $lotteryRepo 'panorama/src/layout/custom_game/survival_hud.xml'
[xml]$lotteryHud = [IO.File]::ReadAllText($lotteryLayout)
if ($lotteryHud.SelectNodes("//*[@id='LotteryWindow']").Count -ne 1) {
    throw 'Expected exactly one active lottery panel in survival_hud.xml.'
}
$lotteryFiles = Get-Content -LiteralPath $lotteryScope -Raw -Encoding UTF8 | ConvertFrom-Json
foreach ($lotteryRelative in $lotteryFiles) {
    if (-not (Test-Path -LiteralPath (Join-Path $lotteryRepo ('panorama/src/' + $lotteryRelative)) -PathType Leaf)) {
        throw "Missing current V10 source: $lotteryRelative"
    }
}
if ($lotteryFiles -notcontains 'scripts/custom_game/menu_purple.js' -or
    $lotteryFiles -notcontains 'layout/custom_game/survival_hud.xml') {
    throw 'The shared compile scope must include the current lottery renderer and HUD.'
}
if ($CheckOnly) { Write-Output 'LOTTERY_V10_DEPLOY_CHECK_PASS'; exit 0 }
& $lotteryCompiler -Scope 'tools/menus_v10/compile_scope.json' -Report 'output/lottery_v10_deploy/compile.json'
Write-Output 'LOTTERY_V10_PANORAMA_DEPLOY_PASS'
