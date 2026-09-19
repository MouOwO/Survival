param([switch]$SkipMap)
$ErrorActionPreference='Stop'
$islandGame=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$islandContent=[IO.Path]::GetFullPath((Join-Path $islandGame '../../../content/dota_addons/survival'))
$islandOut=Join-Path $islandGame 'output/main_island'
$islandSource=Join-Path $islandOut 'source'
$islandCompiler=[IO.Path]::GetFullPath((Join-Path $islandGame '../../bin/win64/resourcecompiler.exe'))
$islandFiles=@(Get-ChildItem -LiteralPath $islandSource -Recurse -File)
foreach($islandFile in $islandFiles){
 $islandRelative=$islandFile.FullName.Substring($islandSource.Length+1)
 $islandTarget=Join-Path $islandContent $islandRelative
 New-Item -ItemType Directory -Force -Path (Split-Path $islandTarget) | Out-Null
 Copy-Item -LiteralPath $islandFile.FullName -Destination $islandTarget -Force
}
foreach($islandExt in @('.vmat','.vmdl')){
 foreach($islandFile in $islandFiles | Where-Object Extension -eq $islandExt){
  $islandTarget=Join-Path $islandContent $islandFile.FullName.Substring($islandSource.Length+1)
  $islandLog=Join-Path $islandOut ($islandFile.Name+'.compile.log')
  & $islandCompiler -i $islandTarget -game (Join-Path $islandGame '../../dota') *> $islandLog
  if($LASTEXITCODE -ne 0 -or -not(Select-String -LiteralPath $islandLog -Pattern '0 failed')){throw "Main island compile failed: $islandLog"}
  Write-Output ('Compiled '+$islandFile.Name)
 }
}
if(-not $SkipMap){
 $islandMap=Join-Path $islandContent 'maps/main_island_review.vmap'
 $islandStart=Get-Date
 & $islandCompiler -i $islandMap -game (Join-Path $islandGame '../../dota') -f *> (Join-Path $islandOut 'map_compile.log')
 $islandVpk=Get-Item -LiteralPath (Join-Path $islandGame 'maps/main_island_review.vpk')
 if($LASTEXITCODE -ne 0 -or $islandVpk.LastWriteTime -lt $islandStart -or -not(Select-String -LiteralPath (Join-Path $islandOut 'map_compile.log') -Pattern 'VPK: Wrote file')){throw 'Main island map did not compile'}
 @{map=$islandVpk.Name;builtAt=$islandVpk.LastWriteTimeUtc.ToString('o');sha256=(Get-FileHash -LiteralPath $islandVpk.FullName).Hash}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $islandOut 'compile.json') -Encoding utf8
 Write-Output 'Compiled main_island_review.vpk'
}
