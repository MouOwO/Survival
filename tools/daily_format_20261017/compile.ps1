$ErrorActionPreference='Stop'
$dailyFormatRepo=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$dailyFormatEngine=[IO.Path]::GetFullPath((Join-Path $dailyFormatRepo '../../..'))
$dailyFormatRelative='scripts/custom_game/daily_remaining_5d5c1152eb.js'
$dailyFormatSource=Join-Path $dailyFormatRepo ('panorama/src/'+$dailyFormatRelative)
$dailyFormatContent=Join-Path $dailyFormatEngine ('content/dota_addons/Survival/panorama/'+$dailyFormatRelative)
$dailyFormatRuntime=Join-Path $dailyFormatRepo 'panorama/scripts/custom_game/daily_remaining_5d5c1152eb.vjs_c'
$dailyFormatCompiler=Join-Path $dailyFormatEngine 'game/bin/win64/resourcecompiler.exe'
$dailyFormatBackup=Join-Path $dailyFormatRepo ('output/daily_format_20261017/compile_'+(Get-Date -Format yyyyMMdd_HHmmss_fff))
foreach($target in @($dailyFormatSource,$dailyFormatContent,$dailyFormatRuntime,$dailyFormatCompiler)){if(-not(Test-Path -LiteralPath $target -PathType Leaf)){throw "Expected existing resource is missing: $target"}}
$dailyFormatHash=(Get-FileHash -LiteralPath $dailyFormatSource -Algorithm SHA256).Hash.ToLowerInvariant()
New-Item -ItemType Directory -Path $dailyFormatBackup -Force|Out-Null
Copy-Item -LiteralPath $dailyFormatSource -Destination (Join-Path $dailyFormatBackup 'source.js')
Copy-Item -LiteralPath $dailyFormatContent -Destination (Join-Path $dailyFormatBackup 'content.js')
Copy-Item -LiteralPath $dailyFormatRuntime -Destination (Join-Path $dailyFormatBackup 'runtime.vjs_c')
try{
 Copy-Item -LiteralPath $dailyFormatSource -Destination $dailyFormatContent -Force
 $dailyFormatStart=(Get-Date).ToUniversalTime()
 $dailyFormatLog=@(& $dailyFormatCompiler -i $dailyFormatContent -game (Join-Path $dailyFormatEngine 'game/dota') -fshallow -nop4 2>&1)
 $dailyFormatLog|Set-Content -LiteralPath (Join-Path $dailyFormatBackup 'resourcecompiler.log') -Encoding utf8
 if($LASTEXITCODE -ne 0 -or -not($dailyFormatLog -match '0 failed')){throw 'Native compile failed.'}
 if((Get-FileHash -LiteralPath $dailyFormatSource -Algorithm SHA256).Hash.ToLowerInvariant() -ne $dailyFormatHash -or (Get-FileHash -LiteralPath $dailyFormatContent -Algorithm SHA256).Hash.ToLowerInvariant() -ne $dailyFormatHash -or (Get-Item -LiteralPath $dailyFormatRuntime).LastWriteTimeUtc -lt $dailyFormatStart){throw 'Source drift or stale runtime artifact.'}
 $dailyFormatRuntimeHash=(Get-FileHash -LiteralPath $dailyFormatRuntime -Algorithm SHA256).Hash.ToLowerInvariant()
}catch{
 Copy-Item -LiteralPath (Join-Path $dailyFormatBackup 'content.js') -Destination $dailyFormatContent -Force
 Copy-Item -LiteralPath (Join-Path $dailyFormatBackup 'runtime.vjs_c') -Destination $dailyFormatRuntime -Force
 throw
}
@{success=$true;source=$dailyFormatSource;sourceSha256=$dailyFormatHash;content=$dailyFormatContent;runtime=$dailyFormatRuntime;runtimeSha256=$dailyFormatRuntimeHash;backup=$dailyFormatBackup}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $dailyFormatRepo 'design_refs/daily_format_20261017/compile.json') -Encoding utf8
Write-Output 'DAILY_FORMAT_NATIVE_COMPILE_PASS: one JS resource, source/content hashes matched, runtime refreshed'
