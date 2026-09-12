param(
    [switch]$SkipCompile,
    [switch]$SceneAndPanoramaOnly
)

$ErrorActionPreference = 'Stop'
$ToolsRoot = $PSScriptRoot
$RepoRoot = Split-Path -Parent $ToolsRoot
$GameAddonsRoot = Split-Path -Parent $RepoRoot
$GameRoot = Split-Path -Parent $GameAddonsRoot
$DotaRoot = Split-Path -Parent $GameRoot
$ContentAddonsRoot = Join-Path $DotaRoot 'content\dota_addons'
$DotaGameRoot = Join-Path $GameRoot 'dota'
$SpikeRoot = Join-Path $RepoRoot 'ui\portrait_world_unit_phase2a'
$StageCsv = Join-Path $SpikeRoot 'data\axe_stages.csv'
$RendererSanityCsv = Join-Path $SpikeRoot 'data\renderer_sanity_control.csv'
$ContentSource = Join-Path $SpikeRoot 'content'
$RuntimeSource = Join-Path $SpikeRoot 'runtime'
$ContentTarget = Join-Path $ContentAddonsRoot 'survival_phase2a'
$GameTarget = Join-Path $GameAddonsRoot 'survival_phase2a'
$OfficialPrefab = Join-Path $DotaRoot 'content\dota\maps\prefabs\hero_showcase_wind_ranger_default_prefab.vmap'
$PlayableTemplate = Join-Path $ContentAddonsRoot 'addon_template\maps\template_map.vmap'
$DmxConvert = Join-Path $GameRoot 'bin\win64\dmxconvert.exe'
$ResourceCompiler = Join-Path $GameRoot 'bin\win64\resourcecompiler.exe'
$ContractTest = Join-Path $ToolsRoot 'test_portrait_world_unit_phase2a_contract.ps1'
$BuildLog = Join-Path $env:TEMP 'survival_phase2a_resource_compile.log'
$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)

function Check([bool]$condition, [string]$message) {
    if (-not $condition) { throw $message }
}

function Get-RowValue($row, [string]$name) {
    $property = $row.PSObject.Properties[$name]
    Check ($null -ne $property) "CSV_COLUMN_MISSING: $name"
    return [string]$property.Value
}

function Set-StringPropertyAfterAnchor(
    [string]$text,
    [string]$anchor,
    [string]$property,
    [string]$value
) {
    $anchorIndex = $text.IndexOf($anchor, [StringComparison]::Ordinal)
    Check ($anchorIndex -ge 0) "VMAP_ANCHOR_MISSING: $anchor"
    $needle = '"' + $property + '" "string" "'
    $propertyIndex = $text.IndexOf($needle, $anchorIndex, [StringComparison]::Ordinal)
    Check ($propertyIndex -ge 0) "VMAP_PROPERTY_MISSING: $property"
    $valueStart = $propertyIndex + $needle.Length
    $valueEnd = $text.IndexOf('"', $valueStart)
    Check ($valueEnd -ge 0) "VMAP_PROPERTY_UNTERMINATED: $property"
    return $text.Substring(0, $valueStart) + $value + $text.Substring($valueEnd)
}

function Set-OrAddStringPropertyAfterAnchor(
    [string]$text,
    [string]$anchor,
    [string]$property,
    [string]$value
) {
    $anchorIndex = $text.IndexOf($anchor, [StringComparison]::Ordinal)
    Check ($anchorIndex -ge 0) "VMAP_ANCHOR_MISSING: $anchor"
    $entityEnd = $text.IndexOf('"CMapEntity"', $anchorIndex, [StringComparison]::Ordinal)
    Check ($entityEnd -gt $anchorIndex) "VMAP_ENTITY_END_MISSING: $anchor"
    $needle = '"' + $property + '" "string" "'
    $propertyIndex = $text.IndexOf($needle, $anchorIndex, [StringComparison]::Ordinal)
    if ($propertyIndex -ge $anchorIndex -and $propertyIndex -lt $entityEnd) {
        return Set-StringPropertyAfterAnchor $text $anchor $property $value
    }

    $lineEnd = $text.IndexOf("`n", $anchorIndex)
    Check ($lineEnd -ge 0 -and $lineEnd -lt $entityEnd) "VMAP_ANCHOR_LINE_END_MISSING: $anchor"
    $lineStart = $text.LastIndexOf("`n", $anchorIndex)
    if ($lineStart -lt 0) { $lineStart = 0 } else { $lineStart += 1 }
    $indent = $text.Substring($lineStart, $anchorIndex - $lineStart)
    $line = '{0}"{1}" "string" "{2}"' -f $indent, $property, $value
    return $text.Substring(0, $lineEnd + 1) + $line + "`r`n" + $text.Substring($lineEnd + 1)
}

function Remove-StringPropertyAfterAnchor(
    [string]$text,
    [string]$anchor,
    [string]$property
) {
    $anchorIndex = $text.IndexOf($anchor, [StringComparison]::Ordinal)
    Check ($anchorIndex -ge 0) "VMAP_ANCHOR_MISSING: $anchor"
    $entityEnd = $text.IndexOf('"CMapEntity"', $anchorIndex, [StringComparison]::Ordinal)
    Check ($entityEnd -gt $anchorIndex) "VMAP_ENTITY_END_MISSING: $anchor"
    $needle = '"' + $property + '" "string" "'
    $propertyIndex = $text.IndexOf($needle, $anchorIndex, [StringComparison]::Ordinal)
    if ($propertyIndex -lt $anchorIndex -or $propertyIndex -ge $entityEnd) { return $text }

    $lineStart = $text.LastIndexOf("`n", $propertyIndex)
    if ($lineStart -lt 0) { $lineStart = 0 } else { $lineStart += 1 }
    $lineEnd = $text.IndexOf("`n", $propertyIndex)
    if ($lineEnd -lt 0 -or $lineEnd -ge $entityEnd) { $lineEnd = $entityEnd } else { $lineEnd += 1 }
    return $text.Substring(0, $lineStart) + $text.Substring($lineEnd)
}

function Set-TypedPropertyAfterAnchor(
    [string]$text,
    [string]$anchor,
    [string]$property,
    [string]$type,
    [string]$value
) {
    $anchorIndex = $text.IndexOf($anchor, [StringComparison]::Ordinal)
    Check ($anchorIndex -ge 0) "VMAP_ANCHOR_MISSING: $anchor"
    $needle = '"' + $property + '" "' + $type + '" "'
    $propertyIndex = $text.IndexOf($needle, $anchorIndex, [StringComparison]::Ordinal)
    Check ($propertyIndex -ge 0) "VMAP_PROPERTY_MISSING: $property"
    $valueStart = $propertyIndex + $needle.Length
    $valueEnd = $text.IndexOf('"', $valueStart)
    Check ($valueEnd -ge 0) "VMAP_PROPERTY_UNTERMINATED: $property"
    return $text.Substring(0, $valueStart) + $value + $text.Substring($valueEnd)
}

function Get-Vector3([string]$value, [string]$name) {
    $parts = @($value -split '\s+' | Where-Object { $_ -ne '' })
    Check ($parts.Count -eq 3) "VECTOR3_INVALID: $name"
    return @(
        [double]::Parse($parts[0], [Globalization.CultureInfo]::InvariantCulture),
        [double]::Parse($parts[1], [Globalization.CultureInfo]::InvariantCulture),
        [double]::Parse($parts[2], [Globalization.CultureInfo]::InvariantCulture)
    )
}

function Find-BalancedDelimiterEnd(
    [string]$text,
    [int]$openIndex,
    [char]$openDelimiter,
    [char]$closeDelimiter
) {
    Check ($openIndex -ge 0 -and $text[$openIndex] -eq $openDelimiter) 'DMX_DELIMITER_START_INVALID'
    $depth = 0
    $inString = $false
    $escaped = $false
    for ($index = $openIndex; $index -lt $text.Length; $index++) {
        $character = $text[$index]
        if ($inString) {
            if ($escaped) {
                $escaped = $false
            } elseif ($character -eq '\') {
                $escaped = $true
            } elseif ($character -eq '"') {
                $inString = $false
            }
            continue
        }
        if ($character -eq '"') {
            $inString = $true
        } elseif ($character -eq $openDelimiter) {
            $depth += 1
        } elseif ($character -eq $closeDelimiter) {
            $depth -= 1
            if ($depth -eq 0) { return $index }
        }
    }
    throw 'DMX_DELIMITER_END_MISSING'
}

function Get-DmxEntityBlock([string]$text, [string]$anchor) {
    $anchorIndex = $text.IndexOf($anchor, [StringComparison]::Ordinal)
    Check ($anchorIndex -ge 0) "DMX_ENTITY_ANCHOR_MISSING: $anchor"
    $entityIndex = $text.LastIndexOf('"CMapEntity"', $anchorIndex, [StringComparison]::Ordinal)
    Check ($entityIndex -ge 0) "DMX_ENTITY_START_MISSING: $anchor"
    $openIndex = $text.IndexOf('{', $entityIndex)
    Check ($openIndex -ge 0 -and $openIndex -lt $anchorIndex) "DMX_ENTITY_OPEN_MISSING: $anchor"
    $closeIndex = Find-BalancedDelimiterEnd $text $openIndex '{' '}'
    return $text.Substring($entityIndex, $closeIndex - $entityIndex + 1)
}

function Set-DmxWorldChildren([string]$text, [string[]]$entityBlocks) {
    Check ($entityBlocks.Count -gt 0) 'CONTROL_ENTITY_BLOCKS_MISSING'
    $worldIndex = $text.IndexOf('"world" "CMapWorld"', [StringComparison]::Ordinal)
    Check ($worldIndex -ge 0) 'DMX_WORLD_MISSING'
    $childrenIndex = $text.IndexOf('"children" "element_array"', $worldIndex, [StringComparison]::Ordinal)
    Check ($childrenIndex -ge 0) 'DMX_WORLD_CHILDREN_MISSING'
    $openIndex = $text.IndexOf('[', $childrenIndex)
    Check ($openIndex -ge 0) 'DMX_WORLD_CHILDREN_OPEN_MISSING'
    $closeIndex = Find-BalancedDelimiterEnd $text $openIndex '[' ']'
    $body = "`r`n`t`t`t" + ($entityBlocks -join ",`r`n`t`t`t") + "`r`n`t`t"
    return $text.Substring(0, $openIndex + 1) + $body + $text.Substring($closeIndex)
}

function Get-LookAngles([string]$originValue, [string]$targetValue) {
    $origin = Get-Vector3 $originValue 'control.camera_origin'
    $target = Get-Vector3 $targetValue 'control.camera_target'
    $deltaX = $target[0] - $origin[0]
    $deltaY = $target[1] - $origin[1]
    $deltaZ = $target[2] - $origin[2]
    $horizontalDistance = [Math]::Sqrt($deltaX * $deltaX + $deltaY * $deltaY)
    Check ($horizontalDistance -gt 0) 'CONTROL_CAMERA_TARGET_OVERLAPS'
    $pitch = [Math]::Atan2(-$deltaZ, $horizontalDistance) * 180.0 / [Math]::PI
    $yaw = [Math]::Atan2($deltaY, $deltaX) * 180.0 / [Math]::PI
    return [string]::Format(
        [Globalization.CultureInfo]::InvariantCulture,
        '{0:F6} {1:F6} 0.000000',
        $pitch,
        $yaw
    )
}

function Copy-Tree([string]$source, [string]$destination) {
    Check (Test-Path -LiteralPath $source -PathType Container) "SOURCE_DIRECTORY_MISSING: $source"
    New-Item -ItemType Directory -Path $destination -Force | Out-Null
    Get-ChildItem -LiteralPath $source -Force | ForEach-Object {
        Copy-Item -LiteralPath $_.FullName -Destination $destination -Recurse -Force
    }
}

function Invoke-LoggedTool([string]$name, [string]$executable, [string[]]$arguments) {
    Add-Content -LiteralPath $BuildLog -Value ("`n=== {0} ===`n{1} {2}" -f $name, $executable, ($arguments -join ' '))
    $output = @(& $executable @arguments 2>&1)
    $exitCode = $LASTEXITCODE
    $output | ForEach-Object { Add-Content -LiteralPath $BuildLog -Value ([string]$_) }
    $output | Select-Object -Last 12 | ForEach-Object { Write-Host ([string]$_) }
    Check ($exitCode -eq 0) "$name FAILED exit=$exitCode log=$BuildLog"
}

function Invoke-ResourceCompile([string]$source, [bool]$looseMap) {
    $arguments = @('-f', '-nop4', '-game', $DotaGameRoot, '-i', $source)
    if ($looseMap) { $arguments += '-novpk' }
    Invoke-LoggedTool -name ("RESOURCE_COMPILE {0}" -f $source) `
        -executable $ResourceCompiler -arguments $arguments
}

function Check-OutputIsFresh([string]$source, [string]$output, [string]$label) {
    Check (Test-Path -LiteralPath $source -PathType Leaf) "${label}_SOURCE_MISSING"
    Check (Test-Path -LiteralPath $output -PathType Leaf) "${label}_OUTPUT_MISSING"
    Check ((Get-Item -LiteralPath $output).Length -gt 0) "${label}_OUTPUT_EMPTY"
    $sourceTime = (Get-Item -LiteralPath $source).LastWriteTimeUtc
    $outputTime = (Get-Item -LiteralPath $output).LastWriteTimeUtc
    Check ($outputTime -ge $sourceTime) "${label}_OUTPUT_STALE"
}

function New-SceneMap($row) {
    $relativeMap = (Get-RowValue $row 'scene_map') -replace '/', '\'
    $target = Join-Path (Join-Path $ContentTarget 'maps') ($relativeMap + '.vmap')
    New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force | Out-Null

    Invoke-LoggedTool -name ("DMX_CONVERT {0}" -f (Get-RowValue $row 'stage_id')) `
        -executable $DmxConvert `
        -arguments @('-i', $OfficialPrefab, '-ie', 'binary', '-o', $target, '-oe', 'keyvalues2', '-of', 'vmap')

    $text = [IO.File]::ReadAllText($target)
    $portraitAnchor = '"classname" "string" "portrait_world_unit"'
    $lightAnchor = '"classname" "string" "env_global_light"'
    $cameraAnchor = '"classname" "string" "point_camera"'
    $worldAnchor = '"world" "CMapWorld"'

    $portraitAnchorIndex = $text.IndexOf($portraitAnchor, [StringComparison]::Ordinal)
    Check ($portraitAnchorIndex -ge 0) 'PORTRAIT_ENTITY_MISSING'
    $portraitEntityEnd = $text.IndexOf('"CMapEntity"', $portraitAnchorIndex, [StringComparison]::Ordinal)
    Check ($portraitEntityEnd -gt $portraitAnchorIndex) 'PORTRAIT_ENTITY_END_MISSING'
    $portraitBlock = $text.Substring($portraitAnchorIndex, $portraitEntityEnd - $portraitAnchorIndex)
    $portraitTargetnameMatch = [regex]::Match($portraitBlock, '"targetname" "string" "([^"]*)"')
    Check ($portraitTargetnameMatch.Success) 'PORTRAIT_TARGETNAME_MISSING'
    $portraitTargetname = $portraitTargetnameMatch.Groups[1].Value
    if ((Get-RowValue $row 'portrait_contract') -eq 'base_minimal' -and [string]::IsNullOrEmpty($portraitTargetname)) {
        $diagnosticTargetname = Get-RowValue $row 'portrait_targetname'
        Check (-not [string]::IsNullOrEmpty($diagnosticTargetname)) 'BASE_PORTRAIT_TARGETNAME_REQUIRED'
        $text = Set-StringPropertyAfterAnchor $text $portraitAnchor 'targetname' $diagnosticTargetname
        $portraitTargetname = $diagnosticTargetname
    }

    $text = Set-StringPropertyAfterAnchor $text $worldAnchor 'mapUsageType' (Get-RowValue $row 'map_usage_type')
    $text = Set-StringPropertyAfterAnchor $text $lightAnchor 'targetname' (Get-RowValue $row 'light_targetname')
    $text = Set-StringPropertyAfterAnchor $text $cameraAnchor 'targetname' (Get-RowValue $row 'camera_name')
    $text = Set-StringPropertyAfterAnchor $text $portraitAnchor 'MapUnitName' (Get-RowValue $row 'map_unit_name')
    $text = Set-StringPropertyAfterAnchor $text $portraitAnchor 'm_iTeamNum' (Get-RowValue $row 'm_iTeamNum')
    $text = Set-StringPropertyAfterAnchor $text $portraitAnchor 'ModelScale' (Get-RowValue $row 'ModelScale')
    $text = Set-StringPropertyAfterAnchor $text $portraitAnchor 'StartDisabled' (Get-RowValue $row 'StartDisabled')
    $text = Set-StringPropertyAfterAnchor $text $portraitAnchor 'suppress_intro_effects' (Get-RowValue $row 'suppress_intro_effects')
    $text = Set-StringPropertyAfterAnchor $text $portraitAnchor 'skip_pet_spawn' (Get-RowValue $row 'skip_pet_spawn')
    $text = Set-OrAddStringPropertyAfterAnchor $text $portraitAnchor 'skip_background_entities' (Get-RowValue $row 'skip_background_entities')
    $text = Set-StringPropertyAfterAnchor $text $portraitAnchor 'parentname' ''
    $text = Set-StringPropertyAfterAnchor $text $portraitAnchor 'parentAttachmentName' ''
    $text = Set-StringPropertyAfterAnchor $text $portraitAnchor 'spawn_wearable_item_defs' (Get-RowValue $row 'spawn_wearable_item_defs')
    if ((Get-RowValue $row 'portrait_contract') -eq 'base_minimal') {
        $text = Set-TypedPropertyAfterAnchor $text $portraitAnchor 'force_hidden' 'bool' '0'
        foreach ($property in @(
            'EnableAutoStyles',
            'spawn_background_models',
            'rare_loadout_anim_chance',
            'suppress_anim_event_sounds',
            'flying_courier',
            'activity',
            'activity_modifier'
        ) + (0..7 | ForEach-Object { "item_def$_" }) + (0..7 | ForEach-Object { "style_index$_" })) {
            $text = Remove-StringPropertyAfterAnchor $text $portraitAnchor $property
        }
    } else {
        $text = Set-StringPropertyAfterAnchor $text $portraitAnchor 'EnableAutoStyles' (Get-RowValue $row 'enable_auto_styles')
        $text = Set-StringPropertyAfterAnchor $text $portraitAnchor 'spawn_background_models' (Get-RowValue $row 'spawn_background_models')
        $text = Set-StringPropertyAfterAnchor $text $portraitAnchor 'rare_loadout_anim_chance' (Get-RowValue $row 'rare_loadout_anim_chance')
        $text = Set-StringPropertyAfterAnchor $text $portraitAnchor 'suppress_anim_event_sounds' (Get-RowValue $row 'suppress_anim_event_sounds')
        $text = Set-StringPropertyAfterAnchor $text $portraitAnchor 'flying_courier' (Get-RowValue $row 'flying_courier')
        $text = Set-StringPropertyAfterAnchor $text $portraitAnchor 'activity' (Get-RowValue $row 'activity')
        $text = Set-StringPropertyAfterAnchor $text $portraitAnchor 'activity_modifier' (Get-RowValue $row 'activity_modifier')
        for ($slot = 0; $slot -lt 8; $slot++) {
            $text = Set-StringPropertyAfterAnchor $text $portraitAnchor ("item_def{0}" -f $slot) `
                (Get-RowValue $row ("item_def{0}" -f $slot))
            $text = Set-StringPropertyAfterAnchor $text $portraitAnchor ("style_index{0}" -f $slot) `
                (Get-RowValue $row ("style_index{0}" -f $slot))
        }
    }

    $text = Set-StringPropertyAfterAnchor $text $cameraAnchor 'parentname' ''
    $text = Set-StringPropertyAfterAnchor $text $cameraAnchor 'parentAttachmentName' ''
    $text = Set-StringPropertyAfterAnchor $text $cameraAnchor 'FOV' (Get-RowValue $row 'camera_fov')
    $text = Set-StringPropertyAfterAnchor $text $cameraAnchor 'dof_enabled' '0'
    $text = Set-TypedPropertyAfterAnchor $text $cameraAnchor 'origin' 'vector3' (Get-RowValue $row 'camera_origin')
    $text = Set-TypedPropertyAfterAnchor $text $cameraAnchor 'angles' 'qangle' (Get-RowValue $row 'camera_angles')

    $cameraAnchorIndex = $text.IndexOf($cameraAnchor, [StringComparison]::Ordinal)
    $cameraEntityEnd = $text.IndexOf('"CMapEntity"', $cameraAnchorIndex, [StringComparison]::Ordinal)
    Check ($cameraEntityEnd -gt $cameraAnchorIndex) 'CAMERA_ENTITY_END_MISSING'
    $cameraBlock = $text.Substring($cameraAnchorIndex, $cameraEntityEnd - $cameraAnchorIndex)
    Check ($cameraBlock.Contains(('"targetname" "string" "{0}"' -f (Get-RowValue $row 'camera_name')))) 'CAMERA_NAME_NOT_APPLIED'
    Check ($cameraBlock.Contains('"parentname" "string" ""')) 'CAMERA_PARENTNAME_NOT_EMPTY'
    Check ($cameraBlock.Contains('"parentAttachmentName" "string" ""')) 'CAMERA_PARENT_ATTACHMENT_NOT_EMPTY'

    $portraitAnchorIndex = $text.IndexOf($portraitAnchor, [StringComparison]::Ordinal)
    $portraitEntityEnd = $text.IndexOf('"CMapEntity"', $portraitAnchorIndex, [StringComparison]::Ordinal)
    Check ($portraitEntityEnd -gt $portraitAnchorIndex) 'PORTRAIT_ENTITY_END_MISSING'
    $portraitBlock = $text.Substring($portraitAnchorIndex, $portraitEntityEnd - $portraitAnchorIndex)
    $targetOriginMatch = [regex]::Match($portraitBlock, '"origin" "vector3" "([^"]*)"')
    Check ($targetOriginMatch.Success) 'PORTRAIT_ORIGIN_MISSING'
    $cameraOrigin = Get-Vector3 (Get-RowValue $row 'camera_origin') 'camera_origin'
    $targetOrigin = Get-Vector3 $targetOriginMatch.Groups[1].Value 'portrait_world_unit.origin'
    $cameraAngles = Get-Vector3 (Get-RowValue $row 'camera_angles') 'camera_angles'
    $deltaX = $targetOrigin[0] - $cameraOrigin[0]
    $deltaY = $targetOrigin[1] - $cameraOrigin[1]
    $deltaZ = $targetOrigin[2] - $cameraOrigin[2]
    $horizontalDistance = [Math]::Sqrt($deltaX * $deltaX + $deltaY * $deltaY)
    Check ($horizontalDistance -gt 0) 'PORTRAIT_CAMERA_TARGET_OVERLAPS'
    $expectedPitch = [Math]::Atan2(-$deltaZ, $horizontalDistance) * 180.0 / [Math]::PI
    $expectedYaw = [Math]::Atan2($deltaY, $deltaX) * 180.0 / [Math]::PI
    Check ([Math]::Abs($cameraAngles[0] - $expectedPitch) -lt 0.001) 'CAMERA_PITCH_NOT_AIMED_AT_PORTRAIT'
    Check ([Math]::Abs($cameraAngles[1] - $expectedYaw) -lt 0.001) 'CAMERA_YAW_NOT_AIMED_AT_PORTRAIT'

    $debutCameraAnchor = '"targetname" "string" "debut_camera"'
    $text = Set-TypedPropertyAfterAnchor $text $debutCameraAnchor 'force_hidden' 'bool' '1'
    $text = Set-TypedPropertyAfterAnchor $text $debutCameraAnchor 'editorOnly' 'bool' '1'

    $portraitAnchorIndex = $text.IndexOf($portraitAnchor, [StringComparison]::Ordinal)
    $portraitEntityEnd = $text.IndexOf('"CMapEntity"', $portraitAnchorIndex, [StringComparison]::Ordinal)
    Check ($portraitEntityEnd -gt $portraitAnchorIndex) 'PORTRAIT_ENTITY_END_MISSING_AFTER_CONFIG'
    $portraitBlock = $text.Substring($portraitAnchorIndex, $portraitEntityEnd - $portraitAnchorIndex)
    Check ($portraitBlock.Contains(('"MapUnitName" "string" "{0}"' -f (Get-RowValue $row 'map_unit_name')))) 'AXE_MAP_UNIT_NAME_NOT_APPLIED'
    Check ($portraitBlock.Contains(('"m_iTeamNum" "string" "{0}"' -f (Get-RowValue $row 'm_iTeamNum')))) 'PORTRAIT_TEAM_NOT_APPLIED'
    Check ($portraitBlock.Contains(('"ModelScale" "string" "{0}"' -f (Get-RowValue $row 'ModelScale')))) 'PORTRAIT_MODEL_SCALE_NOT_APPLIED'
    Check ($portraitBlock.Contains(('"StartDisabled" "string" "{0}"' -f (Get-RowValue $row 'StartDisabled')))) 'PORTRAIT_START_DISABLED_INVALID'
    Check ($portraitBlock.Contains(('"spawn_wearable_item_defs" "string" "{0}"' -f (Get-RowValue $row 'spawn_wearable_item_defs')))) 'SPAWN_WEARABLE_FLAG_NOT_APPLIED'
    Check ($portraitBlock.Contains(('"skip_background_entities" "string" "{0}"' -f (Get-RowValue $row 'skip_background_entities')))) 'SKIP_BACKGROUND_ENTITIES_NOT_APPLIED'
    if ((Get-RowValue $row 'portrait_contract') -eq 'base_minimal') {
        Check ($portraitBlock.Contains('"force_hidden" "bool" "0"')) 'BASE_FORCE_HIDDEN_INVALID'
    }
    Check ($text.Contains(('"mapUsageType" "string" "{0}"' -f (Get-RowValue $row 'map_usage_type')))) 'MAP_USAGE_TYPE_NOT_APPLIED'
    Check ($text.Contains(('"targetname" "string" "{0}"' -f (Get-RowValue $row 'light_targetname')))) 'LIGHT_TARGETNAME_NOT_APPLIED'
    Check (-not $text.Contains('loadout_camera_model')) 'LOADOUT_CAMERA_MODEL_REFERENCE_FORBIDDEN'
    Check (-not $text.Contains('herocamera')) 'LEGACY_CAMERA_NAME_FORBIDDEN'
    Check ($text.Contains('"targetname" "string" "debut_camera"')) 'DEBUT_CAMERA_ENTITY_MISSING'
    if ((Get-RowValue $row 'portrait_contract') -eq 'base_minimal') {
        Check (-not $portraitBlock.Contains('"item_def')) 'BASE_ITEM_DEF_FIELDS_FORBIDDEN'
        Check (-not $portraitBlock.Contains('"style_index')) 'BASE_STYLE_FIELDS_FORBIDDEN'
        Check (-not $portraitBlock.Contains('"activity" "string"')) 'BASE_ACTIVITY_FORBIDDEN'
        Check (-not $portraitBlock.Contains('"activity_modifier" "string"')) 'BASE_ACTIVITY_MODIFIER_FORBIDDEN'
        foreach ($property in @('EnableAutoStyles', 'spawn_background_models', 'rare_loadout_anim_chance', 'suppress_anim_event_sounds', 'flying_courier')) {
            Check (-not $portraitBlock.Contains(('"{0}" "string"' -f $property))) "BASE_NON_MINIMAL_FIELD_FORBIDDEN: $property"
        }
    } else {
        Check ($portraitBlock.Contains(('"EnableAutoStyles" "string" "{0}"' -f (Get-RowValue $row 'enable_auto_styles')))) 'AUTO_STYLES_NOT_DISABLED'
    }
    [IO.File]::WriteAllText($target, $text, $Utf8NoBom)
    return $target
}

function Set-PropControlBlock([string]$block, $row, [string]$prefix) {
    $anchor = '"classname" "string" "prop_dynamic"'
    $block = Set-StringPropertyAfterAnchor $block $anchor 'targetname' (Get-RowValue $row ($prefix + '_targetname'))
    $block = Set-StringPropertyAfterAnchor $block $anchor 'parentname' ''
    $block = Set-StringPropertyAfterAnchor $block $anchor 'parentAttachmentName' ''
    $block = Set-StringPropertyAfterAnchor $block $anchor 'model' (Get-RowValue $row ($prefix + '_model'))
    $block = Set-StringPropertyAfterAnchor $block $anchor 'skin' 'default'
    $block = Set-StringPropertyAfterAnchor $block $anchor 'StartDisabled' '0'
    $block = Set-StringPropertyAfterAnchor $block $anchor 'StartingAnim' (Get-RowValue $row ($prefix + '_starting_anim'))
    $block = Set-StringPropertyAfterAnchor $block $anchor 'IdleAnim' (Get-RowValue $row ($prefix + '_starting_anim'))
    $block = Set-TypedPropertyAfterAnchor $block $anchor 'origin' 'vector3' (Get-RowValue $row ($prefix + '_origin'))
    $block = Set-TypedPropertyAfterAnchor $block $anchor 'angles' 'qangle' (Get-RowValue $row ($prefix + '_angles'))
    $block = Set-TypedPropertyAfterAnchor $block $anchor 'scales' 'vector3' (Get-RowValue $row ($prefix + '_scale'))
    $block = Set-TypedPropertyAfterAnchor $block $anchor 'force_hidden' 'bool' (Get-RowValue $row ($prefix + '_force_hidden'))
    $block = Set-TypedPropertyAfterAnchor $block $anchor 'editorOnly' 'bool' (Get-RowValue $row ($prefix + '_editor_only'))
    return $block
}

function New-PropControlMap($row) {
    $relativeMap = (Get-RowValue $row 'scene_map') -replace '/', '\'
    $target = Join-Path (Join-Path $ContentTarget 'maps') ($relativeMap + '.vmap')
    New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force | Out-Null

    Invoke-LoggedTool -name ("DMX_CONVERT {0}" -f (Get-RowValue $row 'control_id')) `
        -executable $DmxConvert `
        -arguments @('-i', $OfficialPrefab, '-ie', 'binary', '-o', $target, '-oe', 'keyvalues2', '-of', 'vmap')

    $text = [IO.File]::ReadAllText($target)
    $text = Set-StringPropertyAfterAnchor $text '"world" "CMapWorld"' 'mapUsageType' (Get-RowValue $row 'map_usage_type')
    $heroBlock = Get-DmxEntityBlock $text '"targetname" "string" "grass_cyclone"'
    $testBlock = Get-DmxEntityBlock $text '"targetname" "string" "cyclone"'
    $lightBlock = Get-DmxEntityBlock $text '"classname" "string" "env_global_light"'
    $cameraBlock = Get-DmxEntityBlock $text '"classname" "string" "point_camera"'

    $heroBlock = Set-PropControlBlock $heroBlock $row 'hero'
    $testBlock = Set-PropControlBlock $testBlock $row 'test'

    $lightAnchor = '"classname" "string" "env_global_light"'
    $lightBlock = Set-StringPropertyAfterAnchor $lightBlock $lightAnchor 'targetname' (Get-RowValue $row 'light_targetname')
    $lightBlock = Set-StringPropertyAfterAnchor $lightBlock $lightAnchor 'StartDisabled' '0'
    $lightBlock = Set-StringPropertyAfterAnchor $lightBlock $lightAnchor 'color' (Get-RowValue $row 'light_color')
    $lightBlock = Set-StringPropertyAfterAnchor $lightBlock $lightAnchor 'lightscale' (Get-RowValue $row 'light_scale')
    $lightBlock = Set-StringPropertyAfterAnchor $lightBlock $lightAnchor 'ambientcolor1' (Get-RowValue $row 'ambient_color1')
    $lightBlock = Set-StringPropertyAfterAnchor $lightBlock $lightAnchor 'ambientscale1' (Get-RowValue $row 'ambient_scale1')
    $lightBlock = Set-StringPropertyAfterAnchor $lightBlock $lightAnchor 'ambientcolor2' (Get-RowValue $row 'ambient_color2')
    $lightBlock = Set-StringPropertyAfterAnchor $lightBlock $lightAnchor 'ambientscale2' (Get-RowValue $row 'ambient_scale2')
    $lightBlock = Set-TypedPropertyAfterAnchor $lightBlock $lightAnchor 'origin' 'vector3' (Get-RowValue $row 'light_origin')
    $lightBlock = Set-TypedPropertyAfterAnchor $lightBlock $lightAnchor 'angles' 'qangle' (Get-RowValue $row 'light_angles')

    $cameraAnchor = '"classname" "string" "point_camera"'
    $cameraAngles = Get-LookAngles (Get-RowValue $row 'camera_origin') (Get-RowValue $row 'camera_target')
    $cameraBlock = Set-StringPropertyAfterAnchor $cameraBlock $cameraAnchor 'targetname' (Get-RowValue $row 'camera_name')
    $cameraBlock = Set-StringPropertyAfterAnchor $cameraBlock $cameraAnchor 'parentname' ''
    $cameraBlock = Set-StringPropertyAfterAnchor $cameraBlock $cameraAnchor 'parentAttachmentName' ''
    $cameraBlock = Set-StringPropertyAfterAnchor $cameraBlock $cameraAnchor 'FOV' (Get-RowValue $row 'camera_fov')
    $cameraBlock = Set-StringPropertyAfterAnchor $cameraBlock $cameraAnchor 'dof_enabled' '0'
    $cameraBlock = Set-TypedPropertyAfterAnchor $cameraBlock $cameraAnchor 'origin' 'vector3' (Get-RowValue $row 'camera_origin')
    $cameraBlock = Set-TypedPropertyAfterAnchor $cameraBlock $cameraAnchor 'angles' 'qangle' $cameraAngles

    $text = Set-DmxWorldChildren $text @($heroBlock, $testBlock, $lightBlock, $cameraBlock)
    $classNames = @([regex]::Matches($text, '"classname" "string" "([^"]+)"') | ForEach-Object { $_.Groups[1].Value })
    Check (($classNames | Where-Object { $_ -eq 'worldspawn' }).Count -eq 1) 'CONTROL_WORLDSPAWN_COUNT_INVALID'
    Check (($classNames | Where-Object { $_ -eq 'prop_dynamic' }).Count -eq 2) 'CONTROL_PROP_DYNAMIC_COUNT_INVALID'
    Check (($classNames | Where-Object { $_ -eq 'env_global_light' }).Count -eq 1) 'CONTROL_LIGHT_COUNT_INVALID'
    Check (($classNames | Where-Object { $_ -eq 'point_camera' }).Count -eq 1) 'CONTROL_CAMERA_COUNT_INVALID'
    Check (($classNames | Where-Object { $_ -notin @('worldspawn', 'prop_dynamic', 'env_global_light', 'point_camera') }).Count -eq 0) 'CONTROL_UNEXPECTED_ENTITY_CLASS'
    Check (-not $text.Contains('portrait_world_unit')) 'CONTROL_PORTRAIT_WORLD_UNIT_FORBIDDEN'
    Check (-not $text.Contains('item_def')) 'CONTROL_ITEM_DEF_FIELD_FORBIDDEN'
    Check (-not $text.Contains('22217')) 'CONTROL_ITEM_DEF_22217_FORBIDDEN'
    Check ($text.Contains(('"mapUsageType" "string" "{0}"' -f (Get-RowValue $row 'map_usage_type')))) 'CONTROL_MAP_USAGE_TYPE_NOT_APPLIED'
    Check ($lightBlock.Contains(('"targetname" "string" "{0}"' -f (Get-RowValue $row 'light_targetname')))) 'CONTROL_LIGHT_TARGETNAME_NOT_APPLIED'
    Check ($cameraBlock.Contains(('"targetname" "string" "{0}"' -f (Get-RowValue $row 'camera_name')))) 'CONTROL_CAMERA_NAME_NOT_APPLIED'
    Check ($text.Contains('"model" "string" "models/heroes/axe/axe.vmdl"')) 'CONTROL_AXE_MODEL_MISSING'
    Check ($text.Contains('"model" "string" "models/props_gameplay/red_box.vmdl"')) 'CONTROL_TEST_MODEL_MISSING'
    Check ($heroBlock.Contains(('"force_hidden" "bool" "{0}"' -f (Get-RowValue $row 'hero_force_hidden')))) 'CONTROL_AXE_FORCE_HIDDEN_INVALID'
    Check ($heroBlock.Contains(('"editorOnly" "bool" "{0}"' -f (Get-RowValue $row 'hero_editor_only')))) 'CONTROL_AXE_EDITOR_ONLY_INVALID'
    Check ($testBlock.Contains(('"force_hidden" "bool" "{0}"' -f (Get-RowValue $row 'test_force_hidden')))) 'CONTROL_TEST_FORCE_HIDDEN_INVALID'
    Check ($testBlock.Contains(('"editorOnly" "bool" "{0}"' -f (Get-RowValue $row 'test_editor_only')))) 'CONTROL_TEST_EDITOR_ONLY_INVALID'
    Check ($cameraBlock.Contains('"parentname" "string" ""')) 'CONTROL_CAMERA_PARENTNAME_NOT_EMPTY'
    Check ($cameraBlock.Contains('"parentAttachmentName" "string" ""')) 'CONTROL_CAMERA_PARENT_ATTACHMENT_NOT_EMPTY'
    Check ($cameraBlock.Contains(('"angles" "qangle" "{0}"' -f $cameraAngles))) 'CONTROL_CAMERA_NOT_AIMED_AT_TARGET'

    [IO.File]::WriteAllText($target, $text, $Utf8NoBom)
    return $target
}

foreach ($required in @(
    $StageCsv, $RendererSanityCsv, $ContentSource, $RuntimeSource, $OfficialPrefab, $PlayableTemplate,
    $DmxConvert, $ResourceCompiler, $ContractTest, (Join-Path $DotaGameRoot 'gameinfo.gi')
)) {
    Check (Test-Path -LiteralPath $required) "REQUIRED_INPUT_MISSING: $required"
}
Check ((Split-Path -Leaf $ContentTarget) -eq 'survival_phase2a') 'UNSAFE_CONTENT_TARGET'
Check ((Split-Path -Leaf $GameTarget) -eq 'survival_phase2a') 'UNSAFE_GAME_TARGET'

& $ContractTest
$stages = @(Import-Csv -LiteralPath $StageCsv)
Check ($stages.Count -eq 4) 'STAGE_COUNT_MUST_BE_FOUR'
$activeStages = @($stages | Where-Object { (Get-RowValue $_ 'stage_id') -eq 'base' })
Check ($activeStages.Count -eq 1) 'RENDERER_SANITY_MUST_ONLY_ACTIVATE_BASE'
$rendererSanityRows = @(Import-Csv -LiteralPath $RendererSanityCsv)
Check ($rendererSanityRows.Count -eq 1) 'RENDERER_SANITY_CONTROL_COUNT_MUST_BE_ONE'
$rendererSanity = $rendererSanityRows[0]

Remove-Item -LiteralPath $BuildLog -Force -ErrorAction SilentlyContinue
if ($SceneAndPanoramaOnly) {
    Check (Test-Path -LiteralPath (Join-Path $ContentTarget 'maps\phase2a_lab.vmap') -PathType Leaf) 'SELECTIVE_BUILD_CONTENT_TARGET_MISSING'
    Check (Test-Path -LiteralPath (Join-Path $GameTarget 'maps\phase2a_lab.vpk') -PathType Leaf) 'SELECTIVE_BUILD_GAME_TARGET_MISSING'
    Copy-Tree (Join-Path $ContentSource 'panorama') (Join-Path $ContentTarget 'panorama')
} else {
    Remove-Item -LiteralPath $ContentTarget -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $GameTarget -Recurse -Force -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Path $ContentTarget -Force | Out-Null
    New-Item -ItemType Directory -Path $GameTarget -Force | Out-Null
    Copy-Tree $ContentSource $ContentTarget
    Copy-Tree $RuntimeSource $GameTarget
    New-Item -ItemType Directory -Path (Join-Path $ContentTarget 'maps') -Force | Out-Null
    Copy-Item -LiteralPath $PlayableTemplate -Destination (Join-Path $ContentTarget 'maps\phase2a_lab.vmap') -Force
}

New-Item -ItemType Directory -Path (Join-Path $ContentTarget 'data') -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $GameTarget 'data') -Force | Out-Null
Copy-Item -LiteralPath $StageCsv -Destination (Join-Path $ContentTarget 'data\axe_stages.csv') -Force
Copy-Item -LiteralPath $StageCsv -Destination (Join-Path $GameTarget 'data\axe_stages.csv') -Force
Copy-Item -LiteralPath $RendererSanityCsv -Destination (Join-Path $ContentTarget 'data\renderer_sanity_control.csv') -Force
Copy-Item -LiteralPath $RendererSanityCsv -Destination (Join-Path $GameTarget 'data\renderer_sanity_control.csv') -Force

$layoutTemplate = Join-Path $ContentTarget 'panorama\layout\custom_game\phase2a_portrait_spike.xml.in'
$layoutTarget = Join-Path $ContentTarget 'panorama\layout\custom_game\phase2a_portrait_spike.xml'
$layoutText = [IO.File]::ReadAllText($layoutTemplate)
$placeholderPrefixByStage = @{
    base = '__BASE_'
    head = '__HEAD_'
    head_weapon = '__HEAD_WEAPON_'
    all_five = '__ALL_FIVE_'
}
foreach ($row in $stages) {
    $stageId = Get-RowValue $row 'stage_id'
    Check ($placeholderPrefixByStage.ContainsKey($stageId)) "UNKNOWN_STAGE_ID: $stageId"
    $prefix = $placeholderPrefixByStage[$stageId]
    $layoutText = $layoutText.Replace(($prefix + 'SCENE_MAP__'), (Get-RowValue $row 'scene_map'))
    $layoutText = $layoutText.Replace(($prefix + 'CAMERA_NAME__'), (Get-RowValue $row 'camera_name'))
    $layoutText = $layoutText.Replace(($prefix + 'LIGHT_TARGETNAME__'), (Get-RowValue $row 'light_targetname'))
    $layoutText = $layoutText.Replace(($prefix + 'PARTICLE_ONLY__'), (Get-RowValue $row 'particle_only'))
}
$layoutText = $layoutText.Replace('__PROP_CONTROL_SCENE_MAP__', (Get-RowValue $rendererSanity 'scene_map'))
$layoutText = $layoutText.Replace('__PROP_CONTROL_CAMERA_NAME__', (Get-RowValue $rendererSanity 'camera_name'))
$layoutText = $layoutText.Replace('__PROP_CONTROL_LIGHT_TARGETNAME__', (Get-RowValue $rendererSanity 'light_targetname'))
$layoutText = $layoutText.Replace('__PROP_CONTROL_PARTICLE_ONLY__', (Get-RowValue $rendererSanity 'particle_only'))
Check (-not $layoutText.Contains('__')) 'UNRESOLVED_LAYOUT_PLACEHOLDER'
[IO.File]::WriteAllText($layoutTarget, $layoutText, $Utf8NoBom)
Remove-Item -LiteralPath $layoutTemplate -Force

$panoramaStages = @($activeStages | ForEach-Object {
    [ordered]@{
        id = Get-RowValue $_ 'stage_id'
        label = Get-RowValue $_ 'stage_label'
        sceneMap = Get-RowValue $_ 'scene_map'
        snippet = Get-RowValue $_ 'snippet_name'
        expectedItems = Get-RowValue $_ 'expected_items'
        directUnit = Get-RowValue $_ 'map_unit_name'
        backgroundScene = [ordered]@{
            map = Get-RowValue $_ 'scene_map'
            camera = Get-RowValue $_ 'camera_name'
            light = Get-RowValue $_ 'light_targetname'
            particleOnly = Get-RowValue $_ 'particle_only'
        }
        backgroundProp = [ordered]@{
            map = Get-RowValue $rendererSanity 'scene_map'
            camera = Get-RowValue $rendererSanity 'camera_name'
            light = Get-RowValue $rendererSanity 'light_targetname'
            particleOnly = Get-RowValue $rendererSanity 'particle_only'
        }
    }
})
$stageJson = ConvertTo-Json -InputObject $panoramaStages -Compress -Depth 4
$dataScript = "(function () {`n    GameUI.CustomUIConfig().Phase2APortraitData = $stageJson;`n})();`n"
$dataScriptPath = Join-Path $ContentTarget 'panorama\scripts\custom_game\phase2a_portrait_data.js'
[IO.File]::WriteAllText($dataScriptPath, $dataScript, $Utf8NoBom)

$sceneMaps = @()
foreach ($row in $activeStages) {
    $sceneMaps += New-SceneMap $row
}
$sceneMaps += New-PropControlMap $rendererSanity
& $ContractTest -GeneratedContentRoot $ContentTarget

if (-not $SkipCompile) {
    if (-not $SceneAndPanoramaOnly) {
        Invoke-ResourceCompile (Join-Path $ContentTarget 'maps\phase2a_lab.vmap') $false
    }
    foreach ($sceneMap in $sceneMaps) {
        Invoke-ResourceCompile $sceneMap $true
    }
    foreach ($resource in @(
        (Join-Path $ContentTarget 'panorama\layout\custom_game\custom_ui_manifest.xml'),
        $layoutTarget,
        $dataScriptPath,
        (Join-Path $ContentTarget 'panorama\scripts\custom_game\phase2a_portrait_spike.js'),
        (Join-Path $ContentTarget 'panorama\styles\custom_game\phase2a_portrait_spike.css')
    )) {
        Invoke-ResourceCompile $resource $false
    }

    if (-not $SceneAndPanoramaOnly) {
        Check-OutputIsFresh (Join-Path $ContentTarget 'maps\phase2a_lab.vmap') `
            (Join-Path $GameTarget 'maps\phase2a_lab.vpk') 'PLAYABLE_MAP'
    }
    foreach ($row in $activeStages) {
        $relative = (Get-RowValue $row 'scene_map') -replace '/', '\'
        Check-OutputIsFresh (Join-Path (Join-Path $ContentTarget 'maps') ($relative + '.vmap')) `
            (Join-Path (Join-Path $GameTarget 'maps') ($relative + '.vpk')) ("SCENE_MAP_{0}" -f $relative)
    }
    $controlRelative = (Get-RowValue $rendererSanity 'scene_map') -replace '/', '\'
    Check-OutputIsFresh (Join-Path (Join-Path $ContentTarget 'maps') ($controlRelative + '.vmap')) `
        (Join-Path (Join-Path $GameTarget 'maps') ($controlRelative + '.vpk')) 'CONTROL_SCENE_MAP'
    foreach ($panoramaOutput in @(
        [pscustomobject]@{ Source = 'panorama\layout\custom_game\custom_ui_manifest.xml'; Output = 'panorama\layout\custom_game\custom_ui_manifest.vxml_c' },
        [pscustomobject]@{ Source = 'panorama\layout\custom_game\phase2a_portrait_spike.xml'; Output = 'panorama\layout\custom_game\phase2a_portrait_spike.vxml_c' },
        [pscustomobject]@{ Source = 'panorama\scripts\custom_game\phase2a_portrait_data.js'; Output = 'panorama\scripts\custom_game\phase2a_portrait_data.vjs_c' },
        [pscustomobject]@{ Source = 'panorama\scripts\custom_game\phase2a_portrait_spike.js'; Output = 'panorama\scripts\custom_game\phase2a_portrait_spike.vjs_c' },
        [pscustomobject]@{ Source = 'panorama\styles\custom_game\phase2a_portrait_spike.css'; Output = 'panorama\styles\custom_game\phase2a_portrait_spike.vcss_c' }
    )) {
        Check-OutputIsFresh (Join-Path $ContentTarget $panoramaOutput.Source) `
            (Join-Path $GameTarget $panoramaOutput.Output) ("PANORAMA_{0}" -f $panoramaOutput.Output)
    }
}

Write-Host 'PORTRAIT_WORLD_UNIT_PHASE2A_BUILD_PASS' -ForegroundColor Green
Write-Host "Content addon: $ContentTarget"
Write-Host "Game addon: $GameTarget"
Write-Host "Compiler log: $BuildLog"
