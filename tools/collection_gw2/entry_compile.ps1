param(
    [string]$Scope='tools/collection_gw2/entry_compile_scope.json',
    [string]$Report='design_refs/collection_gw2_v2/work/entry_compile.json',
    [switch]$CheckOnly
)
$ErrorActionPreference='Stop'
$entryRepo=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$entryEngine=(Resolve-Path (Join-Path $entryRepo '../../..')).Path
$entryContent=Join-Path $entryEngine 'content/dota_addons/Survival/panorama'
$entryRuntime=Join-Path $entryRepo 'panorama'
$entryCompiler=Join-Path $entryEngine 'game/bin/win64/resourcecompiler.exe'
$entryRequired=@('scripts/custom_game/collection_nav.js','images/custom_game/topnav_reference_v2/collection.svg')
function Get-EntryWorkspacePath([string]$Relative) {
    $resolved=[IO.Path]::GetFullPath((Join-Path $entryRepo $Relative))
    if(-not $resolved.StartsWith($entryRepo+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw "Path outside the workspace: $Relative"}
    return $resolved
}
$entryFiles=@(Get-Content -LiteralPath (Get-EntryWorkspacePath $Scope) -Raw -Encoding UTF8|ConvertFrom-Json)
if($entryFiles.Count -ne 2 -or @($entryFiles|Select-Object -Unique).Count -ne 2 -or @(Compare-Object $entryFiles $entryRequired).Count){throw 'Entry scope must contain only collection_nav.js and collection.svg.'}
if(-not(Test-Path -LiteralPath $entryCompiler -PathType Leaf)){throw 'Native resourcecompiler is missing.'}
$entryReport=Get-EntryWorkspacePath $Report
[xml]$entryHud=Get-Content -LiteralPath (Get-EntryWorkspacePath 'panorama/src/layout/custom_game/survival_hud.xml') -Raw -Encoding UTF8
if(-not $entryHud.SelectSingleNode("//include[@src='file://{resources}/scripts/custom_game/collection_nav.js']")){throw 'Active HUD does not include collection_nav.js.'}
$entryNav=Get-Content -LiteralPath (Get-EntryWorkspacePath 'panorama/src/scripts/custom_game/collection_nav.js') -Raw -Encoding UTF8
if(-not $entryNav.Contains('file://{images}/custom_game/topnav_reference_v2/collection.svg')){throw 'Collection entry does not reference its scoped SVG.'}
$entryCanonical=Get-EntryWorkspacePath 'art/ui/sources/custom_game/topnav_reference_v2/collection.svg'
$entryMirror=Get-EntryWorkspacePath 'panorama/src/images/custom_game/topnav_reference_v2/collection.svg'
if((Get-FileHash -LiteralPath $entryCanonical -Algorithm SHA256).Hash -ne (Get-FileHash -LiteralPath $entryMirror -Algorithm SHA256).Hash){throw 'Canonical SVG and Panorama mirror differ.'}
[xml]$entrySvg=Get-Content -LiteralPath $entryCanonical -Raw -Encoding UTF8
if($entrySvg.DocumentElement.LocalName -ne 'svg'){throw 'Invalid SVG root.'}
if($entrySvg.SelectNodes('//*[local-name()="script" or local-name()="image" or local-name()="use"]').Count){throw 'Entry SVG must be self-contained paths/shapes without external or script dependencies.'}
# Read-only sentinels explicitly protect the existing user-edited top navigation.
$entryProtected=@('panorama/src/scripts/custom_game/topnav_remaining_5d5c1152eb.js','panorama/scripts/custom_game/topnav_remaining_5d5c1152eb.vjs_c','panorama/src/layout/custom_game/survival_hud.xml')|ForEach-Object {
    $file=Get-EntryWorkspacePath $_
    [pscustomobject]@{path=$_;hash=if(Test-Path -LiteralPath $file -PathType Leaf){(Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash}else{$null}}
}
$entryBackup=Get-EntryWorkspacePath ('output/collection_gw2/entry_compile_'+(Get-Date -Format yyyyMMdd_HHmmss_fff)+'_'+[guid]::NewGuid().ToString('N').Substring(0,8))
$entryRecords=@()
foreach($relative in $entryFiles){
    if($entryRequired -notcontains $relative){throw "Out-of-scope file: $relative"}
    $source=Get-EntryWorkspacePath ('panorama/src/'+$relative)
    $content=[IO.Path]::GetFullPath((Join-Path $entryContent $relative))
    $artifactRelative=$relative -replace '\.js$','.vjs_c' -replace '\.svg$','.vsvg_c'
    $artifact=[IO.Path]::GetFullPath((Join-Path $entryRuntime $artifactRelative))
    if(-not $content.StartsWith($entryContent+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase) -or -not $artifact.StartsWith($entryRuntime+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw 'Resolved target escaped task roots.'}
    if(-not(Test-Path -LiteralPath $source -PathType Leaf)){throw "Missing source: $relative"}
    $entryRecords+=[pscustomobject]@{relative=$relative;source=$source;content=$content;artifact=$artifact;sourceHash=(Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash;contentExisted=(Test-Path -LiteralPath $content -PathType Leaf);runtimeExisted=(Test-Path -LiteralPath $artifact -PathType Leaf);sourceBackup=(Join-Path $entryBackup ('source/'+$relative));contentBackup=(Join-Path $entryBackup ('content/'+$relative));runtimeBackup=(Join-Path $entryBackup ('runtime/'+$artifactRelative));compileStartedUtc=$null;compiledHash=$null;artifactBytes=$null;artifactWriteUtc=$null;verified=$false}
}
if($CheckOnly){[pscustomobject]@{success=$true;checkOnly=$true;files=$entryRecords.Count;scope=$Scope;artifacts=@($entryRecords|ForEach-Object {$_.artifact});protected=$entryProtected}|ConvertTo-Json -Depth 5;return}
New-Item -ItemType Directory -Path $entryBackup -Force|Out-Null
foreach($record in $entryRecords){
    foreach($target in @($record.sourceBackup,$record.contentBackup,$record.runtimeBackup)){New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force|Out-Null}
    Copy-Item -LiteralPath $record.source -Destination $record.sourceBackup
    if($record.contentExisted){Copy-Item -LiteralPath $record.content -Destination $record.contentBackup}
    if($record.runtimeExisted){Copy-Item -LiteralPath $record.artifact -Destination $record.runtimeBackup}
}
$entryRecords|ConvertTo-Json -Depth 5|Set-Content -LiteralPath (Join-Path $entryBackup 'manifest_before.json') -Encoding UTF8
try {
    foreach($record in $entryRecords){
        New-Item -ItemType Directory -Path (Split-Path -Parent $record.content) -Force|Out-Null
        Copy-Item -LiteralPath $record.source -Destination $record.content -Force
        if((Get-FileHash -LiteralPath $record.content -Algorithm SHA256).Hash -ne $record.sourceHash){throw "Content copy differs: $($record.relative)"}
        $record.compileStartedUtc=(Get-Date).ToUniversalTime().ToString('o')
        $log=@(& $entryCompiler -i $record.content -game (Join-Path $entryEngine 'game/dota') -fshallow -nop4 2>&1)
        $exitCode=$LASTEXITCODE
        $log|Set-Content -LiteralPath (Join-Path $entryBackup (($record.relative -replace '/','_')+'.log')) -Encoding UTF8
        if($exitCode -ne 0 -or -not($log -match '0 failed')){throw "Native compile failed: $($record.relative)"}
        Write-Output ('COLLECTION_ENTRY_COMPILE_PASS '+$record.relative)
    }
    foreach($record in $entryRecords){
        if((Get-FileHash -LiteralPath $record.source -Algorithm SHA256).Hash -ne $record.sourceHash -or (Get-FileHash -LiteralPath $record.content -Algorithm SHA256).Hash -ne $record.sourceHash){throw "Source changed during compile: $($record.relative)"}
        if(-not(Test-Path -LiteralPath $record.artifact -PathType Leaf)){throw "Missing artifact: $($record.relative)"}
        $file=Get-Item -LiteralPath $record.artifact
        if($file.Length -le 0 -or $file.LastWriteTimeUtc -lt [datetime]::Parse($record.compileStartedUtc).ToUniversalTime()){throw "Stale artifact: $($record.relative)"}
        $record.compiledHash=(Get-FileHash -LiteralPath $record.artifact -Algorithm SHA256).Hash;$record.artifactBytes=$file.Length;$record.artifactWriteUtc=$file.LastWriteTimeUtc.ToString('o');$record.verified=$true
    }
    foreach($sentinel in $entryProtected){$file=Get-EntryWorkspacePath $sentinel.path;$after=if(Test-Path -LiteralPath $file -PathType Leaf){(Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash}else{$null};if($after -ne $sentinel.hash){throw "Protected file changed: $($sentinel.path)"}}
    New-Item -ItemType Directory -Path (Split-Path -Parent $entryReport) -Force|Out-Null
    @{at=(Get-Date -Format o);success=$true;scope=$Scope;backup=$entryBackup;records=$entryRecords;protected=$entryProtected}|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $entryReport -Encoding UTF8
} catch {
    $failure=$_
    foreach($record in $entryRecords){
        if($record.contentExisted){Copy-Item -LiteralPath $record.contentBackup -Destination $record.content -Force}elseif(Test-Path -LiteralPath $record.content -PathType Leaf){Remove-Item -LiteralPath $record.content}
        if($record.runtimeExisted){Copy-Item -LiteralPath $record.runtimeBackup -Destination $record.artifact -Force}elseif(Test-Path -LiteralPath $record.artifact -PathType Leaf){Remove-Item -LiteralPath $record.artifact}
    }
    @{at=(Get-Date -Format o);success=$false;rolledBack=$true;error=$failure.ToString();backup=$entryBackup;records=$entryRecords}|ConvertTo-Json -Depth 8|Set-Content -LiteralPath (Join-Path $entryBackup 'failure.json') -Encoding UTF8
    throw $failure
}
