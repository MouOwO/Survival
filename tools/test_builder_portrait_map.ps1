$ErrorActionPreference = 'Stop'
$portraitTestRepo = Split-Path -Parent $PSScriptRoot
$portraitTestSource = Join-Path $PSScriptRoot 'builder_io_portrait.vmap'
$portraitTestBuilder = Join-Path $PSScriptRoot 'build_builder_portrait_map.ps1'
$portraitTestText = [IO.File]::ReadAllText($portraitTestSource)

function Assert-PortraitMap([bool]$condition, [string]$message) {
    if (-not $condition) { throw $message }
}

# Sequence names were read from Valve's io_ti7.vmdl_c ASEQ/ANIM blocks.
# This model does not provide the generic "idle" used by most heroes.
$portraitTestSequences = @('ti7_io_flail', 'ti7_io_disabled', 'ti7_io_idle', 'io_death', 'ti7_io_idle_versus', 'ti7_io_taunt', 'attack')
Assert-PortraitMap ($portraitTestText.Contains('"model" "string" "models/items/io/io_ti7/io_ti7.vmdl"')) 'BUILDER_IO_COMPANION_MODEL_MISSING'
foreach ($portraitTestKey in @('StartingAnim', 'IdleAnim')) {
    $portraitTestMatches = [regex]::Matches($portraitTestText, ('"' + $portraitTestKey + '"\s+"string"\s+"([^"]*)"'))
    Assert-PortraitMap ($portraitTestMatches.Count -eq 1) "BUILDER_IO_ANIMATION_KEY_COUNT: $portraitTestKey"
    $portraitTestSequence = $portraitTestMatches[0].Groups[1].Value
    Assert-PortraitMap ($portraitTestSequences -contains $portraitTestSequence) "BUILDER_IO_UNKNOWN_SEQUENCE: $portraitTestKey=$portraitTestSequence"
    Assert-PortraitMap ($portraitTestSequence -eq 'ti7_io_idle') "BUILDER_IO_UNSTABLE_IDLE: $portraitTestKey=$portraitTestSequence"
}
Assert-PortraitMap ($portraitTestText.Contains('"IdleAnimationLoopMode" "string" "ANIM_LOOP_MODE_LOOPING"')) 'BUILDER_IO_IDLE_LOOP_MISSING'
Assert-PortraitMap ($portraitTestText.Contains('"use_animgraph" "string" "0"')) 'BUILDER_IO_SEQUENCE_DRIVER_CHANGED'
Assert-PortraitMap ($portraitTestText.Contains('"targetname" "string" "builder_io_camera"')) 'BUILDER_IO_CAMERA_MISSING'
Assert-PortraitMap ($portraitTestText.Contains('particles/econ/items/wisp/wisp_ambient_ti7.vpcf')) 'BUILDER_IO_AMBIENT_MISSING'

$portraitTestTokens = $null
$portraitTestErrors = $null
[void][Management.Automation.Language.Parser]::ParseFile($portraitTestBuilder, [ref]$portraitTestTokens, [ref]$portraitTestErrors)
Assert-PortraitMap ($portraitTestErrors.Count -eq 0) 'BUILDER_IO_COMPILER_SCRIPT_PARSE_FAILED'
$portraitTestBuildText = [IO.File]::ReadAllText($portraitTestBuilder)
Assert-PortraitMap ($portraitTestBuildText.Contains("`$ioPortraitMapName = 'builder_io_companion_v2'")) 'BUILDER_IO_VERSIONED_RUNTIME_MISSING'
Assert-PortraitMap (-not $portraitTestBuildText.Contains('builder_io_companion_v1')) 'BUILDER_IO_LOADED_RUNTIME_MUST_NOT_BE_OVERWRITTEN'

# CheckOnly validates the contract without rewriting the map a live client uses.
$portraitTestRuntime = Join-Path $portraitTestRepo 'maps/portraits'
$portraitTestBefore = @{}
if (Test-Path -LiteralPath $portraitTestRuntime) {
    Get-ChildItem -LiteralPath $portraitTestRuntime -File | ForEach-Object { $portraitTestBefore[$_.Name] = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash }
}
$portraitTestResult = @(& $portraitTestBuilder -CheckOnly)
Assert-PortraitMap ($portraitTestResult -contains 'BUILDER_PORTRAIT_MAP_SOURCE_PASS') 'BUILDER_IO_SOURCE_CHECK_FAILED'
$portraitTestAfter = @{}
if (Test-Path -LiteralPath $portraitTestRuntime) {
    Get-ChildItem -LiteralPath $portraitTestRuntime -File | ForEach-Object { $portraitTestAfter[$_.Name] = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash }
}
Assert-PortraitMap ($portraitTestBefore.Count -eq $portraitTestAfter.Count) 'BUILDER_IO_CHECK_ONLY_CHANGED_RUNTIME_FILES'
foreach ($portraitTestName in $portraitTestBefore.Keys) {
    Assert-PortraitMap ($portraitTestBefore[$portraitTestName] -eq $portraitTestAfter[$portraitTestName]) "BUILDER_IO_CHECK_ONLY_CHANGED_RUNTIME: $portraitTestName"
}
Write-Output 'BUILDER_PORTRAIT_MAP_CONTRACT_PASS: Valve-compatible stable idle, explicit looping, unchanged camera/model/ambient dependencies, v2 runtime target, read-only CheckOnly'
