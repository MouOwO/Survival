param([switch]$CheckOnly)
$ErrorActionPreference='Stop'
$skinRepo=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$skinEngine=[IO.Path]::GetFullPath((Join-Path $skinRepo '../../..'))
$skinContent=Join-Path $skinEngine 'content/dota_addons/Survival/panorama'
$skinCompiler=Join-Path $skinEngine 'game/bin/win64/resourcecompiler.exe'
$skinPlan=Get-Content -LiteralPath (Join-Path $skinRepo 'output/archive_original_skin_20261018/compile_plan.json') -Raw -Encoding utf8 | ConvertFrom-Json
$skinBackup=Join-Path $skinRepo ('output/archive_original_skin_20261018/compile_'+(Get-Date -Format yyyyMMdd_HHmmss_fff))
$skinRecords=@()
foreach($skinEntry in $skinPlan.files){
 $skinRelative=[string]$skinEntry.path
 if($skinRelative -notmatch '^(images/custom_game/archive_parchment_v1/(window_background|header_strip|sidebar_background|content_background)\.png|layout/custom_game/archive_parchment_assets\.xml)$'){throw 'Unexpected original archive skin compilation source'}
 $skinSource=Join-Path $skinRepo ('panorama/src/'+$skinRelative)
 $skinDestination=[IO.Path]::GetFullPath((Join-Path $skinContent $skinRelative))
 $skinCompiled=$skinRelative -replace '\.png$','_png.vtex_c' -replace '\.xml$','.vxml_c'
 $skinArtifact=[IO.Path]::GetFullPath((Join-Path $skinRepo ('panorama/'+$skinCompiled)))
 if(-not $skinDestination.StartsWith($skinContent+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase) -or -not $skinArtifact.StartsWith((Join-Path $skinRepo 'panorama')+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw 'Compiled target escaped intended roots'}
 if((Get-FileHash -LiteralPath $skinSource -Algorithm SHA256).Hash.ToLowerInvariant() -ne $skinEntry.sha256){throw ('Reviewed source drift: '+$skinRelative)}
 $skinHadContent=Test-Path -LiteralPath $skinDestination
 $skinHadArtifact=Test-Path -LiteralPath $skinArtifact
 $skinReuse=$skinHadContent -and $skinHadArtifact -and ((Get-FileHash -LiteralPath $skinDestination -Algorithm SHA256).Hash.ToLowerInvariant() -eq $skinEntry.sha256)
 $skinBefore=if($skinHadArtifact){(Get-FileHash -LiteralPath $skinArtifact -Algorithm SHA256).Hash.ToLowerInvariant()}else{$null}
 $skinRecords+=[pscustomobject]@{relative=$skinRelative;source=$skinSource;sourceHash=$skinEntry.sha256;content=$skinDestination;artifact=$skinArtifact;isImage=($skinRelative -like 'images/*');hadContent=$skinHadContent;hadArtifact=$skinHadArtifact;reusable=$skinReuse;artifactHashBefore=$skinBefore;contentBackup=(Join-Path $skinBackup ('content/'+$skinRelative));artifactBackup=(Join-Path $skinBackup ('runtime/'+$skinCompiled));compiledHash=$null}
}
if($skinRecords.Count -ne 5 -or @($skinRecords.relative|Select-Object -Unique).Count -ne 5){throw 'Expected exactly four textures and the preload XML'}
if($CheckOnly){Write-Output 'ARCHIVE_ORIGINAL_SKIN_SCOPE_PASS 5';return}
foreach($skinRecord in $skinRecords){
 foreach($skinTarget in @($skinRecord.contentBackup,$skinRecord.artifactBackup,$skinRecord.content)){New-Item -ItemType Directory -Path (Split-Path -Parent $skinTarget) -Force|Out-Null}
 if($skinRecord.hadContent){Copy-Item -LiteralPath $skinRecord.content -Destination $skinRecord.contentBackup}
 if($skinRecord.hadArtifact){Copy-Item -LiteralPath $skinRecord.artifact -Destination $skinRecord.artifactBackup}
}
try{
 foreach($skinRecord in $skinRecords){Copy-Item -LiteralPath $skinRecord.source -Destination $skinRecord.content -Force}
 $skinStart=(Get-Date).ToUniversalTime()
 $skinXml=$skinRecords|Where-Object {-not $_.isImage}
 $skinLog=@(& $skinCompiler -i $skinXml.content -game (Join-Path $skinEngine 'game/dota') -fshallow -nop4 2>&1)
 $skinLog|Set-Content -LiteralPath (Join-Path $skinBackup 'native_compile.log') -Encoding utf8
 if($LASTEXITCODE -ne 0 -or -not($skinLog -match '0 failed')){throw 'Archive material native compilation failed'}
 foreach($skinRecord in $skinRecords){
  if((Get-FileHash -LiteralPath $skinRecord.source -Algorithm SHA256).Hash.ToLowerInvariant() -ne $skinRecord.sourceHash -or (Get-FileHash -LiteralPath $skinRecord.content -Algorithm SHA256).Hash.ToLowerInvariant() -ne $skinRecord.sourceHash){throw 'Source/content changed during compilation'}
  $skinFile=Get-Item -LiteralPath $skinRecord.artifact
  $skinRecord.compiledHash=(Get-FileHash -LiteralPath $skinRecord.artifact -Algorithm SHA256).Hash.ToLowerInvariant()
  $skinUnchanged=$skinRecord.isImage -and $skinRecord.reusable -and $skinRecord.artifactHashBefore -eq $skinRecord.compiledHash
  if($skinFile.Length -le 0 -or ($skinFile.LastWriteTimeUtc -lt $skinStart -and -not $skinUnchanged)){throw ('Stale material artifact: '+$skinRecord.relative)}
  Write-Output ('ARCHIVE_ORIGINAL_SKIN_NATIVE_PASS '+$skinRecord.relative)
 }
}catch{
 foreach($skinRecord in $skinRecords){
  if($skinRecord.hadContent){Copy-Item -LiteralPath $skinRecord.contentBackup -Destination $skinRecord.content -Force}elseif(Test-Path -LiteralPath $skinRecord.content){Remove-Item -LiteralPath $skinRecord.content}
  if($skinRecord.hadArtifact){Copy-Item -LiteralPath $skinRecord.artifactBackup -Destination $skinRecord.artifact -Force}elseif(Test-Path -LiteralPath $skinRecord.artifact){Remove-Item -LiteralPath $skinRecord.artifact}
 }
 throw
}
@{at=(Get-Date -Format o);success=$true;records=$skinRecords;backup=$skinBackup}|ConvertTo-Json -Depth 6|Set-Content -LiteralPath (Join-Path $skinRepo 'output/archive_original_skin_20261018/compile.json') -Encoding utf8
