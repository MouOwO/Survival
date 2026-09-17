$ErrorActionPreference='Stop'
$taskRoot='D:\steam\steamapps\common\dota 2 beta\game\dota_addons\survival'
$taskContent='D:\steam\steamapps\common\dota 2 beta\content\dota_addons\survival'
$taskOutput=Join-Path $taskRoot 'output\basin_natural'
if (!(Test-Path -LiteralPath (Join-Path $taskOutput 'materials\slate_normal.png'))) {throw 'Normal bake not ready'}
New-Item -ItemType Directory -Force -Path (Join-Path $taskContent 'materials\basin_natural'),(Join-Path $taskContent 'maps\tilesets') | Out-Null
Copy-Item -LiteralPath (Join-Path $taskOutput 'survival_basin_natural.vmap') -Destination (Join-Path $taskContent 'maps\survival_basin_natural.vmap') -Force
Copy-Item -LiteralPath (Join-Path $taskOutput 'survival_natural_slate.vmap') -Destination (Join-Path $taskContent 'maps\tilesets\survival_natural_slate.vmap') -Force
Get-ChildItem -LiteralPath (Join-Path $taskOutput 'materials') -File | Where-Object { $_.Extension -in '.png','.vmat' } | ForEach-Object { Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $taskContent 'materials\basin_natural') -Force }
& 'D:\steam\steamapps\common\dota 2 beta\game\bin\win64\resourcecompiler.exe' -i (Join-Path $taskContent 'materials\basin_natural\*.vmat') -game 'D:\steam\steamapps\common\dota 2 beta\game\dota' -f *> (Join-Path $taskOutput 'materials_compile.log')
if ($LASTEXITCODE -ne 0) {Get-Content (Join-Path $taskOutput 'materials_compile.log') -Tail 35;throw 'Material compile failed'}
& 'D:\steam\steamapps\common\dota 2 beta\game\bin\win64\resourcecompiler.exe' -i (Join-Path $taskContent 'maps\survival_basin_natural.vmap') -game 'D:\steam\steamapps\common\dota 2 beta\game\dota' -f *> (Join-Path $taskOutput 'compile.log')
if ($LASTEXITCODE -ne 0) {Get-Content (Join-Path $taskOutput 'compile.log') -Tail 45;throw "Compile exit $LASTEXITCODE"}
if (Select-String -LiteralPath (Join-Path $taskOutput 'compile.log') -Pattern 'Write .* Failed!|referencing missing material' -Quiet) {throw 'Map output failed or material missing; do not use this build'}
Get-Content (Join-Path $taskOutput 'compile.log') -Tail 18
