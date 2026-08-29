param(
    [switch]$SkipCompile
)

$ErrorActionPreference = 'Stop'
$ToolsRoot = $PSScriptRoot
$RepoRoot = Split-Path -Parent $ToolsRoot
$GameAddonsRoot = Split-Path -Parent $RepoRoot
$GameRoot = Split-Path -Parent $GameAddonsRoot
$DotaRoot = Split-Path -Parent $GameRoot
$ContentAddonsRoot = Join-Path $DotaRoot 'content\dota_addons'
$DotaGameRoot = Join-Path $GameRoot 'dota'
$SpikeRoot = Join-Path $RepoRoot 'spikes\ta_portrait_probe'
$SceneCsv = Join-Path $SpikeRoot 'data\scene.csv'
$AssetCatalogCsv = Join-Path $RepoRoot 'data\csv\资源系统\asset_catalog.csv'
$AssetComponentsCsv = Join-Path $RepoRoot 'data\csv\资源系统\asset_components.csv'
$TowerDeathCsv = Join-Path $RepoRoot 'data\csv\建筑与工人系统\防御塔\tower_class_death.csv'
$ContentSource = Join-Path $SpikeRoot 'content'
$RuntimeSource = Join-Path $SpikeRoot 'runtime'
$ContentTarget = Join-Path $ContentAddonsRoot 'survival_ta_portrait_probe'
$GameTarget = Join-Path $GameAddonsRoot 'survival_ta_portrait_probe'
$OfficialPrefab = Join-Path $DotaRoot 'content\dota\maps\prefabs\hero_showcase_wind_ranger_default_prefab.vmap'
$PlayableTemplate = Join-Path $ContentAddonsRoot 'addon_template\maps\template_map.vmap'
$DmxConvert = Join-Path $GameRoot 'bin\win64\dmxconvert.exe'
$ResourceCompiler = Join-Path $GameRoot 'bin\win64\resourcecompiler.exe'
$ContractTest = Join-Path $ToolsRoot 'test_ta_portrait_probe_contract.ps1'
$BuildLog = Join-Path $env:TEMP 'survival_ta_portrait_probe_resource_compile.log'
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
    Check ($entityBlocks.Count -gt 0) 'WORLD_ENTITY_BLOCKS_MISSING'
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

function Set-UniqueDmxIds([string]$block, [int]$nodeId) {
    $block = [regex]::Replace($block, '("id" "elementid" ")[^"]+(")', {
        param($match)
        return $match.Groups[1].Value + ([Guid]::NewGuid().ToString()) + $match.Groups[2].Value
    })
    $block = [regex]::Replace($block, '("referenceID" "uint64" ")0x[^"]+(")', {
        param($match)
        return $match.Groups[1].Value + ('0x' + ([Guid]::NewGuid().ToString('N').Substring(0, 16))) + $match.Groups[2].Value
    })
    $block = [regex]::Replace($block, '("nodeID" "int" ")[^"]+(")', {
        param($match)
        return $match.Groups[1].Value + [string]$nodeId + $match.Groups[2].Value
    })
    return $block
}

function Get-LookAngles([string]$originValue, [string]$targetValue) {
    $origin = @($originValue -split '\s+' | Where-Object { $_ -ne '' } | ForEach-Object { [double]::Parse($_, [Globalization.CultureInfo]::InvariantCulture) })
    $target = @($targetValue -split '\s+' | Where-Object { $_ -ne '' } | ForEach-Object { [double]::Parse($_, [Globalization.CultureInfo]::InvariantCulture) })
    Check ($origin.Count -eq 3 -and $target.Count -eq 3) 'CAMERA_VECTOR_INVALID'
    $deltaX = $target[0] - $origin[0]
    $deltaY = $target[1] - $origin[1]
    $deltaZ = $target[2] - $origin[2]
    $horizontalDistance = [Math]::Sqrt($deltaX * $deltaX + $deltaY * $deltaY)
    Check ($horizontalDistance -gt 0) 'CAMERA_TARGET_OVERLAPS_CAMERA'
    $pitch = [Math]::Atan2(-$deltaZ, $horizontalDistance) * 180.0 / [Math]::PI
    $yaw = [Math]::Atan2($deltaY, $deltaX) * 180.0 / [Math]::PI
    return [string]::Format([Globalization.CultureInfo]::InvariantCulture, '{0:F6} {1:F6} 0.000000', $pitch, $yaw)
}

function ConvertTo-LuaString([string]$value) {
    $escaped = $value.Replace('\', '\\').Replace('"', '\"')
    return '"' + $escaped + '"'
}

function ConvertTo-LuaVector([string]$value, [string]$label) {
    $parts = @($value -split '\s+' | Where-Object { $_ -ne '' })
    Check ($parts.Count -eq 3) "LUA_VECTOR_INVALID: $label"
    $numbers = @($parts | ForEach-Object {
        [double]::Parse($_, [Globalization.CultureInfo]::InvariantCulture)
    })
    return [string]::Format(
        [Globalization.CultureInfo]::InvariantCulture,
        '{{ x = {0:G17}, y = {1:G17}, z = {2:G17} }}',
        $numbers[0],
        $numbers[1],
        $numbers[2]
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
    Invoke-LoggedTool -name ("RESOURCE_COMPILE {0}" -f $source) -executable $ResourceCompiler -arguments $arguments
}

function Check-OutputIsFresh([string]$source, [string]$output, [string]$label) {
    Check (Test-Path -LiteralPath $source -PathType Leaf) "${label}_SOURCE_MISSING"
    Check (Test-Path -LiteralPath $output -PathType Leaf) "${label}_OUTPUT_MISSING"
    Check ((Get-Item -LiteralPath $output).Length -gt 0) "${label}_OUTPUT_EMPTY"
    Check ((Get-Item -LiteralPath $output).LastWriteTimeUtc -ge (Get-Item -LiteralPath $source).LastWriteTimeUtc) "${label}_OUTPUT_STALE"
}

foreach ($required in @(
    $SceneCsv, $AssetCatalogCsv, $AssetComponentsCsv, $TowerDeathCsv, $ContentSource, $RuntimeSource,
    $OfficialPrefab, $PlayableTemplate, $DmxConvert, $ResourceCompiler, $ContractTest, (Join-Path $DotaGameRoot 'gameinfo.gi')
)) {
    Check (Test-Path -LiteralPath $required) "REQUIRED_INPUT_MISSING: $required"
}
Check ((Split-Path -Leaf $ContentTarget) -eq 'survival_ta_portrait_probe') 'UNSAFE_CONTENT_TARGET'
Check ((Split-Path -Leaf $GameTarget) -eq 'survival_ta_portrait_probe') 'UNSAFE_GAME_TARGET'

$sceneRows = @(Import-Csv -LiteralPath $SceneCsv)
Check ($sceneRows.Count -eq 1) 'SCENE_CSV_MUST_HAVE_ONE_ROW'
$scene = $sceneRows[0]
$assetId = Get-RowValue $scene 'asset_id'
$assetRows = @(Import-Csv -LiteralPath $AssetCatalogCsv | Where-Object { $_.asset_id -eq $assetId })
Check ($assetRows.Count -eq 1) "ASSET_CSV_ROW_INVALID: $assetId"
$asset = $assetRows[0]
$towerRows = @(Import-Csv -LiteralPath $TowerDeathCsv | Where-Object { $_.model_asset_id -eq $assetId -and $_.enabled -eq '1' })
Check ($towerRows.Count -gt 0) "TOWER_ASSET_NOT_REFERENCED: $assetId"
foreach ($tower in $towerRows) {
    Check ((Get-RowValue $tower 'model_name') -eq (Get-RowValue $asset 'primary_model')) "TOWER_BODY_MODEL_MISMATCH: $($tower.record_id)"
}
$components = @(Import-Csv -LiteralPath $AssetComponentsCsv | Where-Object { $_.asset_id -eq $assetId -and $_.enabled -eq '1' } | Sort-Object { [int]$_.sort_order })
Check ($components.Count -eq 3) 'TA_COMPONENT_COUNT_MUST_BE_THREE'
Check (($components.component_id -join ',') -eq 'head,shoulder,armor') 'TA_COMPONENT_ORDER_INVALID'
foreach ($component in $components) {
    Check ((Get-RowValue $component 'entity_class') -eq 'prop_dynamic') "TA_COMPONENT_CLASS_INVALID: $($component.component_id)"
    Check ((Get-RowValue $component 'attach_mode') -eq 'bone_merge') "TA_COMPONENT_ATTACH_MODE_INVALID: $($component.component_id)"
    Check ([string]::IsNullOrEmpty((Get-RowValue $component 'parent_component_id'))) "TA_COMPONENT_PARENT_COMPONENT_UNEXPECTED: $($component.component_id)"
    Check ((Get-RowValue $component 'default_sequence') -eq (Get-RowValue $asset 'default_sequence')) "TA_COMPONENT_SEQUENCE_MISMATCH: $($component.component_id)"
}

Remove-Item -LiteralPath $ContentTarget -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $GameTarget -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Path $ContentTarget -Force | Out-Null
New-Item -ItemType Directory -Path $GameTarget -Force | Out-Null
Copy-Tree $ContentSource $ContentTarget
Copy-Tree $RuntimeSource $GameTarget

$contentMapsRoot = Join-Path $ContentTarget 'maps'
$sceneRelative = (Get-RowValue $scene 'scene_map') -replace '/', '\'
$sceneTarget = Join-Path (Join-Path $contentMapsRoot ($sceneRelative | Split-Path -Parent)) ((Split-Path -Leaf $sceneRelative) + '.vmap')
New-Item -ItemType Directory -Path (Split-Path -Parent $sceneTarget) -Force | Out-Null
Invoke-LoggedTool -name 'DMX_CONVERT TA_PORTRAIT_TEMPLATE' -executable $DmxConvert -arguments @('-i', $OfficialPrefab, '-ie', 'binary', '-o', $sceneTarget, '-oe', 'keyvalues2', '-of', 'vmap')

$templateText = [IO.File]::ReadAllText($sceneTarget)
$propAnchor = '"classname" "string" "prop_dynamic"'
$bodyBlock = Get-DmxEntityBlock $templateText '"targetname" "string" "grass_cyclone"'
$lightAnchor = '"classname" "string" "env_global_light"'
$cameraAnchor = '"classname" "string" "point_camera"'
$worldAnchor = '"world" "CMapWorld"'
$bodyTargetname = Get-RowValue $scene 'body_targetname'
$bodySequence = Get-RowValue $asset 'default_sequence'
$bodyScale = Get-RowValue $asset 'model_scale'
$commonOrigin = Get-RowValue $scene 'body_origin'
$commonAngles = Get-RowValue $scene 'body_angles'
$forceHidden = Get-RowValue $scene 'force_hidden'
$editorOnly = Get-RowValue $scene 'editor_only'

function Configure-BodyBaselineBlock([string]$block, [int]$nodeId) {
    $block = Set-StringPropertyAfterAnchor $block $propAnchor 'targetname' $bodyTargetname
    $block = Set-StringPropertyAfterAnchor $block $propAnchor 'parentname' ''
    $block = Set-StringPropertyAfterAnchor $block $propAnchor 'parentAttachmentName' ''
    $block = Set-StringPropertyAfterAnchor $block $propAnchor 'model' (Get-RowValue $asset 'primary_model')
    $block = Set-StringPropertyAfterAnchor $block $propAnchor 'skin' 'default'
    $block = Set-StringPropertyAfterAnchor $block $propAnchor 'StartDisabled' '0'
    $block = Set-StringPropertyAfterAnchor $block $propAnchor 'StartingAnim' $bodySequence
    $block = Set-StringPropertyAfterAnchor $block $propAnchor 'IdleAnim' $bodySequence
    $block = Set-StringPropertyAfterAnchor $block $propAnchor 'updatechildren' '1'
    $block = Set-TypedPropertyAfterAnchor $block $propAnchor 'origin' 'vector3' $commonOrigin
    $block = Set-TypedPropertyAfterAnchor $block $propAnchor 'angles' 'qangle' $commonAngles
    $block = Set-TypedPropertyAfterAnchor $block $propAnchor 'scales' 'vector3' "$bodyScale $bodyScale $bodyScale"
    $block = Set-TypedPropertyAfterAnchor $block $propAnchor 'force_hidden' 'bool' $forceHidden
    $block = Set-TypedPropertyAfterAnchor $block $propAnchor 'editorOnly' 'bool' $editorOnly
    return Set-UniqueDmxIds $block $nodeId
}

$sceneEntities = @()
$sceneEntities += Configure-BodyBaselineBlock $bodyBlock 101

$lightBlock = Get-DmxEntityBlock $templateText $lightAnchor
$lightBlock = Set-StringPropertyAfterAnchor $lightBlock $lightAnchor 'targetname' (Get-RowValue $scene 'light_targetname')
$lightBlock = Set-StringPropertyAfterAnchor $lightBlock $lightAnchor 'StartDisabled' '0'
$lightBlock = Set-StringPropertyAfterAnchor $lightBlock $lightAnchor 'color' (Get-RowValue $scene 'light_color')
$lightBlock = Set-StringPropertyAfterAnchor $lightBlock $lightAnchor 'lightscale' (Get-RowValue $scene 'light_scale')
$lightBlock = Set-StringPropertyAfterAnchor $lightBlock $lightAnchor 'ambientcolor1' (Get-RowValue $scene 'ambient_color1')
$lightBlock = Set-StringPropertyAfterAnchor $lightBlock $lightAnchor 'ambientscale1' (Get-RowValue $scene 'ambient_scale1')
$lightBlock = Set-StringPropertyAfterAnchor $lightBlock $lightAnchor 'ambientcolor2' (Get-RowValue $scene 'ambient_color2')
$lightBlock = Set-StringPropertyAfterAnchor $lightBlock $lightAnchor 'ambientscale2' (Get-RowValue $scene 'ambient_scale2')
$lightBlock = Set-TypedPropertyAfterAnchor $lightBlock $lightAnchor 'origin' 'vector3' (Get-RowValue $scene 'light_origin')
$lightBlock = Set-TypedPropertyAfterAnchor $lightBlock $lightAnchor 'angles' 'qangle' (Get-RowValue $scene 'light_angles')
$sceneEntities += Set-UniqueDmxIds $lightBlock 105

$cameraBlock = Get-DmxEntityBlock $templateText $cameraAnchor
$cameraAngles = Get-LookAngles (Get-RowValue $scene 'camera_origin') (Get-RowValue $scene 'camera_target')
$cameraBlock = Set-StringPropertyAfterAnchor $cameraBlock $cameraAnchor 'targetname' (Get-RowValue $scene 'camera_name')
$cameraBlock = Set-StringPropertyAfterAnchor $cameraBlock $cameraAnchor 'parentname' ''
$cameraBlock = Set-StringPropertyAfterAnchor $cameraBlock $cameraAnchor 'parentAttachmentName' ''
$cameraBlock = Set-StringPropertyAfterAnchor $cameraBlock $cameraAnchor 'FOV' (Get-RowValue $scene 'camera_fov')
$cameraBlock = Set-StringPropertyAfterAnchor $cameraBlock $cameraAnchor 'dof_enabled' '0'
$cameraBlock = Set-TypedPropertyAfterAnchor $cameraBlock $cameraAnchor 'origin' 'vector3' (Get-RowValue $scene 'camera_origin')
$cameraBlock = Set-TypedPropertyAfterAnchor $cameraBlock $cameraAnchor 'angles' 'qangle' $cameraAngles
$sceneEntities += Set-UniqueDmxIds $cameraBlock 106

$templateText = Set-StringPropertyAfterAnchor $templateText $worldAnchor 'mapUsageType' (Get-RowValue $scene 'map_usage_type')
$templateText = Set-DmxWorldChildren $templateText $sceneEntities
$classNames = @([regex]::Matches($templateText, '"classname" "string" "([^"]+)"') | ForEach-Object { $_.Groups[1].Value })
Check (($classNames | Where-Object { $_ -eq 'worldspawn' }).Count -eq 1) 'WORLDSPAWN_COUNT_INVALID'
Check (($classNames | Where-Object { $_ -eq 'prop_dynamic' }).Count -eq 1) 'STATIC_BASELINE_PROP_DYNAMIC_COUNT_INVALID'
Check (($classNames | Where-Object { $_ -eq 'env_global_light' }).Count -eq 1) 'LIGHT_COUNT_INVALID'
Check (($classNames | Where-Object { $_ -eq 'point_camera' }).Count -eq 1) 'CAMERA_COUNT_INVALID'
Check (($classNames | Where-Object { $_ -notin @('worldspawn', 'prop_dynamic', 'env_global_light', 'point_camera') }).Count -eq 0) 'UNEXPECTED_ENTITY_CLASS'
Check (-not $templateText.Contains('portrait_world_unit')) 'PORTRAIT_WORLD_UNIT_UNEXPECTED'
Check (-not $templateText.Contains('!bonemerge')) 'UNVALIDATED_BONEMERGE_KEY_UNEXPECTED'
Check (-not $templateText.Contains('DisableBoneMerge')) 'UNVALIDATED_DISABLE_BONEMERGE_KEY_UNEXPECTED'
foreach ($component in $components) {
    Check (-not $templateText.Contains((Get-RowValue $component 'model_path'))) "STATIC_WEARABLE_MODEL_UNEXPECTED: $($component.component_id)"
}
[IO.File]::WriteAllText($sceneTarget, $templateText, $Utf8NoBom)

$dataDirectory = Join-Path $ContentTarget 'data'
New-Item -ItemType Directory -Path $dataDirectory -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $GameTarget 'data') -Force | Out-Null
Copy-Item -LiteralPath $SceneCsv -Destination (Join-Path $dataDirectory 'scene.csv') -Force
Copy-Item -LiteralPath $SceneCsv -Destination (Join-Path $GameTarget 'data\scene.csv') -Force

$resolvedRows = @([pscustomobject]@{
    kind = 'body'
    component_id = ''
    model_path = Get-RowValue $asset 'primary_model'
    entity_class = 'prop_dynamic'
    attach_mode = 'body'
    default_sequence = $bodySequence
    model_scale = $bodyScale
    parentname = ''
})
foreach ($component in $components) {
    $resolvedRows += [pscustomobject]@{
        kind = 'wearable'
        component_id = Get-RowValue $component 'component_id'
        model_path = Get-RowValue $component 'model_path'
        entity_class = Get-RowValue $component 'entity_class'
        attach_mode = Get-RowValue $component 'attach_mode'
        default_sequence = Get-RowValue $component 'default_sequence'
        model_scale = Get-RowValue $component 'model_scale'
        parentname = ''
    }
}
$resolvedCsv = ($resolvedRows | ConvertTo-Csv -NoTypeInformation) -join "`r`n"
[IO.File]::WriteAllText((Join-Path $dataDirectory 'ta_portrait_resolved.csv'), ($resolvedCsv + "`r`n"), $Utf8NoBom)
Copy-Item -LiteralPath (Join-Path $dataDirectory 'ta_portrait_resolved.csv') -Destination (Join-Path $GameTarget 'data\ta_portrait_resolved.csv') -Force

$layoutTemplate = Join-Path $ContentTarget 'panorama\layout\custom_game\ta_portrait_probe.xml.in'
$layoutTarget = Join-Path $ContentTarget 'panorama\layout\custom_game\ta_portrait_probe.xml'
$layoutText = [IO.File]::ReadAllText($layoutTemplate)
$layoutText = $layoutText.Replace('__SCENE_MAP__', (Get-RowValue $scene 'scene_map'))
$layoutText = $layoutText.Replace('__CAMERA_NAME__', (Get-RowValue $scene 'camera_name'))
$layoutText = $layoutText.Replace('__LIGHT_TARGETNAME__', (Get-RowValue $scene 'light_targetname'))
$layoutText = $layoutText.Replace('__PARTICLE_ONLY__', (Get-RowValue $scene 'particle_only'))
Check (-not $layoutText.Contains('__')) 'UNRESOLVED_LAYOUT_PLACEHOLDER'
[IO.File]::WriteAllText($layoutTarget, $layoutText, $Utf8NoBom)
Remove-Item -LiteralPath $layoutTemplate -Force

$runtimeData = [ordered]@{
    addonName = Get-RowValue $scene 'addon_name'
    assetId = $assetId
    sceneMap = Get-RowValue $scene 'scene_map'
    camera = Get-RowValue $scene 'camera_name'
    light = Get-RowValue $scene 'light_targetname'
    runtimeTable = [ordered]@{
        name = 'ta_portrait_probe'
        key = 'runtime'
    }
    body = [ordered]@{
        targetname = $bodyTargetname
        model = Get-RowValue $asset 'primary_model'
        unit = Get-RowValue $asset 'portrait_unit_name'
        sequence = $bodySequence
    }
    wearables = @($components | ForEach-Object {
        [ordered]@{
            id = Get-RowValue $_ 'component_id'
            model = Get-RowValue $_ 'model_path'
            entityClass = Get-RowValue $_ 'entity_class'
            attachMode = Get-RowValue $_ 'attach_mode'
        }
    })
}
$runtimeJson = ConvertTo-Json -InputObject $runtimeData -Compress -Depth 6
$dataScriptPath = Join-Path $ContentTarget 'panorama\scripts\custom_game\ta_portrait_probe_data.js'
$dataScript = "(function () {`n    GameUI.CustomUIConfig().TAPortraitProbeData = $runtimeJson;`n})();`n"
[IO.File]::WriteAllText($dataScriptPath, $dataScript, $Utf8NoBom)

$bodyOriginLua = ConvertTo-LuaVector (Get-RowValue $scene 'body_origin') 'body_origin'
$bodyAnglesLua = ConvertTo-LuaVector (Get-RowValue $scene 'body_angles') 'body_angles'
$wearableConfigRows = @($components | ForEach-Object {
    $componentId = Get-RowValue $_ 'component_id'
    @"
        {
            id = $(ConvertTo-LuaString $componentId),
            targetname = $(ConvertTo-LuaString ('ta_portrait_wearable_' + $componentId)),
            model = $(ConvertTo-LuaString (Get-RowValue $_ 'model_path')),
            entity_class = $(ConvertTo-LuaString (Get-RowValue $_ 'entity_class')),
            attach_mode = $(ConvertTo-LuaString (Get-RowValue $_ 'attach_mode')),
            model_scale = $(Get-RowValue $_ 'model_scale'),
        },
"@
})
$runtimeConfig = @"
-- Generated by tools/build_ta_portrait_probe.ps1 from catalog/component/scene CSV data.
return {
    source = "generated_from_csv",
    body = {
        targetname = $(ConvertTo-LuaString $bodyTargetname),
        model = $(ConvertTo-LuaString (Get-RowValue $asset 'primary_model')),
        sequence = $(ConvertTo-LuaString $bodySequence),
        model_scale = $bodyScale,
        origin = $bodyOriginLua,
        angles = $bodyAnglesLua,
    },
    wearables = {
$($wearableConfigRows -join '')    },
}
"@
$runtimeConfigPath = Join-Path $GameTarget 'scripts\vscripts\ta_portrait_probe_runtime_config.lua'
[IO.File]::WriteAllText($runtimeConfigPath, $runtimeConfig, $Utf8NoBom)

$playableTarget = Join-Path $ContentTarget 'maps\ta_portrait_probe_lab.vmap'
Copy-Item -LiteralPath $PlayableTemplate -Destination $playableTarget -Force

& $ContractTest -GeneratedContentRoot $ContentTarget -GeneratedGameRoot $GameTarget

if (-not $SkipCompile) {
    Invoke-ResourceCompile $playableTarget $false
    Invoke-ResourceCompile $sceneTarget $true
    foreach ($resource in @(
        (Join-Path $ContentTarget 'panorama\layout\custom_game\custom_ui_manifest.xml'),
        $layoutTarget,
        $dataScriptPath,
        (Join-Path $ContentTarget 'panorama\scripts\custom_game\ta_portrait_probe.js'),
        (Join-Path $ContentTarget 'panorama\styles\custom_game\ta_portrait_probe.css')
    )) {
        Invoke-ResourceCompile $resource $false
    }

    Check-OutputIsFresh $playableTarget (Join-Path $GameTarget 'maps\ta_portrait_probe_lab.vpk') 'PLAYABLE_MAP'
    Check-OutputIsFresh $sceneTarget (Join-Path $GameTarget 'maps\ta_portrait\templar_assassin.vpk') 'SCENE_MAP'
    foreach ($panoramaOutput in @(
        [pscustomobject]@{ Source = 'panorama\layout\custom_game\custom_ui_manifest.xml'; Output = 'panorama\layout\custom_game\custom_ui_manifest.vxml_c' },
        [pscustomobject]@{ Source = 'panorama\layout\custom_game\ta_portrait_probe.xml'; Output = 'panorama\layout\custom_game\ta_portrait_probe.vxml_c' },
        [pscustomobject]@{ Source = 'panorama\scripts\custom_game\ta_portrait_probe_data.js'; Output = 'panorama\scripts\custom_game\ta_portrait_probe_data.vjs_c' },
        [pscustomobject]@{ Source = 'panorama\scripts\custom_game\ta_portrait_probe.js'; Output = 'panorama\scripts\custom_game\ta_portrait_probe.vjs_c' },
        [pscustomobject]@{ Source = 'panorama\styles\custom_game\ta_portrait_probe.css'; Output = 'panorama\styles\custom_game\ta_portrait_probe.vcss_c' }
    )) {
        Check-OutputIsFresh (Join-Path $ContentTarget $panoramaOutput.Source) (Join-Path $GameTarget $panoramaOutput.Output) ("PANORAMA_{0}" -f $panoramaOutput.Output)
    }
}

Write-Host 'TA_PORTRAIT_PROBE_BUILD_PASS' -ForegroundColor Green
Write-Host "Content addon: $ContentTarget"
Write-Host "Game addon: $GameTarget"
Write-Host "Compiler log: $BuildLog"
