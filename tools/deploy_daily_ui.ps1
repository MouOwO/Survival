param([switch]$CheckOnly)
$ErrorActionPreference='Stop'
$repo=Split-Path -Parent $PSScriptRoot
$source=Join-Path $repo 'panorama/src'
$engine='D:/SteamLibrary/steamapps/common/dota 2 beta'
$content=Join-Path $engine 'content/dota_addons/Survival/panorama'
$assets=Get-Content -LiteralPath (Join-Path $repo 'art/ui/development/daily_rewards_import/assets.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$files=@('layout/custom_game/archive.xml','scripts/custom_game/daily_resources.js','scripts/custom_game/daily_rewards.js','styles/custom_game/daily_rewards.css','styles/custom_game/daily_assets.css')
foreach($a in $assets.psobject.Properties){
 $relative='images/'+$a.Value.runtime
 if((Get-FileHash -LiteralPath (Join-Path $source $relative)).Hash.ToLowerInvariant() -ne $a.Value.source_sha256){throw "Asset changed: $($a.Name)"}
 $files+=$relative
}
[xml]$layout=Get-Content -LiteralPath (Join-Path $source $files[0]) -Raw -Encoding UTF8
if($CheckOnly){Write-Output "DAILY_DEPLOY_CHECK_PASS: $($files.Count) verified files";exit 0}
$backup=Join-Path $repo ('art/ui/development/daily_rewards_import/backups/'+(Get-Date -Format 'yyyyMMdd_HHmmss'))
foreach($f in $files){
 $dest=Join-Path $content $f
 if(Test-Path -LiteralPath $dest){$old=Join-Path $backup $f;New-Item -ItemType Directory -Path (Split-Path -Parent $old) -Force|Out-Null;Copy-Item -LiteralPath $dest -Destination $old}
 New-Item -ItemType Directory -Path (Split-Path -Parent $dest) -Force|Out-Null
 Copy-Item -LiteralPath (Join-Path $source $f) -Destination $dest -Force
}
$log=Join-Path $repo 'art/ui/development/daily_rewards_import/compile.log'
[IO.File]::WriteAllText($log,'')
$failed=@()
foreach($f in @($files | Where-Object {$_ -notlike 'images/*'})){
 $result=& (Join-Path $engine 'game/bin/win64/resourcecompiler.exe') -i (Join-Path $content $f) -game (Join-Path $engine 'game/dota') -f 2>&1
 $exitCode=$LASTEXITCODE
 $result|Out-File -LiteralPath $log -Append -Encoding UTF8
 if($exitCode -ne 0){$failed+=$f;Write-Output $result}
}
if($failed.Count){throw "Daily compilation failed: $($failed -join ', ')"}
foreach($a in $assets.psobject.Properties){
 $artifact=Join-Path $repo ('panorama/images/'+$a.Value.runtime.Replace('.png','_png.vtex_c'))
 if(-not(Test-Path -LiteralPath $artifact)){throw "Missing compiled texture: $($a.Name)"}
}
Write-Output "DAILY_DEPLOY_PASS: $($files.Count) sources compiled; original content backed up at $backup"
