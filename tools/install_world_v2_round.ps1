$ErrorActionPreference='Stop'
$roundRoot='D:/steam/steamapps/common/dota 2 beta/game/dota_addons/survival'
$roundContent='D:/steam/steamapps/common/dota 2 beta/content/dota_addons/survival'
$roundOut=Join-Path $roundRoot 'output/survival_world_v2'
$roundCompiler='D:/steam/steamapps/common/dota 2 beta/game/bin/win64/resourcecompiler.exe'
$roundEngine='D:/steam/steamapps/common/dota 2 beta/game/dota'
foreach($roundPng in Get-ChildItem -LiteralPath (Join-Path $roundRoot 'output/ocean_study') -Filter '*.png'){
 Copy-Item -LiteralPath $roundPng.FullName -Destination (Join-Path $roundContent ('materials/survival_world_v2/'+$roundPng.Name)) -Force
}
foreach($roundName in @('island_meadow','island_natural_rock','island_ocean_waves','island_shallow_blend','ocean_water')){
 $roundMat=Join-Path $roundContent ('materials/survival_world_v2/'+$roundName+'.vmat')
 Copy-Item -LiteralPath (Join-Path $roundOut ('source_materials/'+$roundName+'.vmat')) -Destination $roundMat -Force
 & $roundCompiler -i $roundMat -game $roundEngine -f *> (Join-Path $roundOut ('round_'+$roundName+'_compile.log'))
 if($LASTEXITCODE -ne 0){throw "Material failed: $roundName"}
}
foreach($roundGame in Get-CimInstance Win32_Process -Filter "Name = 'dota2.exe'"){
 if($roundGame.CommandLine -match 'survival_world_v2'){Stop-Process -Id $roundGame.ProcessId -Force;Wait-Process -Id $roundGame.ProcessId -Timeout 10 -ErrorAction SilentlyContinue}
}
$roundMap=Join-Path $roundContent 'maps/survival_world_v2.vmap'
Copy-Item -LiteralPath (Join-Path $roundOut 'survival_world_v2.vmap') -Destination $roundMap -Force
$roundStart=Get-Date
& $roundCompiler -i $roundMap -game $roundEngine -f *> (Join-Path $roundOut 'round_map_compile.log')
$roundVpk=Get-Item -LiteralPath (Join-Path $roundRoot 'maps/survival_world_v2.vpk')
if($LASTEXITCODE -ne 0 -or $roundVpk.LastWriteTime -lt $roundStart -or -not(Select-String -LiteralPath (Join-Path $roundOut 'round_map_compile.log') -Pattern 'VPK: Wrote file')){throw 'Map package not freshly written'}
@{builtAt=$roundVpk.LastWriteTimeUtc.ToString('o');sha256=(Get-FileHash -LiteralPath $roundVpk.FullName).Hash;source='round island terrain and official ocean shader'} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $roundOut 'round_compile.json') -Encoding utf8
Write-Output "Round map compiled: $($roundVpk.LastWriteTime)"
