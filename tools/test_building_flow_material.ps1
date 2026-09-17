param([string]$Viewer = (Join-Path $env:LOCALAPPDATA 'Temp/source2viewer-cli/Source2Viewer-CLI.exe'))
$ErrorActionPreference='Stop'
$flowGame=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$flowStage=Join-Path $flowGame 'output/building_presentation'
$flowInspector=[IO.Path]::GetFullPath((Join-Path $flowGame '../../bin/win64/resourceinfo.exe'))
$flowTextures=@()
for ($flowStep=0;$flowStep -le 48;$flowStep++) {
    $flowName='build_flow_{0:d2}.vmat' -f $flowStep
    $flowSource=Join-Path $flowStage ('source/materials/survival_buildings/'+$flowName)
    $flowCompiled=Join-Path $flowGame ('materials/survival_buildings/'+$flowName+'_c')
    if ((Get-Item $flowCompiled).LastWriteTimeUtc -lt (Get-Item $flowSource).LastWriteTimeUtc) { throw "Stale $flowName" }
    $flowDump=(& $flowInspector -i $flowCompiled -all | Out-String)
    if ($LASTEXITCODE -ne 0 -or $flowDump -notmatch 'translucent = 1' -or $flowDump -notmatch 'm_name = "F_SEPARATE_ALPHA_TRANSFORM"') { throw "Missing alpha transform: $flowName" }
    if ($flowDump -notmatch 'm_dynamicParams =\s*\[\s*\{\s*m_name = "g_vTexCoordOffset"\s*m_value = #\[') { throw "Missing animated color UVs: $flowName" }
    if ($flowDump -notmatch 'build_flow_mask.png' -or $flowDump -notmatch 'm_name = "g_tNormal"') { throw "Missing mask / normals: $flowName" }
    $flowOffsetMatch=[regex]::Match($flowDump,'m_name = "g_vAlphaTexCoordOffset"\s*m_value = \[ ([^\]]+)')
    if (-not $flowOffsetMatch.Success) { throw "Missing reveal offset: $flowName" }
    $flowOffset=[double]($flowOffsetMatch.Groups[1].Value.Split(',')[1])
    if ([Math]::Abs($flowOffset-$flowStep*0.01) -gt 0.00001) { throw "Incorrect reveal offset: $flowName" }
    $flowMatch=[regex]::Match($flowDump,'m_name = "g_tColor"\s*m_pValue = resource:"([^"]+)"')
    if (-not $flowMatch.Success) { throw "Missing packed texture: $flowName" }
    $flowTextures+=$flowMatch.Groups[1].Value
}
if (@($flowTextures | Select-Object -Unique).Count -ne 1) { throw 'Reveal materials must share one packed texture' }
$flowTexture=$flowTextures[0]
$flowDecode=Join-Path $flowStage 'flow_material_check'
New-Item -ItemType Directory -Force -Path $flowDecode | Out-Null
$flowPng=Join-Path $flowDecode ([IO.Path]::GetFileNameWithoutExtension($flowTexture)+'.png')
& $Viewer -i (Join-Path $flowGame ($flowTexture+'_c')) -o $flowPng -d *> (Join-Path $flowStage 'flow_material_decode.log')
if ($LASTEXITCODE -ne 0) { throw 'Cannot decode compiled flow texture' }
Add-Type -AssemblyName System.Drawing
$flowImage=[Drawing.Bitmap]::FromFile($flowPng)
try {
    $flowAlphas=@();$flowUniqueColors=@{}
    for ($flowY=0;$flowY -lt $flowImage.Height;$flowY++) {
        $flowAlphas+=[int]$flowImage.GetPixel(100,$flowY).A
        for ($flowX=0;$flowX -lt $flowImage.Width;$flowX+=8) {
            $flowPixel=$flowImage.GetPixel($flowX,$flowY)
            $flowUniqueColors[('{0},{1},{2}' -f $flowPixel.R,$flowPixel.G,$flowPixel.B)]=$true
        }
    }
    if ($flowAlphas[25] -ne 255 -or $flowAlphas[204] -ne 255 -or $flowAlphas[230] -le 0 -or $flowAlphas[230] -ge 255 -or $flowAlphas[260] -ne 0) { throw 'Compiled alpha mask is missing or has no feather' }
    for ($flowY=1;$flowY -lt $flowAlphas.Count;$flowY++) { if ($flowAlphas[$flowY] -gt $flowAlphas[$flowY-1]) { throw 'Mask reverses its reveal direction' } }
    if ($flowUniqueColors.Count -lt 100) { throw 'Flow color is flat' }
    $flowStages=@()
    foreach ($flowStep in @(0,24,48)) {
        $flowFloorAlpha=$flowAlphas[[int][Math]::Floor((0.05+$flowStep*0.01)*$flowImage.Height)]
        $flowRoofAlpha=$flowAlphas[[int][Math]::Floor((0.40+$flowStep*0.01)*$flowImage.Height)]
        $flowStages+=@{step=$flowStep;floor_alpha=$flowFloorAlpha;roof_alpha=$flowRoofAlpha}
    }
    if ($flowStages[0].roof_alpha -ne 255 -or $flowStages[1].roof_alpha -ne 0 -or $flowStages[1].floor_alpha -ne 255 -or $flowStages[2].floor_alpha -ne 0) { throw 'Roof must reveal before floor' }
    @{status='PASS';materials=49;compiled_texture=$flowTexture;unique_colors=$flowUniqueColors.Count;stages=$flowStages;animated_color_uv=$true;separate_alpha_uv=$true} | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $flowStage 'flow_material_verification.json') -Encoding UTF8
} finally { $flowImage.Dispose() }
Write-Output 'BUILDING_FLOW_MATERIAL_PASS materials=49 alpha=top_to_bottom animated_color_uv=true'
