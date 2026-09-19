param([switch]$SkipMap)
$ErrorActionPreference='Stop'
$moltenGame=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$moltenContent=[IO.Path]::GetFullPath((Join-Path $moltenGame '../../../content/dota_addons/survival'))
$moltenOut=Join-Path $moltenGame 'output/molten_core_room'
$moltenSource=Join-Path $moltenOut 'source'
$moltenCompiler=[IO.Path]::GetFullPath((Join-Path $moltenGame '../../bin/win64/resourcecompiler.exe'))
$moltenFiles=@(Get-ChildItem -LiteralPath $moltenSource -Recurse -File)
foreach($moltenFile in $moltenFiles){
 $moltenRelative=$moltenFile.FullName.Substring($moltenSource.Length+1)
 $moltenTarget=Join-Path $moltenContent $moltenRelative
 New-Item -ItemType Directory -Force -Path (Split-Path $moltenTarget) | Out-Null
 Copy-Item -LiteralPath $moltenFile.FullName -Destination $moltenTarget -Force
}
foreach($moltenExt in @('.vmat','.vmdl')){
 foreach($moltenFile in $moltenFiles | Where-Object Extension -eq $moltenExt){
  $moltenTarget=Join-Path $moltenContent $moltenFile.FullName.Substring($moltenSource.Length+1)
  $moltenLog=Join-Path $moltenOut ($moltenFile.Name+'.compile.log')
  & $moltenCompiler -i $moltenTarget -game (Join-Path $moltenGame '../../dota') *> $moltenLog
  if($LASTEXITCODE -ne 0 -or -not(Select-String -LiteralPath $moltenLog -Pattern '0 failed')){throw "Molten room compile failed: $moltenLog"}
  Write-Output ('Compiled '+$moltenFile.Name)
 }
}
if(-not $SkipMap){
 $moltenMap=Join-Path $moltenContent 'maps/molten_core_room_review.vmap'
 $moltenStart=Get-Date
 & $moltenCompiler -i $moltenMap -game (Join-Path $moltenGame '../../dota') -f *> (Join-Path $moltenOut 'map_compile.log')
 $moltenVpk=Get-Item -LiteralPath (Join-Path $moltenGame 'maps/molten_core_room_review.vpk')
 if($LASTEXITCODE -ne 0 -or $moltenVpk.LastWriteTime -lt $moltenStart -or -not(Select-String -LiteralPath (Join-Path $moltenOut 'map_compile.log') -Pattern 'VPK: Wrote file')){throw 'Molten room map did not compile'}
 @{map=$moltenVpk.Name;builtAt=$moltenVpk.LastWriteTimeUtc.ToString('o');sha256=(Get-FileHash -LiteralPath $moltenVpk.FullName).Hash}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $moltenOut 'compile.json') -Encoding utf8
 Write-Output 'Compiled molten_core_room_review.vpk'
}
