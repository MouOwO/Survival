param(
    [string]$Scope='tools/collection_gw2/onepage_compile_scope.json',
    [string]$Report='design_refs/collection_gw2_v2/work/onepage_compile.json',
    [string]$SourceRoot='panorama/src',
    [switch]$CheckOnly
)
$ErrorActionPreference='Stop'
$onepageRepo=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$onepageEngine=(Resolve-Path (Join-Path $onepageRepo '../../..')).Path
$onepageContent=Join-Path $onepageEngine 'content/dota_addons/Survival/panorama'
$onepageRuntime=Join-Path $onepageRepo 'panorama'
$onepageCompiler=Join-Path $onepageEngine 'game/bin/win64/resourcecompiler.exe'
$onepageRequired=@(
    'scripts/custom_game/collection_gw2_data.js',
    'scripts/custom_game/collection_gw2.js'
)
function Get-OnepageChildPath([string]$Root,[string]$Relative) {
    $inputPath=if([IO.Path]::IsPathRooted($Relative)){$Relative}else{Join-Path $Root $Relative}
    $resolved=[IO.Path]::GetFullPath($inputPath).TrimEnd([IO.Path]::DirectorySeparatorChar)
    if(-not $resolved.StartsWith($Root+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw "Path escaped its root: $Relative"}
    return $resolved
}
function Assert-OnepageNoLinks([string]$Path,[string]$Boundary) {
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
function Get-OnepageWorkspacePath([string]$Relative) {
    $resolved=Get-OnepageChildPath $onepageRepo $Relative
    Assert-OnepageNoLinks $resolved $onepageRepo
    return $resolved
}
function Get-OnepageArtifactRelative([string]$Relative) {
    return $Relative -replace '\.js$','.vjs_c' -replace '\.css$','.vcss_c' -replace '\.xml$','.vxml_c' -replace '\.png$','_png.vtex_c' -replace '\.svg$','.vsvg_c'
}
function Get-OnepageHash([string]$Path) {
    if(Test-Path -LiteralPath $Path -PathType Leaf){return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash}
    return $null
}
$onepageScopePath=Get-OnepageWorkspacePath $Scope
$onepageFiles=@(Get-Content -LiteralPath $onepageScopePath -Raw -Encoding UTF8|ConvertFrom-Json)
if(($onepageFiles -join "`n") -cne ($onepageRequired -join "`n")){throw 'Collection one-page scope must contain exactly data and collection JS, in order; CSS, XML, images and business resources are excluded.'}
$onepageSource=Get-OnepageWorkspacePath $SourceRoot
$onepageDefaultSource=Join-Path $onepageRuntime 'src'
if(($onepageSource.Equals($onepageRuntime,[StringComparison]::OrdinalIgnoreCase) -or $onepageSource.StartsWith($onepageRuntime+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)) -and
    -not($onepageSource.Equals($onepageDefaultSource,[StringComparison]::OrdinalIgnoreCase) -or $onepageSource.StartsWith($onepageDefaultSource+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase))){throw 'SourceRoot must not point into Panorama runtime artifacts.'}
if(-not(Test-Path -LiteralPath $onepageSource -PathType Container)){throw "SourceRoot directory is missing: $SourceRoot"}
function Get-OnepageSourcePath([string]$Relative) {
    $resolved=Get-OnepageChildPath $onepageSource $Relative
    Assert-OnepageNoLinks $resolved $onepageRepo
    if(-not(Test-Path -LiteralPath $resolved -PathType Leaf)){throw "Missing source: $Relative"}
    return $resolved
}
$onepageReport=Get-OnepageWorkspacePath $Report
$onepageOutputRoot=Join-Path $onepageRepo 'output'
$onepageDesignWork=Join-Path $onepageRepo 'design_refs/collection_gw2_v2/work'
if(-not $onepageReport.EndsWith('.json',[StringComparison]::OrdinalIgnoreCase) -or
    -not($onepageReport.StartsWith($onepageOutputRoot+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase) -or $onepageReport.StartsWith($onepageDesignWork+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase))){throw 'Report must be a JSON file below output/ or design_refs/collection_gw2_v2/work/.'}
if(-not(Test-Path -LiteralPath $onepageCompiler -PathType Leaf)){throw 'Native resourcecompiler is missing.'}
function Assert-OnepageLayout([string]$Path) {
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
    foreach($owner in $onepageRequired|Where-Object {$_ -like '*.js' -and $_ -ne 'scripts/custom_game/common/tooltip_dismiss.js'}){
        $uri='file://{resources}/'+$owner
        $count=@($scripts|Where-Object {$_ -eq $uri}).Count
        if($count -gt 1 -or ($count -eq 1 -and [array]::IndexOf($scripts,$uri) -le $helperAt)){throw "Tooltip owner must occur once after the helper: $owner ($Path)"}
    }
    return $layout
}
$onepageActiveLayouts=@{}
foreach($relative in @('layout/custom_game/archive.xml','layout/custom_game/survival_hud.xml','layout/custom_game/payment_test.xml')){
    $onepageActiveLayouts[$relative]=Assert-OnepageLayout (Get-OnepageWorkspacePath ('panorama/src/'+$relative))
}
$onepageSelectedLayouts=@{} # A two-source snapshot does not copy or compile active layouts.
[xml]$onepageManifest=Get-Content -LiteralPath (Get-OnepageWorkspacePath 'panorama/src/layout/custom_game/custom_ui_manifest.xml') -Raw -Encoding UTF8
foreach($relative in $onepageActiveLayouts.Keys){
    if(-not $onepageManifest.SelectSingleNode("//CustomUIElement[@layoutfile='file://{resources}/$relative']")){throw "Active UI manifest does not load $relative"}
}
$onepageArchive=$onepageActiveLayouts['layout/custom_game/archive.xml']
$onepageScripts=@($onepageArchive.SelectNodes('//scripts/include')|ForEach-Object {$_.GetAttribute('src')})
$onepageConsumer='file://{resources}/scripts/custom_game/collection_gw2.js'
foreach($uri in @('file://{resources}/scripts/custom_game/collection_gw2_data.js','file://{resources}/scripts/custom_game/common/archive_tooltip.js','file://{resources}/scripts/custom_game/common/tooltip_dismiss.js')){
    if(@($onepageScripts|Where-Object {$_ -eq $uri}).Count -ne 1 -or [array]::IndexOf($onepageScripts,$uri) -ge [array]::IndexOf($onepageScripts,$onepageConsumer)){throw "Collection dependency must load once before its controller: $uri"}
}
if(@($onepageScripts|Where-Object {$_ -eq $onepageConsumer}).Count -ne 1 -or -not $onepageArchive.SelectSingleNode("//include[@src='file://{resources}/styles/custom_game/collection_gw2.css']")){throw 'Active collection controller/CSS includes are missing or duplicated.'}
if(-not $onepageActiveLayouts['layout/custom_game/survival_hud.xml'].SelectSingleNode("//include[@src='file://{resources}/scripts/custom_game/collection_nav.js']")){throw 'Active HUD collection navigation is missing.'}
function Read-OnepageData([string]$Path){
    $sourceText=Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    $match=[regex]::Match($sourceText,'CollectionGW2Data=(\{[^\r\n]+\});')
    if(-not $match.Success){throw "Collection data payload is missing: $Path"}
    return ($match.Groups[1].Value|ConvertFrom-Json)
}
$onepageData=Read-OnepageData (Get-OnepageSourcePath 'scripts/custom_game/collection_gw2_data.js')
$onepageActualData=Read-OnepageData (Get-OnepageWorkspacePath 'panorama/src/scripts/custom_game/collection_gw2_data.js')
$onepageArtManifestPath=Get-OnepageWorkspacePath 'tools/collection_gw2/asset_manifest.json'
$onepageArtManifest=Get-Content -LiteralPath $onepageArtManifestPath -Raw -Encoding UTF8|ConvertFrom-Json
$onepageSplitterPath=Get-OnepageWorkspacePath 'tools/collection_gw2/split_reference_assets.py'
$onepageSplitter=Get-Content -LiteralPath $onepageSplitterPath -Raw -Encoding UTF8
foreach($canvas in @($onepageData,$onepageActualData,$onepageArtManifest)){
    if(($canvas.canvas -join ',') -ne '900,478'){throw 'Selected/actual runtime data and art manifest canvas must all be 900x478.'}
}
if(-not [regex]::IsMatch($onepageSplitter,'(?m)^CANVAS\s*=\s*\[900,\s*478\]\s*$')){throw 'Asset generator CANVAS must be 900x478; do not rerun image generation to update it.'}

$onepageProtectedByPath=@{}
function Add-OnepageProtected([string]$Path,[string]$Reason) {
    if($onepageProtectedByPath.ContainsKey($Path)){return}
    $onepageProtectedByPath[$Path]=[pscustomobject]@{path=$Path;reason=$Reason;hash=(Get-OnepageHash $Path)}
}
function Add-OnepageProtectedResource([string]$Relative,[string]$Reason) {
    if($onepageRequired -contains $Relative){return}
    Add-OnepageProtected (Get-OnepageWorkspacePath ('panorama/src/'+$Relative)) $Reason
    Add-OnepageProtected (Get-OnepageChildPath $onepageContent $Relative) $Reason
    Add-OnepageProtected (Get-OnepageChildPath $onepageRuntime (Get-OnepageArtifactRelative $Relative)) $Reason
}
# Every unrelated include in either selected or actual layouts is immutable during compilation.
$onepageDependencyPaths=@{}
foreach($layout in @($onepageActiveLayouts.Values)+@($onepageSelectedLayouts.Values)){
    foreach($node in $layout.SelectNodes('//include[@src]')){
        $uri=$node.GetAttribute('src')
        if($uri -match '^file://\{resources\}/((?:scripts|styles|layout)/custom_game/[a-zA-Z0-9_./-]+\.(?:js|css|xml))$'){
            $relative=$Matches[1]
            Add-OnepageProtectedResource $relative 'unrelated active/selected layout dependency'
            $onepageDependencyPaths[$relative]=$true
        }
    }
}
foreach($relative in @('styles/custom_game/common/menu_v10.css','scripts/custom_game/topnav_remaining_5d5c1152eb.js','layout/custom_game/custom_ui_manifest.xml','scripts/custom_game/collection_nav.js','scripts/custom_game/archive_v10_data.js','scripts/custom_game/archive_parchment_data.js','scripts/custom_game/collection_gw2_data.js','layout/custom_game/collection_gw2_assets.xml','styles/custom_game/archive_v10.css','styles/custom_game/collection_gw2.css','styles/custom_game/common/archive_tooltip.css','scripts/custom_game/lottery_ui_remaining_5d5c1152eb.js','scripts/custom_game/remaining_5d5c1152eb.js')){Add-OnepageProtectedResource $relative 'explicit protected CSS/topnav/data/resource/business'}
Add-OnepageProtected $PSCommandPath 'compiler script frozen'
Add-OnepageProtected $onepageScopePath 'compiler scope frozen'
if(-not $onepageSource.Equals($onepageDefaultSource,[StringComparison]::OrdinalIgnoreCase)){
    foreach($relative in $onepageRequired){Add-OnepageProtected (Get-OnepageWorkspacePath ('panorama/src/'+$relative)) 'working source preserved while compiling snapshot'}
}

# Preserve existing local art referenced by the layouts and their scripts/styles. Never compile images.
$onepageImagePaths=@{}
$onepageRequiredImages=@(
    'images/custom_game/archive_parchment_v1/tooltip_background.png',
    'images/custom_game/archive_parchment_v1/tooltip_frame.png',
    'images/custom_game/archive_v10/tooltip/tooltip_separator.png',
    'images/custom_game/archive_parchment_v1/scroll_track.png',
    'images/custom_game/archive_parchment_v1/scroll_thumb.png'
)
foreach($relative in $onepageRequiredImages){$onepageImagePaths[$relative]=$true}
foreach($relative in @($onepageRequired)+@($onepageDependencyPaths.Keys)){
    $dependencyPath=if($onepageRequired -contains $relative){Get-OnepageSourcePath $relative}else{Get-OnepageWorkspacePath ('panorama/src/'+$relative)}
    if(-not(Test-Path -LiteralPath $dependencyPath -PathType Leaf)){continue}
    $text=Get-Content -LiteralPath $dependencyPath -Raw -Encoding UTF8
    foreach($match in [regex]::Matches($text,'file://\{images\}/(custom_game/[a-zA-Z0-9_./-]+\.(?:png|svg))')){$onepageImagePaths['images/'+$match.Groups[1].Value]=$true}
}
$onepageImages=@()
foreach($relative in @($onepageImagePaths.Keys|Sort-Object)){
    $source=Get-OnepageWorkspacePath ('panorama/src/'+$relative)
    $content=Get-OnepageChildPath $onepageContent $relative
    $artifact=Get-OnepageChildPath $onepageRuntime (Get-OnepageArtifactRelative $relative)
    foreach($file in @($source,$content,$artifact)){Add-OnepageProtected $file 'existing image reference; read only'}
    $sourceHash=Get-OnepageHash $source
    $contentHash=Get-OnepageHash $content
    $artifactHash=Get-OnepageHash $artifact
    if($onepageRequiredImages -contains $relative){
        foreach($file in @($source,$content,$artifact)){if(-not(Test-Path -LiteralPath $file -PathType Leaf) -or (Get-Item -LiteralPath $file).Length -le 0){throw "Existing shared Tooltip image is missing or empty: $file"}}
        if($sourceHash -ne $contentHash){throw "Existing shared Tooltip image source/Content mismatch: $relative"}
    }
    $onepageImages+=[pscustomobject]@{relative=$relative;sourceHash=$sourceHash;contentHash=$contentHash;compiledHash=$artifactHash;requiredArchiveSkin=($onepageRequiredImages -contains $relative)}
}
# The presentation material stays byte-identical in art, source, Content and runtime.
Add-OnepageProtected $onepageArtManifestPath 'frozen canvas/art metadata'
Add-OnepageProtected $onepageSplitterPath 'frozen generator metadata; never executed'
foreach($relative in $onepageActiveLayouts.Keys){Add-OnepageProtectedResource $relative 'active layouts are read-only'}
Add-OnepageProtectedResource 'layout/custom_game/collection_gw2_assets.xml' 'unchanged image preload XML'
$onepageAssetProperties=@($onepageArtManifest.assets.PSObject.Properties)
if($onepageAssetProperties.Count -ne 22 -or @($onepageData.assets.PSObject.Properties).Count -ne 22){throw 'Expected exactly 22 unchanged collection assets.'}
[xml]$onepagePreload=Get-Content -LiteralPath (Get-OnepageWorkspacePath 'panorama/src/layout/custom_game/collection_gw2_assets.xml') -Raw -Encoding UTF8
$onepagePreloadUris=@($onepagePreload.SelectNodes('//Image[@src]')|ForEach-Object {$_.GetAttribute('src')})
if($onepagePreload.SelectNodes('//include').Count -or $onepagePreloadUris.Count -ne 22 -or @($onepagePreloadUris|Select-Object -Unique).Count -ne 22){throw 'The existing image-only preload must contain 22 distinct assets.'}
$onepageMaterialRecords=@()
foreach($property in $onepageAssetProperties){
    $asset=$property.Value
    if($asset.file -notmatch '^art/ui/sources/(custom_game/collection_gw2_v2/[a-z0-9_]+\.png)$'){throw "Unexpected material path: $($asset.file)"}
    $imageRelative=$Matches[1];$uri='file://{images}/'+$imageRelative
    $dataAsset=$onepageData.assets.PSObject.Properties[$property.Name].Value
    if(-not $dataAsset -or $dataAsset.file -ne $uri -or ($dataAsset.size -join ',') -ne ($asset.size -join ',') -or $onepagePreloadUris -notcontains $uri){throw "Runtime/preload art metadata differs: $($property.Name)"}
    $art=Get-OnepageWorkspacePath $asset.file
    $imageSource=Get-OnepageWorkspacePath ('panorama/src/images/'+$imageRelative)
    $imageContent=Get-OnepageChildPath $onepageContent ('images/'+$imageRelative)
    $imageRuntime=Get-OnepageChildPath $onepageRuntime (Get-OnepageArtifactRelative ('images/'+$imageRelative))
    foreach($file in @($art,$imageSource,$imageContent)){
        if((Get-OnepageHash $file) -ne $asset.sha256){throw "Existing material SHA differs from manifest: $file"}
        Add-OnepageProtected $file '22 approved materials; read only'
    }
    if(-not(Test-Path -LiteralPath $imageRuntime -PathType Leaf) -or (Get-Item -LiteralPath $imageRuntime).Length -le 0){throw "Compiled collection material missing: $imageRuntime"}
    Add-OnepageProtected $imageRuntime 'compiled material; never rebuilt'
    $onepageMaterialRecords+=[pscustomobject]@{key=$property.Name;sourceHash=$asset.sha256;artifact=$imageRuntime;compiledHash=(Get-OnepageHash $imageRuntime)}
}
# Validate the formal eighty portrait mappings and the existing GPU resources without compiling them.
$onepageSocialPath=Get-OnepageWorkspacePath 'data/csv/存档系统/archive_social_items.csv'
$onepageIconPath=Get-OnepageWorkspacePath 'data/csv/存档系统/archive_item_icons.csv'
$onepageSocial=@(Import-Csv -LiteralPath $onepageSocialPath -Encoding UTF8|Where-Object {$_.enabled -eq '1' -and $_.pool_id -in @('ex','friend')})
$onepageIcons=@(Import-Csv -LiteralPath $onepageIconPath -Encoding UTF8|Where-Object {$_.enabled -eq '1'})
Add-OnepageProtected $onepageSocialPath 'formal portrait pool definitions; read only'
Add-OnepageProtected $onepageIconPath 'formal portrait icon mappings; read only'
Add-OnepageProtected (Get-OnepageWorkspacePath 'data/csv/存档系统/archive_social_rules.csv') 'social currency/draw rules; read only'
$onepageCatalogPath=Get-OnepageWorkspacePath 'panorama/src/scripts/custom_game/icons_remaining_5d5c1152eb.js'
$onepageCatalogText=Get-Content -LiteralPath $onepageCatalogPath -Raw -Encoding UTF8
$onepageCatalogMatch=[regex]::Match($onepageCatalogText,'entries=(\[[^\r\n]+\]);')
if(-not $onepageCatalogMatch.Success){throw 'Formal runtime icon catalog payload is missing.'}
$onepageCatalog=@($onepageCatalogMatch.Groups[1].Value|ConvertFrom-Json)
foreach($pool in @('ex','friend')){if(@($onepageSocial|Where-Object {$_.pool_id -eq $pool}).Count -ne 40){throw "Formal $pool pool must contain 40 real entries."}}
if(@($onepageSocial.item_id|Select-Object -Unique).Count -ne 80){throw 'Formal portrait IDs are not eighty unique entries.'}
$onepagePortraitRecords=@()
foreach($item in $onepageSocial){
    $mapped=@($onepageIcons|Where-Object {$_.item_id -eq $item.item_id -and $_.category_id -eq $item.pool_id})
    $catalog=@($onepageCatalog|Where-Object {$_.item_id -eq $item.item_id -and $_.category_id -eq $item.pool_id -and $_.enabled -eq '1'})
    if($mapped.Count -ne 1 -or $catalog.Count -ne 1 -or $mapped[0].icon_path -ne ('custom_game/archive_portraits_v3/'+$item.item_id+'.png') -or $catalog[0].icon_path -ne $mapped[0].icon_path){throw "Formal portrait mapping is missing or ambiguous: $($item.item_id)"}
    $imageRelative='images/'+$mapped[0].icon_path
    $portraitSource=Get-OnepageWorkspacePath ('panorama/src/'+$imageRelative)
    $portraitContent=Get-OnepageChildPath $onepageContent $imageRelative
    foreach($file in @($portraitSource,$portraitContent)){
        if((Get-OnepageHash $file) -ne $catalog[0].sha256){throw "Formal original portrait SHA differs from catalog: $file"}
        Add-OnepageProtected $file 'formal v3 portrait original; read only'
    }
    $runtimeUri=$catalog[0].runtime_uri
    if($runtimeUri -ne ('s2r://panorama/images/custom_game/archive_gpu_regular/head_v5_'+$item.item_id+'.vtex')){throw "Unexpected formal GPU portrait URI: $($item.item_id)"}
    $portraitRuntime=Get-OnepageChildPath $onepageRuntime ($runtimeUri.Substring('s2r://panorama/'.Length)+'_c')
    if(-not(Test-Path -LiteralPath $portraitRuntime -PathType Leaf) -or (Get-Item -LiteralPath $portraitRuntime).Length -le 0){throw "Existing compiled portrait missing: $portraitRuntime"}
    Add-OnepageProtected $portraitRuntime 'formal GPU portrait; never rebuilt'
    $onepagePortraitRecords+=[pscustomobject]@{id=$item.item_id;pool=$item.pool_id;sourceHash=$catalog[0].sha256;runtimeUri=$runtimeUri;compiledHash=(Get-OnepageHash $portraitRuntime)}
}
$onepageProtected=@($onepageProtectedByPath.Values|Sort-Object path)
function Get-OnepageProtectedChanges {
    return @($onepageProtected|Where-Object {(Get-OnepageHash $_.path) -ne $_.hash}|ForEach-Object {$_.path})
}
$onepageBackup=Get-OnepageWorkspacePath ('output/collection_onepage/compile_'+(Get-Date -Format yyyyMMdd_HHmmss_fff)+'_'+[guid]::NewGuid().ToString('N').Substring(0,8))
$onepageRecords=@()
foreach($relative in $onepageRequired){
    $source=Get-OnepageSourcePath $relative
    $content=Get-OnepageChildPath $onepageContent $relative
    $artifactRelative=Get-OnepageArtifactRelative $relative
    $artifact=Get-OnepageChildPath $onepageRuntime $artifactRelative
    Assert-OnepageNoLinks $content $onepageContent
    Assert-OnepageNoLinks $artifact $onepageRuntime
    $onepageRecords+=[pscustomobject]@{relative=$relative;source=$source;content=$content;artifact=$artifact;sourceHash=(Get-OnepageHash $source);contentExisted=(Test-Path -LiteralPath $content -PathType Leaf);runtimeExisted=(Test-Path -LiteralPath $artifact -PathType Leaf);contentBeforeHash=(Get-OnepageHash $content);runtimeBeforeHash=(Get-OnepageHash $artifact);sourceBackup=(Join-Path $onepageBackup ('source/'+$relative));contentBackup=(Join-Path $onepageBackup ('content/'+$relative));runtimeBackup=(Join-Path $onepageBackup ('runtime/'+$artifactRelative));compileStartedUtc=$null;compiledHash=$null;artifactBytes=$null;artifactWriteUtc=$null;verified=$false}
}
# Keep this return before any writes, backup directories, copies, or compiler invocation.
if($CheckOnly){[pscustomobject]@{success=$true;checkOnly=$true;files=$onepageRequired.Count;imagesToCompile=0;cssToCompile=0;scope=$Scope;sourceRoot=$onepageSource;report=$Report;canvas=@(900,478);unchangedMaterialCount=$onepageMaterialRecords.Count;formalPortraitCount=$onepagePortraitRecords.Count;existingImageReferences=$onepageImages.Count;requiredImageDependencies=$onepageRequiredImages;protectedFiles=$onepageProtected.Count;activeIncludeOrderVerified=$true;nativeFlags=@('-fshallow','-nop4');sourceRecords=@($onepageRecords|Select-Object relative,sourceHash)}|ConvertTo-Json -Depth 6;return}

New-Item -ItemType Directory -Path $onepageBackup -Force|Out-Null
foreach($record in $onepageRecords){
    foreach($target in @($record.sourceBackup,$record.contentBackup,$record.runtimeBackup)){New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force|Out-Null}
    Copy-Item -LiteralPath $record.source -Destination $record.sourceBackup
    if($record.contentExisted){Copy-Item -LiteralPath $record.content -Destination $record.contentBackup}
    if($record.runtimeExisted){Copy-Item -LiteralPath $record.artifact -Destination $record.runtimeBackup}
}
@{records=$onepageRecords;protected=$onepageProtected;images=$onepageImages}|ConvertTo-Json -Depth 8|Set-Content -LiteralPath (Join-Path $onepageBackup 'manifest_before.json') -Encoding UTF8
try {
    foreach($record in $onepageRecords){
        if((Get-OnepageHash $record.source) -ne $record.sourceHash){throw "Source changed before compile: $($record.relative)"}
        New-Item -ItemType Directory -Path (Split-Path -Parent $record.content) -Force|Out-Null
        Copy-Item -LiteralPath $record.source -Destination $record.content -Force
        if((Get-OnepageHash $record.content) -ne $record.sourceHash){throw "Content copy differs: $($record.relative)"}
    }
    # Only the art metadata JS and collection controller compile. No recursive -f or layout/image compilation.
    foreach($record in $onepageRecords){
        $record.compileStartedUtc=(Get-Date).ToUniversalTime().ToString('o')
        $log=@(& $onepageCompiler -i $record.content -game (Join-Path $onepageEngine 'game/dota') -fshallow -nop4 2>&1)
        $exitCode=$LASTEXITCODE
        $log|Set-Content -LiteralPath (Join-Path $onepageBackup (($record.relative -replace '/','_')+'.log')) -Encoding UTF8
        if($exitCode -ne 0 -or -not($log -match '0 failed')){throw "Native compile failed: $($record.relative)"}
        Write-Output ('COLLECTION_ONEPAGE_COMPILE_PASS '+$record.relative)
    }
    foreach($record in $onepageRecords){
        if((Get-OnepageHash $record.source) -ne $record.sourceHash -or (Get-OnepageHash $record.content) -ne $record.sourceHash){throw "Source/Content changed during compile: $($record.relative)"}
        if(-not(Test-Path -LiteralPath $record.artifact -PathType Leaf)){throw "Missing artifact: $($record.relative)"}
        $file=Get-Item -LiteralPath $record.artifact
        if($file.Length -le 0 -or $file.LastWriteTimeUtc -lt [datetime]::Parse($record.compileStartedUtc).ToUniversalTime()){throw "Stale or empty artifact: $($record.relative)"}
        $record.compiledHash=Get-OnepageHash $record.artifact;$record.artifactBytes=$file.Length;$record.artifactWriteUtc=$file.LastWriteTimeUtc.ToString('o');$record.verified=$true
    }
    $protectedChanges=@(Get-OnepageProtectedChanges)
    if($protectedChanges.Count){throw ('Protected files changed during compile: '+($protectedChanges -join ', '))}
    foreach($relative in $onepageRequired|Where-Object {$_ -like '*.xml'}){
        $null=Assert-OnepageLayout (Get-OnepageSourcePath $relative)
        $null=Assert-OnepageLayout (Join-Path $onepageContent $relative)
        $null=Assert-OnepageLayout (Get-OnepageWorkspacePath ('panorama/src/'+$relative))
    }
    New-Item -ItemType Directory -Path (Split-Path -Parent $onepageReport) -Force|Out-Null
    @{at=(Get-Date -Format o);success=$true;scope=$Scope;sourceRoot=$onepageSource;backup=$onepageBackup;records=$onepageRecords;imagesCompiled=0;cssCompiled=0;canvas=@(900,478);materials=$onepageMaterialRecords;portraits=$onepagePortraitRecords;existingImageReferences=$onepageImages;protected=$onepageProtected;protectedChanges=@();activeIncludeOrderVerified=$true;nativeFlags=@('-fshallow','-nop4')}|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $onepageReport -Encoding UTF8
} catch {
    $failure=$_
    $rollbackErrors=@()
    foreach($record in $onepageRecords){
        try {
            if($record.contentExisted){Copy-Item -LiteralPath $record.contentBackup -Destination $record.content -Force}elseif(Test-Path -LiteralPath $record.content -PathType Leaf){Remove-Item -LiteralPath $record.content}
            if($record.runtimeExisted){Copy-Item -LiteralPath $record.runtimeBackup -Destination $record.artifact -Force}elseif(Test-Path -LiteralPath $record.artifact -PathType Leaf){Remove-Item -LiteralPath $record.artifact}
            if((Get-OnepageHash $record.content) -ne $record.contentBeforeHash -or (Get-OnepageHash $record.artifact) -ne $record.runtimeBeforeHash){throw "Rollback hash mismatch: $($record.relative)"}
        } catch {$rollbackErrors+=$_.ToString()}
    }
    # Preserve concurrent edits to unrelated files; only the two approved output pairs are rolled back.
    @{at=(Get-Date -Format o);success=$false;rolledBack=($rollbackErrors.Count -eq 0);error=$failure.ToString();rollbackErrors=$rollbackErrors;protectedChanges=@(Get-OnepageProtectedChanges);backup=$onepageBackup;records=$onepageRecords;protected=$onepageProtected}|ConvertTo-Json -Depth 8|Set-Content -LiteralPath (Join-Path $onepageBackup 'failure.json') -Encoding UTF8
    throw $failure
}
