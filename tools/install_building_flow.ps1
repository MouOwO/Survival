param([string[]]$ModelNames, [switch]$ModelsOnly, [switch]$MaterialsOnly)
$ErrorActionPreference='Stop'
$flowGame=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$flowContent=[IO.Path]::GetFullPath((Join-Path $flowGame '../../../content/dota_addons/survival'))
$flowCompiler=[IO.Path]::GetFullPath((Join-Path $flowGame '../../bin/win64/resourcecompiler.exe'))
$flowStage=Join-Path $flowGame 'output/building_presentation'
$flowModelStage=Join-Path $flowGame 'output/unique_buildings'
if (-not $ModelNames) { $ModelNames=@((Get-Content -LiteralPath (Join-Path $flowModelStage 'manifest.json') -Raw | ConvertFrom-Json).name) }
$flowFiles=@()
if (-not $ModelsOnly) {
    $flowMaterialDir=Join-Path $flowStage 'source/materials/survival_buildings'
    $flowMaterialTarget=Join-Path $flowContent 'materials/survival_buildings'
    New-Item -ItemType Directory -Force -Path $flowMaterialTarget | Out-Null
    foreach ($flowTexture in @('build_flow_color.png','build_flow_normal.png','build_flow_mask.png')) {
        Copy-Item -LiteralPath (Join-Path $flowMaterialDir $flowTexture) -Destination (Join-Path $flowMaterialTarget $flowTexture) -Force
    }
    foreach ($flowMat in Get-ChildItem -LiteralPath $flowMaterialDir -Filter 'build_flow_*.vmat' -File) {
        $flowTarget=Join-Path $flowMaterialTarget $flowMat.Name
        Copy-Item -LiteralPath $flowMat.FullName -Destination $flowTarget -Force
        $flowFiles+=Get-Item -LiteralPath $flowTarget
    }
}
foreach ($flowName in $(if ($MaterialsOnly) { @() } else { $ModelNames })) {
    foreach ($flowExtension in @('_flow.fbx','_white_shell.vmdl')) {
        $flowRelative='models/survival_buildings/'+$flowName+$flowExtension
        $flowTarget=Join-Path $flowContent $flowRelative
        Copy-Item -LiteralPath (Join-Path $flowModelStage ('source/'+$flowRelative)) -Destination $flowTarget -Force
        if ($flowExtension -eq '_white_shell.vmdl') { $flowFiles+=Get-Item -LiteralPath $flowTarget }
    }
}
foreach ($flowFile in $flowFiles) {
    $flowLog=Join-Path $flowStage ($flowFile.Name+'.flow.compile.log')
    & $flowCompiler -i $flowFile.FullName -game (Join-Path $flowGame '../../dota') -f *> $flowLog
    if ($LASTEXITCODE -ne 0 -or -not (Select-String -LiteralPath $flowLog -Pattern '0 failed')) { throw "Flow compilation failed: $flowLog" }
    Write-Output ('Compiled '+$flowFile.Name)
}
