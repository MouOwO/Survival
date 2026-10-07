$ErrorActionPreference='Stop'
$shopRepo=(Get-Location).Path
$shopEngine=[IO.Path]::GetFullPath((Join-Path $shopRepo '../../..'))
$shopContent=Join-Path $shopEngine 'content/dota_addons/Survival/panorama/scripts/custom_game/survival_ui.js'
$shopCompiled=Join-Path $shopRepo 'panorama/scripts/custom_game/survival_ui.vjs_c'
$shopBackup=Join-Path $shopRepo 'output/commerce_ui_12h/mode_probe'
if($args[0] -eq 'restore') {
    Copy-Item -LiteralPath (Join-Path $shopBackup 'survival_ui.js') -Destination $shopContent -Force
    Copy-Item -LiteralPath (Join-Path $shopBackup 'survival_ui.vjs_c') -Destination $shopCompiled -Force
    Write-Output 'MODE_PROBE_RESTORED'
    exit
}
if((Test-Path -LiteralPath (Join-Path $shopBackup 'survival_ui.js')) -and $args[0] -ne 'update') {throw 'Existing probe backup: restore it before starting another probe.'}
New-Item -ItemType Directory -Path $shopBackup -Force|Out-Null
if($args[0] -ne 'update') {
    Copy-Item -LiteralPath $shopContent -Destination (Join-Path $shopBackup 'survival_ui.js')
    Copy-Item -LiteralPath $shopCompiled -Destination (Join-Path $shopBackup 'survival_ui.vjs_c')
}
$shopOriginal=[IO.File]::ReadAllText((Join-Path $shopBackup 'survival_ui.js'))
$shopCode='if (Game.IsInToolsMode && Game.IsInToolsMode()) { Game.AddCommand("survival_shop_mode_probe", function(){ modeChoice="pure"; confirmMode(); }, "Choose pure mode via the existing guarded UI handler", 0); Game.AddCommand("survival_shop_difficulty_probe", function(){ var a=difficultyOptions().filter(difficultyUnlocked); if(a.length){difficultyChoice=String(a[0].difficulty_id);selectDifficulty();} }, "Choose first unlocked difficulty via the existing guarded UI handler", 0); }'
$shopGeneration=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
$shopMode='survival_shop_mode_probe_'+$shopGeneration
$shopDifficulty='survival_shop_difficulty_probe_'+$shopGeneration
$shopCode=$shopCode.Replace('survival_shop_mode_probe',$shopMode).Replace('survival_shop_difficulty_probe',$shopDifficulty)
@{mode=$shopMode;difficulty=$shopDifficulty}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $shopBackup 'commands.json')
$shopModified=$shopOriginal.Replace('scheduleInitialBuilderSelection("hud_ready");',$shopCode+"`r`n"+'    scheduleInitialBuilderSelection("hud_ready");')
if($shopModified -eq $shopOriginal){throw 'Mode probe insertion point missing'}
[IO.File]::WriteAllText($shopContent,$shopModified, [Text.UTF8Encoding]::new($false))
& (Join-Path $shopEngine 'game/bin/win64/resourcecompiler.exe') -i $shopContent -fshallow -nop4
if($LASTEXITCODE -ne 0){throw 'Mode probe compilation failed; restore backup'}
Write-Output 'MODE_PROBE_READY'
