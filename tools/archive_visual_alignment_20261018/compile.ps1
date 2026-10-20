param([switch]$CheckOnly)
$ErrorActionPreference='Stop'
$visualRepo=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$visualEngine=[IO.Path]::GetFullPath((Join-Path $visualRepo '../../..'))
$visualContent=Join-Path $visualEngine 'content/dota_addons/Survival/panorama'
$visualCompiler=Join-Path $visualEngine 'game/bin/win64/resourcecompiler.exe'
$visualOutput=Join-Path $visualRepo 'output/archive_visual_alignment_20261018'
$visualPlan=Get-Content -LiteralPath (Join-Path $visualOutput 'compile_plan.json') -Raw -Encoding utf8|ConvertFrom-Json
$visualBackup=Join-Path $visualOutput ('compile_'+(Get-Date -Format yyyyMMdd_HHmmss_fff))
$visualRecords=@()
foreach($visualEntry in $visualPlan.files){
 $visualRelative=[string]$visualEntry.path
 if($visualRelative -notmatch '^(scripts/custom_game/archive_v10\.js|styles/custom_game/archive_v10\.css|layout/custom_game/archive_parchment_assets\.xml|images/custom_game/archive_polish_v2/(nav/[a-z_]+|icon_ring)\.svg)$'){throw 'Unexpected archive visual compile source'}
 $visualSource=Join-Path $visualRepo ('panorama/src/'+$visualRelative)
 $visualDestination=[IO.Path]::GetFullPath((Join-Path $visualContent $visualRelative))
 $visualCompiled=$visualRelative -replace '\.js$','.vjs_c' -replace '\.css$','.vcss_c' -replace '\.xml$','.vxml_c' -replace '\.svg$','.vsvg_c'
 $visualArtifact=[IO.Path]::GetFullPath((Join-Path $visualRepo ('panorama/'+$visualCompiled)))
 if(-not $visualDestination.StartsWith($visualContent+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase) -or -not $visualArtifact.StartsWith((Join-Path $visualRepo 'panorama')+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw 'Compile target escaped intended roots'}
 if((Get-FileHash -LiteralPath $visualSource -Algorithm SHA256).Hash.ToLowerInvariant() -ne $visualEntry.sha256){throw "Reviewed source changed: $visualRelative"}
 $visualHadContent=Test-Path -LiteralPath $visualDestination
 $visualHadArtifact=Test-Path -LiteralPath $visualArtifact
 $visualRecords+=[pscustomobject]@{relative=$visualRelative;source=$visualSource;sha256=$visualEntry.sha256;content=$visualDestination;artifact=$visualArtifact;isImage=($visualRelative -like 'images/*');hadContent=$visualHadContent;hadArtifact=$visualHadArtifact;reusable=($visualHadContent -and $visualHadArtifact -and ((Get-FileHash -LiteralPath $visualDestination -Algorithm SHA256).Hash.ToLowerInvariant() -eq $visualEntry.sha256));beforeHash=$(if($visualHadArtifact){(Get-FileHash -LiteralPath $visualArtifact -Algorithm SHA256).Hash.ToLowerInvariant()}else{$null});contentBackup=(Join-Path $visualBackup ('content/'+$visualRelative));artifactBackup=(Join-Path $visualBackup ('runtime/'+$visualCompiled));compiledHash=$null}
}
if(-not $visualRecords.Count -or @($visualRecords.relative|Select-Object -Unique).Count -ne $visualRecords.Count){throw 'Empty or duplicate compile plan'}
if($CheckOnly){Write-Output ('ARCHIVE_VISUAL_COMPILE_SCOPE_PASS '+$visualRecords.Count);return}
foreach($visualRecord in $visualRecords){
 foreach($visualTarget in @($visualRecord.contentBackup,$visualRecord.artifactBackup,$visualRecord.content)){New-Item -ItemType Directory -Path (Split-Path -Parent $visualTarget) -Force|Out-Null}
 if($visualRecord.hadContent){Copy-Item -LiteralPath $visualRecord.content -Destination $visualRecord.contentBackup}
 if($visualRecord.hadArtifact){Copy-Item -LiteralPath $visualRecord.artifact -Destination $visualRecord.artifactBackup}
}
try{
 foreach($visualRecord in $visualRecords){Copy-Item -LiteralPath $visualRecord.source -Destination $visualRecord.content -Force}
 $visualStart=(Get-Date).ToUniversalTime()
 foreach($visualRecord in @($visualRecords|Where-Object {-not $_.isImage})){
  $visualLog=@(& $visualCompiler -i $visualRecord.content -game (Join-Path $visualEngine 'game/dota') -fshallow -nop4 2>&1)
  $visualLog|Set-Content -LiteralPath (Join-Path $visualBackup (([IO.Path]::GetFileName($visualRecord.source))+'.log')) -Encoding utf8
  if($LASTEXITCODE -ne 0 -or -not($visualLog -match '0 failed')){throw "Archive compile failed: $($visualRecord.relative)"}
 }
 foreach($visualRecord in $visualRecords){
  if((Get-FileHash -LiteralPath $visualRecord.source -Algorithm SHA256).Hash.ToLowerInvariant() -ne $visualRecord.sha256 -or (Get-FileHash -LiteralPath $visualRecord.content -Algorithm SHA256).Hash.ToLowerInvariant() -ne $visualRecord.sha256){throw 'Source/content changed during compile'}
  $visualFile=Get-Item -LiteralPath $visualRecord.artifact
  $visualRecord.compiledHash=(Get-FileHash -LiteralPath $visualRecord.artifact -Algorithm SHA256).Hash.ToLowerInvariant()
  if($visualFile.Length -le 0 -or ($visualFile.LastWriteTimeUtc -lt $visualStart -and -not($visualRecord.reusable -and $visualRecord.beforeHash -eq $visualRecord.compiledHash))){throw "Stale archive artifact: $($visualRecord.relative)"}
  Write-Output ('ARCHIVE_VISUAL_NATIVE_PASS '+$visualRecord.relative)
 }
}catch{
 foreach($visualRecord in $visualRecords){
  if($visualRecord.hadContent){Copy-Item -LiteralPath $visualRecord.contentBackup -Destination $visualRecord.content -Force}elseif(Test-Path -LiteralPath $visualRecord.content){Remove-Item -LiteralPath $visualRecord.content}
  if($visualRecord.hadArtifact){Copy-Item -LiteralPath $visualRecord.artifactBackup -Destination $visualRecord.artifact -Force}elseif(Test-Path -LiteralPath $visualRecord.artifact){Remove-Item -LiteralPath $visualRecord.artifact}
 }
 throw
}
@{at=(Get-Date -Format o);success=$true;records=$visualRecords;backup=$visualBackup}|ConvertTo-Json -Depth 6|Set-Content -LiteralPath (Join-Path $visualOutput 'compile.json') -Encoding utf8
