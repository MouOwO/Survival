$ErrorActionPreference = 'Stop'
$treeRepo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$treeEngine = (Resolve-Path (Join-Path $treeRepo '../../..')).Path
$treeContent = Join-Path $treeEngine 'content/dota_addons/survival/models/survival_resources'
$treeLogs = Join-Path $treeRepo ('output/resource_tree/' + (Get-Date -Format 'yyyyMMdd_HHmmss'))
New-Item -ItemType Directory -Force -Path $treeLogs | Out-Null
New-Item -ItemType Directory -Force -Path $treeContent | Out-Null
foreach ($treeName in @('resource_tree.vmdl', 'resource_tree.dmx')) {
    $treeDestination = Join-Path $treeContent $treeName
    if (Test-Path -LiteralPath $treeDestination) {
        Copy-Item -LiteralPath $treeDestination -Destination (Join-Path $treeLogs ($treeName + '.before'))
    }
    Copy-Item -LiteralPath (Join-Path $treeRepo ('art/resource_tree/source/models/survival_resources/' + $treeName)) -Destination $treeDestination -Force
}
$treeLog = @(& (Join-Path $treeEngine 'game/bin/win64/resourcecompiler.exe') -i (Join-Path $treeContent 'resource_tree.vmdl') -game (Join-Path $treeEngine 'game/dota') -fshallow -nop4 2>&1)
$treeExit = $LASTEXITCODE
$treeLog | Set-Content -LiteralPath (Join-Path $treeLogs 'compile.log')
$treeLog | Where-Object { $_ -match 'RESOURCE COMPILE|ERROR:|failed' } | Write-Output
if ($treeExit -ne 0 -or -not ($treeLog -match '0 failed')) { throw 'Resource tree compile failed' }
if (-not (Test-Path -LiteralPath (Join-Path $treeRepo 'models/survival_resources/resource_tree.vmdl_c'))) {
    throw 'Compiled resource tree is missing'
}
Write-Output ('RESOURCE_TREE_COMPILE_PASS logs=' + $treeLogs)
