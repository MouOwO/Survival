$ErrorActionPreference='Stop'
$stripeRepo=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$stripeEngine=[IO.Path]::GetFullPath((Join-Path $stripeRepo '../../..'))
$stripeRel='scripts/custom_game/archive_blackgold_v1.js'
$stripeSource=Join-Path $stripeRepo ('panorama/src/'+$stripeRel)
$stripeContent=Join-Path $stripeEngine ('content/dota_addons/Survival/panorama/'+$stripeRel)
$stripeArtifact=Join-Path $stripeRepo 'panorama/scripts/custom_game/archive_blackgold_v1.vjs_c'
$stripeBackup=Join-Path $stripeRepo ('output/archive_row_stripes_20261020/compile_'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $stripeBackup -Force|Out-Null
Copy-Item -LiteralPath $stripeContent -Destination (Join-Path $stripeBackup 'original.js')
Copy-Item -LiteralPath $stripeArtifact -Destination (Join-Path $stripeBackup 'original.vjs_c')
$stripeHash=(Get-FileHash -LiteralPath $stripeSource).Hash
try{
 Copy-Item -LiteralPath $stripeSource -Destination $stripeContent -Force
 $stripeStart=(Get-Date).ToUniversalTime()
 $stripeLog=@(& (Join-Path $stripeEngine 'game/bin/win64/resourcecompiler.exe') -i $stripeContent -game (Join-Path $stripeEngine 'game/dota') -fshallow -nop4 2>&1)
 $stripeLog|Set-Content -LiteralPath (Join-Path $stripeBackup 'compile.log') -Encoding utf8
 if($LASTEXITCODE -ne 0 -or -not($stripeLog -match '0 failed')){throw 'Native compilation failed'}
 if((Get-FileHash -LiteralPath $stripeSource).Hash -ne $stripeHash -or (Get-FileHash -LiteralPath $stripeContent).Hash -ne $stripeHash -or (Get-Item -LiteralPath $stripeArtifact).LastWriteTimeUtc -lt $stripeStart){throw 'Source drift or stale runtime artifact'}
 Write-Output "ARCHIVE_ROW_STRIPES_NATIVE_COMPILE_PASS backup=$stripeBackup"
}catch{
 Copy-Item -LiteralPath (Join-Path $stripeBackup 'original.js') -Destination $stripeContent -Force
 Copy-Item -LiteralPath (Join-Path $stripeBackup 'original.vjs_c') -Destination $stripeArtifact -Force
 throw
}
