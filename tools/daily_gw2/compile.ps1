param(
    [string]$Scope='tools/daily_gw2/compile_scope.json',
    [string]$Report='design_refs/daily_gw2_v1/work/compile.json',
    [switch]$CheckOnly
)
$ErrorActionPreference='Stop'
$dailyGW2Repo=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$dailyGW2Engine=(Resolve-Path (Join-Path $dailyGW2Repo '../../..')).Path
$dailyGW2Content=Join-Path $dailyGW2Engine 'content/dota_addons/Survival/panorama'
$dailyGW2Runtime=Join-Path $dailyGW2Repo 'panorama'
$dailyGW2Compiler=Join-Path $dailyGW2Engine 'game/bin/win64/resourcecompiler.exe'
$dailyGW2Assets='layout/custom_game/daily_gw2_assets.xml'
$dailyGW2Allowed='^(?:scripts/custom_game/(?:daily_remaining_5d5c1152eb|daily_gw2_data|topnav_remaining_5d5c1152eb)\.js|styles/custom_game/daily_gw2\.css|layout/custom_game/(?:archive|daily_gw2_assets)\.xml|images/custom_game/daily_gw2_v1/[a-z0-9_]+\.png)$'
function Get-WorkspacePath([string]$Relative) {
    $resolved=[IO.Path]::GetFullPath((Join-Path $dailyGW2Repo $Relative))
    if(-not $resolved.StartsWith($dailyGW2Repo+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw "Path outside the workspace: $Relative"}
    return $resolved
}
$dailyGW2ScopePath=Get-WorkspacePath $Scope
$dailyGW2Report=Get-WorkspacePath $Report
$dailyGW2Files=@(Get-Content -LiteralPath $dailyGW2ScopePath -Raw -Encoding UTF8|ConvertFrom-Json)
if(-not $dailyGW2Files.Count){throw 'Compile scope is empty.'}
if(@($dailyGW2Files|Select-Object -Unique).Count -ne $dailyGW2Files.Count){throw 'Compile scope contains duplicates.'}
foreach($relative in $dailyGW2Files){if($relative -isnot [string] -or $relative -notmatch $dailyGW2Allowed){throw "Path is outside the dailyGW2 task: $relative"}}
$dailyGW2Required=@('scripts/custom_game/daily_remaining_5d5c1152eb.js','scripts/custom_game/daily_gw2_data.js','styles/custom_game/daily_gw2.css','layout/custom_game/archive.xml',$dailyGW2Assets)
foreach($required in $dailyGW2Required){if($dailyGW2Files -notcontains $required){throw "Required daily source is missing from scope: $required"}}
if(-not(Test-Path -LiteralPath $dailyGW2Compiler -PathType Leaf)){throw 'Native resourcecompiler is missing.'}
[xml]$dailyGW2Xml=Get-Content -LiteralPath (Get-WorkspacePath ('panorama/src/'+$dailyGW2Assets)) -Raw -Encoding UTF8
if($dailyGW2Xml.SelectNodes('//include').Count){throw 'Asset preload XML must not include other resources.'}
$dailyGW2Dependencies=@($dailyGW2Xml.SelectNodes('//Image[@src]')|ForEach-Object {
    $src=$_.GetAttribute('src')
    if($src -notmatch '^file://\{images\}/custom_game/daily_gw2_v1/[a-z0-9_]+\.png$'){throw "Unexpected preload image: $src"}
    'images/'+$src.Substring('file://{images}/'.Length)
})
$dailyGW2Pngs=@($dailyGW2Files|Where-Object {$_ -like '*.png'})
if(-not $dailyGW2Pngs.Count -or @($dailyGW2Dependencies|Select-Object -Unique).Count -ne $dailyGW2Dependencies.Count -or
    $dailyGW2Dependencies.Count -ne $dailyGW2Pngs.Count -or @(Compare-Object $dailyGW2Dependencies $dailyGW2Pngs).Count){throw 'Preload PNG dependencies must exactly equal the unique compile scope PNGs.'}
$dailyGW2Manifest=Get-Content -LiteralPath (Get-WorkspacePath 'tools/daily_gw2/asset_manifest.json') -Raw -Encoding UTF8|ConvertFrom-Json
$dailyGW2ManifestHashes=@{}
$dailyGW2ManifestImages=@($dailyGW2Manifest.assets.PSObject.Properties|ForEach-Object {
    $asset=$_.Value
    if($asset.file -notmatch '^art/ui/sources/custom_game/daily_gw2_v1/[a-z0-9_]+\.png$'){throw "Unexpected manifest path: $($asset.file)"}
    $assetPath=Get-WorkspacePath $asset.file
    if((Get-FileHash -LiteralPath $assetPath -Algorithm SHA256).Hash -ne $asset.sha256){throw "Manifest hash mismatch: $($asset.file)"}
    $imageRelative='images/'+$asset.file.Substring('art/ui/sources/'.Length)
    $dailyGW2ManifestHashes[$imageRelative]=$asset.sha256
    $imageRelative
})
if($dailyGW2ManifestImages.Count -ne $dailyGW2Pngs.Count -or @($dailyGW2ManifestImages|Select-Object -Unique).Count -ne $dailyGW2ManifestImages.Count -or
    @(Compare-Object $dailyGW2ManifestImages $dailyGW2Pngs).Count){throw 'Manifest and compile scope PNGs differ. Run node tools/daily_gw2/build_scope.cjs.'}
# Check every dailyGW2 image referenced by the selected production sources.
foreach($relative in @($dailyGW2Files|Where-Object {$_ -notlike '*.png'})){
    $sourceText=Get-Content -LiteralPath (Get-WorkspacePath ('panorama/src/'+$relative)) -Raw -Encoding UTF8
    foreach($match in [regex]::Matches($sourceText,'(?:file://\{images\}/)?custom_game/daily_gw2_v1/([a-z0-9_]+\.png)')){
        $dependency='images/custom_game/daily_gw2_v1/'+$match.Groups[1].Value
        if($dailyGW2Pngs -notcontains $dependency){throw "Referenced image is absent from scope/preload: $dependency"}
    }
}
[xml]$dailyGW2Main=Get-Content -LiteralPath (Get-WorkspacePath 'panorama/src/layout/custom_game/archive.xml') -Raw -Encoding UTF8
$dailyGW2Includes=@($dailyGW2Main.SelectNodes('//*[@src or @layoutfile]')|ForEach-Object {if($_.HasAttribute('src')){$_.GetAttribute('src')}if($_.HasAttribute('layoutfile')){$_.GetAttribute('layoutfile')}})
foreach($required in @('scripts/custom_game/daily_remaining_5d5c1152eb.js','scripts/custom_game/daily_gw2_data.js','styles/custom_game/daily_gw2.css')){
    if($dailyGW2Includes -notcontains ('file://{resources}/'+$required)){throw "archive.xml does not include the daily runtime source: $required"}
}
$dailyGW2Backup=Get-WorkspacePath ('output/daily_gw2/compile_'+(Get-Date -Format yyyyMMdd_HHmmss_fff)+'_'+[guid]::NewGuid().ToString('N').Substring(0,8))
$dailyGW2Records=@()
foreach($relative in $dailyGW2Files){
    if($relative -isnot [string] -or $relative -notmatch $dailyGW2Allowed){throw "Path is outside the dailyGW2 task: $relative"}
    $source=Get-WorkspacePath ('panorama/src/'+$relative)
    $destination=[IO.Path]::GetFullPath((Join-Path $dailyGW2Content $relative))
    $artifactRelative=$relative -replace '\.js$','.vjs_c' -replace '\.css$','.vcss_c' -replace '\.xml$','.vxml_c' -replace '\.png$','_png.vtex_c'
    $artifact=[IO.Path]::GetFullPath((Join-Path $dailyGW2Runtime $artifactRelative))
    if(-not $destination.StartsWith($dailyGW2Content+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase) -or
        -not $artifact.StartsWith($dailyGW2Runtime+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw "Resolved target escaped task roots: $relative"}
    if(-not(Test-Path -LiteralPath $source -PathType Leaf)){throw "Missing source: $relative"}
    $sourceHash=(Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash
    if($relative.EndsWith('.png') -and $sourceHash -ne $dailyGW2ManifestHashes[$relative]){throw "Panorama PNG differs from canonical manifest art: $relative"}
    $dailyGW2Records+=[pscustomobject]@{
        relative=$relative;source=$source;content=$destination;artifact=$artifact;isImage=$relative.EndsWith('.png')
        sourceHash=$sourceHash
        contentExisted=(Test-Path -LiteralPath $destination -PathType Leaf);runtimeExisted=(Test-Path -LiteralPath $artifact -PathType Leaf)
        sourceBackup=(Join-Path $dailyGW2Backup ('source/'+$relative));contentBackup=(Join-Path $dailyGW2Backup ('content/'+$relative))
        runtimeBackup=(Join-Path $dailyGW2Backup ('runtime/'+$artifactRelative));compileStartedUtc=$null
        compiledHash=$null;artifactBytes=$null;artifactWriteUtc=$null;verified=$false
    }
}
if($CheckOnly){[pscustomobject]@{success=$true;checkOnly=$true;files=$dailyGW2Records.Count;pngs=$dailyGW2Pngs.Count;scope=$Scope;report=$Report}|ConvertTo-Json;return}
New-Item -ItemType Directory -Path $dailyGW2Backup -Force|Out-Null
foreach($record in $dailyGW2Records){
    foreach($target in @($record.sourceBackup,$record.contentBackup,$record.runtimeBackup)){New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force|Out-Null}
    Copy-Item -LiteralPath $record.source -Destination $record.sourceBackup
    if($record.contentExisted){Copy-Item -LiteralPath $record.content -Destination $record.contentBackup}
    if($record.runtimeExisted){Copy-Item -LiteralPath $record.artifact -Destination $record.runtimeBackup}
}
$dailyGW2Records|ConvertTo-Json -Depth 6|Set-Content -LiteralPath (Join-Path $dailyGW2Backup 'manifest_before.json') -Encoding UTF8
try {
    foreach($record in $dailyGW2Records){
        New-Item -ItemType Directory -Path (Split-Path -Parent $record.content) -Force|Out-Null
        Copy-Item -LiteralPath $record.source -Destination $record.content -Force
        if((Get-FileHash -LiteralPath $record.content -Algorithm SHA256).Hash -ne $record.sourceHash){throw "Content copy differs: $($record.relative)"}
    }
    $compileStart=(Get-Date).ToUniversalTime()
    $build=@($dailyGW2Records|Where-Object {-not $_.isImage}|Sort-Object @{Expression={if($_.relative -eq $dailyGW2Assets){1}elseif($_.relative.StartsWith('layout/')){2}else{0}}},relative)
    foreach($record in $build){
        $record.compileStartedUtc=(Get-Date).ToUniversalTime().ToString('o')
        $force=if($record.relative -eq $dailyGW2Assets){'-f'}else{'-fshallow'}
        $log=@(& $dailyGW2Compiler -i $record.content -game (Join-Path $dailyGW2Engine 'game/dota') $force -nop4 2>&1)
        $exitCode=$LASTEXITCODE
        $log|Set-Content -LiteralPath (Join-Path $dailyGW2Backup (($record.relative -replace '/','_')+'.log')) -Encoding UTF8
        if($exitCode -ne 0 -or -not($log -match '0 failed')){throw "Native compile failed: $($record.relative)"}
        Write-Output ('DAILY_GW2_COMPILE_PASS '+$record.relative)
    }
    foreach($record in $dailyGW2Records){
        if((Get-FileHash -LiteralPath $record.source -Algorithm SHA256).Hash -ne $record.sourceHash -or
            (Get-FileHash -LiteralPath $record.content -Algorithm SHA256).Hash -ne $record.sourceHash){throw "Source changed during compile: $($record.relative)"}
        if(-not(Test-Path -LiteralPath $record.artifact -PathType Leaf)){throw "Missing compiled file: $($record.relative)"}
        $file=Get-Item -LiteralPath $record.artifact
        $minimum=if($record.isImage){$compileStart}else{[datetime]::Parse($record.compileStartedUtc).ToUniversalTime()}
        if($file.Length -le 0 -or $file.LastWriteTimeUtc -lt $minimum){throw "Stale or empty compiled file: $($record.relative)"}
        $record.compiledHash=(Get-FileHash -LiteralPath $record.artifact -Algorithm SHA256).Hash
        $record.artifactBytes=$file.Length;$record.artifactWriteUtc=$file.LastWriteTimeUtc.ToString('o');$record.verified=$true
    }
    New-Item -ItemType Directory -Path (Split-Path -Parent $dailyGW2Report) -Force|Out-Null
    @{at=(Get-Date -Format o);success=$true;backup=$dailyGW2Backup;records=$dailyGW2Records;scope=$Scope;compileStartedUtc=$compileStart.ToString('o');pngDependencies=$dailyGW2Dependencies}|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $dailyGW2Report -Encoding UTF8
} catch {
    $failure=$_
    foreach($record in $dailyGW2Records){
        if($record.contentExisted){Copy-Item -LiteralPath $record.contentBackup -Destination $record.content -Force}
        elseif(Test-Path -LiteralPath $record.content -PathType Leaf){Remove-Item -LiteralPath $record.content}
        if($record.runtimeExisted){Copy-Item -LiteralPath $record.runtimeBackup -Destination $record.artifact -Force}
        elseif(Test-Path -LiteralPath $record.artifact -PathType Leaf){Remove-Item -LiteralPath $record.artifact}
    }
    @{at=(Get-Date -Format o);success=$false;rolledBack=$true;error=$failure.ToString();backup=$dailyGW2Backup;records=$dailyGW2Records}|ConvertTo-Json -Depth 8|Set-Content -LiteralPath (Join-Path $dailyGW2Backup 'failure.json') -Encoding UTF8
    throw $failure
}
