param([string]$Viewer = (Join-Path $env:LOCALAPPDATA 'Temp/source2viewer-cli/Source2Viewer-CLI.exe'))
$ErrorActionPreference = 'Stop'
$whiteGame = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$whiteStage = Join-Path $whiteGame 'output/building_presentation'
$whiteInspector = [IO.Path]::GetFullPath((Join-Path $whiteGame '../../bin/win64/resourceinfo.exe'))
$whiteMaterial = Join-Path $whiteGame 'materials/survival_buildings/build_white_glow.vmat_c'
$whiteDump = (& $whiteInspector -i $whiteMaterial -all | Out-String)
if ($LASTEXITCODE -ne 0) { throw 'Cannot inspect compiled white material' }
$whiteDump | Set-Content -LiteralPath (Join-Path $whiteStage 'build_white_glow_compiled.txt') -Encoding UTF8
if ($whiteDump -notmatch 'F_FULLBRIGHT = 1' -or $whiteDump -notmatch 'F_TRANSLUCENT = 1') {
    throw 'Compiled white material is missing fullbright/translucent rendering'
}
$whiteTextureMatch = [regex]::Match($whiteDump, 'resource:"(materials/survival_buildings/[^"\r\n]+\.vtex)"')
if (-not $whiteTextureMatch.Success) { throw 'White material has no compiled color texture' }
$whiteTextureRelative = $whiteTextureMatch.Groups[1].Value
$whiteTexture = Join-Path $whiteGame ($whiteTextureRelative + '_c')
if (-not (Test-Path -LiteralPath $whiteTexture)) { throw "Missing texture: $whiteTextureRelative" }
$whiteDecode = Join-Path $whiteStage 'white_material_check'
New-Item -ItemType Directory -Path $whiteDecode -Force | Out-Null
$whitePng = Join-Path $whiteDecode ([IO.Path]::GetFileNameWithoutExtension($whiteTextureRelative) + '.png')
& $Viewer -i $whiteTexture -o $whitePng -d *> (Join-Path $whiteStage 'white_material_decode.log')
if ($LASTEXITCODE -ne 0) { throw 'Cannot decode compiled white texture' }
Add-Type -AssemblyName System.Drawing
$whiteImage = [Drawing.Bitmap]::FromFile($whitePng)
$whiteMinimum = @(255,255,255,255)
$whiteMaximum = @(0,0,0,0)
try {
    for ($whiteY = 0; $whiteY -lt $whiteImage.Height; $whiteY++) {
        for ($whiteX = 0; $whiteX -lt $whiteImage.Width; $whiteX++) {
            $whitePixel = $whiteImage.GetPixel($whiteX, $whiteY)
            $whiteChannels = @([int]$whitePixel.R,[int]$whitePixel.G,[int]$whitePixel.B,[int]$whitePixel.A)
            for ($whiteChannel = 0; $whiteChannel -lt 4; $whiteChannel++) {
                $whiteMinimum[$whiteChannel] = [Math]::Min($whiteMinimum[$whiteChannel],$whiteChannels[$whiteChannel])
                $whiteMaximum[$whiteChannel] = [Math]::Max($whiteMaximum[$whiteChannel],$whiteChannels[$whiteChannel])
            }
        }
    }
    $whitePassed = $whiteMinimum[0] -ge 250 -and $whiteMinimum[1] -ge 250 -and $whiteMinimum[2] -ge 250 -and $whiteMinimum[3] -eq 255
    [ordered]@{
        status = $(if ($whitePassed) { 'PASS' } else { 'FAIL' })
        compiled_texture = $whiteTextureRelative
        width = $whiteImage.Width; height = $whiteImage.Height
        minimum_rgba = $whiteMinimum; maximum_rgba = $whiteMaximum
    } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $whiteStage 'white_material_verification.json') -Encoding UTF8
    if (-not $whitePassed) { throw "White light texture is dark or transparent: min RGBA=$($whiteMinimum -join ',')" }
} finally {
    $whiteImage.Dispose()
}
Write-Output "BUILDING_WHITE_MATERIAL_PASS compiled_min_RGBA=$($whiteMinimum -join ',')"
