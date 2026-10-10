param([string]$Scope='design_refs/void_shadow_v1/work/compile_scope.json')
$ErrorActionPreference='Stop'
$voidRepo=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$voidEngine=(Resolve-Path (Join-Path $voidRepo '../../..')).Path
$voidContent=Join-Path $voidEngine 'content/dota_addons/Survival/panorama'
$voidRuntime=Join-Path $voidRepo 'panorama'
$voidCompiler=Join-Path $voidEngine 'game/bin/win64/resourcecompiler.exe'
$voidBackup=Join-Path $voidRepo ('output/void_shadow_v1/compile_'+(Get-Date -Format yyyyMMdd_HHmmss_fff)+'_'+[guid]::NewGuid().ToString('N').Substring(0,8))
$voidReport=Join-Path $voidRepo 'design_refs/void_shadow_v1/work/compile.json'
$voidAllowed='^(?:scripts/custom_game/archive_(?:void_v1(?:_[a-z0-9_]+)?|180de7e38b_titles_compact_v6)\.js|styles/custom_game/archive_void_v1(?:_[a-z0-9_]+)?\.css|layout/custom_game/archive(?:_void_v1(?:_[a-z0-9_]+)?)?\.xml|images/custom_game/void_shadow_v1/(?:[a-z0-9_]+/)*[a-z0-9_]+\.png)$'
$voidAssetLayout='layout/custom_game/archive_void_v1_assets.xml'
$voidFiles=Get-Content -LiteralPath (Join-Path $voidRepo $Scope) -Raw -Encoding UTF8|ConvertFrom-Json
if(-not $voidFiles.Count){throw 'Compile scope is empty.'}
if(($voidFiles|Select-Object -Unique).Count -ne $voidFiles.Count){throw 'Compile scope contains duplicate paths.'}
if(($voidFiles|Where-Object {$_ -like '*.png'}).Count -and $voidFiles -notcontains $voidAssetLayout){throw 'PNG scope requires archive_void_v1_assets.xml.'}
if($voidFiles -contains $voidAssetLayout){
    [xml]$voidAssetXml=Get-Content -LiteralPath (Join-Path $voidRepo ('panorama/src/'+$voidAssetLayout)) -Raw -Encoding UTF8
    if($voidAssetXml.SelectNodes('//include').Count){throw 'Task preload layout must not include other resources.'}
    $voidAssetImages=@($voidAssetXml.SelectNodes('//Image[@src]')|ForEach-Object {
        $voidImageSrc=$_.GetAttribute('src')
        if($voidImageSrc -notmatch '^file://\{images\}/custom_game/void_shadow_v1/(?:[a-z0-9_]+/)*[a-z0-9_]+\.png$'){throw "Asset layout includes a non-task image: $voidImageSrc"}
        'images/'+$voidImageSrc.Substring('file://{images}/'.Length)
    })
    $voidScopedImages=@($voidFiles|Where-Object {$_ -like '*.png'})
    if($voidAssetImages.Count -ne $voidScopedImages.Count -or @(Compare-Object $voidAssetImages $voidScopedImages).Count){throw 'Asset layout and scoped PNG list differ.'}
}
$voidRecords=@()
# Validate and back up every selected file before writing outside the workspace.
foreach($voidRel in $voidFiles){
    if($voidRel -notmatch $voidAllowed){throw "Path is outside this task: $voidRel"}
    $voidSource=Join-Path $voidRepo ('panorama/src/'+$voidRel)
    $voidDest=Join-Path $voidContent $voidRel
    $voidArtifactRel=$voidRel -replace '\.js$','.vjs_c' -replace '\.css$','.vcss_c' -replace '\.xml$','.vxml_c' -replace '\.png$','_png.vtex_c'
    $voidArtifact=Join-Path $voidRuntime $voidArtifactRel
    if(-not(Test-Path -LiteralPath $voidSource -PathType Leaf)){throw "Missing source: $voidRel"}
    $voidRecords+=[pscustomobject]@{
        relative=$voidRel;source=$voidSource;content=$voidDest;artifact=$voidArtifact
        isImage=$voidRel.EndsWith('.png');sourceHash=(Get-FileHash -LiteralPath $voidSource -Algorithm SHA256).Hash
        contentExisted=(Test-Path -LiteralPath $voidDest -PathType Leaf);runtimeExisted=(Test-Path -LiteralPath $voidArtifact -PathType Leaf)
        sourceBackup=(Join-Path $voidBackup ('source/'+$voidRel));contentBackup=(Join-Path $voidBackup ('content/'+$voidRel))
        runtimeBackup=(Join-Path $voidBackup ('runtime/'+$voidArtifactRel));compiledHash=$null;artifactBytes=$null;artifactWriteUtc=$null
        compileStartedUtc=$null;verified=$false
    }
}
New-Item -ItemType Directory -Path $voidBackup -Force|Out-Null
foreach($voidRecord in $voidRecords){
    foreach($voidPath in @($voidRecord.sourceBackup,$voidRecord.contentBackup,$voidRecord.runtimeBackup)){New-Item -ItemType Directory -Path (Split-Path -Parent $voidPath) -Force|Out-Null}
    Copy-Item -LiteralPath $voidRecord.source -Destination $voidRecord.sourceBackup
    if($voidRecord.contentExisted){Copy-Item -LiteralPath $voidRecord.content -Destination $voidRecord.contentBackup}
    if($voidRecord.runtimeExisted){Copy-Item -LiteralPath $voidRecord.artifact -Destination $voidRecord.runtimeBackup}
}
$voidRecords|ConvertTo-Json -Depth 6|Set-Content -LiteralPath (Join-Path $voidBackup 'manifest_before.json') -Encoding UTF8
try {
    foreach($voidRecord in $voidRecords){
        New-Item -ItemType Directory -Path (Split-Path -Parent $voidRecord.content) -Force|Out-Null
        # Preserve the source PNG bytes and alpha; no raster conversion or resampling.
        Copy-Item -LiteralPath $voidRecord.source -Destination $voidRecord.content -Force
        if((Get-FileHash -LiteralPath $voidRecord.content -Algorithm SHA256).Hash -ne $voidRecord.sourceHash){throw "Content copy differs: $($voidRecord.relative)"}
    }
    $voidCompileStart=(Get-Date).ToUniversalTime()
    # Scripts/styles first, explicit image dependency layout next, archive layout last.
    $voidBuild=@($voidRecords|Where-Object {-not $_.isImage}|Sort-Object @{Expression={if($_.relative -eq $voidAssetLayout){1}elseif($_.relative.StartsWith('layout/')){2}else{0}}},relative)
    foreach($voidRecord in $voidBuild){
        $voidStart=(Get-Date).ToUniversalTime()
        $voidRecord.compileStartedUtc=$voidStart.ToString('o')
        # The dedicated asset layout only references task PNGs. Force its dependencies
        # so a rebuilt manifest cannot silently accept an old compiled image.
        $voidForce=if($voidRecord.relative -eq $voidAssetLayout){'-f'}else{'-fshallow'}
        $voidLog=@(& $voidCompiler -i $voidRecord.content -game (Join-Path $voidEngine 'game/dota') $voidForce -nop4 2>&1)
        $voidExit=$LASTEXITCODE
        $voidLog|Set-Content -LiteralPath (Join-Path $voidBackup (($voidRecord.relative -replace '/','_')+'.log')) -Encoding UTF8
        if($voidExit -ne 0 -or -not ($voidLog -match '0 failed')){throw "Native compile failed: $($voidRecord.relative)"}
        if(-not(Test-Path -LiteralPath $voidRecord.artifact -PathType Leaf)){throw "Missing compiled file: $($voidRecord.relative)"}
        $voidFile=Get-Item -LiteralPath $voidRecord.artifact
        if($voidFile.Length -le 0 -or $voidFile.LastWriteTimeUtc -lt $voidStart){throw "Stale or empty compiled file: $($voidRecord.relative)"}
        Write-Output ('VOID_COMPILE_PASS '+$voidRecord.relative)
    }
    # Verify images only after their preload layout and every UI source compiled.
    foreach($voidRecord in $voidRecords){
        if((Get-FileHash -LiteralPath $voidRecord.source -Algorithm SHA256).Hash -ne $voidRecord.sourceHash){throw "Source changed during compile: $($voidRecord.relative)"}
        if(-not(Test-Path -LiteralPath $voidRecord.artifact -PathType Leaf)){throw "Missing compiled file: $($voidRecord.relative)"}
        $voidFile=Get-Item -LiteralPath $voidRecord.artifact
        $voidMinimum=if($voidRecord.isImage){$voidCompileStart}else{[datetime]::Parse($voidRecord.compileStartedUtc).ToUniversalTime()}
        if($voidFile.Length -le 0 -or $voidFile.LastWriteTimeUtc -lt $voidMinimum){throw "Stale or empty compiled file: $($voidRecord.relative)"}
        $voidRecord.compiledHash=(Get-FileHash -LiteralPath $voidRecord.artifact -Algorithm SHA256).Hash
        $voidRecord.artifactBytes=$voidFile.Length
        $voidRecord.artifactWriteUtc=$voidFile.LastWriteTimeUtc.ToString('o')
        $voidRecord.verified=$true
        if($voidRecord.isImage){Write-Output ('VOID_IMAGE_PASS '+$voidRecord.relative)}
    }
    $voidRecords|ConvertTo-Json -Depth 6|Set-Content -LiteralPath (Join-Path $voidBackup 'manifest.json') -Encoding UTF8
    New-Item -ItemType Directory -Path (Split-Path -Parent $voidReport) -Force|Out-Null
    @{at=(Get-Date -Format o);success=$true;backup=$voidBackup;records=$voidRecords;scope=$Scope;compileStartedUtc=$voidCompileStart.ToString('o');policy='Only explicit task files; original RGBA PNG bytes; no broad Content sync or system font changes'}|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $voidReport -Encoding UTF8
} catch {
    $voidFailure=$_
    foreach($voidRecord in $voidRecords){
        if($voidRecord.contentExisted){Copy-Item -LiteralPath $voidRecord.contentBackup -Destination $voidRecord.content -Force}
        elseif(Test-Path -LiteralPath $voidRecord.content -PathType Leaf){Remove-Item -LiteralPath $voidRecord.content}
        if($voidRecord.runtimeExisted){Copy-Item -LiteralPath $voidRecord.runtimeBackup -Destination $voidRecord.artifact -Force}
        elseif(Test-Path -LiteralPath $voidRecord.artifact -PathType Leaf){Remove-Item -LiteralPath $voidRecord.artifact}
    }
    @{at=(Get-Date -Format o);success=$false;rolledBack=$true;error=$voidFailure.ToString();backup=$voidBackup;records=$voidRecords}|ConvertTo-Json -Depth 8|Set-Content -LiteralPath (Join-Path $voidBackup 'failure.json') -Encoding UTF8
    throw $voidFailure
}
