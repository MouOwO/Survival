param([switch]$SkipMap)
$ErrorActionPreference='Stop'
$arenaGame=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$arenaContent=[IO.Path]::GetFullPath((Join-Path $arenaGame '../../../content/dota_addons/survival'))
$arenaCompiler=[IO.Path]::GetFullPath((Join-Path $arenaGame '../../bin/win64/resourcecompiler.exe'))
$arenaOut=Join-Path $arenaGame 'output/ascension_arenas'
$arenaSource=Join-Path $arenaOut 'source'
$arenaFiles=@(Get-ChildItem -LiteralPath $arenaSource -Recurse -File)
if(-not $arenaFiles){throw 'No ascension sources built.'}
foreach($arenaFile in $arenaFiles){
 $arenaRelative=$arenaFile.FullName.Substring($arenaSource.Length+1)
 if($arenaRelative -notmatch '^(models|materials)\\ascension_arenas\\|^maps\\(ascension_arenas_review\.vmap|prefabs\\ascension_arena_\d{2}\.vmap)$'){throw "Unexpected asset path: $arenaRelative"}
 $arenaTarget=Join-Path $arenaContent $arenaRelative
 New-Item -ItemType Directory -Force -Path (Split-Path $arenaTarget) | Out-Null
 Copy-Item -LiteralPath $arenaFile.FullName -Destination $arenaTarget -Force
}
foreach($arenaExt in @('.vmat','.vmdl')){
 foreach($arenaFile in $arenaFiles | Where-Object Extension -eq $arenaExt){
  $arenaTarget=Join-Path $arenaContent $arenaFile.FullName.Substring($arenaSource.Length+1)
  $arenaLog=Join-Path $arenaOut ($arenaFile.Name+'.compile.log')
  & $arenaCompiler -i $arenaTarget -game (Join-Path $arenaGame '../../dota') *> $arenaLog
  if($LASTEXITCODE -ne 0 -or -not(Select-String -LiteralPath $arenaLog -Pattern '0 failed')){throw "Compile failed: $arenaLog"}
  Write-Output ('ARENA_COMPILED '+$arenaFile.Name)
 }
}
if(-not $SkipMap){
 $arenaStart=Get-Date
 & $arenaCompiler -i (Join-Path $arenaContent 'maps/ascension_arenas_review.vmap') -game (Join-Path $arenaGame '../../dota') -f *> (Join-Path $arenaOut 'map_compile.log')
 if($LASTEXITCODE -ne 0){throw 'Arena map compiler returned an error.'}
 $arenaVpk=Get-Item -LiteralPath (Join-Path $arenaGame 'maps/ascension_arenas_review.vpk')
 if($arenaVpk.LastWriteTime -lt $arenaStart -or -not(Select-String -LiteralPath (Join-Path $arenaOut 'map_compile.log') -Pattern 'VPK: Wrote file')){throw 'Arena map did not produce a fresh VPK.'}
 @{map=$arenaVpk.Name;builtAt=$arenaVpk.LastWriteTimeUtc.ToString('o');sha256=(Get-FileHash -LiteralPath $arenaVpk.FullName).Hash}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $arenaOut 'compile.json') -Encoding utf8
}
Write-Output 'ASCENSION_ASSETS_INSTALLED'
