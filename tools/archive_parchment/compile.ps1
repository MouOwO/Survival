param(
    [string]$Scope='tools/archive_parchment/compile_scope.json',
    [string]$Report='design_refs/archive_parchment_v1/work/compile.json',
    [switch]$CheckOnly
)
$ErrorActionPreference='Stop'
$parchmentRepo=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$parchmentEngine=(Resolve-Path (Join-Path $parchmentRepo '../../..')).Path
$parchmentContent=Join-Path $parchmentEngine 'content/dota_addons/Survival/panorama'
$parchmentRuntime=Join-Path $parchmentRepo 'panorama'
$parchmentCompiler=Join-Path $parchmentEngine 'game/bin/win64/resourcecompiler.exe'
$parchmentAssets='layout/custom_game/archive_parchment_assets.xml'
$parchmentAllowed='^(?:scripts/custom_game/(?:archive_v10(?:_semantics)?|archive_parchment_data)\.js|styles/custom_game/archive_v10\.css|layout/custom_game/archive(?:_parchment_assets)?\.xml|images/custom_game/archive_parchment_v1/[a-z0-9_]+\.png)$'
function Get-WorkspacePath([string]$Relative) {
    $resolved=[IO.Path]::GetFullPath((Join-Path $parchmentRepo $Relative))
    if(-not $resolved.StartsWith($parchmentRepo+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw "Path outside the workspace: $Relative"}
    return $resolved
}
$parchmentScopePath=Get-WorkspacePath $Scope
$parchmentReport=Get-WorkspacePath $Report
$parchmentFiles=@(Get-Content -LiteralPath $parchmentScopePath -Raw -Encoding UTF8|ConvertFrom-Json)
if(-not $parchmentFiles.Count){throw 'Compile scope is empty.'}
if(@($parchmentFiles|Select-Object -Unique).Count -ne $parchmentFiles.Count){throw 'Compile scope contains duplicates.'}
foreach($relative in $parchmentFiles){if($relative -isnot [string] -or $relative -notmatch $parchmentAllowed){throw "Path is outside the parchment task: $relative"}}
if($parchmentFiles -notcontains $parchmentAssets){throw 'Scope must include the parchment asset preload XML.'}
if(-not(Test-Path -LiteralPath $parchmentCompiler -PathType Leaf)){throw 'Native resourcecompiler is missing.'}
[xml]$parchmentXml=Get-Content -LiteralPath (Get-WorkspacePath ('panorama/src/'+$parchmentAssets)) -Raw -Encoding UTF8
if($parchmentXml.SelectNodes('//include').Count){throw 'Asset preload XML must not include other resources.'}
$parchmentDependencies=@($parchmentXml.SelectNodes('//Image[@src]')|ForEach-Object {
    $src=$_.GetAttribute('src')
    if($src -notmatch '^file://\{images\}/custom_game/archive_parchment_v1/[a-z0-9_]+\.png$'){throw "Unexpected preload image: $src"}
    'images/'+$src.Substring('file://{images}/'.Length)
})
$parchmentPngs=@($parchmentFiles|Where-Object {$_ -like '*.png'})
if(-not $parchmentPngs.Count -or @($parchmentDependencies|Select-Object -Unique).Count -ne $parchmentDependencies.Count -or
    $parchmentDependencies.Count -ne $parchmentPngs.Count -or @(Compare-Object $parchmentDependencies $parchmentPngs).Count){throw 'Preload PNG dependencies must exactly equal the unique compile scope PNGs.'}
$parchmentManifest=Get-Content -LiteralPath (Get-WorkspacePath 'tools/archive_parchment/asset_manifest.json') -Raw -Encoding UTF8|ConvertFrom-Json
$parchmentManifestHashes=@{}
$parchmentManifestImages=@($parchmentManifest.assets.PSObject.Properties|ForEach-Object {
    $asset=$_.Value
    if($asset.file -notmatch '^art/ui/sources/custom_game/archive_parchment_v1/[a-z0-9_]+\.png$'){throw "Unexpected manifest path: $($asset.file)"}
    $assetPath=Get-WorkspacePath $asset.file
    if((Get-FileHash -LiteralPath $assetPath -Algorithm SHA256).Hash -ne $asset.sha256){throw "Manifest hash mismatch: $($asset.file)"}
    $imageRelative='images/'+$asset.file.Substring('art/ui/sources/'.Length)
    $parchmentManifestHashes[$imageRelative]=$asset.sha256
    $imageRelative
})
if($parchmentManifestImages.Count -ne $parchmentPngs.Count -or @($parchmentManifestImages|Select-Object -Unique).Count -ne $parchmentManifestImages.Count -or
    @(Compare-Object $parchmentManifestImages $parchmentPngs).Count){throw 'Manifest and compile scope PNGs differ. Run node tools/archive_parchment/build_scope.cjs.'}
# Check every parchment image referenced by the selected production sources.
foreach($relative in @($parchmentFiles|Where-Object {$_ -notlike '*.png'})){
    $sourceText=Get-Content -LiteralPath (Get-WorkspacePath ('panorama/src/'+$relative)) -Raw -Encoding UTF8
    foreach($match in [regex]::Matches($sourceText,'(?:file://\{images\}/)?custom_game/archive_parchment_v1/([a-z0-9_]+\.png)')){
        $dependency='images/custom_game/archive_parchment_v1/'+$match.Groups[1].Value
        if($parchmentPngs -notcontains $dependency){throw "Referenced image is absent from scope/preload: $dependency"}
    }
}
[xml]$parchmentMain=Get-Content -LiteralPath (Get-WorkspacePath 'panorama/src/layout/custom_game/archive.xml') -Raw -Encoding UTF8
$parchmentIncludes=@($parchmentMain.SelectNodes('//*[@src or @layoutfile]')|ForEach-Object {if($_.HasAttribute('src')){$_.GetAttribute('src')}if($_.HasAttribute('layoutfile')){$_.GetAttribute('layoutfile')}})
if($parchmentIncludes -notcontains 'file://{resources}/scripts/custom_game/archive_parchment_data.js'){throw 'archive.xml does not include the parchment runtime data script.'}
$parchmentBackup=Get-WorkspacePath ('output/archive_parchment/compile_'+(Get-Date -Format yyyyMMdd_HHmmss_fff)+'_'+[guid]::NewGuid().ToString('N').Substring(0,8))
$parchmentRecords=@()
foreach($relative in $parchmentFiles){
    if($relative -isnot [string] -or $relative -notmatch $parchmentAllowed){throw "Path is outside the parchment task: $relative"}
    $source=Get-WorkspacePath ('panorama/src/'+$relative)
    $destination=[IO.Path]::GetFullPath((Join-Path $parchmentContent $relative))
    $artifactRelative=$relative -replace '\.js$','.vjs_c' -replace '\.css$','.vcss_c' -replace '\.xml$','.vxml_c' -replace '\.png$','_png.vtex_c'
    $artifact=[IO.Path]::GetFullPath((Join-Path $parchmentRuntime $artifactRelative))
    if(-not $destination.StartsWith($parchmentContent+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase) -or
        -not $artifact.StartsWith($parchmentRuntime+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw "Resolved target escaped task roots: $relative"}
    if(-not(Test-Path -LiteralPath $source -PathType Leaf)){throw "Missing source: $relative"}
    $sourceHash=(Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash
    if($relative.EndsWith('.png') -and $sourceHash -ne $parchmentManifestHashes[$relative]){throw "Panorama PNG differs from canonical manifest art: $relative"}
    $parchmentRecords+=[pscustomobject]@{
        relative=$relative;source=$source;content=$destination;artifact=$artifact;isImage=$relative.EndsWith('.png')
        sourceHash=$sourceHash
        contentExisted=(Test-Path -LiteralPath $destination -PathType Leaf);runtimeExisted=(Test-Path -LiteralPath $artifact -PathType Leaf)
        sourceBackup=(Join-Path $parchmentBackup ('source/'+$relative));contentBackup=(Join-Path $parchmentBackup ('content/'+$relative))
        runtimeBackup=(Join-Path $parchmentBackup ('runtime/'+$artifactRelative));compileStartedUtc=$null
        compiledHash=$null;artifactBytes=$null;artifactWriteUtc=$null;verified=$false
    }
}
if($CheckOnly){[pscustomobject]@{success=$true;checkOnly=$true;files=$parchmentRecords.Count;pngs=$parchmentPngs.Count;scope=$Scope;report=$Report}|ConvertTo-Json;return}
New-Item -ItemType Directory -Path $parchmentBackup -Force|Out-Null
foreach($record in $parchmentRecords){
    foreach($target in @($record.sourceBackup,$record.contentBackup,$record.runtimeBackup)){New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force|Out-Null}
    Copy-Item -LiteralPath $record.source -Destination $record.sourceBackup
    if($record.contentExisted){Copy-Item -LiteralPath $record.content -Destination $record.contentBackup}
    if($record.runtimeExisted){Copy-Item -LiteralPath $record.artifact -Destination $record.runtimeBackup}
}
$parchmentRecords|ConvertTo-Json -Depth 6|Set-Content -LiteralPath (Join-Path $parchmentBackup 'manifest_before.json') -Encoding UTF8
try {
    foreach($record in $parchmentRecords){
        New-Item -ItemType Directory -Path (Split-Path -Parent $record.content) -Force|Out-Null
        Copy-Item -LiteralPath $record.source -Destination $record.content -Force
        if((Get-FileHash -LiteralPath $record.content -Algorithm SHA256).Hash -ne $record.sourceHash){throw "Content copy differs: $($record.relative)"}
    }
    $compileStart=(Get-Date).ToUniversalTime()
    $build=@($parchmentRecords|Where-Object {-not $_.isImage}|Sort-Object @{Expression={if($_.relative -eq $parchmentAssets){1}elseif($_.relative.StartsWith('layout/')){2}else{0}}},relative)
    foreach($record in $build){
        $record.compileStartedUtc=(Get-Date).ToUniversalTime().ToString('o')
        $force=if($record.relative -eq $parchmentAssets){'-f'}else{'-fshallow'}
        $log=@(& $parchmentCompiler -i $record.content -game (Join-Path $parchmentEngine 'game/dota') $force -nop4 2>&1)
        $exitCode=$LASTEXITCODE
        $log|Set-Content -LiteralPath (Join-Path $parchmentBackup (($record.relative -replace '/','_')+'.log')) -Encoding UTF8
        if($exitCode -ne 0 -or -not($log -match '0 failed')){throw "Native compile failed: $($record.relative)"}
        Write-Output ('ARCHIVE_PARCHMENT_COMPILE_PASS '+$record.relative)
    }
    foreach($record in $parchmentRecords){
        if((Get-FileHash -LiteralPath $record.source -Algorithm SHA256).Hash -ne $record.sourceHash -or
            (Get-FileHash -LiteralPath $record.content -Algorithm SHA256).Hash -ne $record.sourceHash){throw "Source changed during compile: $($record.relative)"}
        if(-not(Test-Path -LiteralPath $record.artifact -PathType Leaf)){throw "Missing compiled file: $($record.relative)"}
        $file=Get-Item -LiteralPath $record.artifact
        $minimum=if($record.isImage){$compileStart}else{[datetime]::Parse($record.compileStartedUtc).ToUniversalTime()}
        if($file.Length -le 0 -or $file.LastWriteTimeUtc -lt $minimum){throw "Stale or empty compiled file: $($record.relative)"}
        $record.compiledHash=(Get-FileHash -LiteralPath $record.artifact -Algorithm SHA256).Hash
        $record.artifactBytes=$file.Length;$record.artifactWriteUtc=$file.LastWriteTimeUtc.ToString('o');$record.verified=$true
    }
    New-Item -ItemType Directory -Path (Split-Path -Parent $parchmentReport) -Force|Out-Null
    @{at=(Get-Date -Format o);success=$true;backup=$parchmentBackup;records=$parchmentRecords;scope=$Scope;compileStartedUtc=$compileStart.ToString('o');pngDependencies=$parchmentDependencies}|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $parchmentReport -Encoding UTF8
} catch {
    $failure=$_
    foreach($record in $parchmentRecords){
        if($record.contentExisted){Copy-Item -LiteralPath $record.contentBackup -Destination $record.content -Force}
        elseif(Test-Path -LiteralPath $record.content -PathType Leaf){Remove-Item -LiteralPath $record.content}
        if($record.runtimeExisted){Copy-Item -LiteralPath $record.runtimeBackup -Destination $record.artifact -Force}
        elseif(Test-Path -LiteralPath $record.artifact -PathType Leaf){Remove-Item -LiteralPath $record.artifact}
    }
    @{at=(Get-Date -Format o);success=$false;rolledBack=$true;error=$failure.ToString();backup=$parchmentBackup;records=$parchmentRecords}|ConvertTo-Json -Depth 8|Set-Content -LiteralPath (Join-Path $parchmentBackup 'failure.json') -Encoding UTF8
    throw $failure
}
