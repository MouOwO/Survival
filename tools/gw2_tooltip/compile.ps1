param([switch]$CheckOnly,[string]$Report='output/tooltip_reference_extract_20261015/compile.json')
$ErrorActionPreference='Stop'
$tooltipRepo=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$tooltipEngine=[IO.Path]::GetFullPath((Join-Path $tooltipRepo '../../..'))
$tooltipContent=Join-Path $tooltipEngine 'content/dota_addons/Survival/panorama'
$tooltipRuntime=Join-Path $tooltipRepo 'panorama'
$tooltipCompiler=Join-Path $tooltipEngine 'game/bin/win64/resourcecompiler.exe'
$tooltipBackup=Join-Path $tooltipRepo ('output/tooltip_reference_extract_20261015/compile_'+(Get-Date -Format yyyyMMdd_HHmmss_fff))
function Resolve-TooltipChild([string]$Base,[string]$Child){
    $resolved=[IO.Path]::GetFullPath((Join-Path $Base $Child))
    if(-not $resolved.StartsWith($Base+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw "Tooltip path escaped its root: $Child"}
    return $resolved
}
$tooltipReport=Resolve-TooltipChild $tooltipRepo $Report
$tooltipSpecs=@(
    @('art/ui/sources/custom_game/gw2_tooltip_v1/background.png','images/custom_game/gw2_tooltip_v1/background.png',$null),
    @('art/ui/sources/custom_game/gw2_tooltip_v1/background_png.vtex','images/custom_game/gw2_tooltip_v1/background_png.vtex','images/custom_game/gw2_tooltip_v1/background_png.vtex_c'),
    @('panorama/src/scripts/custom_game/common/archive_tooltip.js','scripts/custom_game/common/archive_tooltip.js','scripts/custom_game/common/archive_tooltip.vjs_c'),
    @('panorama/src/styles/custom_game/common/archive_tooltip.css','styles/custom_game/common/archive_tooltip.css','styles/custom_game/common/archive_tooltip.vcss_c')
)
$tooltipRecords=@()
foreach($spec in $tooltipSpecs){
    $source=Resolve-TooltipChild $tooltipRepo $spec[0]
    $content=Resolve-TooltipChild $tooltipContent $spec[1]
    $artifact=if($spec[2]){Resolve-TooltipChild $tooltipRuntime $spec[2]}else{$null}
    if(-not(Test-Path -LiteralPath $source -PathType Leaf)){throw "Missing tooltip source: $source"}
    $tooltipRecords+=[pscustomobject]@{source=$source;relative=$spec[1];content=$content;artifact=$artifact;sourceHash=(Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash;contentExisted=(Test-Path -LiteralPath $content -PathType Leaf);artifactExisted=($artifact -and (Test-Path -LiteralPath $artifact -PathType Leaf));contentBackup=(Join-Path $tooltipBackup ('content/'+$spec[1]));artifactBackup=(Join-Path $tooltipBackup ('runtime/'+$spec[2]));compiledHash=$null}
}
if($CheckOnly){'GW2_TOOLTIP_COMPILE_CHECK_PASS: original PNG, lossless texture, shared JS/CSS';return}
foreach($record in $tooltipRecords){
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $record.contentBackup)|Out-Null
    if($record.contentExisted){Copy-Item -LiteralPath $record.content -Destination $record.contentBackup}
    if($record.artifactExisted){New-Item -ItemType Directory -Force -Path (Split-Path -Parent $record.artifactBackup)|Out-Null;Copy-Item -LiteralPath $record.artifact -Destination $record.artifactBackup}
}
try{
    foreach($record in $tooltipRecords){New-Item -ItemType Directory -Force -Path (Split-Path -Parent $record.content)|Out-Null;Copy-Item -LiteralPath $record.source -Destination $record.content -Force}
    foreach($record in $tooltipRecords|Where-Object {$_.artifact}){
        $started=(Get-Date).ToUniversalTime()
        $log=@(& $tooltipCompiler -i $record.content -game (Join-Path $tooltipEngine 'game/dota') -fshallow -nop4 2>&1)
        $log|Set-Content -LiteralPath (Join-Path $tooltipBackup (([IO.Path]::GetFileName($record.source))+'.log')) -Encoding UTF8
        if($LASTEXITCODE -ne 0 -or -not($log -match '0 failed')){throw "Tooltip compile failed: $($record.relative)"}
        if(-not(Test-Path -LiteralPath $record.artifact -PathType Leaf) -or (Get-Item -LiteralPath $record.artifact).LastWriteTimeUtc -lt $started){throw "Missing or stale tooltip artifact: $($record.relative)"}
        $record.compiledHash=(Get-FileHash -LiteralPath $record.artifact -Algorithm SHA256).Hash
        Write-Output ('GW2_TOOLTIP_COMPILE_PASS '+$record.relative)
    }
    foreach($record in $tooltipRecords){if((Get-FileHash -LiteralPath $record.source -Algorithm SHA256).Hash -ne $record.sourceHash -or (Get-FileHash -LiteralPath $record.content -Algorithm SHA256).Hash -ne $record.sourceHash){throw "Tooltip source changed while compiling: $($record.relative)"}}
}catch{
    foreach($record in $tooltipRecords){
        if($record.contentExisted){Copy-Item -LiteralPath $record.contentBackup -Destination $record.content -Force}elseif(Test-Path -LiteralPath $record.content -PathType Leaf){Remove-Item -LiteralPath $record.content}
        if($record.artifactExisted){Copy-Item -LiteralPath $record.artifactBackup -Destination $record.artifact -Force}elseif($record.artifact -and (Test-Path -LiteralPath $record.artifact -PathType Leaf)){Remove-Item -LiteralPath $record.artifact}
    }
    throw
}
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $tooltipReport)|Out-Null
@{success=$true;at=(Get-Date -Format o);backup=$tooltipBackup;records=$tooltipRecords}|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $tooltipReport -Encoding UTF8
