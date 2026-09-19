param([switch]$SkipMap,[switch]$MaterialsOnly)
$ErrorActionPreference='Stop'
$goldGame=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$goldContent=[IO.Path]::GetFullPath((Join-Path $goldGame '../../../content/dota_addons/survival'))
$goldOut=Join-Path $goldGame 'output/gold_training_room'
$goldSource=Join-Path $goldOut 'source'
$goldCompiler=[IO.Path]::GetFullPath((Join-Path $goldGame '../../bin/win64/resourcecompiler.exe'))
$goldFiles=@(Get-ChildItem -LiteralPath $goldSource -Recurse -File)
if($MaterialsOnly){
 # A surface revision must not replace model/map edits or the navigation support.
 $goldMaterialRoot=Join-Path $goldSource 'materials/gold_training_room'
 $goldFiles=@(Get-ChildItem -LiteralPath $goldMaterialRoot -File | Where-Object {
  $_.Name -ne 'floor_support.vmat' -and $_.Extension -in '.vmat','.png'
 })
 $SkipMap=$true
}
foreach($goldFile in $goldFiles){
 $goldRelative=$goldFile.FullName.Substring($goldSource.Length+1)
 $goldTarget=Join-Path $goldContent $goldRelative
 New-Item -ItemType Directory -Force -Path (Split-Path $goldTarget) | Out-Null
 Copy-Item -LiteralPath $goldFile.FullName -Destination $goldTarget -Force
}
foreach($goldExt in @('.vmat','.vmdl')){
 foreach($goldFile in $goldFiles | Where-Object Extension -eq $goldExt){
  $goldTarget=Join-Path $goldContent $goldFile.FullName.Substring($goldSource.Length+1)
  $goldLog=Join-Path $goldOut ($goldFile.Name+'.compile.log')
  & $goldCompiler -i $goldTarget -game (Join-Path $goldGame '../../dota') *> $goldLog
  if($LASTEXITCODE -ne 0 -or -not(Select-String -LiteralPath $goldLog -Pattern '0 failed')){throw "Gold room compile failed: $goldLog"}
  Write-Output ('Compiled '+$goldFile.Name)
 }
}
if(-not $SkipMap){
 $goldMap=Join-Path $goldContent 'maps/gold_training_room_review.vmap'
 $goldStart=Get-Date
 & $goldCompiler -i $goldMap -game (Join-Path $goldGame '../../dota') -f *> (Join-Path $goldOut 'map_compile.log')
 $goldVpk=Get-Item -LiteralPath (Join-Path $goldGame 'maps/gold_training_room_review.vpk')
 if($LASTEXITCODE -ne 0 -or $goldVpk.LastWriteTime -lt $goldStart -or -not(Select-String -LiteralPath (Join-Path $goldOut 'map_compile.log') -Pattern 'VPK: Wrote file')){throw 'Gold room map did not compile'}
 @{map=$goldVpk.Name;builtAt=$goldVpk.LastWriteTimeUtc.ToString('o');sha256=(Get-FileHash -LiteralPath $goldVpk.FullName).Hash}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $goldOut 'compile.json') -Encoding utf8
 Write-Output 'Compiled gold_training_room_review.vpk'
}
