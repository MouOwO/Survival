param([switch]$CheckOnly)
$ErrorActionPreference='Stop'
$skinRepo=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$skinEngine=[IO.Path]::GetFullPath((Join-Path $skinRepo '../../..'))
$skinContent=Join-Path $skinEngine 'content/dota_addons/Survival/panorama'
$skinCompiler=Join-Path $skinEngine 'game/bin/win64/resourcecompiler.exe'
$skinOutput=Join-Path $skinRepo 'output/collection_user_skin_20261019'
$skinPlan=Get-Content -LiteralPath (Join-Path $skinOutput 'compile_plan.json') -Raw -Encoding utf8|ConvertFrom-Json
$skinBackup=Join-Path $skinOutput ('compile_'+(Get-Date -Format yyyyMMdd_HHmmss_fff))
$skinRecords=@()
foreach($skinEntry in $skinPlan.files){
 $skinRelative=[string]$skinEntry.path
 if($skinRelative -notmatch '^(scripts/custom_game/collection_gw2\.js|styles/custom_game/collection_gw2\.css|layout/custom_game/collection_user_skin_assets\.xml|images/custom_game/collection_user_skin_v1/background\.(png|vtex))$'){throw 'Unexpected collection skin compilation source'}
 $skinSource=Join-Path $skinRepo ('panorama/src/'+$skinRelative)
 $skinDestination=[IO.Path]::GetFullPath((Join-Path $skinContent $skinRelative))
 $skinCompiled=$skinRelative -replace '\.js$','.vjs_c' -replace '\.css$','.vcss_c' -replace '\.xml$','.vxml_c' -replace '\.svg$','.vsvg_c' -replace '\.vtex$','.vtex_c'
 $skinArtifact=if($skinRelative -notlike '*.png'){[IO.Path]::GetFullPath((Join-Path $skinRepo ('panorama/'+$skinCompiled)))}else{$null}
 if(-not $skinDestination.StartsWith($skinContent+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase) -or ($skinArtifact -and -not $skinArtifact.StartsWith((Join-Path $skinRepo 'panorama')+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase))){throw 'Compile target escaped intended roots'}
 if((Get-FileHash -LiteralPath $skinSource -Algorithm SHA256).Hash.ToLowerInvariant() -ne $skinEntry.sha256){throw "Reviewed source changed: $skinRelative"}
 $skinHadContent=Test-Path -LiteralPath $skinDestination
 $skinHadArtifact=$skinArtifact -and (Test-Path -LiteralPath $skinArtifact)
 $skinRecords+=[pscustomobject]@{relative=$skinRelative;source=$skinSource;sha256=$skinEntry.sha256;content=$skinDestination;artifact=$skinArtifact;hadContent=$skinHadContent;hadArtifact=$skinHadArtifact;contentBackup=(Join-Path $skinBackup ('content/'+$skinRelative));runtimeBackup=$(if($skinArtifact){Join-Path $skinBackup ('runtime/'+$skinCompiled)}else{$null});reusable=($skinHadContent -and $skinHadArtifact -and ((Get-FileHash -LiteralPath $skinDestination -Algorithm SHA256).Hash.ToLowerInvariant() -eq $skinEntry.sha256));beforeHash=$(if($skinHadArtifact){(Get-FileHash -LiteralPath $skinArtifact -Algorithm SHA256).Hash.ToLowerInvariant()}else{$null});compiledHash=$null}
}
if($skinRecords.Count -ne 5 -or @($skinRecords.relative|Select-Object -Unique).Count -ne 5){throw 'Expected five unique collection skin source/dependency files'}
if($CheckOnly){Write-Output 'COLLECTION_USER_SKIN_COMPILE_SCOPE_PASS 5';return}
foreach($skinRecord in $skinRecords){
 foreach($skinTarget in @($skinRecord.contentBackup,$skinRecord.runtimeBackup,$skinRecord.content)|Where-Object {$_}){New-Item -ItemType Directory -Path (Split-Path -Parent $skinTarget) -Force|Out-Null}
 if($skinRecord.hadContent){Copy-Item -LiteralPath $skinRecord.content -Destination $skinRecord.contentBackup}
 if($skinRecord.hadArtifact){Copy-Item -LiteralPath $skinRecord.artifact -Destination $skinRecord.runtimeBackup}
}
try{
 foreach($skinRecord in $skinRecords){Copy-Item -LiteralPath $skinRecord.source -Destination $skinRecord.content -Force}
 $skinStart=(Get-Date).ToUniversalTime()
 $skinRoots=@($skinRecords|Where-Object {$_.relative -match '\.(vtex|js|css|xml)$'}|Sort-Object @{Expression={if($_.relative -like '*.vtex'){0}elseif($_.relative -like '*.xml'){2}else{1}}},relative)
 foreach($skinRecord in $skinRoots){
  $skinLog=@(& $skinCompiler -i $skinRecord.content -game (Join-Path $skinEngine 'game/dota') -fshallow -nop4 2>&1)
  $skinLog|Set-Content -LiteralPath (Join-Path $skinBackup (([IO.Path]::GetFileName($skinRecord.source))+'.log')) -Encoding utf8
  if($LASTEXITCODE -ne 0 -or -not($skinLog -match '0 failed')){throw "Native compile failed: $($skinRecord.relative)"}
 }
 foreach($skinRecord in $skinRecords){
  if((Get-FileHash -LiteralPath $skinRecord.source -Algorithm SHA256).Hash.ToLowerInvariant() -ne $skinRecord.sha256 -or (Get-FileHash -LiteralPath $skinRecord.content -Algorithm SHA256).Hash.ToLowerInvariant() -ne $skinRecord.sha256){throw 'Source/content drift during compilation'}
  if($skinRecord.artifact){
   $skinCompiledFile=Get-Item -LiteralPath $skinRecord.artifact
   $skinRecord.compiledHash=(Get-FileHash -LiteralPath $skinRecord.artifact -Algorithm SHA256).Hash.ToLowerInvariant()
   if($skinCompiledFile.Length -le 0 -or ($skinCompiledFile.LastWriteTimeUtc -lt $skinStart -and -not($skinRecord.reusable -and $skinRecord.compiledHash -eq $skinRecord.beforeHash))){throw "Compiled file stale: $($skinRecord.relative)"}
  }
  Write-Output ('COLLECTION_USER_SKIN_NATIVE_PASS '+$skinRecord.relative)
 }
}catch{
 foreach($skinRecord in $skinRecords){
  if($skinRecord.hadContent){Copy-Item -LiteralPath $skinRecord.contentBackup -Destination $skinRecord.content -Force}elseif(Test-Path -LiteralPath $skinRecord.content){Remove-Item -LiteralPath $skinRecord.content}
  if($skinRecord.artifact){if($skinRecord.hadArtifact){Copy-Item -LiteralPath $skinRecord.runtimeBackup -Destination $skinRecord.artifact -Force}elseif(Test-Path -LiteralPath $skinRecord.artifact){Remove-Item -LiteralPath $skinRecord.artifact}}
 }
 throw
}
@{at=(Get-Date -Format o);success=$true;records=$skinRecords;backup=$skinBackup}|ConvertTo-Json -Depth 6|Set-Content -LiteralPath (Join-Path $skinOutput 'compile.json') -Encoding utf8
