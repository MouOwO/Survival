param(
    [string]$Scope='tools/collection_gw2/compile_scope.json',
    [string]$Report='design_refs/collection_gw2_v2/work/compile.json',
    [switch]$CheckOnly
)
$ErrorActionPreference='Stop'
$collectionGW2Repo=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$collectionGW2Engine=(Resolve-Path (Join-Path $collectionGW2Repo '../../..')).Path
$collectionGW2Content=Join-Path $collectionGW2Engine 'content/dota_addons/Survival/panorama'
$collectionGW2Runtime=Join-Path $collectionGW2Repo 'panorama'
$collectionGW2Compiler=Join-Path $collectionGW2Engine 'game/bin/win64/resourcecompiler.exe'
$collectionGW2Assets='layout/custom_game/collection_gw2_assets.xml'
$collectionGW2Allowed='^(?:scripts/custom_game/(?:collection_gw2|collection_gw2_data)\.js|styles/custom_game/collection_gw2\.css|layout/custom_game/collection_gw2_assets\.xml|images/custom_game/collection_gw2_v2/[a-z0-9_]+\.png)$'
function Get-WorkspacePath([string]$Relative) {
    $resolved=[IO.Path]::GetFullPath((Join-Path $collectionGW2Repo $Relative))
    if(-not $resolved.StartsWith($collectionGW2Repo+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw "Path outside the workspace: $Relative"}
    return $resolved
}
$collectionGW2ScopePath=Get-WorkspacePath $Scope
$collectionGW2Report=Get-WorkspacePath $Report
$collectionGW2Files=@(Get-Content -LiteralPath $collectionGW2ScopePath -Raw -Encoding UTF8|ConvertFrom-Json)
if(-not $collectionGW2Files.Count){throw 'Compile scope is empty.'}
if(@($collectionGW2Files|Select-Object -Unique).Count -ne $collectionGW2Files.Count){throw 'Compile scope contains duplicates.'}
foreach($relative in $collectionGW2Files){if($relative -isnot [string] -or $relative -notmatch $collectionGW2Allowed){throw "Path is outside the collectionGW2 task: $relative"}}
$collectionGW2Required=@('scripts/custom_game/collection_gw2.js','scripts/custom_game/collection_gw2_data.js','styles/custom_game/collection_gw2.css',$collectionGW2Assets)
foreach($required in $collectionGW2Required){if($collectionGW2Files -notcontains $required){throw "Required collection source is missing from scope: $required"}}
if(-not(Test-Path -LiteralPath $collectionGW2Compiler -PathType Leaf)){throw 'Native resourcecompiler is missing.'}
[xml]$collectionGW2Xml=Get-Content -LiteralPath (Get-WorkspacePath ('panorama/src/'+$collectionGW2Assets)) -Raw -Encoding UTF8
if($collectionGW2Xml.SelectNodes('//include').Count){throw 'Asset preload XML must not include other resources.'}
$collectionGW2Dependencies=@($collectionGW2Xml.SelectNodes('//Image[@src]')|ForEach-Object {
    $src=$_.GetAttribute('src')
    if($src -notmatch '^file://\{images\}/custom_game/collection_gw2_v2/[a-z0-9_]+\.png$'){throw "Unexpected preload image: $src"}
    'images/'+$src.Substring('file://{images}/'.Length)
})
$collectionGW2Pngs=@($collectionGW2Files|Where-Object {$_ -like '*.png'})
if(-not $collectionGW2Pngs.Count -or @($collectionGW2Dependencies|Select-Object -Unique).Count -ne $collectionGW2Dependencies.Count -or
    $collectionGW2Dependencies.Count -ne $collectionGW2Pngs.Count -or @(Compare-Object $collectionGW2Dependencies $collectionGW2Pngs).Count){throw 'Preload PNG dependencies must exactly equal the unique compile scope PNGs.'}
$collectionGW2Manifest=Get-Content -LiteralPath (Get-WorkspacePath 'tools/collection_gw2/asset_manifest.json') -Raw -Encoding UTF8|ConvertFrom-Json
$collectionGW2ManifestHashes=@{}
$collectionGW2ManifestImages=@($collectionGW2Manifest.assets.PSObject.Properties|ForEach-Object {
    $asset=$_.Value
    if($asset.file -notmatch '^art/ui/sources/custom_game/collection_gw2_v2/[a-z0-9_]+\.png$'){throw "Unexpected manifest path: $($asset.file)"}
    $assetPath=Get-WorkspacePath $asset.file
    if((Get-FileHash -LiteralPath $assetPath -Algorithm SHA256).Hash -ne $asset.sha256){throw "Manifest hash mismatch: $($asset.file)"}
    $imageRelative='images/'+$asset.file.Substring('art/ui/sources/'.Length)
    $collectionGW2ManifestHashes[$imageRelative]=$asset.sha256
    $imageRelative
})
if($collectionGW2ManifestImages.Count -ne $collectionGW2Pngs.Count -or @($collectionGW2ManifestImages|Select-Object -Unique).Count -ne $collectionGW2ManifestImages.Count -or
    @(Compare-Object $collectionGW2ManifestImages $collectionGW2Pngs).Count){throw 'Manifest and compile scope PNGs differ. Run node tools/collection_gw2/build_scope.cjs.'}
# Check every collectionGW2 image referenced by the selected production sources.
foreach($relative in @($collectionGW2Files|Where-Object {$_ -notlike '*.png'})){
    $sourceText=Get-Content -LiteralPath (Get-WorkspacePath ('panorama/src/'+$relative)) -Raw -Encoding UTF8
    foreach($match in [regex]::Matches($sourceText,'(?:file://\{images\}/)?custom_game/collection_gw2_v2/([a-z0-9_]+\.png)')){
        $dependency='images/custom_game/collection_gw2_v2/'+$match.Groups[1].Value
        if($collectionGW2Pngs -notcontains $dependency){throw "Referenced image is absent from scope/preload: $dependency"}
    }
}
[xml]$collectionGW2Main=Get-Content -LiteralPath (Get-WorkspacePath 'panorama/src/layout/custom_game/archive.xml') -Raw -Encoding UTF8
$collectionGW2Includes=@($collectionGW2Main.SelectNodes('//*[@src or @layoutfile]')|ForEach-Object {if($_.HasAttribute('src')){$_.GetAttribute('src')}if($_.HasAttribute('layoutfile')){$_.GetAttribute('layoutfile')}})
foreach($required in @('scripts/custom_game/collection_gw2.js','scripts/custom_game/collection_gw2_data.js','styles/custom_game/collection_gw2.css')){
    if($collectionGW2Includes -notcontains ('file://{resources}/'+$required)){throw "archive.xml does not include the collection runtime source: $required"}
}
[xml]$collectionGW2Hud=Get-Content -LiteralPath (Get-WorkspacePath 'panorama/src/layout/custom_game/survival_hud.xml') -Raw -Encoding UTF8
if(-not $collectionGW2Hud.SelectSingleNode("//include[@src='file://{resources}/scripts/custom_game/collection_nav.js']")){throw 'survival_hud.xml does not include collection_nav.js'}
# topnav_remaining has pre-existing user edits and is deliberately excluded.
$collectionGW2Backup=Get-WorkspacePath ('output/collection_gw2/compile_'+(Get-Date -Format yyyyMMdd_HHmmss_fff)+'_'+[guid]::NewGuid().ToString('N').Substring(0,8))
$collectionGW2Records=@()
foreach($relative in $collectionGW2Files){
    if($relative -isnot [string] -or $relative -notmatch $collectionGW2Allowed){throw "Path is outside the collectionGW2 task: $relative"}
    $source=Get-WorkspacePath ('panorama/src/'+$relative)
    $destination=[IO.Path]::GetFullPath((Join-Path $collectionGW2Content $relative))
    $artifactRelative=$relative -replace '\.js$','.vjs_c' -replace '\.css$','.vcss_c' -replace '\.xml$','.vxml_c' -replace '\.png$','_png.vtex_c'
    $artifact=[IO.Path]::GetFullPath((Join-Path $collectionGW2Runtime $artifactRelative))
    if(-not $destination.StartsWith($collectionGW2Content+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase) -or
        -not $artifact.StartsWith($collectionGW2Runtime+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw "Resolved target escaped task roots: $relative"}
    if(-not(Test-Path -LiteralPath $source -PathType Leaf)){throw "Missing source: $relative"}
    $sourceHash=(Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash
    if($relative.EndsWith('.png') -and $sourceHash -ne $collectionGW2ManifestHashes[$relative]){throw "Panorama PNG differs from canonical manifest art: $relative"}
    $collectionGW2Records+=[pscustomobject]@{
        relative=$relative;source=$source;content=$destination;artifact=$artifact;isImage=$relative.EndsWith('.png')
        sourceHash=$sourceHash
        contentExisted=(Test-Path -LiteralPath $destination -PathType Leaf);runtimeExisted=(Test-Path -LiteralPath $artifact -PathType Leaf)
        sourceBackup=(Join-Path $collectionGW2Backup ('source/'+$relative));contentBackup=(Join-Path $collectionGW2Backup ('content/'+$relative))
        runtimeBackup=(Join-Path $collectionGW2Backup ('runtime/'+$artifactRelative));compileStartedUtc=$null
        compiledHash=$null;artifactBytes=$null;artifactWriteUtc=$null;verified=$false
    }
}
if($CheckOnly){[pscustomobject]@{success=$true;checkOnly=$true;files=$collectionGW2Records.Count;pngs=$collectionGW2Pngs.Count;scope=$Scope;report=$Report}|ConvertTo-Json;return}
New-Item -ItemType Directory -Path $collectionGW2Backup -Force|Out-Null
foreach($record in $collectionGW2Records){
    foreach($target in @($record.sourceBackup,$record.contentBackup,$record.runtimeBackup)){New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force|Out-Null}
    Copy-Item -LiteralPath $record.source -Destination $record.sourceBackup
    if($record.contentExisted){Copy-Item -LiteralPath $record.content -Destination $record.contentBackup}
    if($record.runtimeExisted){Copy-Item -LiteralPath $record.artifact -Destination $record.runtimeBackup}
}
$collectionGW2Records|ConvertTo-Json -Depth 6|Set-Content -LiteralPath (Join-Path $collectionGW2Backup 'manifest_before.json') -Encoding UTF8
try {
    foreach($record in $collectionGW2Records){
        New-Item -ItemType Directory -Path (Split-Path -Parent $record.content) -Force|Out-Null
        Copy-Item -LiteralPath $record.source -Destination $record.content -Force
        if((Get-FileHash -LiteralPath $record.content -Algorithm SHA256).Hash -ne $record.sourceHash){throw "Content copy differs: $($record.relative)"}
    }
    $compileStart=(Get-Date).ToUniversalTime()
    $build=@($collectionGW2Records|Where-Object {-not $_.isImage}|Sort-Object @{Expression={if($_.relative -eq $collectionGW2Assets){1}elseif($_.relative.StartsWith('layout/')){2}else{0}}},relative)
    foreach($record in $build){
        $record.compileStartedUtc=(Get-Date).ToUniversalTime().ToString('o')
        $force=if($record.relative -eq $collectionGW2Assets){'-f'}else{'-fshallow'}
        $log=@(& $collectionGW2Compiler -i $record.content -game (Join-Path $collectionGW2Engine 'game/dota') $force -nop4 2>&1)
        $exitCode=$LASTEXITCODE
        $log|Set-Content -LiteralPath (Join-Path $collectionGW2Backup (($record.relative -replace '/','_')+'.log')) -Encoding UTF8
        if($exitCode -ne 0 -or -not($log -match '0 failed')){throw "Native compile failed: $($record.relative)"}
        Write-Output ('COLLECTION_GW2_COMPILE_PASS '+$record.relative)
    }
    foreach($record in $collectionGW2Records){
        if((Get-FileHash -LiteralPath $record.source -Algorithm SHA256).Hash -ne $record.sourceHash -or
            (Get-FileHash -LiteralPath $record.content -Algorithm SHA256).Hash -ne $record.sourceHash){throw "Source changed during compile: $($record.relative)"}
        if(-not(Test-Path -LiteralPath $record.artifact -PathType Leaf)){throw "Missing compiled file: $($record.relative)"}
        $file=Get-Item -LiteralPath $record.artifact
        $minimum=if($record.isImage){$compileStart}else{[datetime]::Parse($record.compileStartedUtc).ToUniversalTime()}
        if($file.Length -le 0 -or $file.LastWriteTimeUtc -lt $minimum){throw "Stale or empty compiled file: $($record.relative)"}
        $record.compiledHash=(Get-FileHash -LiteralPath $record.artifact -Algorithm SHA256).Hash
        $record.artifactBytes=$file.Length;$record.artifactWriteUtc=$file.LastWriteTimeUtc.ToString('o');$record.verified=$true
    }
    New-Item -ItemType Directory -Path (Split-Path -Parent $collectionGW2Report) -Force|Out-Null
    @{at=(Get-Date -Format o);success=$true;backup=$collectionGW2Backup;records=$collectionGW2Records;scope=$Scope;compileStartedUtc=$compileStart.ToString('o');pngDependencies=$collectionGW2Dependencies}|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $collectionGW2Report -Encoding UTF8
} catch {
    $failure=$_
    foreach($record in $collectionGW2Records){
        if($record.contentExisted){Copy-Item -LiteralPath $record.contentBackup -Destination $record.content -Force}
        elseif(Test-Path -LiteralPath $record.content -PathType Leaf){Remove-Item -LiteralPath $record.content}
        if($record.runtimeExisted){Copy-Item -LiteralPath $record.runtimeBackup -Destination $record.artifact -Force}
        elseif(Test-Path -LiteralPath $record.artifact -PathType Leaf){Remove-Item -LiteralPath $record.artifact}
    }
    @{at=(Get-Date -Format o);success=$false;rolledBack=$true;error=$failure.ToString();backup=$collectionGW2Backup;records=$collectionGW2Records}|ConvertTo-Json -Depth 8|Set-Content -LiteralPath (Join-Path $collectionGW2Backup 'failure.json') -Encoding UTF8
    throw $failure
}
