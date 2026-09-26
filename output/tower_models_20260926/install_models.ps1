param([int]$OnlyLevel=0)
$ErrorActionPreference='Stop'
$repo=(Get-Location).Path;$engine=[IO.Path]::GetFullPath((Join-Path $repo '../../..'))
$content=Join-Path $engine 'content/dota_addons/survival';$stage=Join-Path $repo 'output/tower_models_20260926'
$names=if($OnlyLevel){@(('arrow_tower_lv{0:d2}' -f $OnlyLevel))}else{@(1..5|ForEach-Object {'arrow_tower_lv{0:d2}' -f $_})}
foreach($name in $names){
 foreach($kind in @('models','materials')){
  $rel=$kind+'/survival_buildings';$dst=Join-Path $content $rel
  New-Item -ItemType Directory -Force $dst|Out-Null
  Get-ChildItem -LiteralPath (Join-Path $stage ('source/'+$rel)) -Filter ($name+'*') -File|ForEach-Object {
   $target=Join-Path $dst $_.Name
   if(Test-Path -LiteralPath $target){$saved=Join-Path $stage ('content_before/'+$rel+'/'+$_.Name);if(!(Test-Path -LiteralPath $saved)){New-Item -ItemType Directory -Force (Split-Path $saved)|Out-Null;Copy-Item -LiteralPath $target -Destination $saved}}
   Copy-Item -LiteralPath $_.FullName -Destination $target -Force
  }
 }
 $models=@($name)
 if(Test-Path -LiteralPath (Join-Path $content ('models/survival_buildings/'+$name+'_white_shell.vmdl'))){$models+=($name+'_white_shell')}
 foreach($model in $models){
  $log=@(& (Join-Path $engine 'game/bin/win64/resourcecompiler.exe') -i (Join-Path $content ('models/survival_buildings/'+$model+'.vmdl')) -game (Join-Path $engine 'game/dota') -nop4 2>&1)
  $code=$LASTEXITCODE;$log|Set-Content -Encoding UTF8 (Join-Path $stage ($model+'.compile.log'))
  if($code -ne 0 -or -not ($log -match '0 failed')){throw ('Model compilation failed: '+$model)}
  $log|Where-Object {$_ -match 'RESOURCE COMPILE|failed'}|Write-Output
 }
}
Write-Output 'ARROW_TOWER_MODEL_COMPILE_PASS'
