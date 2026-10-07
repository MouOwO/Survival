param([string[]]$Names=@(), [string]$Stage="output/building_models_20260927")
$ErrorActionPreference='Stop'
$repo=Split-Path $PSScriptRoot -Parent
$engine=[IO.Path]::GetFullPath((Join-Path $repo '../../..'))
$content=Join-Path $engine 'content/dota_addons/survival'
$stage=[IO.Path]::GetFullPath((Join-Path $repo $Stage))
$manifest=Get-Content -LiteralPath (Join-Path $stage 'manifest.json') -Raw|ConvertFrom-Json
foreach($asset in $manifest){
 $name=$asset.name
 if($Names.Count -and $name -notin $Names){continue}
 foreach($kind in @('models','materials')){
  $rel=$kind+'/survival_buildings';$dst=Join-Path $content $rel
  New-Item -ItemType Directory -Force $dst|Out-Null
  Get-ChildItem -LiteralPath (Join-Path $stage ('source/'+$rel)) -Filter ($name+'*') -File|ForEach-Object {
   $target=Join-Path $dst $_.Name
   if(Test-Path -LiteralPath $target){$saved=Join-Path $stage ('content_before/'+$rel+'/'+$_.Name);if(!(Test-Path -LiteralPath $saved)){New-Item -ItemType Directory -Force (Split-Path $saved)|Out-Null;Copy-Item -LiteralPath $target -Destination $saved}}
   Copy-Item -LiteralPath $_.FullName -Destination $target -Force
  }
  Get-ChildItem -LiteralPath (Join-Path $repo $rel) -Filter ($name+'*') -File|ForEach-Object {
   $saved=Join-Path $stage ('before/'+$rel+'/'+$_.Name)
   if(!(Test-Path -LiteralPath $saved)){New-Item -ItemType Directory -Force (Split-Path $saved)|Out-Null;Copy-Item -LiteralPath $_.FullName -Destination $saved}
  }
 }
 foreach($model in @($name,($name+'_white_shell'))){
  $log=@(& (Join-Path $engine 'game/bin/win64/resourcecompiler.exe') -i (Join-Path $content ('models/survival_buildings/'+$model+'.vmdl')) -game (Join-Path $engine 'game/dota') -nop4 2>&1)
  $code=$LASTEXITCODE;$log|Set-Content -Encoding UTF8 (Join-Path $stage ($model+'.compile.log'))
  if($code -ne 0 -or -not ($log -match '0 failed')){throw ('Model compilation failed: '+$model)}
  Write-Output ('COMPILED '+$model)
 }
}
Write-Output 'CONCEPT_BUILDING_MODEL_COMPILE_PASS'
