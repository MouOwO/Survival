param(
    [string]$Scope='tools/tooltip_hover/compile_scope.json',
    [string]$Report='output/tooltip_hover_unification/compile.json',
    [string]$SourceRoot='panorama/src',
    [switch]$CheckOnly
)
$ErrorActionPreference='Stop'
$hoverRepo=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$hoverEngine=(Resolve-Path (Join-Path $hoverRepo '../../..')).Path
$hoverContent=Join-Path $hoverEngine 'content/dota_addons/Survival/panorama'
$hoverRuntime=Join-Path $hoverRepo 'panorama'
$hoverCompiler=Join-Path $hoverEngine 'game/bin/win64/resourcecompiler.exe'
$hoverRequired=@(
    'scripts/custom_game/common/tooltip_dismiss.js',
    'scripts/custom_game/common/archive_tooltip.js',
    'scripts/custom_game/common/menu_v10.js',
    'scripts/custom_game/daily_remaining_5d5c1152eb.js',
    'scripts/custom_game/lottery_gw2.js',
    'scripts/custom_game/archive_handoff_180de7e38b.js',
    'scripts/custom_game/inventory_tooltip.js',
    'scripts/custom_game/ability_tooltip.js',
    'scripts/custom_game/hud_takeover.js',
    'scripts/custom_game/shop_tooltip_remaining_5d5c1152eb.js',
    'scripts/custom_game/remaining_5d5c1152eb.js',
    'scripts/custom_game/lottery_ui_remaining_5d5c1152eb.js',
    'layout/custom_game/archive.xml',
    'layout/custom_game/survival_hud.xml',
    'layout/custom_game/payment_test.xml'
)
function Get-HoverChildPath([string]$Root,[string]$Relative) {
    $inputPath=if([IO.Path]::IsPathRooted($Relative)){$Relative}else{Join-Path $Root $Relative}
    $resolved=[IO.Path]::GetFullPath($inputPath).TrimEnd([IO.Path]::DirectorySeparatorChar)
    if(-not $resolved.StartsWith($Root+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw "Path escaped its root: $Relative"}
    return $resolved
}
function Assert-HoverNoLinks([string]$Path,[string]$Boundary) {
    $cursor=$Path
    while(-not(Test-Path -LiteralPath $cursor)){
        $cursor=Split-Path -Parent $cursor
        if(-not $cursor -or $cursor.Length -lt $Boundary.Length){throw "Missing path boundary: $Path"}
    }
    $item=Get-Item -LiteralPath $cursor -Force
    while($item){
        if($item.Attributes -band [IO.FileAttributes]::ReparsePoint){throw "Path must not traverse a link: $Path"}
        if($item.FullName.Equals($Boundary,[StringComparison]::OrdinalIgnoreCase)){return}
        $item=if($item -is [IO.DirectoryInfo]){$item.Parent}else{$item.Directory}
    }
    throw "Path did not reach its expected boundary: $Path"
}
function Get-HoverWorkspacePath([string]$Relative) {
    $resolved=Get-HoverChildPath $hoverRepo $Relative
    Assert-HoverNoLinks $resolved $hoverRepo
    return $resolved
}
function Get-HoverArtifactRelative([string]$Relative) {
    return $Relative -replace '\.js$','.vjs_c' -replace '\.css$','.vcss_c' -replace '\.xml$','.vxml_c' -replace '\.png$','_png.vtex_c' -replace '\.svg$','.vsvg_c'
}
function Get-HoverHash([string]$Path) {
    if(Test-Path -LiteralPath $Path -PathType Leaf){return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash}
    return $null
}
$hoverScopePath=Get-HoverWorkspacePath $Scope
$hoverFiles=@(Get-Content -LiteralPath $hoverScopePath -Raw -Encoding UTF8|ConvertFrom-Json)
if(($hoverFiles -join "`n") -cne ($hoverRequired -join "`n")){throw 'Tooltip hover scope must contain exactly the 15 approved sources in order: helper, eleven owners, then three XML layouts. CSS/data/images and unrelated business sources are excluded.'}
$hoverSource=Get-HoverWorkspacePath $SourceRoot
$hoverDefaultSource=Join-Path $hoverRuntime 'src'
if(($hoverSource.Equals($hoverRuntime,[StringComparison]::OrdinalIgnoreCase) -or $hoverSource.StartsWith($hoverRuntime+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)) -and
    -not($hoverSource.Equals($hoverDefaultSource,[StringComparison]::OrdinalIgnoreCase) -or $hoverSource.StartsWith($hoverDefaultSource+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase))){throw 'SourceRoot must not point into Panorama runtime artifacts.'}
if(-not(Test-Path -LiteralPath $hoverSource -PathType Container)){throw "SourceRoot directory is missing: $SourceRoot"}
function Get-HoverSourcePath([string]$Relative) {
    $resolved=Get-HoverChildPath $hoverSource $Relative
    Assert-HoverNoLinks $resolved $hoverRepo
    if(-not(Test-Path -LiteralPath $resolved -PathType Leaf)){throw "Missing source: $Relative"}
    return $resolved
}
$hoverReport=Get-HoverWorkspacePath $Report
$hoverOutputRoot=Join-Path $hoverRepo 'output'
$hoverDesignWork=Join-Path $hoverRepo 'design_refs/tooltip_hover_unification/work'
if(-not $hoverReport.EndsWith('.json',[StringComparison]::OrdinalIgnoreCase) -or
    -not($hoverReport.StartsWith($hoverOutputRoot+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase) -or $hoverReport.StartsWith($hoverDesignWork+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase))){throw 'Report must be a JSON file below output/ or design_refs/tooltip_hover_unification/work/.'}
if(-not(Test-Path -LiteralPath $hoverCompiler -PathType Leaf)){throw 'Native resourcecompiler is missing.'}
function Assert-HoverLayout([string]$Path) {
    [xml]$layout=Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    $scripts=@($layout.SelectNodes('//scripts/include')|ForEach-Object {$_.GetAttribute('src')})
    $helper='file://{resources}/scripts/custom_game/common/tooltip_dismiss.js'
    $components='file://{resources}/scripts/custom_game/common/ui_components.js'
    $menu='file://{resources}/scripts/custom_game/common/menu_v10.js'
    foreach($uri in @($helper,$components,$menu)){
        if(@($scripts|Where-Object {$_ -eq $uri}).Count -ne 1){throw "Required Tooltip script must occur exactly once: $uri ($Path)"}
    }
    $helperAt=[array]::IndexOf($scripts,$helper)
    if([array]::IndexOf($scripts,$components) -ge $helperAt -or [array]::IndexOf($scripts,$menu) -le $helperAt){throw "Tooltip helper must load after ui_components and before menu_v10: $Path"}
    foreach($owner in $hoverRequired|Where-Object {$_ -like '*.js' -and $_ -ne 'scripts/custom_game/common/tooltip_dismiss.js'}){
        $uri='file://{resources}/'+$owner
        $count=@($scripts|Where-Object {$_ -eq $uri}).Count
        if($count -gt 1 -or ($count -eq 1 -and [array]::IndexOf($scripts,$uri) -le $helperAt)){throw "Tooltip owner must occur once after the helper: $owner ($Path)"}
    }
    return $layout
}
$hoverActiveLayouts=@{}
$hoverSelectedLayouts=@{}
foreach($relative in $hoverRequired|Where-Object {$_ -like '*.xml'}){
    $hoverActiveLayouts[$relative]=Assert-HoverLayout (Get-HoverWorkspacePath ('panorama/src/'+$relative))
    $hoverSelectedLayouts[$relative]=Assert-HoverLayout (Get-HoverSourcePath $relative)
}
[xml]$hoverManifest=Get-Content -LiteralPath (Get-HoverWorkspacePath 'panorama/src/layout/custom_game/custom_ui_manifest.xml') -Raw -Encoding UTF8
foreach($relative in $hoverActiveLayouts.Keys){
    if(-not $hoverManifest.SelectSingleNode("//CustomUIElement[@layoutfile='file://{resources}/$relative']")){throw "Active UI manifest does not load $relative"}
}

$hoverProtectedByPath=@{}
function Add-HoverProtected([string]$Path,[string]$Reason) {
    if($hoverProtectedByPath.ContainsKey($Path)){return}
    $hoverProtectedByPath[$Path]=[pscustomobject]@{path=$Path;reason=$Reason;hash=(Get-HoverHash $Path)}
}
function Add-HoverProtectedResource([string]$Relative,[string]$Reason) {
    if($hoverRequired -contains $Relative){return}
    Add-HoverProtected (Get-HoverWorkspacePath ('panorama/src/'+$Relative)) $Reason
    Add-HoverProtected (Get-HoverChildPath $hoverContent $Relative) $Reason
    Add-HoverProtected (Get-HoverChildPath $hoverRuntime (Get-HoverArtifactRelative $Relative)) $Reason
}
# Every unrelated include in either selected or actual layouts is immutable during compilation.
$hoverDependencyPaths=@{}
foreach($layout in @($hoverActiveLayouts.Values)+@($hoverSelectedLayouts.Values)){
    foreach($node in $layout.SelectNodes('//include[@src]')){
        $uri=$node.GetAttribute('src')
        if($uri -match '^file://\{resources\}/((?:scripts|styles|layout)/custom_game/[a-zA-Z0-9_./-]+\.(?:js|css|xml))$'){
            $relative=$Matches[1]
            Add-HoverProtectedResource $relative 'unrelated active/selected layout dependency'
            $hoverDependencyPaths[$relative]=$true
        }
    }
}
foreach($relative in @('styles/custom_game/common/menu_v10.css','scripts/custom_game/topnav_remaining_5d5c1152eb.js','layout/custom_game/custom_ui_manifest.xml','scripts/custom_game/collection_nav.js','scripts/custom_game/archive_v10_data.js','scripts/custom_game/archive_parchment_data.js','scripts/custom_game/collection_gw2_data.js','layout/custom_game/collection_gw2_assets.xml','styles/custom_game/archive_v10.css','styles/custom_game/collection_gw2.css','styles/custom_game/common/archive_tooltip.css','scripts/custom_game/lottery_ui_remaining_5d5c1152eb.js','scripts/custom_game/remaining_5d5c1152eb.js')){Add-HoverProtectedResource $relative 'explicit protected CSS/topnav/data/resource/business'}
Add-HoverProtected $PSCommandPath 'compiler script frozen'
Add-HoverProtected $hoverScopePath 'compiler scope frozen'
if(-not $hoverSource.Equals($hoverDefaultSource,[StringComparison]::OrdinalIgnoreCase)){
    foreach($relative in $hoverRequired){Add-HoverProtected (Get-HoverWorkspacePath ('panorama/src/'+$relative)) 'working source preserved while compiling snapshot'}
}

# Preserve existing local art referenced by the layouts and their scripts/styles. Never compile images.
$hoverImagePaths=@{}
$hoverRequiredImages=@(
    'images/custom_game/archive_parchment_v1/tooltip_background.png',
    'images/custom_game/archive_parchment_v1/tooltip_frame.png',
    'images/custom_game/archive_v10/tooltip/tooltip_separator.png',
    'images/custom_game/archive_parchment_v1/scroll_track.png',
    'images/custom_game/archive_parchment_v1/scroll_thumb.png'
)
foreach($relative in $hoverRequiredImages){$hoverImagePaths[$relative]=$true}
foreach($relative in @($hoverRequired)+@($hoverDependencyPaths.Keys)){
    $dependencyPath=if($hoverRequired -contains $relative){Get-HoverSourcePath $relative}else{Get-HoverWorkspacePath ('panorama/src/'+$relative)}
    if(-not(Test-Path -LiteralPath $dependencyPath -PathType Leaf)){continue}
    $text=Get-Content -LiteralPath $dependencyPath -Raw -Encoding UTF8
    foreach($match in [regex]::Matches($text,'file://\{images\}/(custom_game/[a-zA-Z0-9_./-]+\.(?:png|svg))')){$hoverImagePaths['images/'+$match.Groups[1].Value]=$true}
}
$hoverImages=@()
foreach($relative in @($hoverImagePaths.Keys|Sort-Object)){
    $source=Get-HoverWorkspacePath ('panorama/src/'+$relative)
    $content=Get-HoverChildPath $hoverContent $relative
    $artifact=Get-HoverChildPath $hoverRuntime (Get-HoverArtifactRelative $relative)
    foreach($file in @($source,$content,$artifact)){Add-HoverProtected $file 'existing image reference; read only'}
    $sourceHash=Get-HoverHash $source
    $contentHash=Get-HoverHash $content
    $artifactHash=Get-HoverHash $artifact
    if($hoverRequiredImages -contains $relative){
        foreach($file in @($source,$content,$artifact)){if(-not(Test-Path -LiteralPath $file -PathType Leaf) -or (Get-Item -LiteralPath $file).Length -le 0){throw "Existing shared Tooltip image is missing or empty: $file"}}
        if($sourceHash -ne $contentHash){throw "Existing shared Tooltip image source/Content mismatch: $relative"}
    }
    $hoverImages+=[pscustomobject]@{relative=$relative;sourceHash=$sourceHash;contentHash=$contentHash;compiledHash=$artifactHash;requiredArchiveSkin=($hoverRequiredImages -contains $relative)}
}
$hoverProtected=@($hoverProtectedByPath.Values|Sort-Object path)
function Get-HoverProtectedChanges {
    return @($hoverProtected|Where-Object {(Get-HoverHash $_.path) -ne $_.hash}|ForEach-Object {$_.path})
}
$hoverBackup=Get-HoverWorkspacePath ('output/tooltip_hover_unification/compile_'+(Get-Date -Format yyyyMMdd_HHmmss_fff)+'_'+[guid]::NewGuid().ToString('N').Substring(0,8))
$hoverRecords=@()
foreach($relative in $hoverRequired){
    $source=Get-HoverSourcePath $relative
    $content=Get-HoverChildPath $hoverContent $relative
    $artifactRelative=Get-HoverArtifactRelative $relative
    $artifact=Get-HoverChildPath $hoverRuntime $artifactRelative
    Assert-HoverNoLinks $content $hoverContent
    Assert-HoverNoLinks $artifact $hoverRuntime
    $hoverRecords+=[pscustomobject]@{relative=$relative;source=$source;content=$content;artifact=$artifact;sourceHash=(Get-HoverHash $source);contentExisted=(Test-Path -LiteralPath $content -PathType Leaf);runtimeExisted=(Test-Path -LiteralPath $artifact -PathType Leaf);contentBeforeHash=(Get-HoverHash $content);runtimeBeforeHash=(Get-HoverHash $artifact);sourceBackup=(Join-Path $hoverBackup ('source/'+$relative));contentBackup=(Join-Path $hoverBackup ('content/'+$relative));runtimeBackup=(Join-Path $hoverBackup ('runtime/'+$artifactRelative));compileStartedUtc=$null;compiledHash=$null;artifactBytes=$null;artifactWriteUtc=$null;verified=$false}
}
# Keep this return before any writes, backup directories, copies, or compiler invocation.
if($CheckOnly){[pscustomobject]@{success=$true;checkOnly=$true;files=$hoverRequired.Count;imagesToCompile=0;cssToCompile=0;scope=$Scope;sourceRoot=$hoverSource;report=$Report;existingImageReferences=$hoverImages.Count;requiredImageDependencies=$hoverRequiredImages;protectedFiles=$hoverProtected.Count;activeAndSelectedIncludeOrderVerified=$true;nativeFlags=@('-fshallow','-nop4');sourceRecords=@($hoverRecords|Select-Object relative,sourceHash)}|ConvertTo-Json -Depth 6;return}

New-Item -ItemType Directory -Path $hoverBackup -Force|Out-Null
foreach($record in $hoverRecords){
    foreach($target in @($record.sourceBackup,$record.contentBackup,$record.runtimeBackup)){New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force|Out-Null}
    Copy-Item -LiteralPath $record.source -Destination $record.sourceBackup
    if($record.contentExisted){Copy-Item -LiteralPath $record.content -Destination $record.contentBackup}
    if($record.runtimeExisted){Copy-Item -LiteralPath $record.artifact -Destination $record.runtimeBackup}
}
@{records=$hoverRecords;protected=$hoverProtected;images=$hoverImages}|ConvertTo-Json -Depth 8|Set-Content -LiteralPath (Join-Path $hoverBackup 'manifest_before.json') -Encoding UTF8
try {
    foreach($record in $hoverRecords){
        if((Get-HoverHash $record.source) -ne $record.sourceHash){throw "Source changed before compile: $($record.relative)"}
        New-Item -ItemType Directory -Path (Split-Path -Parent $record.content) -Force|Out-Null
        Copy-Item -LiteralPath $record.source -Destination $record.content -Force
        if((Get-HoverHash $record.content) -ne $record.sourceHash){throw "Content copy differs: $($record.relative)"}
    }
    # The helper and all owners compile before the three layouts. No recursive -f is permitted.
    foreach($record in $hoverRecords){
        $record.compileStartedUtc=(Get-Date).ToUniversalTime().ToString('o')
        $log=@(& $hoverCompiler -i $record.content -game (Join-Path $hoverEngine 'game/dota') -fshallow -nop4 2>&1)
        $exitCode=$LASTEXITCODE
        $log|Set-Content -LiteralPath (Join-Path $hoverBackup (($record.relative -replace '/','_')+'.log')) -Encoding UTF8
        if($exitCode -ne 0 -or -not($log -match '0 failed')){throw "Native compile failed: $($record.relative)"}
        Write-Output ('TOOLTIP_HOVER_COMPILE_PASS '+$record.relative)
    }
    foreach($record in $hoverRecords){
        if((Get-HoverHash $record.source) -ne $record.sourceHash -or (Get-HoverHash $record.content) -ne $record.sourceHash){throw "Source/Content changed during compile: $($record.relative)"}
        if(-not(Test-Path -LiteralPath $record.artifact -PathType Leaf)){throw "Missing artifact: $($record.relative)"}
        $file=Get-Item -LiteralPath $record.artifact
        if($file.Length -le 0 -or $file.LastWriteTimeUtc -lt [datetime]::Parse($record.compileStartedUtc).ToUniversalTime()){throw "Stale or empty artifact: $($record.relative)"}
        $record.compiledHash=Get-HoverHash $record.artifact;$record.artifactBytes=$file.Length;$record.artifactWriteUtc=$file.LastWriteTimeUtc.ToString('o');$record.verified=$true
    }
    $protectedChanges=@(Get-HoverProtectedChanges)
    if($protectedChanges.Count){throw ('Protected files changed during compile: '+($protectedChanges -join ', '))}
    foreach($relative in $hoverRequired|Where-Object {$_ -like '*.xml'}){
        $null=Assert-HoverLayout (Get-HoverSourcePath $relative)
        $null=Assert-HoverLayout (Join-Path $hoverContent $relative)
        $null=Assert-HoverLayout (Get-HoverWorkspacePath ('panorama/src/'+$relative))
    }
    New-Item -ItemType Directory -Path (Split-Path -Parent $hoverReport) -Force|Out-Null
    @{at=(Get-Date -Format o);success=$true;scope=$Scope;sourceRoot=$hoverSource;backup=$hoverBackup;records=$hoverRecords;imagesCompiled=0;cssCompiled=0;existingImageReferences=$hoverImages;protected=$hoverProtected;protectedChanges=@();activeAndSelectedIncludeOrderVerified=$true;nativeFlags=@('-fshallow','-nop4')}|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $hoverReport -Encoding UTF8
} catch {
    $failure=$_
    $rollbackErrors=@()
    foreach($record in $hoverRecords){
        try {
            if($record.contentExisted){Copy-Item -LiteralPath $record.contentBackup -Destination $record.content -Force}elseif(Test-Path -LiteralPath $record.content -PathType Leaf){Remove-Item -LiteralPath $record.content}
            if($record.runtimeExisted){Copy-Item -LiteralPath $record.runtimeBackup -Destination $record.artifact -Force}elseif(Test-Path -LiteralPath $record.artifact -PathType Leaf){Remove-Item -LiteralPath $record.artifact}
            if((Get-HoverHash $record.content) -ne $record.contentBeforeHash -or (Get-HoverHash $record.artifact) -ne $record.runtimeBeforeHash){throw "Rollback hash mismatch: $($record.relative)"}
        } catch {$rollbackErrors+=$_.ToString()}
    }
    # Preserve concurrent edits to unrelated files; only the 15 approved output pairs are rolled back.
    @{at=(Get-Date -Format o);success=$false;rolledBack=($rollbackErrors.Count -eq 0);error=$failure.ToString();rollbackErrors=$rollbackErrors;protectedChanges=@(Get-HoverProtectedChanges);backup=$hoverBackup;records=$hoverRecords;protected=$hoverProtected}|ConvertTo-Json -Depth 8|Set-Content -LiteralPath (Join-Path $hoverBackup 'failure.json') -Encoding UTF8
    throw $failure
}
