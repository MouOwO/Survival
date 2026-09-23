$ErrorActionPreference = 'Stop'
$verify = Join-Path $PSScriptRoot 'verify_minimap_sync.ps1'
$repair = Join-Path $PSScriptRoot 'repair_minimap_client.ps1'
$fixtureOutput = Join-Path ([IO.Path]::GetTempPath()) 'SurvivalMinimapOfflineTests'
# Source 2 scans VPKs below the addon, including ignored output directories.
# Synthetic test packages must never be created anywhere inside the game tree.
$fixtureOutput = [IO.Path]::GetFullPath($fixtureOutput)
$engineRoot = [IO.Path]::GetFullPath((Join-Path (Split-Path -Parent $PSScriptRoot) '../../..'))
if ($fixtureOutput.TrimEnd('\', '/') -eq $engineRoot.TrimEnd('\', '/') -or $fixtureOutput.StartsWith($engineRoot.TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'MINIMAP_TEST_TEMP_MUST_BE_OUTSIDE_ENGINE: refusing synthetic VPK inside the Dota installation'
}
$root = Join-Path $fixtureOutput ('offline_fixture_' + [Guid]::NewGuid().ToString('N'))
$game = Join-Path $root 'game/dota_addons/survival'
$content = Join-Path $root 'content/dota_addons/survival'
foreach ($directory in @('resource/overviews', 'materials/overviews', 'maps', 'tools/map_c6')) { $null = New-Item -ItemType Directory -Path (Join-Path $game $directory) -Force }
foreach ($directory in @('materials/overviews', 'maps')) { $null = New-Item -ItemType Directory -Path (Join-Path $content $directory) -Force }
$encoder = [Text.UTF8Encoding]::new($false)
function Write-Text([string]$path, [string]$value) { [IO.File]::WriteAllText($path, $value, $encoder) }
function Assert($value, [string]$message) { if (-not $value) { throw "TEST_FAILED: $message" } }
function Fails([scriptblock]$action, [string]$code) {
    try { $null = & $action } catch { Assert ($_.Exception.Message.Contains($code)) "wrong failure, expected $code, got $($_.Exception.Message)"; return }
    throw "TEST_FAILED: expected $code"
}
$overview = Join-Path $game 'resource/overviews/template_map.txt'
$material = Join-Path $content 'materials/overviews/renamed_current.vmat'
$image = Join-Path $content 'materials/overviews/renamed_image.tga'
$compiledMaterial = Join-Path $game 'materials/overviews/renamed_current.vmat_c'
$compiledTexture = Join-Path $game 'materials/overviews/renamed_image_tga_abcdef12.vtex_c'
$overviewText = "template_map`n{`n material materials/overviews/renamed_current.vmat`n pos_x -16384`n pos_y 16384`n scale 32.000`n}"
$materialText = "`"Layer0`"`n{`n `"Shader`" `"ui.vfx`"`n `"Texture`" `"materials/overviews/renamed_image.tga`"`n}"
Write-Text $overview $overviewText
Write-Text $material $materialText
Write-Text (Join-Path $content 'materials/overviews/renamed_image.txt') "`"clampu`" `"1`"`n`"clampv`" `"1`"`n`"nocompress`" `"1`"`n`"nomip`" `"1`""
$pixels = New-Object byte[] (18 + 2048 * 2048 * 3)
$pixels[2] = 2; $pixels[13] = 8; $pixels[15] = 8; $pixels[16] = 24
[IO.File]::WriteAllBytes($image, $pixels)
Write-Text (Join-Path $content 'maps/template_map.vmap') 'fixture source'
Write-Text (Join-Path $game 'maps/template_map.vpk') 'fixture map'
Write-Text $compiledMaterial "header`0materials/overviews/renamed_image_tga_abcdef12.vtex`0end"
Write-Text $compiledTexture "header`0materials/overviews/renamed_image.tga`0end"
$now = [DateTime]::UtcNow
(Get-Item -LiteralPath (Join-Path $content 'maps/template_map.vmap')).LastWriteTimeUtc = $now.AddSeconds(-30)
(Get-Item -LiteralPath (Join-Path $game 'maps/template_map.vpk')).LastWriteTimeUtc = $now.AddSeconds(-20)
(Get-Item -LiteralPath $image).LastWriteTimeUtc = $now.AddSeconds(-10)
$arguments = @{ GameRoot = $game; ContentRoot = $content; ExpectedOutputSize = 2048; AsObject = $true }
$report = & $verify @arguments
Assert ($report.status -eq 'resource_chain_pass' -and $report.material -eq 'materials/overviews/renamed_current.vmat' -and $report.compiled_texture -eq 'materials/overviews/renamed_image_tga_abcdef12.vtex_c') 'actual renamed dependency chain must be used'
Assert ($report.tga.width -eq 2048 -and $report.bounds.max_x -eq 16384 -and $report.bounds.min_y -eq -16384) '2048 pixels must not change scale32 world bounds'
Assert (-not $report.compiler_dependencies_checked -and -not $report.visual_current_map_verified) 'offline checks must not claim engine/CRC verification'
Write-Host 'PASS dynamic names, 2048 dimensions, independent world bounds, verification limits'

Write-Text $overview ($overviewText.Replace('-16384', '-8192'))
Fails { & $verify @arguments } 'MINIMAP_OVERVIEW_BOUNDS_MISMATCH'
Write-Text $overview $overviewText
Write-Text $material ($materialText.Replace('materials/overviews/renamed_image.tga', 'materials/../outside.tga'))
Fails { & $verify @arguments } 'MINIMAP_UNSAFE_RESOURCE_PATH'
Write-Text $material $materialText
(Get-Item -LiteralPath $compiledMaterial).LastWriteTimeUtc = [DateTime]::UtcNow
Write-Text $compiledMaterial 'materials/overviews/old_image_tga_00000000.vtex'
Fails { & $verify @arguments } 'MINIMAP_COMPILED_TEXTURE_REFERENCE_MISSING_OR_AMBIGUOUS'
Write-Text $compiledMaterial "header`0materials/overviews/renamed_image_tga_abcdef12.vtex`0end"
Write-Text $compiledTexture 'materials/overviews/unrelated.tga'
Fails { & $verify @arguments } 'MINIMAP_COMPILED_TEXTURE_SOURCE_REFERENCE_MISSING'
Write-Text $compiledTexture "header`0materials/overviews/renamed_image.tga`0end"
Write-Host 'PASS wrong bounds, path traversal, stale VMAT reference, wrong texture input rejected'

(Get-Item -LiteralPath $image).LastWriteTimeUtc = $now.AddSeconds(-50)
Fails { & $verify @arguments } 'MINIMAP_IMAGE_OLDER_THAN_MAP'
$sourceOnly = & $verify @arguments -SourceOnly
Assert ($sourceOnly.status -eq 'source_validated_only') 'source preflight must allow an old image to be refreshed'
(Get-Item -LiteralPath $image).LastWriteTimeUtc = $now.AddSeconds(-10)
$headerOnly = New-Object byte[] 18
[Array]::Copy($pixels, $headerOnly, 18)
[IO.File]::WriteAllBytes($image, $headerOnly)
Fails { & $verify @arguments } 'MINIMAP_TGA_PIXEL_DATA_TRUNCATED'
[IO.File]::WriteAllBytes($image, $pixels)
(Get-Item -LiteralPath $image).LastWriteTimeUtc = $now.AddSeconds(-10)
Write-Host 'PASS stale image and truncated pixel data rejected'

$vtex = Join-Path $content 'materials/overviews/explicit_input.vtex'
Write-Text $vtex '"m_fileName" "string" "./renamed_image.tga"'
Write-Text $material ($materialText.Replace('renamed_image.tga', 'explicit_input.vtex'))
Write-Text $compiledMaterial "header`0materials/overviews/explicit_input.vtex`0end"
Write-Text (Join-Path $game 'materials/overviews/explicit_input.vtex_c') "header`0materials/overviews/renamed_image.tga`0end"
$explicit = & $verify @arguments
Assert ($explicit.compiled_texture -eq 'materials/overviews/explicit_input.vtex_c' -and $explicit.source_image -eq 'materials/overviews/renamed_image.tga') 'explicit VTEX single TGA chain'
Write-Host 'PASS explicit VTEX input dependency'

$json = Join-Path $root 'report.json'
$null = & $verify @arguments -ReportPath $json
Fails { & $verify @arguments -ReportPath $json } 'MINIMAP_REPORT_ALREADY_EXISTS'
Write-Host 'PASS acceptance reports cannot be overwritten'

# WhatIf is fully offline; a non-executable sentinel makes any accidental tool
# invocation fail, and the console file would throw if Node were ever invoked.
$fakeCompiler = Join-Path $root 'never_execute_resourcecompiler.exe'
Write-Text $fakeCompiler 'not executable'
Write-Text (Join-Path $game 'tools/map_c6/console.cjs') 'throw new Error("console must not run in WhatIf");'
$sourceHash = (Get-FileHash -LiteralPath (Join-Path $content 'maps/template_map.vmap')).Hash
$packageHash = (Get-FileHash -LiteralPath (Join-Path $game 'maps/template_map.vpk')).Hash
& $repair -GameRoot $game -ContentRoot $content -ResourceCompiler $fakeCompiler -WhatIf
Assert (-not (Test-Path -LiteralPath (Join-Path $game 'output'))) 'WhatIf must not create requests/backups or contact console'
Assert ($sourceHash -eq (Get-FileHash -LiteralPath (Join-Path $content 'maps/template_map.vmap')).Hash -and $packageHash -eq (Get-FileHash -LiteralPath (Join-Path $game 'maps/template_map.vpk')).Hash) 'map inputs unchanged'
Write-Host 'PASS repair WhatIf never invokes console/compiler and leaves map inputs untouched'
Write-Host "MINIMAP_OFFLINE_TESTS_PASS fixture=$root"
