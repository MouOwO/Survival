param([switch]$CheckOnly,[switch]$SetupManifestOnly)
$ErrorActionPreference='Stop'
$taskRepo=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$taskEngine=[IO.Path]::GetFullPath((Join-Path $taskRepo '../../..'))
$taskContent=Join-Path $taskEngine 'content/dota_addons/Survival/panorama'
$taskCompiler=Join-Path $taskEngine 'game/bin/win64/resourcecompiler.exe'
$taskBackup=Join-Path $taskRepo ('output/loading_refine_20261016/compile_'+(Get-Date -Format yyyyMMdd_HHmmss_fff)+'_'+[guid]::NewGuid().ToString('N').Substring(0,8))
$taskFiles=@('layout/custom_game/custom_ui_manifest.xml','styles/custom_game/startup_loading.css','scripts/custom_game/startup_loading.js','layout/custom_game/startup_loading.xml','layout/custom_game/custom_loading_screen.xml','images/custom_game/loading/dawnward_citadel_background.png','images/custom_game/loading/warcraft_loading_fill.png','images/custom_game/loading/warcraft_loading_frame_left.png','images/custom_game/loading/warcraft_loading_frame_center.png','images/custom_game/loading/warcraft_loading_frame_right.png')
$taskSetupFiles=@('scripts/custom_game/native_team_setup.js','layout/custom_game/native_team_setup.xml','layout/custom_game/startup_team_setup_loading.xml','layout/custom_game/custom_ui_manifest.xml')
if($SetupManifestOnly){$taskFiles=$taskSetupFiles}else{$taskFiles=$taskSetupFiles+@($taskFiles | Where-Object {$_ -ne 'layout/custom_game/custom_ui_manifest.xml'})}
$taskRecords=@()
foreach($relative in $taskFiles){
 $authored=Join-Path $taskRepo ('panorama/src/'+$relative)
 $source=$authored
 # Loading image sources are versioned under art; panorama/src/images is ignored.
 if($relative -like 'images/custom_game/loading/warcraft_loading_*.png' -or $relative -eq 'images/custom_game/loading/dawnward_citadel_background.png'){$source=Join-Path $taskRepo ('art/ui/sources/'+($relative -replace '^images/',''))}
 if(-not(Test-Path -LiteralPath $source)){throw "Missing source $relative"}
 $compiled=$relative -replace '\.js$','.vjs_c' -replace '\.css$','.vcss_c' -replace '\.xml$','.vxml_c' -replace '\.png$','_png.vtex_c'
 $content=Join-Path $taskContent $relative
 $artifact=Join-Path $taskRepo ('panorama/'+$compiled)
 $taskRecords+=[pscustomobject]@{relative=$relative;source=$source;authored=$authored;content=$content;artifact=$artifact;sourceHash=(Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash;compiledHash=$null;hadAuthored=(Test-Path -LiteralPath $authored);hadContent=(Test-Path -LiteralPath $content);hadArtifact=(Test-Path -LiteralPath $artifact);authoredBackup=(Join-Path $taskBackup ('authored/'+$relative));contentBackup=(Join-Path $taskBackup ('content/'+$relative));runtimeBackup=(Join-Path $taskBackup ('runtime/'+$compiled))}
}
if($CheckOnly){'DAWNWARD_LOADING_COMPILE_SCOPE_PASS '+$taskFiles.Count+' reviewed sources/dependencies';return}
foreach($record in $taskRecords){
 foreach($target in @($record.authoredBackup,$record.contentBackup,$record.runtimeBackup,$record.content)){New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force|Out-Null}
 if($record.source -ne $record.authored -and $record.hadAuthored){Copy-Item -LiteralPath $record.authored -Destination $record.authoredBackup}
 if($record.hadContent){Copy-Item -LiteralPath $record.content -Destination $record.contentBackup}
 if($record.hadArtifact){Copy-Item -LiteralPath $record.artifact -Destination $record.runtimeBackup}
}
try{
 foreach($record in $taskRecords){
  if($record.source -ne $record.authored){New-Item -ItemType Directory -Path (Split-Path -Parent $record.authored) -Force|Out-Null;Copy-Item -LiteralPath $record.source -Destination $record.authored -Force}
  Copy-Item -LiteralPath $record.source -Destination $record.content -Force
 }
 foreach($record in $taskRecords){
  if($record.relative -like '*.png'){continue}
  $compileArgs=@('-i',$record.content,'-game',(Join-Path $taskEngine 'game/dota'),'-nop4')
  # Manifest needs compilation, not a recursive rebuild of unrelated HUDs.
  if($record.relative -notlike '*.xml' -or $record.relative -eq 'layout/custom_game/custom_ui_manifest.xml'){$compileArgs+='-fshallow'}
  $log=@(& $taskCompiler @compileArgs 2>&1)
  $log|Set-Content -LiteralPath (Join-Path $taskBackup (([IO.Path]::GetFileName($record.source))+'.log')) -Encoding utf8
  if($LASTEXITCODE -ne 0 -or -not($log -match '0 failed')){throw "Compile failed: $($record.relative)"}
  Write-Output ('DAWNWARD_LOADING_COMPILE_PASS '+$record.relative)
 }
 foreach($record in $taskRecords){
  if((Get-FileHash -LiteralPath $record.source -Algorithm SHA256).Hash -ne $record.sourceHash -or (Get-FileHash -LiteralPath $record.authored -Algorithm SHA256).Hash -ne $record.sourceHash -or (Get-FileHash -LiteralPath $record.content -Algorithm SHA256).Hash -ne $record.sourceHash -or -not(Test-Path -LiteralPath $record.artifact)){throw "Source drift or missing resource: $($record.relative)"}
  $record.compiledHash=(Get-FileHash -LiteralPath $record.artifact -Algorithm SHA256).Hash
 }
}catch{
 foreach($record in $taskRecords){
  if($record.source -ne $record.authored){
   if($record.hadAuthored){Copy-Item -LiteralPath $record.authoredBackup -Destination $record.authored -Force}elseif(Test-Path -LiteralPath $record.authored){Remove-Item -LiteralPath $record.authored}
  }
  if($record.hadContent){Copy-Item -LiteralPath $record.contentBackup -Destination $record.content -Force}elseif(Test-Path -LiteralPath $record.content){Remove-Item -LiteralPath $record.content}
  if($record.hadArtifact){Copy-Item -LiteralPath $record.runtimeBackup -Destination $record.artifact -Force}elseif(Test-Path -LiteralPath $record.artifact){Remove-Item -LiteralPath $record.artifact}
 }
 throw
}
$taskReport=Join-Path $taskRepo 'output/loading_refine_20261016/compile.json'
if($SetupManifestOnly){$taskReport=Join-Path $taskRepo 'output/loading_refine_20261016/setup_manifest_compile.json'}
@{at=(Get-Date -Format o);success=$true;backup=$taskBackup;records=$taskRecords;native_setup_manifest_compiled=$true;unrelated_huds_compiled=$false}|ConvertTo-Json -Depth 6|Set-Content -LiteralPath $taskReport -Encoding utf8
'DAWNWARD_LOADING_NATIVE_IMAGE_PASS'
