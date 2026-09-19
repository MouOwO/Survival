param([switch]$SkipMap)
$ErrorActionPreference='Stop'
$realmGame=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$realmContent=[IO.Path]::GetFullPath((Join-Path $realmGame '../../../content/dota_addons/survival'))
$realmCompiler=[IO.Path]::GetFullPath((Join-Path $realmGame '../../bin/win64/resourcecompiler.exe'))
$realmOut=Join-Path $realmGame 'output/ten_realm_arenas'
$realmSource=Join-Path $realmOut 'source'
if(-not(Test-Path -LiteralPath $realmSource -PathType Container)){throw 'No ten-realm source directory. Build assets and maps first.'}
if(-not(Test-Path -LiteralPath $realmCompiler -PathType Leaf)){throw "Compiler not found: $realmCompiler"}
$realmFiles=@(Get-ChildItem -LiteralPath $realmSource -Recurse -File)
if(-not $realmFiles){throw 'No ten-realm sources built.'}
$realmModels=@($realmFiles | Where-Object Extension -eq '.vmdl')
if($realmModels.Count -ne 10){throw 'Expected exactly ten realm model sources.'}
foreach($realmRank in 1..10){
 $realmName='realm_{0:d2}.vmdl' -f $realmRank
 if(-not($realmModels | Where-Object Name -eq $realmName)){throw "Missing realm model: $realmName"}
}
# Validate the complete copy set before writing any file into content.
foreach($realmFile in $realmFiles){
 $realmRelative=$realmFile.FullName.Substring($realmSource.Length+1)
 if($realmRelative -notmatch '^(models|materials)\\ten_realm_arenas\\|^maps\\(ten_realm_arenas_review\.vmap|prefabs\\ten_realm_arena_(0[1-9]|10)\.vmap)$'){
  throw "Unexpected asset path: $realmRelative"
 }
 $realmTarget=[IO.Path]::GetFullPath((Join-Path $realmContent $realmRelative))
 if(-not $realmTarget.StartsWith($realmContent+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){
  throw "Target outside addon content: $realmTarget"
 }
}
if(-not $SkipMap){
 if(-not(Test-Path -LiteralPath (Join-Path $realmSource 'maps/ten_realm_arenas_review.vmap') -PathType Leaf)){
  throw 'Build the ten-realm review map before installing it.'
 }
 foreach($realmRank in 1..10){
  $realmPrefab=Join-Path $realmSource ('maps/prefabs/ten_realm_arena_{0:d2}.vmap' -f $realmRank)
  if(-not(Test-Path -LiteralPath $realmPrefab -PathType Leaf)){throw "Missing realm prefab: $realmPrefab"}
 }
}
foreach($realmFile in $realmFiles){
 $realmRelative=$realmFile.FullName.Substring($realmSource.Length+1)
 $realmTarget=Join-Path $realmContent $realmRelative
 New-Item -ItemType Directory -Force -Path (Split-Path $realmTarget) | Out-Null
 Copy-Item -LiteralPath $realmFile.FullName -Destination $realmTarget -Force
}
foreach($realmExt in @('.vmat','.vmdl')){
 foreach($realmFile in $realmFiles | Where-Object Extension -eq $realmExt){
  $realmTarget=Join-Path $realmContent $realmFile.FullName.Substring($realmSource.Length+1)
  $realmLog=Join-Path $realmOut ($realmFile.Name+'.compile.log')
  & $realmCompiler -i $realmTarget -game (Join-Path $realmGame '../../dota') *> $realmLog
  if($LASTEXITCODE -ne 0 -or -not(Select-String -LiteralPath $realmLog -Pattern '0 failed')){
   throw "Ten-realm resource compilation failed: $realmLog"
  }
  Write-Output ('TEN_REALM_COMPILED '+$realmFile.Name)
 }
}
if(-not $SkipMap){
 $realmStart=Get-Date
 $realmMapLog=Join-Path $realmOut 'map_compile.log'
 & $realmCompiler -i (Join-Path $realmContent 'maps/ten_realm_arenas_review.vmap') -game (Join-Path $realmGame '../../dota') -f *> $realmMapLog
 if($LASTEXITCODE -ne 0){throw "Ten-realm map compiler returned an error: $realmMapLog"}
 $realmVpk=Get-Item -LiteralPath (Join-Path $realmGame 'maps/ten_realm_arenas_review.vpk')
 if($realmVpk.LastWriteTime -lt $realmStart -or -not(Select-String -LiteralPath $realmMapLog -Pattern 'VPK: Wrote file')){
  throw 'Ten-realm map did not produce a fresh VPK.'
 }
 @{map=$realmVpk.Name;builtAt=$realmVpk.LastWriteTimeUtc.ToString('o');sha256=(Get-FileHash -LiteralPath $realmVpk.FullName).Hash}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $realmOut 'compile.json') -Encoding utf8
}
Write-Output 'TEN_REALM_ASSETS_INSTALLED'
