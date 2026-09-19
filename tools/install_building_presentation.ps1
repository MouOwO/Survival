param([switch]$ParticlesOnly)
$ErrorActionPreference = 'Stop'
$presentationGame = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$presentationContent = [IO.Path]::GetFullPath((Join-Path $presentationGame '../../../content/dota_addons/survival'))
$presentationStage = Join-Path $presentationGame 'output/building_presentation'
$presentationCompiler = [IO.Path]::GetFullPath((Join-Path $presentationGame '../../bin/win64/resourcecompiler.exe'))
$presentationSources = Join-Path $presentationStage 'source'
$presentationFiles = @(Get-Item -LiteralPath (Join-Path $presentationSources 'materials/survival_buildings/build_white_glow.vmat'))
foreach ($presentationParticle in @('white_build_channel', 'white_build_reveal')) {
    $presentationFiles += Get-Item -LiteralPath (Join-Path $presentationSources ('particles/survival_buildings/' + $presentationParticle + '.vpcf'))
}
if (-not $ParticlesOnly) {
    $presentationFiles += Get-Item -LiteralPath (Join-Path $presentationSources 'panorama/scripts/custom_game/survival_grid_placement.js')
}
$presentationInputs = @($presentationFiles)
$presentationInputs += Get-Item -LiteralPath (Join-Path $presentationSources 'materials/survival_buildings/build_white_glow_color.png')
foreach ($presentationFile in $presentationInputs) {
    $presentationRelative = $presentationFile.FullName.Substring($presentationSources.Length + 1)
    $presentationTarget = Join-Path $presentationContent $presentationRelative
    New-Item -ItemType Directory -Path (Split-Path $presentationTarget) -Force | Out-Null
    Copy-Item -LiteralPath $presentationFile.FullName -Destination $presentationTarget -Force
}
foreach ($presentationFile in $presentationFiles) {
    $presentationRelative = $presentationFile.FullName.Substring($presentationSources.Length + 1)
    $presentationTarget = Join-Path $presentationContent $presentationRelative
    $presentationLog = Join-Path $presentationStage ($presentationFile.Name + '.compile.log')
    & $presentationCompiler -i $presentationTarget -game (Join-Path $presentationGame '../../dota') -f *> $presentationLog
    if ($LASTEXITCODE -ne 0 -or -not (Select-String -LiteralPath $presentationLog -Pattern '0 failed')) {
        throw "Presentation compilation failed: $presentationTarget; see $presentationLog"
    }
    Write-Output "Compiled $($presentationFile.Name)"
}
