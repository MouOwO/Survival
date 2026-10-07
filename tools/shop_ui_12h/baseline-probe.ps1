$ErrorActionPreference='Stop'
$shopRepo=(Get-Location).Path
$shopEngine=[IO.Path]::GetFullPath((Join-Path $shopRepo '../../..'))
$shopContent=Join-Path $shopEngine 'content/dota_addons/Survival/panorama/scripts/custom_game/commerce_remaining_5d5c1152eb.js'
$shopCompiled=Join-Path $shopRepo 'panorama/scripts/custom_game/commerce_remaining_5d5c1152eb.vjs_c'
$shopBackup=Join-Path $shopRepo 'output/commerce_ui_12h/native_before_probe'
if($args[0] -eq 'restore') {
    Copy-Item -LiteralPath (Join-Path $shopBackup 'controller.js') -Destination $shopContent -Force
    Copy-Item -LiteralPath (Join-Path $shopBackup 'controller.vjs_c') -Destination $shopCompiled -Force
    Write-Output 'BASELINE_PROBE_RESTORED'
    exit
}
if(Test-Path -LiteralPath (Join-Path $shopBackup 'controller.js')){throw 'Baseline probe backup already exists: restore before another probe'}
New-Item -ItemType Directory -Path $shopBackup -Force|Out-Null
Copy-Item -LiteralPath $shopContent -Destination (Join-Path $shopBackup 'controller.js')
Copy-Item -LiteralPath $shopCompiled -Destination (Join-Path $shopBackup 'controller.vjs_c')
$shopOriginal=[IO.File]::ReadAllText((Join-Path $shopRepo 'design_refs/shop_ui_12h/work/checkpoints/baseline/commerce_remaining_5d5c1152eb.js'))
$shopCommand='survival_commerce_baseline_'+[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
$shopCode='if(Game.IsInToolsMode && Game.IsInToolsMode()){Game.AddCommand("'+$shopCommand+'",function(){cfg.SurvivalCommerceView.Open();},"Open saved task baseline; no checkout",0);}'
$shopModified=$shopOriginal.Replace('}());',$shopCode+"`r`n"+'}());')
if($shopModified -eq $shopOriginal){throw 'Baseline insertion point missing'}
[IO.File]::WriteAllText($shopContent,$shopModified,[Text.UTF8Encoding]::new($false))
[IO.File]::WriteAllText((Join-Path $shopBackup 'command.json'),('{"open":"'+$shopCommand+'"}'),[Text.UTF8Encoding]::new($false))
& (Join-Path $shopEngine 'game/bin/win64/resourcecompiler.exe') -i $shopContent -fshallow -nop4
if($LASTEXITCODE -ne 0){throw 'Baseline compilation failed; restore backup'}
Write-Output ('BASELINE_PROBE_READY '+$shopCommand)
