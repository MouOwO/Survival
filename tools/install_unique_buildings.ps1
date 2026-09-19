param([switch]$ModelsOnly, [switch]$WhiteShellsOnly)
$ErrorActionPreference = 'Stop'
$buildingGame = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$buildingContent = 'D:/steam/steamapps/common/dota 2 beta/content/dota_addons/survival'
$buildingStage = Join-Path $buildingGame 'output/unique_buildings'
$buildingCompiler = 'D:/steam/steamapps/common/dota 2 beta/game/bin/win64/resourcecompiler.exe'
$buildingNames = @((Get-Content -LiteralPath (Join-Path $buildingStage 'manifest.json') -Raw | ConvertFrom-Json).name)
$buildingShellNames = @($buildingNames | ForEach-Object { $_ + '_white_shell' })
if ($WhiteShellsOnly) { $buildingNames = $buildingShellNames } else { $buildingNames += $buildingShellNames }
$buildingKinds = if ($ModelsOnly -or $WhiteShellsOnly) { @('models') } else { @('materials','models') }
foreach ($buildingKind in $buildingKinds) {
    $buildingRelative = "$buildingKind/survival_buildings"
    $buildingDestination = Join-Path $buildingContent $buildingRelative
    New-Item -ItemType Directory -Path $buildingDestination -Force | Out-Null
    Get-ChildItem -LiteralPath (Join-Path $buildingStage "source/$buildingRelative") -File | ForEach-Object {
        Copy-Item -LiteralPath $_.FullName -Destination $buildingDestination -Force
    }
    $buildingExtension = if ($buildingKind -eq 'models') { '*.vmdl' } else { '*.vmat' }
    foreach ($buildingFile in Get-ChildItem -LiteralPath $buildingDestination -Filter $buildingExtension) {
        # Revision 3 exports one baked material per model. Palette materials are
        # authoring inputs only and need no runtime compilation.
        if ($buildingFile.BaseName -notin $buildingNames) { continue }
        $buildingLog = Join-Path $buildingStage ($buildingFile.Name + '.log')
        & $buildingCompiler -i $buildingFile.FullName -game 'D:/steam/steamapps/common/dota 2 beta/game/dota' -f *> $buildingLog
        $buildingResult = Join-Path $buildingGame ($buildingRelative+'/'+$buildingFile.Name+'_c')
        if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $buildingResult) -or -not (Select-String -LiteralPath $buildingLog -Pattern '0 failed')) {
            throw "Building resource failed: $($buildingFile.Name); see $buildingLog"
        }
        Write-Output "Compiled $($buildingFile.Name)"
    }
}
