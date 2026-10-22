$ErrorActionPreference = 'Stop'
$richRepo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$richEngine = (Resolve-Path (Join-Path $richRepo '../../..')).Path
$richLogs = Join-Path $richRepo 'tmp/portal_native_graph_20261022/rich_compile'
New-Item -ItemType Directory -Force -Path $richLogs | Out-Null
& node (Join-Path $PSScriptRoot 'map_c6/build-rich-portal-particles.cjs')
if ($LASTEXITCODE -ne 0) { throw 'Rich portal source generation failed' }
$richManifest = Get-Content -LiteralPath (Join-Path $richRepo 'art/effects/rich_portal/manifest.json') -Raw | ConvertFrom-Json
foreach ($richRow in $richManifest.outputs) {
    $richTarget = Join-Path $richEngine ('content/dota_addons/Survival/' + $richRow.resource)
    $richSource = Join-Path $richRepo ('art/effects/rich_portal/source/' + $richRow.resource)
    if (Test-Path -LiteralPath $richTarget) {
        $richCurrent = (Get-FileHash -LiteralPath $richTarget -Algorithm SHA256).Hash
        $richExpected = (Get-FileHash -LiteralPath $richSource -Algorithm SHA256).Hash
        if ($richCurrent -ne $richExpected) {
            $richBackup = Join-Path $richLogs ('before/' + $richRow.resource)
            New-Item -ItemType Directory -Force -Path (Split-Path -Parent $richBackup) | Out-Null
            Copy-Item -LiteralPath $richTarget -Destination $richBackup -Force
        }
    }
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $richTarget) | Out-Null
    Copy-Item -LiteralPath $richSource -Destination $richTarget -Force
}
foreach ($richRow in $richManifest.outputs) {
    $richTarget = Join-Path $richEngine ('content/dota_addons/Survival/' + $richRow.resource)
    $richLog = @(& (Join-Path $richEngine 'game/bin/win64/resourcecompiler.exe') -i $richTarget -game (Join-Path $richEngine 'game/dota') -fshallow -nop4 2>&1)
    $richExit = $LASTEXITCODE
    $richLog | Set-Content -LiteralPath (Join-Path $richLogs ([IO.Path]::GetFileName($richRow.resource) + '.log')) -Encoding utf8
    $richLog | Where-Object { $_ -match 'RESOURCE COMPILE|ERROR:|failed' } | Write-Output
    if ($richExit -ne 0 -or -not ($richLog -match '0 failed') -or $richLog -match 'LoadKV3ObjectInPlace error|ERROR:') { throw "Rich portal compile failed: $($richRow.resource)" }
    if (-not (Test-Path -LiteralPath (Join-Path $richRepo ($richRow.resource + '_c')))) { throw "Compiled resource missing: $($richRow.resource)" }
}
# Source 2 omits default schema values in serialized DATA. A counterexample
# confirms that scale booleans and the external CP are recognized fields;
# these scratch resources stay under ignored tmp, outside the delivered graph.
$richProbeDirectory = Join-Path $richEngine 'content/dota_addons/Survival/tmp/portal_native_graph_20261022/schema'
New-Item -ItemType Directory -Force -Path $richProbeDirectory | Out-Null
$richProbeHeader = '<!-- kv3 encoding:text:version{e21c7f3c-8a33-41c5-9977-a76d3a32aa0d} format:vpcf45:version{73c3d623-a141-4df2-b548-41dd786e6300} -->'
$richProbeSources = @{
    'defaults' = '{ _class = "CParticleSystemDefinition" m_nMaxParticles = 1 m_Initializers = [ { _class = "C_INIT_GlobalScale" } ] }'
    'counterexample' = '{ _class = "CParticleSystemDefinition" m_nMaxParticles = 1 m_Initializers = [ { _class = "C_INIT_GlobalScale" m_flScale = 3.0 m_nScaleControlPointNumber = 17 m_nControlPointNumber = 2 m_bScaleRadius = false m_bScalePosition = false m_bScaleVelocity = false } ] }'
}
foreach ($richProbe in $richProbeSources.GetEnumerator()) {
    $richProbeFile = Join-Path $richProbeDirectory ($richProbe.Key + '.vpcf')
    [IO.File]::WriteAllText($richProbeFile, $richProbeHeader + "`n" + $richProbe.Value + "`n", (New-Object Text.UTF8Encoding($false)))
    $richProbeLog = @(& (Join-Path $richEngine 'game/bin/win64/resourcecompiler.exe') -i $richProbeFile -game (Join-Path $richEngine 'game/dota') -fshallow -nop4 2>&1)
    $richProbeExit = $LASTEXITCODE
    $richProbeLog | Set-Content -LiteralPath (Join-Path $richLogs ('schema_' + $richProbe.Key + '.log')) -Encoding utf8
    if ($richProbeExit -ne 0 -or -not ($richProbeLog -match '0 failed') -or $richProbeLog -match 'ERROR:') { throw 'Native GlobalScale schema probe failed' }
}
& node (Join-Path $PSScriptRoot 'verify_rich_portal_particles.cjs')
if ($LASTEXITCODE -ne 0) { throw 'Rich portal compiled verification failed' }
Write-Output 'RICH_PORTAL_COMPILE_PASS'
