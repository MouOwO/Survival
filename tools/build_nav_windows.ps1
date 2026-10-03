$ErrorActionPreference='Stop'
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$engine=[IO.Path]::GetFullPath((Join-Path $repo '../../..'))
$content=Join-Path $engine 'content/dota_addons/Survival/panorama'
$compiler=Join-Path $engine 'game/bin/win64/resourcecompiler.exe'
$files=@(
 'styles/custom_game/nav_windows_modern_20260929.css'
 'layout/custom_game/survival_hud.xml'
 'layout/custom_game/archive.xml')
$failed=@()
foreach($rel in $files){
 $target=Join-Path $content $rel
 if(-not (Test-Path $target)){throw "Missing source: $target"}
 $output=& $compiler -i $target -game (Join-Path $engine 'game/dota') -f -nop4 2>&1
 $output | Set-Content (Join-Path $repo ('tools/nav_windows_'+[IO.Path]::GetFileName($rel)+'.log'))
 $ok=($LASTEXITCODE -eq 0) -and ($output -match '0 failed')
 if(-not $ok){$failed+=$rel}
 $output | Select-String 'OK:' | ForEach-Object {$_.Line}
}
if($failed.Count){Write-Host ('FAILED: '+($failed -join ', '));exit 1}
Write-Host 'PANORAMA_COMPILE_PASS'
