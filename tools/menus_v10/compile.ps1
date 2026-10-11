param([string]$Scope='tools/menus_v10/compile_scope.json',
      [string]$Report='design_refs/menus_v10/work/compile.json')
$ErrorActionPreference='Stop'
$archiveRepo=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$archiveEngine=(Resolve-Path (Join-Path $archiveRepo '../../..')).Path
$archiveContent=Join-Path $archiveEngine 'content/dota_addons/Survival/panorama'
$archiveRuntime=Join-Path $archiveRepo 'panorama'
$archiveCompiler=Join-Path $archiveEngine 'game/bin/win64/resourcecompiler.exe'
$archiveBackup=Join-Path $archiveRepo ('output/menus_v10/compile_'+(Get-Date -Format yyyyMMdd_HHmmss_fff)+'_'+[guid]::NewGuid().ToString('N').Substring(0,8))
$archiveReport=[IO.Path]::GetFullPath((Join-Path $archiveRepo $Report))
if(-not $archiveReport.StartsWith($archiveRepo+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw 'Compile report is outside the workspace.'}
$archiveAllowed='^(?:scripts/custom_game/common/menu_v10\.js|scripts/custom_game/common/purple_shell\.js|scripts/custom_game/archive_v10\.js|scripts/custom_game/archive_180de7e38b_titles_compact_v6\.js|scripts/custom_game/archive_handoff_180de7e38b\.js|scripts/custom_game/shop_remaining_5d5c1152eb\.js|scripts/custom_game/shop_tooltip_remaining_5d5c1152eb\.js|scripts/custom_game/common/commerce_components\.js|scripts/custom_game/commerce_remaining_5d5c1152eb\.js|scripts/custom_game/commerce_wallet\.js|scripts/custom_game/payment_test\.js|scripts/custom_game/menu_purple\.js|scripts/custom_game/lottery_handoff_bb9968eef7\.js|scripts/custom_game/lottery_ui_remaining_5d5c1152eb\.js|scripts/custom_game/lottery_cinematic_v1\.js|scripts/custom_game/treasure_history\.js|scripts/custom_game/daily_remaining_5d5c1152eb\.js|scripts/custom_game/vip_window\.js|styles/custom_game/common/menu_v10\.css|styles/custom_game/menus_v10_commerce\.css|styles/custom_game/menus_v10_lottery\.css|styles/custom_game/menus_v10_archive_pages\.css|layout/custom_game/archive\.xml|layout/custom_game/survival_hud\.xml|layout/custom_game/payment_test\.xml)$'
$archiveAssetLayout='layout/custom_game/archive_v10_assets.xml'
$archiveScopePath=[IO.Path]::GetFullPath((Join-Path $archiveRepo $Scope))
if(-not $archiveScopePath.StartsWith($archiveRepo+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw 'Compile scope is outside the workspace.'}
$archiveFiles=Get-Content -LiteralPath $archiveScopePath -Raw -Encoding UTF8|ConvertFrom-Json
if(-not $archiveFiles.Count){throw 'Compile scope is empty.'}
if(@($archiveFiles|Select-Object -Unique).Count -ne $archiveFiles.Count){throw 'Compile scope contains duplicate paths.'}
if(@($archiveFiles|Where-Object {$_ -like '*.png'}).Count -and $archiveFiles -notcontains $archiveAssetLayout){throw 'PNG scope requires archive_v10_assets.xml.'}
if($archiveFiles -contains $archiveAssetLayout){
    [xml]$archiveAssetXml=Get-Content -LiteralPath (Join-Path $archiveRepo ('panorama/src/'+$archiveAssetLayout)) -Raw -Encoding UTF8
    if($archiveAssetXml.SelectNodes('//include').Count){throw 'Task preload layout must not include other resources.'}
    $archiveAssetImages=@($archiveAssetXml.SelectNodes('//Image[@src]')|ForEach-Object {
        $archiveImageSrc=$_.GetAttribute('src')
        if($archiveImageSrc -notmatch '^file://\{images\}/custom_game/archive_v10/(?:backgrounds|common|items|tooltip)/[a-z0-9_]+\.png$'){throw "Asset layout includes a non-task image: $archiveImageSrc"}
        'images/'+$archiveImageSrc.Substring('file://{images}/'.Length)
    })
    $archiveScopedImages=@($archiveFiles|Where-Object {$_ -like '*.png'})
    if($archiveAssetImages.Count -ne $archiveScopedImages.Count -or @(Compare-Object $archiveAssetImages $archiveScopedImages).Count){throw 'Asset layout and scoped PNG list differ.'}
}
$archiveRecords=@()
# Validate the complete allowlist before any source or runtime copy.
foreach($archiveRel in $archiveFiles){
    if($archiveRel -notmatch $archiveAllowed){throw "Path is outside this archive task: $archiveRel"}
    $archiveSource=Join-Path $archiveRepo ('panorama/src/'+$archiveRel)
    $archiveDest=[IO.Path]::GetFullPath((Join-Path $archiveContent $archiveRel))
    $archiveArtifactRel=$archiveRel -replace '\.js$','.vjs_c' -replace '\.css$','.vcss_c' -replace '\.xml$','.vxml_c' -replace '\.png$','_png.vtex_c'
    $archiveArtifact=[IO.Path]::GetFullPath((Join-Path $archiveRuntime $archiveArtifactRel))
    if(-not $archiveDest.StartsWith($archiveContent+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw "Content target escaped task root: $archiveRel"}
    if(-not $archiveArtifact.StartsWith($archiveRuntime+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw "Runtime target escaped task root: $archiveRel"}
    if(-not(Test-Path -LiteralPath $archiveSource -PathType Leaf)){throw "Missing source: $archiveRel"}
    $archiveRecords+=[pscustomobject]@{
        relative=$archiveRel;source=$archiveSource;content=$archiveDest;artifact=$archiveArtifact
        isImage=$archiveRel.EndsWith('.png');sourceHash=(Get-FileHash -LiteralPath $archiveSource -Algorithm SHA256).Hash
        contentExisted=(Test-Path -LiteralPath $archiveDest -PathType Leaf);runtimeExisted=(Test-Path -LiteralPath $archiveArtifact -PathType Leaf)
        sourceBackup=(Join-Path $archiveBackup ('source/'+$archiveRel));contentBackup=(Join-Path $archiveBackup ('content/'+$archiveRel))
        runtimeBackup=(Join-Path $archiveBackup ('runtime/'+$archiveArtifactRel));compiledHash=$null;artifactBytes=$null;artifactWriteUtc=$null
        compileStartedUtc=$null;verified=$false
    }
}
New-Item -ItemType Directory -Path $archiveBackup -Force|Out-Null
foreach($archiveRecord in $archiveRecords){
    foreach($archivePath in @($archiveRecord.sourceBackup,$archiveRecord.contentBackup,$archiveRecord.runtimeBackup)){New-Item -ItemType Directory -Path (Split-Path -Parent $archivePath) -Force|Out-Null}
    Copy-Item -LiteralPath $archiveRecord.source -Destination $archiveRecord.sourceBackup
    if($archiveRecord.contentExisted){Copy-Item -LiteralPath $archiveRecord.content -Destination $archiveRecord.contentBackup}
    if($archiveRecord.runtimeExisted){Copy-Item -LiteralPath $archiveRecord.artifact -Destination $archiveRecord.runtimeBackup}
}
$archiveRecords|ConvertTo-Json -Depth 6|Set-Content -LiteralPath (Join-Path $archiveBackup 'manifest_before.json') -Encoding UTF8
try {
    foreach($archiveRecord in $archiveRecords){
        New-Item -ItemType Directory -Path (Split-Path -Parent $archiveRecord.content) -Force|Out-Null
        # Byte-for-byte source PNG copies; preserve original alpha, no raster redraw.
        Copy-Item -LiteralPath $archiveRecord.source -Destination $archiveRecord.content -Force
        if((Get-FileHash -LiteralPath $archiveRecord.content -Algorithm SHA256).Hash -ne $archiveRecord.sourceHash){throw "Content copy differs: $($archiveRecord.relative)"}
    }
    $archiveCompileStart=(Get-Date).ToUniversalTime()
    # Scripts and CSS first, task-only bitmap dependency layout next, main archive XML last.
    $archiveBuild=@($archiveRecords|Where-Object {-not $_.isImage}|Sort-Object @{Expression={if($_.relative -eq $archiveAssetLayout){1}elseif($_.relative.StartsWith('layout/')){2}else{0}}},relative)
    foreach($archiveRecord in $archiveBuild){
        $archiveStart=(Get-Date).ToUniversalTime()
        $archiveRecord.compileStartedUtc=$archiveStart.ToString('o')
        $archiveForce=if($archiveRecord.relative -eq $archiveAssetLayout){'-f'}else{'-fshallow'}
        $archiveLog=@(& $archiveCompiler -i $archiveRecord.content -game (Join-Path $archiveEngine 'game/dota') $archiveForce -nop4 2>&1)
        $archiveExit=$LASTEXITCODE
        $archiveLog|Set-Content -LiteralPath (Join-Path $archiveBackup (($archiveRecord.relative -replace '/','_')+'.log')) -Encoding UTF8
        if($archiveExit -ne 0 -or -not ($archiveLog -match '0 failed')){throw "Native compile failed: $($archiveRecord.relative)"}
        if(-not(Test-Path -LiteralPath $archiveRecord.artifact -PathType Leaf)){throw "Missing compiled file: $($archiveRecord.relative)"}
        $archiveFile=Get-Item -LiteralPath $archiveRecord.artifact
        if($archiveFile.Length -le 0 -or $archiveFile.LastWriteTimeUtc -lt $archiveStart){throw "Stale or empty compiled file: $($archiveRecord.relative)"}
        Write-Output ('ARCHIVE_V10_COMPILE_PASS '+$archiveRecord.relative)
    }
    foreach($archiveRecord in $archiveRecords){
        if((Get-FileHash -LiteralPath $archiveRecord.source -Algorithm SHA256).Hash -ne $archiveRecord.sourceHash){throw "Source changed during compile: $($archiveRecord.relative)"}
        if(-not(Test-Path -LiteralPath $archiveRecord.artifact -PathType Leaf)){throw "Missing compiled file: $($archiveRecord.relative)"}
        $archiveFile=Get-Item -LiteralPath $archiveRecord.artifact
        $archiveMinimum=if($archiveRecord.isImage){$archiveCompileStart}else{[datetime]::Parse($archiveRecord.compileStartedUtc).ToUniversalTime()}
        if($archiveFile.Length -le 0 -or $archiveFile.LastWriteTimeUtc -lt $archiveMinimum){throw "Stale or empty compiled file: $($archiveRecord.relative)"}
        $archiveRecord.compiledHash=(Get-FileHash -LiteralPath $archiveRecord.artifact -Algorithm SHA256).Hash
        $archiveRecord.artifactBytes=$archiveFile.Length
        $archiveRecord.artifactWriteUtc=$archiveFile.LastWriteTimeUtc.ToString('o')
        $archiveRecord.verified=$true
        if($archiveRecord.isImage){Write-Output ('ARCHIVE_V10_IMAGE_PASS '+$archiveRecord.relative)}
    }
    $archiveRecords|ConvertTo-Json -Depth 6|Set-Content -LiteralPath (Join-Path $archiveBackup 'manifest.json') -Encoding UTF8
    New-Item -ItemType Directory -Path (Split-Path -Parent $archiveReport) -Force|Out-Null
    @{at=(Get-Date -Format o);success=$true;backup=$archiveBackup;records=$archiveRecords;scope=$Scope;compileStartedUtc=$archiveCompileStart.ToString('o');policy='Only explicit archive task files; original PNG bytes; existing registered font; no broad Content sync'}|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $archiveReport -Encoding UTF8
} catch {
    $archiveFailure=$_
    foreach($archiveRecord in $archiveRecords){
        if($archiveRecord.contentExisted){Copy-Item -LiteralPath $archiveRecord.contentBackup -Destination $archiveRecord.content -Force}
        elseif(Test-Path -LiteralPath $archiveRecord.content -PathType Leaf){Remove-Item -LiteralPath $archiveRecord.content}
        if($archiveRecord.runtimeExisted){Copy-Item -LiteralPath $archiveRecord.runtimeBackup -Destination $archiveRecord.artifact -Force}
        elseif(Test-Path -LiteralPath $archiveRecord.artifact -PathType Leaf){Remove-Item -LiteralPath $archiveRecord.artifact}
    }
    @{at=(Get-Date -Format o);success=$false;rolledBack=$true;error=$archiveFailure.ToString();backup=$archiveBackup;records=$archiveRecords}|ConvertTo-Json -Depth 8|Set-Content -LiteralPath (Join-Path $archiveBackup 'failure.json') -Encoding UTF8
    throw $archiveFailure
}
