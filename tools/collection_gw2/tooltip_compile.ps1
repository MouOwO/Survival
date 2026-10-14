param(
    [string]$Scope='tools/collection_gw2/tooltip_compile_scope.json',
    [string]$Report='design_refs/collection_gw2_v2/work/tooltip_compile.json',
    [string]$SourceRoot='panorama/src',
    [switch]$CheckOnly
)
$ErrorActionPreference='Stop'
$tooltipRepo=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$tooltipEngine=(Resolve-Path (Join-Path $tooltipRepo '../../..')).Path
$tooltipContent=Join-Path $tooltipEngine 'content/dota_addons/Survival/panorama'
$tooltipRuntime=Join-Path $tooltipRepo 'panorama'
$tooltipCompiler=Join-Path $tooltipEngine 'game/bin/win64/resourcecompiler.exe'
$tooltipRequired=@(
    'scripts/custom_game/common/archive_tooltip.js',
    'styles/custom_game/common/archive_tooltip.css',
    'scripts/custom_game/archive_v10.js',
    'scripts/custom_game/collection_gw2.js',
    'styles/custom_game/collection_gw2.css',
    'layout/custom_game/archive.xml'
)
function Get-TooltipChildPath([string]$Root,[string]$Relative) {
    $inputPath=if([IO.Path]::IsPathRooted($Relative)){$Relative}else{Join-Path $Root $Relative}
    $resolved=[IO.Path]::GetFullPath($inputPath).TrimEnd([IO.Path]::DirectorySeparatorChar)
    if(-not $resolved.StartsWith($Root+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw "Path escaped its root: $Relative"}
    return $resolved
}
function Assert-TooltipNoLinks([string]$Path,[string]$Boundary) {
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
function Get-TooltipWorkspacePath([string]$Relative) {
    $resolved=Get-TooltipChildPath $tooltipRepo $Relative
    Assert-TooltipNoLinks $resolved $tooltipRepo
    return $resolved
}
function Get-TooltipArtifactRelative([string]$Relative) {
    return $Relative -replace '\.js$','.vjs_c' -replace '\.css$','.vcss_c' -replace '\.xml$','.vxml_c' -replace '\.png$','_png.vtex_c' -replace '\.svg$','.vsvg_c'
}
function Get-TooltipHash([string]$Path) {
    if(Test-Path -LiteralPath $Path -PathType Leaf){return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash}
    return $null
}
$tooltipFiles=@(Get-Content -LiteralPath (Get-TooltipWorkspacePath $Scope) -Raw -Encoding UTF8|ConvertFrom-Json)
if($tooltipFiles.Count -ne 6 -or @($tooltipFiles|Select-Object -Unique).Count -ne 6 -or @(Compare-Object $tooltipFiles $tooltipRequired).Count){throw 'Tooltip scope must contain exactly the six approved JS/CSS/archive XML sources; image/data/HUD/common menu sources are excluded.'}
$tooltipSource=Get-TooltipWorkspacePath $SourceRoot
$tooltipDefaultSource=Join-Path $tooltipRuntime 'src'
if(($tooltipSource.Equals($tooltipRuntime,[StringComparison]::OrdinalIgnoreCase) -or $tooltipSource.StartsWith($tooltipRuntime+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)) -and
    -not($tooltipSource.Equals($tooltipDefaultSource,[StringComparison]::OrdinalIgnoreCase) -or $tooltipSource.StartsWith($tooltipDefaultSource+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase))){throw 'SourceRoot must not point into Panorama runtime artifacts.'}
if(-not(Test-Path -LiteralPath $tooltipSource -PathType Container)){throw "SourceRoot directory is missing: $SourceRoot"}
function Get-TooltipSourcePath([string]$Relative) {
    $resolved=Get-TooltipChildPath $tooltipSource $Relative
    Assert-TooltipNoLinks $resolved $tooltipRepo
    if(-not(Test-Path -LiteralPath $resolved -PathType Leaf)){throw "Missing source: $Relative"}
    return $resolved
}
$tooltipReport=Get-TooltipWorkspacePath $Report
$tooltipOutputRoot=Join-Path $tooltipRepo 'output'
$tooltipDesignWork=Join-Path $tooltipRepo 'design_refs/collection_gw2_v2/work'
if(-not $tooltipReport.EndsWith('.json',[StringComparison]::OrdinalIgnoreCase) -or
    -not($tooltipReport.StartsWith($tooltipOutputRoot+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase) -or $tooltipReport.StartsWith($tooltipDesignWork+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase))){throw 'Report must be a JSON file below output/ or design_refs/collection_gw2_v2/work/.'}
if(-not(Test-Path -LiteralPath $tooltipCompiler -PathType Leaf)){throw 'Native resourcecompiler is missing.'}
function Assert-TooltipArchiveLayout([string]$Path) {
    [xml]$layout=Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    $scripts=@($layout.SelectNodes('//scripts/include')|ForEach-Object {$_.GetAttribute('src')})
    $styles=@($layout.SelectNodes('//styles/include')|ForEach-Object {$_.GetAttribute('src')})
    $factory='file://{resources}/scripts/custom_game/common/archive_tooltip.js'
    $sheet='file://{resources}/styles/custom_game/common/archive_tooltip.css'
    if(@($scripts|Where-Object {$_ -eq $factory}).Count -ne 1 -or @($styles|Where-Object {$_ -eq $sheet}).Count -ne 1){throw "Archive layout must include the shared Tooltip factory and CSS exactly once: $Path"}
    $factoryAt=[array]::IndexOf($scripts,$factory)
    foreach($dependency in @('archive_v10_data.js','archive_parchment_data.js','archive_v10_semantics.js','archive_handoff_180de7e38b.js','common/ui_components.js')){
        $uri='file://{resources}/scripts/custom_game/'+$dependency
        if(@($scripts|Where-Object {$_ -eq $uri}).Count -ne 1 -or [array]::IndexOf($scripts,$uri) -ge $factoryAt){throw "Tooltip prerequisite must load before the shared factory: $dependency ($Path)"}
    }
    foreach($consumer in @('archive_v10.js','collection_gw2.js')){
        $uri='file://{resources}/scripts/custom_game/'+$consumer
        if(@($scripts|Where-Object {$_ -eq $uri}).Count -ne 1 -or [array]::IndexOf($scripts,$uri) -le $factoryAt){throw "Tooltip consumer must load after the shared factory: $consumer ($Path)"}
    }
    foreach($pageStyle in @('archive_v10.css','collection_gw2.css')){
        $uri='file://{resources}/styles/custom_game/'+$pageStyle
        if(@($styles|Where-Object {$_ -eq $uri}).Count -ne 1 -or [array]::IndexOf($styles,$uri) -ge [array]::IndexOf($styles,$sheet)){throw "Shared Tooltip CSS must follow the page stylesheet: $pageStyle ($Path)"}
    }
    foreach($id in @('CollectionWindow','CollectionScrim')){if(-not $layout.SelectSingleNode("//*[@id='$id']")){throw "Archive layout is missing $id"}}
    return $layout
}
$tooltipActiveArchive=Get-TooltipWorkspacePath 'panorama/src/layout/custom_game/archive.xml'
$tooltipActiveLayout=Assert-TooltipArchiveLayout $tooltipActiveArchive
$tooltipSelectedLayout=Assert-TooltipArchiveLayout (Get-TooltipSourcePath 'layout/custom_game/archive.xml')
# The active HUD and manifest are read-only prerequisites, never compile inputs.
[xml]$tooltipHud=Get-Content -LiteralPath (Get-TooltipWorkspacePath 'panorama/src/layout/custom_game/survival_hud.xml') -Raw -Encoding UTF8
if(-not $tooltipHud.SelectSingleNode("//include[@src='file://{resources}/scripts/custom_game/collection_nav.js']")){throw 'Active HUD does not include collection_nav.js.'}
[xml]$tooltipManifest=Get-Content -LiteralPath (Get-TooltipWorkspacePath 'panorama/src/layout/custom_game/custom_ui_manifest.xml') -Raw -Encoding UTF8
if(-not $tooltipManifest.SelectSingleNode("//CustomUIElement[@layoutfile='file://{resources}/layout/custom_game/archive.xml']")){throw 'Active UI manifest does not load archive.xml.'}

$tooltipProtectedByPath=@{}
function Add-TooltipProtected([string]$Path,[string]$Reason) {
    if($tooltipProtectedByPath.ContainsKey($Path)){return}
    $tooltipProtectedByPath[$Path]=[pscustomobject]@{path=$Path;reason=$Reason;hash=(Get-TooltipHash $Path)}
}
function Add-TooltipProtectedResource([string]$Relative,[string]$Reason) {
    if($tooltipRequired -contains $Relative){return}
    Add-TooltipProtected (Get-TooltipWorkspacePath ('panorama/src/'+$Relative)) $Reason
    Add-TooltipProtected (Get-TooltipChildPath $tooltipContent $Relative) $Reason
    Add-TooltipProtected (Get-TooltipChildPath $tooltipRuntime (Get-TooltipArtifactRelative $Relative)) $Reason
}
# Preserve all unrelated active-layout dependencies, including existing dirty business code.
foreach($node in $tooltipActiveLayout.SelectNodes('//include[@src]')){
    $uri=$node.GetAttribute('src')
    if($uri -match '^file://\{resources\}/((?:scripts|styles|layout)/custom_game/[a-zA-Z0-9_./-]+\.(?:js|css|xml))$'){Add-TooltipProtectedResource $Matches[1] 'unrelated active archive include'}
}
foreach($relative in @('scripts/custom_game/common/menu_v10.js','styles/custom_game/common/menu_v10.css','scripts/custom_game/topnav_remaining_5d5c1152eb.js','layout/custom_game/survival_hud.xml','layout/custom_game/custom_ui_manifest.xml','scripts/custom_game/collection_nav.js','scripts/custom_game/archive_v10_data.js','scripts/custom_game/archive_parchment_data.js','scripts/custom_game/collection_gw2_data.js','layout/custom_game/collection_gw2_assets.xml','styles/custom_game/archive_v10.css')){Add-TooltipProtectedResource $relative 'explicit protected common/HUD/topnav/data/resource'}
if(-not $tooltipSource.Equals($tooltipDefaultSource,[StringComparison]::OrdinalIgnoreCase)){
    foreach($relative in $tooltipRequired){Add-TooltipProtected (Get-TooltipWorkspacePath ('panorama/src/'+$relative)) 'working source preserved while compiling snapshot'}
}

# These are the exact existing archive skin bitmaps; they are checked, never rebuilt.
$tooltipRequiredImages=@(
    'images/custom_game/archive_parchment_v1/tooltip_background.png',
    'images/custom_game/archive_parchment_v1/tooltip_frame.png',
    'images/custom_game/archive_v10/tooltip/tooltip_separator.png',
    'images/custom_game/archive_parchment_v1/scroll_track.png',
    'images/custom_game/archive_parchment_v1/scroll_thumb.png'
)
$tooltipImagePaths=@($tooltipRequiredImages)
foreach($relative in $tooltipRequired){
    $text=Get-Content -LiteralPath (Get-TooltipSourcePath $relative) -Raw -Encoding UTF8
    foreach($match in [regex]::Matches($text,'file://\{images\}/(custom_game/[a-zA-Z0-9_./-]+\.(?:png|svg))')){$tooltipImagePaths+='images/'+$match.Groups[1].Value}
}
$tooltipImages=@()
foreach($relative in @($tooltipImagePaths|Sort-Object -Unique)){
    $source=Get-TooltipWorkspacePath ('panorama/src/'+$relative)
    $content=Get-TooltipChildPath $tooltipContent $relative
    $artifact=Get-TooltipChildPath $tooltipRuntime (Get-TooltipArtifactRelative $relative)
    foreach($file in @($source,$content,$artifact)){if(-not(Test-Path -LiteralPath $file -PathType Leaf) -or (Get-Item -LiteralPath $file).Length -le 0){throw "Existing Tooltip image dependency is missing or empty: $file"};Add-TooltipProtected $file 'existing image dependency; read only'}
    $sourceHash=Get-TooltipHash $source
    if($sourceHash -ne (Get-TooltipHash $content)){throw "Existing image source/Content mismatch: $relative"}
    $tooltipImages+=[pscustomobject]@{relative=$relative;sourceHash=$sourceHash;compiledHash=(Get-TooltipHash $artifact);requiredArchiveSkin=($tooltipRequiredImages -contains $relative)}
}
# Inventory the related PNG sets as sentinels, including art originals; no copy or compile.
foreach($imageDirectory in @('custom_game/collection_gw2_v2','custom_game/archive_parchment_v1','custom_game/archive_v10/tooltip')){
    $mirror=Get-TooltipWorkspacePath ('panorama/src/images/'+$imageDirectory)
    if(Test-Path -LiteralPath $mirror -PathType Container){
        foreach($file in Get-ChildItem -LiteralPath $mirror -Filter '*.png' -File){
            Add-TooltipProtectedResource ('images/'+$imageDirectory+'/'+$file.Name) 'protected PNG set'
            $art=Get-TooltipWorkspacePath ('art/ui/sources/'+$imageDirectory+'/'+$file.Name)
            Add-TooltipProtected $art 'canonical PNG art'
        }
    }
}
$tooltipProtected=@($tooltipProtectedByPath.Values|Sort-Object path)
function Get-TooltipProtectedChanges {
    return @($tooltipProtected|Where-Object {(Get-TooltipHash $_.path) -ne $_.hash}|ForEach-Object {$_.path})
}
$tooltipBackup=Get-TooltipWorkspacePath ('output/collection_gw2/tooltip_compile_'+(Get-Date -Format yyyyMMdd_HHmmss_fff)+'_'+[guid]::NewGuid().ToString('N').Substring(0,8))
$tooltipRecords=@()
foreach($relative in $tooltipRequired){
    $source=Get-TooltipSourcePath $relative
    $content=Get-TooltipChildPath $tooltipContent $relative
    $artifactRelative=Get-TooltipArtifactRelative $relative
    $artifact=Get-TooltipChildPath $tooltipRuntime $artifactRelative
    Assert-TooltipNoLinks $content $tooltipContent
    Assert-TooltipNoLinks $artifact $tooltipRuntime
    $tooltipRecords+=[pscustomobject]@{relative=$relative;source=$source;content=$content;artifact=$artifact;sourceHash=(Get-TooltipHash $source);contentExisted=(Test-Path -LiteralPath $content -PathType Leaf);runtimeExisted=(Test-Path -LiteralPath $artifact -PathType Leaf);contentBeforeHash=(Get-TooltipHash $content);runtimeBeforeHash=(Get-TooltipHash $artifact);sourceBackup=(Join-Path $tooltipBackup ('source/'+$relative));contentBackup=(Join-Path $tooltipBackup ('content/'+$relative));runtimeBackup=(Join-Path $tooltipBackup ('runtime/'+$artifactRelative));compileStartedUtc=$null;compiledHash=$null;artifactBytes=$null;artifactWriteUtc=$null;verified=$false}
}
if($CheckOnly){[pscustomobject]@{success=$true;checkOnly=$true;files=6;imagesToCompile=0;scope=$Scope;sourceRoot=$tooltipSource;report=$Report;requiredImageDependencies=$tooltipRequiredImages;existingImageDependencies=$tooltipImages.Count;protectedFiles=$tooltipProtected.Count;activeAndSelectedIncludeOrderVerified=$true;nativeFlag='-fshallow'}|ConvertTo-Json -Depth 5;return}

New-Item -ItemType Directory -Path $tooltipBackup -Force|Out-Null
foreach($record in $tooltipRecords){
    foreach($target in @($record.sourceBackup,$record.contentBackup,$record.runtimeBackup)){New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force|Out-Null}
    Copy-Item -LiteralPath $record.source -Destination $record.sourceBackup
    if($record.contentExisted){Copy-Item -LiteralPath $record.content -Destination $record.contentBackup}
    if($record.runtimeExisted){Copy-Item -LiteralPath $record.artifact -Destination $record.runtimeBackup}
}
@{records=$tooltipRecords;protected=$tooltipProtected;images=$tooltipImages}|ConvertTo-Json -Depth 8|Set-Content -LiteralPath (Join-Path $tooltipBackup 'manifest_before.json') -Encoding UTF8
try {
    foreach($record in $tooltipRecords){
        if((Get-TooltipHash $record.source) -ne $record.sourceHash){throw "Source changed before compile: $($record.relative)"}
        New-Item -ItemType Directory -Path (Split-Path -Parent $record.content) -Force|Out-Null
        Copy-Item -LiteralPath $record.source -Destination $record.content -Force
        if((Get-TooltipHash $record.content) -ne $record.sourceHash){throw "Content copy differs: $($record.relative)"}
    }
    # Both shared components and callers compile first; archive XML is last. No recursive -f.
    foreach($record in $tooltipRecords){
        $record.compileStartedUtc=(Get-Date).ToUniversalTime().ToString('o')
        $log=@(& $tooltipCompiler -i $record.content -game (Join-Path $tooltipEngine 'game/dota') -fshallow -nop4 2>&1)
        $exitCode=$LASTEXITCODE
        $log|Set-Content -LiteralPath (Join-Path $tooltipBackup (($record.relative -replace '/','_')+'.log')) -Encoding UTF8
        if($exitCode -ne 0 -or -not($log -match '0 failed')){throw "Native compile failed: $($record.relative)"}
        Write-Output ('COLLECTION_TOOLTIP_COMPILE_PASS '+$record.relative)
    }
    foreach($record in $tooltipRecords){
        if((Get-TooltipHash $record.source) -ne $record.sourceHash -or (Get-TooltipHash $record.content) -ne $record.sourceHash){throw "Source/Content changed during compile: $($record.relative)"}
        if(-not(Test-Path -LiteralPath $record.artifact -PathType Leaf)){throw "Missing artifact: $($record.relative)"}
        $file=Get-Item -LiteralPath $record.artifact
        if($file.Length -le 0 -or $file.LastWriteTimeUtc -lt [datetime]::Parse($record.compileStartedUtc).ToUniversalTime()){throw "Stale or empty artifact: $($record.relative)"}
        $record.compiledHash=Get-TooltipHash $record.artifact;$record.artifactBytes=$file.Length;$record.artifactWriteUtc=$file.LastWriteTimeUtc.ToString('o');$record.verified=$true
    }
    $protectedChanges=@(Get-TooltipProtectedChanges)
    if($protectedChanges.Count){throw ('Protected files changed during compile: '+($protectedChanges -join ', '))}
    $null=Assert-TooltipArchiveLayout (Get-TooltipSourcePath 'layout/custom_game/archive.xml')
    $null=Assert-TooltipArchiveLayout (Join-Path $tooltipContent 'layout/custom_game/archive.xml')
    $null=Assert-TooltipArchiveLayout $tooltipActiveArchive
    New-Item -ItemType Directory -Path (Split-Path -Parent $tooltipReport) -Force|Out-Null
    @{at=(Get-Date -Format o);success=$true;scope=$Scope;sourceRoot=$tooltipSource;backup=$tooltipBackup;records=$tooltipRecords;imagesCompiled=0;existingImageDependencies=$tooltipImages;protected=$tooltipProtected;protectedChanges=@();activeAndSelectedIncludeOrderVerified=$true;nativeFlag='-fshallow'}|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $tooltipReport -Encoding UTF8
} catch {
    $failure=$_
    $rollbackErrors=@()
    foreach($record in $tooltipRecords){
        try {
            if($record.contentExisted){Copy-Item -LiteralPath $record.contentBackup -Destination $record.content -Force}elseif(Test-Path -LiteralPath $record.content -PathType Leaf){Remove-Item -LiteralPath $record.content}
            if($record.runtimeExisted){Copy-Item -LiteralPath $record.runtimeBackup -Destination $record.artifact -Force}elseif(Test-Path -LiteralPath $record.artifact -PathType Leaf){Remove-Item -LiteralPath $record.artifact}
            if((Get-TooltipHash $record.content) -ne $record.contentBeforeHash -or (Get-TooltipHash $record.artifact) -ne $record.runtimeBeforeHash){throw "Rollback hash mismatch: $($record.relative)"}
        } catch {$rollbackErrors+=$_.ToString()}
    }
    # Never overwrite unrelated files to repair a sentinel mismatch: it may be a concurrent user edit.
    @{at=(Get-Date -Format o);success=$false;rolledBack=($rollbackErrors.Count -eq 0);error=$failure.ToString();rollbackErrors=$rollbackErrors;protectedChanges=@(Get-TooltipProtectedChanges);backup=$tooltipBackup;records=$tooltipRecords;protected=$tooltipProtected}|ConvertTo-Json -Depth 8|Set-Content -LiteralPath (Join-Path $tooltipBackup 'failure.json') -Encoding UTF8
    throw $failure
}
