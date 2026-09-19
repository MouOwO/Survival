$ErrorActionPreference='Stop'
$cloudGameRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$cloudContentRoot='D:/steam/steamapps/common/dota 2 beta/content/dota_addons/survival'
$cloudOut=Join-Path $cloudGameRoot 'output/survival_world_v2'
$cloudBackup=Join-Path $cloudOut 'before_cloud_integration_v2'
$cloudCompiler='D:/steam/steamapps/common/dota 2 beta/game/bin/win64/resourcecompiler.exe'
$cloudEngine='D:/steam/steamapps/common/dota 2 beta/game/dota'
if (-not (Test-Path (Join-Path $cloudBackup 'compiled_particles'))) {
 New-Item -ItemType Directory -Path (Join-Path $cloudBackup 'compiled_particles') -Force | Out-Null
 New-Item -ItemType Directory -Path (Join-Path $cloudBackup 'source_particles') -Force | Out-Null
 Get-ChildItem -LiteralPath (Join-Path $cloudGameRoot 'particles/survival_world_v2') -Filter 'cloud_bank*' | ForEach-Object {Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $cloudBackup 'compiled_particles')}
 Get-ChildItem -LiteralPath (Join-Path $cloudContentRoot 'particles/survival_world_v2') -Filter 'cloud_bank*' | ForEach-Object {Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $cloudBackup 'source_particles')}
}
$cloudJobs=@()
$cloudVariants=Join-Path $cloudGameRoot 'output/xianxia_kit/cloud_revision_v2/variants/source_materials'
Get-ChildItem -LiteralPath $cloudVariants -File | ForEach-Object {Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $cloudContentRoot 'materials/xianxia_kit') -Force;if($_.Extension -eq '.vtex'){$cloudJobs+=(Join-Path $cloudContentRoot ('materials/xianxia_kit/'+$_.Name))}}
Copy-Item -LiteralPath (Join-Path $cloudOut 'source_materials/cloud_horizon.vmat') -Destination (Join-Path $cloudContentRoot 'materials/survival_world_v2/cloud_horizon.vmat') -Force
$cloudJobs+=(Join-Path $cloudContentRoot 'materials/survival_world_v2/cloud_horizon.vmat')
$cloudDesign=Get-Content -LiteralPath (Join-Path $cloudOut 'cultivation_design.json') -Raw | ConvertFrom-Json
foreach($cloudGroup in @('outer','inner')){for($cloudIndex=0;$cloudIndex -lt $cloudDesign.$cloudGroup.Count;$cloudIndex++){
 $cloudName='cloud_bank_'+$cloudGroup+'_'+$cloudIndex.ToString('00')+'.vpcf'
 $cloudDest=Join-Path $cloudContentRoot ('particles/survival_world_v2/'+$cloudName)
 Copy-Item -LiteralPath (Join-Path $cloudOut ('source_particles/'+$cloudName)) -Destination $cloudDest -Force
 $cloudJobs+=$cloudDest
}}
$cloudCombinedLog=Join-Path $cloudOut 'cloud_composition_resources.log'
Set-Content -LiteralPath $cloudCombinedLog -Value ''
foreach($cloudJob in $cloudJobs){
 $cloudTemp=Join-Path $cloudOut 'cloud_current_resource.log'
 & $cloudCompiler -i $cloudJob -game $cloudEngine -f *> $cloudTemp
 Get-Content -LiteralPath $cloudTemp | Add-Content -LiteralPath $cloudCombinedLog
 if($LASTEXITCODE -ne 0 -or -not (Select-String -LiteralPath $cloudTemp -Pattern '0 failed')){throw "Cloud compilation failed: $cloudJob"}
}
Write-Output "Compiled $($cloudJobs.Count) cloud resources"
foreach($cloudGame in Get-CimInstance Win32_Process -Filter "Name = 'dota2.exe'"){
 if($cloudGame.CommandLine -match '(survival_world_v2|xianxia_kit_review)'){Stop-Process -Id $cloudGame.ProcessId -Force;Wait-Process -Id $cloudGame.ProcessId -Timeout 10 -ErrorAction SilentlyContinue}
}
$cloudMap=Join-Path $cloudContentRoot 'maps/survival_world_v2.vmap'
Copy-Item -LiteralPath (Join-Path $cloudOut 'survival_world_v2.vmap') -Destination $cloudMap -Force
$cloudStart=Get-Date
& $cloudCompiler -i $cloudMap -game $cloudEngine -f *> (Join-Path $cloudOut 'cloud_composition_map.log')
$cloudVpk=Get-Item -LiteralPath (Join-Path $cloudGameRoot 'maps/survival_world_v2.vpk')
if($LASTEXITCODE -ne 0 -or $cloudVpk.LastWriteTime -lt $cloudStart -or -not (Select-String -LiteralPath (Join-Path $cloudOut 'cloud_composition_map.log') -Pattern 'VPK: Wrote file')){throw 'Main map package not freshly written'}
@{map='survival_world_v2';builtAt=$cloudVpk.LastWriteTime.ToUniversalTime().ToString('o');sha256=(Get-FileHash -LiteralPath $cloudVpk.FullName).Hash;resources=$cloudJobs.Count;outer=$cloudDesign.outer.Count;inner=$cloudDesign.inner.Count;backup=$cloudBackup} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $cloudOut 'cloud_composition_compile.json') -Encoding utf8
Write-Output "World map compiled: $($cloudVpk.LastWriteTime)"
