param([switch]$CheckOnly,[switch]$IdentityOnly)
$ErrorActionPreference='Stop'
$rankRepo=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$rankEngine=[IO.Path]::GetFullPath((Join-Path $rankRepo '../../..'))
$rankContent=[IO.Path]::GetFullPath((Join-Path $rankEngine 'content/dota_addons/Survival/panorama'))
$rankRuntime=[IO.Path]::GetFullPath((Join-Path $rankRepo 'panorama'))
$rankCompiler=Join-Path $rankEngine 'game/bin/win64/resourcecompiler.exe'
$rankFiles=@('scripts/custom_game/endless_leaderboard.js','styles/custom_game/endless_leaderboard.css','scripts/custom_game/archive_v10.js','scripts/custom_game/archive_180de7e38b_titles_compact_v6.js','layout/custom_game/archive.xml')
$rankReport=Join-Path $rankRepo 'design_refs/endless_leaderboard_20261016/ui/compile.json'
$rankSourceManifest=Get-Content -LiteralPath (Join-Path $rankRepo 'design_refs/endless_leaderboard_20261016/ui/source_manifest.json') -Raw -Encoding UTF8|ConvertFrom-Json
$rankAssembly=Get-Content -LiteralPath (Join-Path $rankRepo 'design_refs/endless_leaderboard_20261016/ui/preview/assembly.json') -Raw -Encoding UTF8|ConvertFrom-Json
$rankVisual=Get-Content -LiteralPath (Join-Path $rankRepo 'design_refs/endless_leaderboard_20261016/ui/visual_report.json') -Raw -Encoding UTF8|ConvertFrom-Json
if($rankVisual.status -ne 'PASS' -or -not $rankVisual.notGameCapture){throw 'The final reviewed component screenshots must pass before native compilation.'}
if(@($rankSourceManifest.sources.PSObject.Properties).Count -ne $rankFiles.Count){throw 'Reviewed source manifest does not match the exact five-file compile scope.'}
if(-not(Test-Path -LiteralPath $rankCompiler -PathType Leaf)){throw 'Native resourcecompiler is missing.'}
$rankBackup=Join-Path $rankRepo ('output/endless_leaderboard_20261016/compile_'+(Get-Date -Format yyyyMMdd_HHmmss_fff)+'_'+[guid]::NewGuid().ToString('N').Substring(0,8))
$rankRecords=@()
foreach($relative in $rankFiles){
 $source=[IO.Path]::GetFullPath((Join-Path $rankRepo ('panorama/src/'+$relative)))
 $content=[IO.Path]::GetFullPath((Join-Path $rankContent $relative))
 $compiled=$relative -replace '\.js$','.vjs_c' -replace '\.css$','.vcss_c' -replace '\.xml$','.vxml_c'
 $artifact=[IO.Path]::GetFullPath((Join-Path $rankRuntime $compiled))
 if(-not $source.StartsWith((Join-Path $rankRepo 'panorama/src')+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase) -or -not $content.StartsWith($rankContent+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase) -or -not $artifact.StartsWith($rankRuntime+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw "Compile path escaped the approved roots: $relative"}
 if(-not(Test-Path -LiteralPath $source -PathType Leaf)){throw "Missing source: $relative"}
 $hash=(Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash.ToLowerInvariant()
 $expected=$rankSourceManifest.sources.PSObject.Properties[$relative].Value
 $preview=@($rankAssembly.sourceGraph|Where-Object {$_.path -eq $relative})
 if($hash -ne $expected -or $preview.Count -ne 1 -or $hash -ne $preview[0].sha256){throw "Reviewed screenshot/source hash mismatch: $relative"}
 $rankRecords+=[pscustomobject]@{relative=$relative;source=$source;content=$content;artifact=$artifact;sourceHash=$hash;previewSourceHash=$preview[0].sha256;contentHash=$null;compiledHash=$null;artifactBytes=$null;artifactWriteUtc=$null;verified=$false;hadContent=(Test-Path -LiteralPath $content -PathType Leaf);hadArtifact=(Test-Path -LiteralPath $artifact -PathType Leaf);sourceBackup=(Join-Path $rankBackup ('source/'+$relative));contentBackup=(Join-Path $rankBackup ('content/'+$relative));runtimeBackup=(Join-Path $rankBackup ('runtime/'+$compiled));log=(Join-Path $rankBackup (([IO.Path]::GetFileName($source))+'.log'))}
}
$rankCompileRecords=$rankRecords
if($IdentityOnly){
 $rankPrevious=Get-Content -LiteralPath $rankReport -Raw -Encoding UTF8|ConvertFrom-Json
 if(-not $rankPrevious.success -or $rankPrevious.records.Count -ne 5){throw 'Incremental identity repair requires the preceding successful five-file compile report.'}
 foreach($record in $rankRecords|Where-Object {$_.relative -ne 'scripts/custom_game/endless_leaderboard.js'}){
  $old=@($rankPrevious.records|Where-Object {$_.relative -eq $record.relative})
  if($old.Count -ne 1 -or $old[0].sourceHash -ne $record.sourceHash -or (Get-FileHash -LiteralPath $record.content -Algorithm SHA256).Hash.ToLowerInvariant() -ne $record.sourceHash -or (Get-FileHash -LiteralPath $record.artifact -Algorithm SHA256).Hash.ToLowerInvariant() -ne $old[0].compiledHash){throw "Unselected source/content/runtime changed: $($record.relative)"}
  foreach($name in @('contentHash','compiledHash','artifactBytes','artifactWriteUtc','verified','sourceBackup','contentBackup','runtimeBackup','log')){$record.$name=$old[0].$name}
 }
 $rankCompileRecords=@($rankRecords|Where-Object {$_.relative -eq 'scripts/custom_game/endless_leaderboard.js'})
}
if($CheckOnly){[pscustomobject]@{success=$true;checkOnly=$true;files=$rankFiles.Count;previewSourceMatch=$true;visualStatus=$rankVisual.status}|ConvertTo-Json;return}
$rankBackedUp=$false
try{
 foreach($record in $rankCompileRecords){
  foreach($target in @($record.sourceBackup,$record.contentBackup,$record.runtimeBackup)){New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force|Out-Null}
  Copy-Item -LiteralPath $record.source -Destination $record.sourceBackup
  if($record.hadContent){Copy-Item -LiteralPath $record.content -Destination $record.contentBackup}
  if($record.hadArtifact){Copy-Item -LiteralPath $record.artifact -Destination $record.runtimeBackup}
 }
 if(Test-Path -LiteralPath $rankReport -PathType Leaf){Copy-Item -LiteralPath $rankReport -Destination (Join-Path $rankBackup 'previous_compile.json')}
 $rankBackedUp=$true
 # Place every reviewed dependency before compiling the manifest last.
 foreach($record in $rankCompileRecords){New-Item -ItemType Directory -Path (Split-Path -Parent $record.content) -Force|Out-Null;Copy-Item -LiteralPath $record.source -Destination $record.content -Force}
 foreach($record in $rankCompileRecords){
  $start=(Get-Date).ToUniversalTime()
  $log=@(& $rankCompiler -i $record.content -game (Join-Path $rankEngine 'game/dota') -fshallow -nop4 2>&1)
  $exitCode=$LASTEXITCODE
  $log|Set-Content -LiteralPath $record.log -Encoding utf8
  if($exitCode -ne 0 -or -not($log -match '0 failed')){throw "Native compilation failed: $($record.relative); see $($record.log)"}
  if(-not(Test-Path -LiteralPath $record.artifact -PathType Leaf)){throw "Missing compiled artifact: $($record.relative)"}
  $record.contentHash=(Get-FileHash -LiteralPath $record.content -Algorithm SHA256).Hash.ToLowerInvariant()
  if((Get-FileHash -LiteralPath $record.source -Algorithm SHA256).Hash.ToLowerInvariant() -ne $record.sourceHash -or $record.contentHash -ne $record.sourceHash -or (Get-Item -LiteralPath $record.artifact).LastWriteTimeUtc -lt $start){throw "Source drift or stale artifact: $($record.relative)"}
  $record.compiledHash=(Get-FileHash -LiteralPath $record.artifact -Algorithm SHA256).Hash.ToLowerInvariant()
  $record.artifactBytes=(Get-Item -LiteralPath $record.artifact).Length
  $record.artifactWriteUtc=(Get-Item -LiteralPath $record.artifact).LastWriteTimeUtc.ToString('o')
  $record.verified=$true
  Write-Output ('ENDLESS_LEADERBOARD_NATIVE_COMPILE_PASS '+$record.relative)
 }
 # Recheck all sources after the final compile to catch cross-file edits.
 foreach($record in $rankRecords){if((Get-FileHash -LiteralPath $record.source -Algorithm SHA256).Hash.ToLowerInvariant() -ne $record.sourceHash -or (Get-FileHash -LiteralPath $record.content -Algorithm SHA256).Hash.ToLowerInvariant() -ne $record.sourceHash -or (Get-FileHash -LiteralPath $record.artifact -Algorithm SHA256).Hash.ToLowerInvariant() -ne $record.compiledHash){throw "Final source/content/artifact drift: $($record.relative)"}}
 @{at=[DateTime]::UtcNow.ToString('o');success=$true;files=$rankFiles.Count;compiledThisRun=$rankCompileRecords.Count;identityOnly=[bool]$IdentityOnly;previewSourceMatch=$true;notGameCapture=$true;visualReport='design_refs/endless_leaderboard_20261016/ui/visual_report.json';compiler=$rankCompiler;backup=$rankBackup;records=$rankRecords}|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $rankReport -Encoding utf8
}catch{
 $failure=$_
 if($rankBackedUp){foreach($record in $rankCompileRecords){
  if($record.hadContent){Copy-Item -LiteralPath $record.contentBackup -Destination $record.content -Force}else{if(Test-Path -LiteralPath $record.content -PathType Leaf){Remove-Item -LiteralPath $record.content}}
  if($record.hadArtifact){Copy-Item -LiteralPath $record.runtimeBackup -Destination $record.artifact -Force}else{if(Test-Path -LiteralPath $record.artifact -PathType Leaf){Remove-Item -LiteralPath $record.artifact}}
 }}
 @{at=[DateTime]::UtcNow.ToString('o');success=$false;restored=$rankBackedUp;failure=[string]$failure;backup=$rankBackup;records=$rankRecords}|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $rankReport -Encoding utf8
 throw $failure
}
