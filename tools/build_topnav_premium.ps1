$ErrorActionPreference='Stop'
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$engine=[IO.Path]::GetFullPath((Join-Path $repo '../../..'))
$content=Join-Path $engine 'content/dota_addons/Survival/panorama'
$compiler=Join-Path $engine 'game/bin/win64/resourcecompiler.exe'
$files=@(
 'images/custom_game/topnav_v2/return.svg'
 'images/custom_game/topnav_v2/treasure.svg'
 'images/custom_game/topnav_v2/archive.svg'
 'images/custom_game/topnav_v2/lottery.svg'
 'images/custom_game/topnav_v2/benefit.svg'
 'images/custom_game/topnav_v2/shop.svg'
 'images/custom_game/topnav_v2/survival_shop.svg'
 'styles/custom_game/handoff_v1.css'
 'scripts/custom_game/topnav_remaining_5d5c1152eb.js')
$failed=@()
foreach($rel in $files){
 $target=Join-Path $content $rel
 if(-not (Test-Path $target)){throw "Missing source: $target"}
 $output=& $compiler -i $target -game (Join-Path $engine 'game/dota') -f -nop4 2>&1
 $output | Set-Content (Join-Path $repo ('tools/topnav_premium_'+[IO.Path]::GetFileName($rel)+'.log'))
 $ok=($LASTEXITCODE -eq 0) -and ($output -match '0 failed')
 if(-not $ok){$failed+=$rel}
 $output | Select-String 'OK:' | ForEach-Object {$_.Line}
}
if($failed.Count){Write-Host ('FAILED: '+($failed -join ', '));exit 1}
Write-Host 'PANORAMA_COMPILE_PASS'
