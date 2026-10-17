param(
    [string]$Scope='tools/lottery_gw2/compile_scope.json',
    [string]$Report='design_refs/lottery_gw2_v1/work/compile.json',
    [switch]$CheckOnly
)
$ErrorActionPreference='Stop'
$lotteryGW2Repo=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$lotteryGW2Engine=(Resolve-Path (Join-Path $lotteryGW2Repo '../../..')).Path
$lotteryGW2Content=Join-Path $lotteryGW2Engine 'content/dota_addons/Survival/panorama'
$lotteryGW2Runtime=Join-Path $lotteryGW2Repo 'panorama'
$lotteryGW2Compiler=Join-Path $lotteryGW2Engine 'game/bin/win64/resourcecompiler.exe'
$lotteryGW2Assets='layout/custom_game/lottery_gw2_assets.xml'
$lotteryGW2Allowed='^(?:scripts/custom_game/(?:lottery_gw2|lottery_gw2_data|lottery_ui_remaining_5d5c1152eb)\.js|styles/custom_game/lottery_gw2\.css|layout/custom_game/(?:survival_hud|lottery_gw2_assets)\.xml|images/custom_game/lottery_gw2_v1/[a-z0-9_]+\.png)$'
function Get-WorkspacePath([string]$Relative) {
    $resolved=[IO.Path]::GetFullPath((Join-Path $lotteryGW2Repo $Relative))
    if(-not $resolved.StartsWith($lotteryGW2Repo+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw "Path outside the workspace: $Relative"}
    return $resolved
}
$lotteryGW2ScopePath=Get-WorkspacePath $Scope
$lotteryGW2Report=Get-WorkspacePath $Report
$lotteryGW2Files=@(Get-Content -LiteralPath $lotteryGW2ScopePath -Raw -Encoding UTF8|ConvertFrom-Json)
if(-not $lotteryGW2Files.Count){throw 'Compile scope is empty.'}
if(@($lotteryGW2Files|Select-Object -Unique).Count -ne $lotteryGW2Files.Count){throw 'Compile scope contains duplicates.'}
foreach($relative in $lotteryGW2Files){if($relative -isnot [string] -or $relative -notmatch $lotteryGW2Allowed){throw "Path is outside the lotteryGW2 task: $relative"}}
$lotteryGW2Required=@('scripts/custom_game/lottery_gw2.js','scripts/custom_game/lottery_gw2_data.js','styles/custom_game/lottery_gw2.css','layout/custom_game/survival_hud.xml',$lotteryGW2Assets)
foreach($required in $lotteryGW2Required){if($lotteryGW2Files -notcontains $required){throw "Required lottery source is missing from scope: $required"}}
if(-not(Test-Path -LiteralPath $lotteryGW2Compiler -PathType Leaf)){throw 'Native resourcecompiler is missing.'}
[xml]$lotteryGW2Xml=Get-Content -LiteralPath (Get-WorkspacePath ('panorama/src/'+$lotteryGW2Assets)) -Raw -Encoding UTF8
if($lotteryGW2Xml.SelectNodes('//include').Count){throw 'Asset preload XML must not include other resources.'}
$lotteryGW2Dependencies=@($lotteryGW2Xml.SelectNodes('//Image[@src]')|ForEach-Object {
    $src=$_.GetAttribute('src')
    if($src -notmatch '^file://\{images\}/custom_game/lottery_gw2_v1/[a-z0-9_]+\.png$'){throw "Unexpected preload image: $src"}
    'images/'+$src.Substring('file://{images}/'.Length)
})
$lotteryGW2Pngs=@($lotteryGW2Files|Where-Object {$_ -like '*.png'})
if(-not $lotteryGW2Pngs.Count -or @($lotteryGW2Dependencies|Select-Object -Unique).Count -ne $lotteryGW2Dependencies.Count -or
    $lotteryGW2Dependencies.Count -ne $lotteryGW2Pngs.Count -or @(Compare-Object $lotteryGW2Dependencies $lotteryGW2Pngs).Count){throw 'Preload PNG dependencies must exactly equal the unique compile scope PNGs.'}
$lotteryGW2Manifest=Get-Content -LiteralPath (Get-WorkspacePath 'tools/lottery_gw2/asset_manifest.json') -Raw -Encoding UTF8|ConvertFrom-Json
$lotteryGW2ManifestHashes=@{}
$lotteryGW2ManifestImages=@($lotteryGW2Manifest.assets.PSObject.Properties|ForEach-Object {
    $asset=$_.Value
    if($asset.file -notmatch '^art/ui/sources/custom_game/lottery_gw2_v1/[a-z0-9_]+\.png$'){throw "Unexpected manifest path: $($asset.file)"}
    $assetPath=Get-WorkspacePath $asset.file
    if((Get-FileHash -LiteralPath $assetPath -Algorithm SHA256).Hash -ne $asset.sha256){throw "Manifest hash mismatch: $($asset.file)"}
    $imageRelative='images/'+$asset.file.Substring('art/ui/sources/'.Length)
    $lotteryGW2ManifestHashes[$imageRelative]=$asset.sha256
    $imageRelative
})
if($lotteryGW2ManifestImages.Count -ne $lotteryGW2Pngs.Count -or @($lotteryGW2ManifestImages|Select-Object -Unique).Count -ne $lotteryGW2ManifestImages.Count -or
    @(Compare-Object $lotteryGW2ManifestImages $lotteryGW2Pngs).Count){throw 'Manifest and compile scope PNGs differ. Run node tools/lottery_gw2/build_scope.cjs.'}
# Check every lotteryGW2 image referenced by the selected production sources.
foreach($relative in @($lotteryGW2Files|Where-Object {$_ -notlike '*.png'})){
    $sourceText=Get-Content -LiteralPath (Get-WorkspacePath ('panorama/src/'+$relative)) -Raw -Encoding UTF8
    foreach($match in [regex]::Matches($sourceText,'(?:file://\{images\}/)?custom_game/lottery_gw2_v1/([a-z0-9_]+\.png)')){
        $dependency='images/custom_game/lottery_gw2_v1/'+$match.Groups[1].Value
        if($lotteryGW2Pngs -notcontains $dependency){throw "Referenced image is absent from scope/preload: $dependency"}
    }
}
[xml]$lotteryGW2Main=Get-Content -LiteralPath (Get-WorkspacePath 'panorama/src/layout/custom_game/survival_hud.xml') -Raw -Encoding UTF8
$lotteryGW2Includes=@($lotteryGW2Main.SelectNodes('//*[@src or @layoutfile]')|ForEach-Object {if($_.HasAttribute('src')){$_.GetAttribute('src')}if($_.HasAttribute('layoutfile')){$_.GetAttribute('layoutfile')}})
foreach($required in @('scripts/custom_game/lottery_gw2.js','scripts/custom_game/lottery_gw2_data.js','styles/custom_game/lottery_gw2.css')){
    if($lotteryGW2Includes -notcontains ('file://{resources}/'+$required)){throw "survival_hud.xml does not include the lottery runtime source: $required"}
}
$lotteryGW2Backup=Get-WorkspacePath ('output/lottery_gw2/compile_'+(Get-Date -Format yyyyMMdd_HHmmss_fff)+'_'+[guid]::NewGuid().ToString('N').Substring(0,8))
$lotteryGW2Records=@()
foreach($relative in $lotteryGW2Files){
    if($relative -isnot [string] -or $relative -notmatch $lotteryGW2Allowed){throw "Path is outside the lotteryGW2 task: $relative"}
    $source=Get-WorkspacePath ('panorama/src/'+$relative)
    $destination=[IO.Path]::GetFullPath((Join-Path $lotteryGW2Content $relative))
    $artifactRelative=$relative -replace '\.js$','.vjs_c' -replace '\.css$','.vcss_c' -replace '\.xml$','.vxml_c' -replace '\.png$','_png.vtex_c'
    $artifact=[IO.Path]::GetFullPath((Join-Path $lotteryGW2Runtime $artifactRelative))
    if(-not $destination.StartsWith($lotteryGW2Content+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase) -or
        -not $artifact.StartsWith($lotteryGW2Runtime+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw "Resolved target escaped task roots: $relative"}
    if(-not(Test-Path -LiteralPath $source -PathType Leaf)){throw "Missing source: $relative"}
    $sourceHash=(Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash
    if($relative.EndsWith('.png') -and $sourceHash -ne $lotteryGW2ManifestHashes[$relative]){throw "Panorama PNG differs from canonical manifest art: $relative"}
    $lotteryGW2Records+=[pscustomobject]@{
        relative=$relative;source=$source;content=$destination;artifact=$artifact;isImage=$relative.EndsWith('.png')
        sourceHash=$sourceHash
        contentExisted=(Test-Path -LiteralPath $destination -PathType Leaf);runtimeExisted=(Test-Path -LiteralPath $artifact -PathType Leaf)
        sourceBackup=(Join-Path $lotteryGW2Backup ('source/'+$relative));contentBackup=(Join-Path $lotteryGW2Backup ('content/'+$relative))
        runtimeBackup=(Join-Path $lotteryGW2Backup ('runtime/'+$artifactRelative));compileStartedUtc=$null
        compiledHash=$null;artifactBytes=$null;artifactWriteUtc=$null;verified=$false
    }
}
if($CheckOnly){[pscustomobject]@{success=$true;checkOnly=$true;files=$lotteryGW2Records.Count;pngs=$lotteryGW2Pngs.Count;scope=$Scope;report=$Report}|ConvertTo-Json;return}
New-Item -ItemType Directory -Path $lotteryGW2Backup -Force|Out-Null
foreach($record in $lotteryGW2Records){
    foreach($target in @($record.sourceBackup,$record.contentBackup,$record.runtimeBackup)){New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force|Out-Null}
    Copy-Item -LiteralPath $record.source -Destination $record.sourceBackup
    if($record.contentExisted){Copy-Item -LiteralPath $record.content -Destination $record.contentBackup}
    if($record.runtimeExisted){Copy-Item -LiteralPath $record.artifact -Destination $record.runtimeBackup}
}
$lotteryGW2Records|ConvertTo-Json -Depth 6|Set-Content -LiteralPath (Join-Path $lotteryGW2Backup 'manifest_before.json') -Encoding UTF8
try {
    foreach($record in $lotteryGW2Records){
        New-Item -ItemType Directory -Path (Split-Path -Parent $record.content) -Force|Out-Null
        Copy-Item -LiteralPath $record.source -Destination $record.content -Force
        if((Get-FileHash -LiteralPath $record.content -Algorithm SHA256).Hash -ne $record.sourceHash){throw "Content copy differs: $($record.relative)"}
    }
    $compileStart=(Get-Date).ToUniversalTime()
    $build=@($lotteryGW2Records|Where-Object {-not $_.isImage}|Sort-Object @{Expression={if($_.relative -eq $lotteryGW2Assets){1}elseif($_.relative.StartsWith('layout/')){2}else{0}}},relative)
    foreach($record in $build){
        $record.compileStartedUtc=(Get-Date).ToUniversalTime().ToString('o')
        $force=if($record.relative -eq $lotteryGW2Assets){'-f'}else{'-fshallow'}
        $log=@(& $lotteryGW2Compiler -i $record.content -game (Join-Path $lotteryGW2Engine 'game/dota') $force -nop4 2>&1)
        $exitCode=$LASTEXITCODE
        $log|Set-Content -LiteralPath (Join-Path $lotteryGW2Backup (($record.relative -replace '/','_')+'.log')) -Encoding UTF8
        if($exitCode -ne 0 -or -not($log -match '0 failed')){throw "Native compile failed: $($record.relative)"}
        Write-Output ('LOTTERY_GW2_COMPILE_PASS '+$record.relative)
    }
    foreach($record in $lotteryGW2Records){
        if((Get-FileHash -LiteralPath $record.source -Algorithm SHA256).Hash -ne $record.sourceHash -or
            (Get-FileHash -LiteralPath $record.content -Algorithm SHA256).Hash -ne $record.sourceHash){throw "Source changed during compile: $($record.relative)"}
        if(-not(Test-Path -LiteralPath $record.artifact -PathType Leaf)){throw "Missing compiled file: $($record.relative)"}
        $file=Get-Item -LiteralPath $record.artifact
        $minimum=if($record.isImage){$compileStart}else{[datetime]::Parse($record.compileStartedUtc).ToUniversalTime()}
        if($file.Length -le 0 -or $file.LastWriteTimeUtc -lt $minimum){throw "Stale or empty compiled file: $($record.relative)"}
        $record.compiledHash=(Get-FileHash -LiteralPath $record.artifact -Algorithm SHA256).Hash
        $record.artifactBytes=$file.Length;$record.artifactWriteUtc=$file.LastWriteTimeUtc.ToString('o');$record.verified=$true
    }
    New-Item -ItemType Directory -Path (Split-Path -Parent $lotteryGW2Report) -Force|Out-Null
    @{at=(Get-Date -Format o);success=$true;backup=$lotteryGW2Backup;records=$lotteryGW2Records;scope=$Scope;compileStartedUtc=$compileStart.ToString('o');pngDependencies=$lotteryGW2Dependencies}|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $lotteryGW2Report -Encoding UTF8
} catch {
    $failure=$_
    foreach($record in $lotteryGW2Records){
        if($record.contentExisted){Copy-Item -LiteralPath $record.contentBackup -Destination $record.content -Force}
        elseif(Test-Path -LiteralPath $record.content -PathType Leaf){Remove-Item -LiteralPath $record.content}
        if($record.runtimeExisted){Copy-Item -LiteralPath $record.runtimeBackup -Destination $record.artifact -Force}
        elseif(Test-Path -LiteralPath $record.artifact -PathType Leaf){Remove-Item -LiteralPath $record.artifact}
    }
    @{at=(Get-Date -Format o);success=$false;rolledBack=$true;error=$failure.ToString();backup=$lotteryGW2Backup;records=$lotteryGW2Records}|ConvertTo-Json -Depth 8|Set-Content -LiteralPath (Join-Path $lotteryGW2Backup 'failure.json') -Encoding UTF8
    throw $failure
}
