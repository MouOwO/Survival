$ErrorActionPreference='Stop'
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$engine=[IO.Path]::GetFullPath((Join-Path $repo '../../..'))
$content=Join-Path $engine 'content/dota_addons/survival/panorama'
$compiler=Join-Path $engine 'game/bin/win64/resourcecompiler.exe'
$backup=Join-Path $repo ('output/combat_revision_build_'+(Get-Date -Format 'yyyyMMdd_HHmmss'))
New-Item -ItemType Directory -Force -Path $backup | Out-Null
$files=@('scripts/custom_game/combat_stats.js','scripts/custom_game/topnav_remaining_5d5c1152eb.js','scripts/custom_game/archive_handoff_180de7e38b.js','scripts/custom_game/archive_theme.js','scripts/custom_game/archive_theme_tokens.js','styles/custom_game/archive_comfort.css','layout/custom_game/archive.xml','layout/custom_game/survival_hud.xml')
foreach($rel in $files){
 $source=Join-Path $repo ('panorama/src/'+$rel)
 $destination=Join-Path $content $rel
 $saved=Join-Path $backup $rel
 New-Item -ItemType Directory -Force -Path (Split-Path $saved) | Out-Null
 if(Test-Path -LiteralPath $destination){Copy-Item -LiteralPath $destination -Destination $saved}
 New-Item -ItemType Directory -Force -Path (Split-Path $destination) | Out-Null
 Copy-Item -LiteralPath $source -Destination $destination -Force
}
foreach($rel in $files){
 $destination=Join-Path $content $rel
 $log=@(& $compiler -i $destination -game (Join-Path $engine 'game/dota') -f -nop4 2>&1)
 $log | Out-File (Join-Path $backup (([IO.Path]::GetFileName($rel))+'.compile.log')) -Encoding utf8
 if($LASTEXITCODE -ne 0 -or -not($log -match '0 failed')){throw "Compilation failed: $rel"}
 Write-Output "COMPILED $rel"
}
Write-Output "COMBAT_REVISION_BUILD_PASS $backup"
