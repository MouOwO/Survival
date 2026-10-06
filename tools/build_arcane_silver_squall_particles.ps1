$ErrorActionPreference = 'Stop'
$arcaneRepo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$arcaneEngine = (Resolve-Path (Join-Path $arcaneRepo '../../..')).Path
$arcaneManifest = Get-Content (Join-Path $arcaneRepo 'art/effects/arcane_silver_squall/manifest.json') -Raw | ConvertFrom-Json
$arcaneOutput = Join-Path $arcaneRepo 'output/arcane_silver_squall'
New-Item -ItemType Directory -Force -Path $arcaneOutput | Out-Null
foreach ($resource in $arcaneManifest.outputs) {
    if ($resource -notmatch '^particles/survival/skills/arcane_silver_squall_(?:impact|field)(?:_[a-z_]+)?\.vpcf$') { throw "Unexpected Arcane Silver Squall path: $resource" }
    $arcaneDestination = Join-Path $arcaneEngine ('content/dota_addons/survival/' + $resource)
    if (Test-Path -LiteralPath $arcaneDestination) {
        $arcaneBackup = Join-Path $arcaneOutput ('content_backup/' + $resource)
        if (-not (Test-Path -LiteralPath $arcaneBackup)) {
            New-Item -ItemType Directory -Force -Path (Split-Path $arcaneBackup) | Out-Null
            Copy-Item -LiteralPath $arcaneDestination -Destination $arcaneBackup
        }
    }
    New-Item -ItemType Directory -Force -Path (Split-Path $arcaneDestination) | Out-Null
    Copy-Item -LiteralPath (Join-Path $arcaneRepo ('art/effects/arcane_silver_squall/source/' + $resource)) -Destination $arcaneDestination -Force
}
foreach ($resource in $arcaneManifest.outputs) {
    $arcaneDestination = Join-Path $arcaneEngine ('content/dota_addons/survival/' + $resource)
    $arcaneLog = @(& (Join-Path $arcaneEngine 'game/bin/win64/resourcecompiler.exe') -i $arcaneDestination -game (Join-Path $arcaneEngine 'game/dota') -fshallow -nop4 2>&1)
    $arcaneExitCode = $LASTEXITCODE
    $arcaneLog | Set-Content (Join-Path $arcaneOutput ('compile_' + [IO.Path]::GetFileName($resource) + '.log'))
    $arcaneLog | Where-Object { $_ -match 'RESOURCE COMPILE|ERROR:|failed' } | Write-Output
    if ($arcaneExitCode -ne 0 -or -not ($arcaneLog -match '0 failed')) { throw "Arcane Silver Squall compile failed: $resource" }
    if (-not (Test-Path -LiteralPath (Join-Path $arcaneRepo ($resource + '_c')))) { throw "Compiled Arcane Silver Squall missing: $resource" }
}
Write-Output ('ARCANE_SILVER_SQUALL_COMPILE_PASS particles=' + $arcaneManifest.outputs.Count)
