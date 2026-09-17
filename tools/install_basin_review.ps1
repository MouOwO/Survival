$ErrorActionPreference='Stop'
$basinRoot='D:/steam/steamapps/common/dota 2 beta/game/dota_addons/survival'
$basinContent='D:/steam/steamapps/common/dota 2 beta/content/dota_addons/survival'
$basinOut=Join-Path $basinRoot 'output/basin_review'
$basinCompiler='D:/steam/steamapps/common/dota 2 beta/game/bin/win64/resourcecompiler.exe'
$basinEngine='D:/steam/steamapps/common/dota 2 beta/game/dota'
New-Item -ItemType Directory -Path (Join-Path $basinContent 'materials/basin_review') -Force | Out-Null
if(Test-Path -LiteralPath (Join-Path $basinOut 'snow_material/bake_report.json')){
 foreach($basinTexture in Get-ChildItem -LiteralPath (Join-Path $basinOut 'snow_material') -Filter '*.png'){
  Copy-Item -LiteralPath $basinTexture.FullName -Destination (Join-Path $basinContent ('materials/basin_review/'+$basinTexture.Name)) -Force
 }
}
foreach($basinMat in Get-ChildItem -LiteralPath (Join-Path $basinOut 'materials') -Filter '*.vmat'){
 $basinTarget=Join-Path $basinContent ('materials/basin_review/'+$basinMat.Name)
 Copy-Item -LiteralPath $basinMat.FullName -Destination $basinTarget -Force
 & $basinCompiler -i $basinTarget -game $basinEngine -f *> (Join-Path $basinOut ($basinMat.BaseName+'_compile.log'))
 if($LASTEXITCODE -ne 0){throw ('Material compile failed '+$basinMat.Name)}
}
foreach($basinGame in Get-CimInstance Win32_Process -Filter "Name = 'dota2.exe'"){
 if($basinGame.CommandLine -match 'survival_basin_review'){Stop-Process -Id $basinGame.ProcessId -Force;Wait-Process -Id $basinGame.ProcessId -Timeout 10 -ErrorAction SilentlyContinue}
}
$basinMap=Join-Path $basinContent 'maps/survival_basin_review.vmap'
Copy-Item -LiteralPath (Join-Path $basinOut 'survival_basin_review.vmap') -Destination $basinMap -Force
$basinStart=Get-Date
& $basinCompiler -i $basinMap -game $basinEngine -f *> (Join-Path $basinOut 'map_compile.log')
$basinVpk=Get-Item -LiteralPath (Join-Path $basinRoot 'maps/survival_basin_review.vpk')
if($LASTEXITCODE -ne 0 -or $basinVpk.LastWriteTime -lt $basinStart -or -not(Select-String -LiteralPath (Join-Path $basinOut 'map_compile.log') -Pattern 'VPK: Wrote file')){throw 'Map package not freshly written'}
@{builtAt=$basinVpk.LastWriteTimeUtc.ToString('o');sha256=(Get-FileHash -LiteralPath $basinVpk.FullName).Hash} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $basinOut 'compile.json') -Encoding utf8
Write-Output "Basin review compiled: $($basinVpk.LastWriteTime)"
$basinEditable=Join-Path $basinContent 'maps/survival_basin_edit.vmap'
& node (Join-Path $basinRoot 'tools/basin_handoff_merge.cjs') $basinEditable
if($LASTEXITCODE -ne 0){throw 'User detail preservation check failed'}
