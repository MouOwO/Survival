param([ValidateSet('all','wood','attribute','greater_attribute')][string]$Theme='all',[switch]$SkipMap)
$ErrorActionPreference='Stop'
$roomGame=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$roomContent=[IO.Path]::GetFullPath((Join-Path $roomGame '../../../content/dota_addons/survival'))
$roomCompiler=[IO.Path]::GetFullPath((Join-Path $roomGame '../../bin/win64/resourcecompiler.exe'))
$roomThemes=if($Theme -eq 'all'){@('wood','attribute','greater_attribute')}else{@($Theme)}
foreach($roomTheme in $roomThemes){
 $roomNamespace=$roomTheme+'_training_room'
 $roomOut=Join-Path $roomGame ('output/'+$roomNamespace)
 $roomSource=Join-Path $roomOut 'source'
 $roomFiles=@(Get-ChildItem -LiteralPath $roomSource -Recurse -File)
 foreach($roomFile in $roomFiles){
  $roomRelative=$roomFile.FullName.Substring($roomSource.Length+1)
  $roomTarget=Join-Path $roomContent $roomRelative
  New-Item -ItemType Directory -Force -Path (Split-Path $roomTarget) | Out-Null
  Copy-Item -LiteralPath $roomFile.FullName -Destination $roomTarget -Force
 }
 foreach($roomExt in @('.vmat','.vmdl')){
  foreach($roomFile in $roomFiles | Where-Object Extension -eq $roomExt){
   $roomTarget=Join-Path $roomContent $roomFile.FullName.Substring($roomSource.Length+1)
   $roomLog=Join-Path $roomOut ($roomFile.Name+'.compile.log')
   & $roomCompiler -i $roomTarget -game (Join-Path $roomGame '../../dota') *> $roomLog
   if($LASTEXITCODE -ne 0 -or -not(Select-String -LiteralPath $roomLog -Pattern '0 failed')){throw "Compile failed: $roomLog"}
  }
 }
 if(-not $SkipMap){
  $roomStart=Get-Date
  & $roomCompiler -i (Join-Path $roomContent ('maps/'+$roomNamespace+'_review.vmap')) -game (Join-Path $roomGame '../../dota') -f *> (Join-Path $roomOut 'map_compile.log')
  $roomVpk=Get-Item -LiteralPath (Join-Path $roomGame ('maps/'+$roomNamespace+'_review.vpk'))
  if($LASTEXITCODE -ne 0 -or $roomVpk.LastWriteTime -lt $roomStart -or -not(Select-String -LiteralPath (Join-Path $roomOut 'map_compile.log') -Pattern 'VPK: Wrote file')){throw "Map compile failed: $roomNamespace"}
  @{map=$roomVpk.Name;builtAt=$roomVpk.LastWriteTimeUtc.ToString('o');sha256=(Get-FileHash -LiteralPath $roomVpk.FullName).Hash}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $roomOut 'compile.json') -Encoding utf8
 }
 Write-Output ('THEME_INSTALLED '+$roomNamespace)
}
