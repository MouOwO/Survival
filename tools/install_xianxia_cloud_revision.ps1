$ErrorActionPreference = 'Stop'
$kitGameRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$kitContentRoot = 'D:/steam/steamapps/common/dota 2 beta/content/dota_addons/survival'
$kitStage = Join-Path $kitGameRoot 'output/xianxia_kit/cloud_revision_v2'
$kitCompiler = 'D:/steam/steamapps/common/dota 2 beta/game/bin/win64/resourcecompiler.exe'
$kitDotaRoot = 'D:/steam/steamapps/common/dota 2 beta/game/dota'
foreach ($kitSubdir in @('materials/xianxia_kit','particles/xianxia_kit')) {
    New-Item -ItemType Directory -Path (Join-Path $kitContentRoot $kitSubdir) -Force | Out-Null
}
Get-ChildItem -LiteralPath (Join-Path $kitStage 'source_materials') -File | ForEach-Object { Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $kitContentRoot 'materials/xianxia_kit') -Force }
Get-ChildItem -LiteralPath (Join-Path $kitStage 'source_particles') -File | ForEach-Object { Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $kitContentRoot 'particles/xianxia_kit') -Force }
$kitBuilds = @()
foreach ($kitType in @(@('materials/xianxia_kit','*_v2.vtex'),@('particles/xianxia_kit','*_v2.vpcf'))) {
    foreach ($kitFile in Get-ChildItem -LiteralPath (Join-Path $kitContentRoot $kitType[0]) -Filter $kitType[1]) {
        $kitLog = Join-Path $kitStage ($kitFile.Name + '.log')
        & $kitCompiler -i $kitFile.FullName -game $kitDotaRoot -f *> $kitLog
        $kitCompiled = Join-Path $kitGameRoot ($kitType[0]+'/'+$kitFile.Name+'_c')
        $kitOkay = ($LASTEXITCODE -eq 0) -and (Test-Path -LiteralPath $kitCompiled) -and [bool](Select-String -LiteralPath $kitLog -Pattern '0 failed')
        $kitBuilds += @{file=$kitFile.Name;ok=$kitOkay}
        if (-not $kitOkay) { throw "Cloud resource compile failed: $($kitFile.Name)" }
        Write-Output "Compiled $($kitFile.Name)"
    }
}
foreach ($kitGame in Get-CimInstance Win32_Process -Filter "Name = 'dota2.exe'") {
    if ($kitGame.CommandLine -like '*xianxia_kit_review*') { Stop-Process -Id $kitGame.ProcessId -Force; Wait-Process -Id $kitGame.ProcessId -Timeout 10 -ErrorAction SilentlyContinue }
}
$kitMap = Join-Path $kitContentRoot 'maps/xianxia_kit_review.vmap'
Copy-Item -LiteralPath (Join-Path $kitStage 'xianxia_kit_review.vmap') -Destination $kitMap -Force
$kitStarted = Get-Date
& $kitCompiler -i $kitMap -game $kitDotaRoot -f *> (Join-Path $kitStage 'map_compile.log')
$kitVpk = Get-Item -LiteralPath (Join-Path $kitGameRoot 'maps/xianxia_kit_review.vpk')
if ($LASTEXITCODE -ne 0 -or $kitVpk.LastWriteTime -lt $kitStarted -or -not (Select-String -LiteralPath (Join-Path $kitStage 'map_compile.log') -Pattern 'VPK: Wrote file')) { throw 'Test map package was not freshly written' }
@{resources=$kitBuilds;reviewMapModified=$kitVpk.LastWriteTime.ToUniversalTime().ToString('o');reviewMapSHA256=(Get-FileHash -LiteralPath $kitVpk.FullName -Algorithm SHA256).Hash;mainMapModified=$false} | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $kitStage 'compile_validation.json') -Encoding utf8
Write-Output "New test map package written: $($kitVpk.LastWriteTime)"
