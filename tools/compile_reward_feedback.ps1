param([string]$SourceRoot='panorama/src')
$ErrorActionPreference='Stop'
$repo=(Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$source=[IO.Path]::GetFullPath((Join-Path $repo $SourceRoot))
if(-not $source.StartsWith($repo+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw 'Source root must remain inside the addon workspace.'}
$engine=(Resolve-Path (Join-Path $repo '../../..')).Path
$content=Join-Path $engine 'content/dota_addons/Survival/panorama'
$runtime=Join-Path $repo 'panorama'
$compiler=Join-Path $engine 'game/bin/win64/resourcecompiler.exe'
$files=@(
    'styles/custom_game/common/reward_feedback.css',
    'layout/custom_game/common/reward_feedback.xml',
    'scripts/custom_game/common/reward_feedback.js',
    'scripts/custom_game/daily_remaining_5d5c1152eb.js',
    'scripts/custom_game/collection_gw2.js',
    'scripts/custom_game/lottery_ui_remaining_5d5c1152eb.js',
    'layout/custom_game/archive.xml',
    'layout/custom_game/survival_hud.xml'
)
$backup=Join-Path $repo ('output/reward_feedback_compile/'+(Get-Date -Format yyyyMMdd_HHmmss_fff)+'_'+[guid]::NewGuid().ToString('N').Substring(0,8))
$records=@()
foreach($relative in $files){
    $inputFile=Join-Path $source $relative
    if(-not(Test-Path -LiteralPath $inputFile -PathType Leaf)){throw "Missing source: $relative"}
    $extension=[IO.Path]::GetExtension($relative)
    $artifact=$relative.Substring(0,$relative.Length-$extension.Length)+@{'.css'='.vcss_c';'.xml'='.vxml_c';'.js'='.vjs_c'}[$extension]
    $records+=[pscustomobject]@{relative=$relative;source=$inputFile;content=(Join-Path $content $relative);artifact=(Join-Path $runtime $artifact);sourceHash=(Get-FileHash -LiteralPath $inputFile -Algorithm SHA256).Hash;compiledHash=$null}
}
New-Item -ItemType Directory -Path $backup -Force|Out-Null
foreach($record in $records){
    foreach($kind in @('content','artifact')){
        $path=$record.$kind
        if(Test-Path -LiteralPath $path -PathType Leaf){
            $saved=Join-Path $backup ($kind+'/'+$record.relative)
            New-Item -ItemType Directory -Path (Split-Path -Parent $saved) -Force|Out-Null
            Copy-Item -LiteralPath $path -Destination $saved
        }
    }
    New-Item -ItemType Directory -Path (Split-Path -Parent $record.content) -Force|Out-Null
    Copy-Item -LiteralPath $record.source -Destination $record.content -Force
}
foreach($record in $records){
    $started=(Get-Date).ToUniversalTime()
    $log=@(& $compiler -i $record.content -game (Join-Path $engine 'game/dota') -fshallow -nop4 2>&1)
    $code=$LASTEXITCODE
    $log|Set-Content -LiteralPath (Join-Path $backup (($record.relative -replace '/','_')+'.log')) -Encoding UTF8
    if($code -ne 0 -or -not($log -match '0 failed')){throw "Native compile failed: $($record.relative). See $backup"}
    if(-not(Test-Path -LiteralPath $record.artifact -PathType Leaf)){throw "Missing compiled resource: $($record.relative)"}
    $built=Get-Item -LiteralPath $record.artifact
    if($built.Length -le 0 -or $built.LastWriteTimeUtc -lt $started){throw "Compiled resource is empty or stale: $($record.relative)"}
    if((Get-FileHash -LiteralPath $record.content -Algorithm SHA256).Hash -ne $record.sourceHash){throw "Content changed during compile: $($record.relative)"}
    $record.compiledHash=(Get-FileHash -LiteralPath $record.artifact -Algorithm SHA256).Hash
    Write-Output ('REWARD_FEEDBACK_COMPILE_PASS '+$record.relative)
}
$records|ConvertTo-Json -Depth 5|Set-Content -LiteralPath (Join-Path $backup 'manifest.json') -Encoding UTF8
Write-Output ('REWARD_FEEDBACK_COMPILE_REPORT '+$backup)
