param([string]$SourceRoot='panorama/src', [switch]$Isolated, [string]$AddonRoot='')
$ErrorActionPreference='Stop'
$addon=if($AddonRoot){(Resolve-Path -LiteralPath $AddonRoot).Path}else{(Resolve-Path (Join-Path $PSScriptRoot '..')).Path}
$source=[IO.Path]::GetFullPath((Join-Path $addon $SourceRoot))
if(-not $source.StartsWith($addon+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw 'Source must stay inside the addon.'}
$engine=[IO.Path]::GetFullPath((Join-Path $addon '../../..'))
$content=Join-Path $engine 'content/dota_addons/Survival/panorama'
$runtime=Join-Path $addon 'panorama'
$isolatedRuntime=Split-Path -Parent $source
if($Isolated -and $isolatedRuntime -eq $runtime){throw 'Isolated compilation requires a separate source worktree.'}
$compiler=Join-Path $engine 'game/bin/win64/resourcecompiler.exe'
$files=@('styles/custom_game/archive_difficulty.css','scripts/custom_game/survival_ui.js','layout/custom_game/survival_hud.xml')
$backup=Join-Path $addon ('output/difficulty_popup_compile/'+(Get-Date -Format yyyyMMdd_HHmmss_fff)+'_'+[guid]::NewGuid().ToString('N').Substring(0,8))
$records=@()
New-Item -ItemType Directory -Force -Path $backup|Out-Null
foreach($relative in $files){
    $extension=[IO.Path]::GetExtension($relative)
    $compiled=$relative.Substring(0,$relative.Length-$extension.Length)+@{'.css'='.vcss_c';'.js'='.vjs_c';'.xml'='.vxml_c'}[$extension]
    $record=[pscustomobject]@{relative=$relative;compiled=$compiled;source=(Join-Path $source $relative);content=(Join-Path $content $relative);runtime=(Join-Path $runtime $compiled);sourceHash=$null;compiledHash=$null;contentBackup=(Join-Path $backup ('content/'+$relative));runtimeBackup=(Join-Path $backup ('runtime/'+$compiled));copied=$false}
    if(-not(Test-Path -LiteralPath $record.source -PathType Leaf)){throw "Missing source: $relative"}
    $record.sourceHash=(Get-FileHash -LiteralPath $record.source -Algorithm SHA256).Hash
    foreach($kind in @('content','runtime')){
        $saved=$record.($kind+'Backup');$original=$record.$kind
        if(Test-Path -LiteralPath $original -PathType Leaf){
            New-Item -ItemType Directory -Force -Path (Split-Path -Parent $saved)|Out-Null
            Copy-Item -LiteralPath $original -Destination $saved
        }
    }
    $records+=$record
}
$succeeded=$false
try {
    foreach($record in $records){
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $record.content)|Out-Null
        Copy-Item -LiteralPath $record.source -Destination $record.content -Force
        $record.copied=$true
    }
    foreach($record in $records){
        $started=(Get-Date).ToUniversalTime()
        $log=@(& $compiler -i $record.content -game (Join-Path $engine 'game/dota') -fshallow -nop4 2>&1)
        $code=$LASTEXITCODE
        $log|Set-Content -LiteralPath (Join-Path $backup (($record.relative -replace '/','_')+'.log')) -Encoding UTF8
        if($code -ne 0 -or -not($log -match '0 failed')){throw "Native compile failed: $($record.relative). See $backup"}
        $built=Get-Item -LiteralPath $record.runtime
        if($built.Length -le 0 -or $built.LastWriteTimeUtc -lt $started){throw "Compiled resource is empty or stale: $($record.relative)"}
        if((Get-FileHash -LiteralPath $record.source -Algorithm SHA256).Hash -ne $record.sourceHash -or (Get-FileHash -LiteralPath $record.content -Algorithm SHA256).Hash -ne $record.sourceHash){throw "Source changed during compile: $($record.relative)"}
        $record.compiledHash=(Get-FileHash -LiteralPath $record.runtime -Algorithm SHA256).Hash
        if($Isolated){
            $destination=Join-Path $isolatedRuntime $record.compiled
            New-Item -ItemType Directory -Force -Path (Split-Path -Parent $destination)|Out-Null
            Copy-Item -LiteralPath $record.runtime -Destination $destination -Force
        }
        Write-Output ('DIFFICULTY_POPUP_COMPILE_PASS '+$record.relative)
    }
    $succeeded=$true
} finally {
    if($Isolated -or -not $succeeded){
        foreach($record in $records){
            if(-not $record.copied){continue}
            foreach($kind in @('content','runtime')){
                $target=$record.$kind;$saved=$record.($kind+'Backup')
                $ownedHash=if($kind -eq 'content'){$record.sourceHash}else{$record.compiledHash}
                if($ownedHash -and (Test-Path -LiteralPath $target) -and (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash -ne $ownedHash){throw "Concurrent compile changed $target; retained it and backup $saved"}
                if(Test-Path -LiteralPath $saved){Copy-Item -LiteralPath $saved -Destination $target -Force}
                elseif(Test-Path -LiteralPath $target){Remove-Item -LiteralPath $target}
            }
        }
    }
    $records|ConvertTo-Json -Depth 5|Set-Content -LiteralPath (Join-Path $backup 'manifest.json') -Encoding UTF8
}
Write-Output ('DIFFICULTY_POPUP_COMPILE_REPORT '+$backup)
