$ErrorActionPreference='Stop'
$shopRepo=(Get-Location).Path
$shopEngine=Split-Path (Split-Path $shopRepo -Parent) -Parent
$shopContent=Join-Path (Split-Path $shopEngine -Parent) 'content/dota_addons/Survival/panorama/scripts/custom_game/startup_loading.js'
$shopCompiled=Join-Path $shopRepo 'panorama/scripts/custom_game/startup_loading.vjs_c'
$shopBackup=Join-Path $shopRepo 'output/commerce_ui_12h/startup_probe'
if($args[0] -eq 'restore') {
    Copy-Item -LiteralPath (Join-Path $shopBackup 'startup_loading.js') -Destination $shopContent -Force
    Copy-Item -LiteralPath (Join-Path $shopBackup 'startup_loading.vjs_c') -Destination $shopCompiled -Force
    Write-Output 'STARTUP_PROBE_RESTORED'
    exit
}
if((Test-Path -LiteralPath (Join-Path $shopBackup 'startup_loading.js')) -and $args[0] -ne 'update') {throw 'Existing probe backup: restore it before starting another probe.'}
New-Item -ItemType Directory -Path $shopBackup -Force|Out-Null
if($args[0] -ne 'update') {
    Copy-Item -LiteralPath $shopContent -Destination (Join-Path $shopBackup 'startup_loading.js')
    Copy-Item -LiteralPath $shopCompiled -Destination (Join-Path $shopBackup 'startup_loading.vjs_c')
}
$shopOriginal=[IO.File]::ReadAllText((Join-Path $shopBackup 'startup_loading.js'))
$shopCode='if (Game.IsInToolsMode && Game.IsInToolsMode()) { Game.AddCommand("survival_shop_startup_probe2", function(){ if (state && state.phase === "party_waiting" && state.selector_player_id === playerId()) send("survival_party_start"); }, "Same party start request and guard as the existing UI; no admission bypass", 0); }'
$shopCommand='survival_shop_startup_probe_'+[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
$shopCode=$shopCode.Replace('survival_shop_startup_probe2',$shopCommand)
$shopRetry=$shopCommand+'_retry'
$shopCode+=' if(Game.IsInToolsMode && Game.IsInToolsMode()){Game.AddCommand("'+$shopRetry+'",function(){ if(!released()){retry();background.SetImage("file://{images}/custom_game/commerce_jade_v1/startup_probe.png");}},"Same guarded retry with byte-identical startup image alias to test cache reload",0);}'
@{start=$shopCommand;retry=$shopRetry}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $shopBackup 'commands.json')
$shopModified=$shopOriginal.Replace('retryControl.button.SetPanelEvent("onactivate", retry);',$shopCode+"`r`n"+'    retryControl.button.SetPanelEvent("onactivate", retry);')
if($shopModified -eq $shopOriginal){throw 'Startup probe insertion point missing'}
[IO.File]::WriteAllText($shopContent,$shopModified, [Text.UTF8Encoding]::new($false))
$shopCompiler=Join-Path $shopEngine 'bin/win64/resourcecompiler.exe'
& $shopCompiler -i $shopContent -fshallow -nop4
if($LASTEXITCODE -ne 0){throw 'Startup probe compilation failed; restore backup'}
Write-Output 'STARTUP_PROBE_READY: survival_shop_startup_probe; restore after the normal startup flow'
