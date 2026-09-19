param(
    [string]$GameRoot = ''
)

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($GameRoot)) {
    $GameRoot = $repo
}
function Check([bool]$condition, [string]$message) {
    if (-not $condition) { throw $message }
}

function ReadText([string]$path) {
    Check (Test-Path -LiteralPath $path -PathType Leaf) "MISSING_FILE: $path"
    return [IO.File]::ReadAllText($path)
}

function GetField([object]$row, [string]$name) {
    return [string]$row.$name
}

function GetBalancedBlock([string]$text, [string]$key) {
    $anchor = '"' + $key + '"'
    $start = $text.IndexOf($anchor, [StringComparison]::Ordinal)
    Check ($start -ge 0) "KV_KEY_MISSING: $key"
    $open = $text.IndexOf('{', $start)
    Check ($open -ge 0) "KV_BLOCK_OPEN_MISSING: $key"

    $depth = 0
    $quoted = $false
    $escaped = $false
    for ($index = $open; $index -lt $text.Length; $index++) {
        $character = $text[$index]
        if ($quoted) {
            if ($escaped) {
                $escaped = $false
            } elseif ($character -eq '\') {
                $escaped = $true
            } elseif ($character -eq '"') {
                $quoted = $false
            }
            continue
        }
        if ($character -eq '"') {
            $quoted = $true
        } elseif ($character -eq '{') {
            $depth++
        } elseif ($character -eq '}') {
            $depth--
            if ($depth -eq 0) {
                return $text.Substring($start, $index - $start + 1)
            }
        }
    }
    throw "KV_BLOCK_CLOSE_MISSING: $key"
}

function GetNestedBlock([string]$block, [string]$key) {
    return GetBalancedBlock $block $key
}

$csvRoot = Join-Path $repo 'data\csv'
$resourceCsvDirectory = @(
    Get-ChildItem -LiteralPath $csvRoot -Directory |
        Where-Object {
            (Test-Path (Join-Path $_.FullName 'asset_native_wearable_stages.csv')) -and
            (Test-Path (Join-Path $_.FullName 'asset_native_wearables.csv')) -and
            (Test-Path (Join-Path $_.FullName 'asset_catalog.csv'))
        }
)
Check ($resourceCsvDirectory.Count -eq 1) 'RESOURCE_CSV_DIRECTORY_INVALID'
$stagePath = Join-Path $resourceCsvDirectory[0].FullName 'asset_native_wearable_stages.csv'
$wearablePath = Join-Path $resourceCsvDirectory[0].FullName 'asset_native_wearables.csv'
$componentPath = Join-Path $resourceCsvDirectory[0].FullName 'asset_components.csv'
$catalogPath = Join-Path $resourceCsvDirectory[0].FullName 'asset_catalog.csv'
$npcPath = Join-Path $GameRoot 'scripts\npc\npc_units_custom.txt'
$generatedWearablePath = Join-Path $GameRoot 'scripts\vscripts\config\generated\asset_native_wearables.lua'
$generatedComponentPath = Join-Path $GameRoot 'scripts\vscripts\config\generated\asset_components.lua'
$stages = @(Import-Csv -LiteralPath $stagePath | Where-Object { $_.asset_id -notlike '#*' })
$wearables = @(Import-Csv -LiteralPath $wearablePath | Where-Object { $_.wearable_key -notlike '#*' })
$components = @(Import-Csv -LiteralPath $componentPath | Where-Object { $_.component_key -notlike '#*' })
$componentsByKey = @{}
foreach ($row in $components) { $componentsByKey[(GetField $row 'component_key')] = $row }
$catalog = @{}
foreach ($row in @(Import-Csv -LiteralPath $catalogPath | Where-Object { $_.asset_id -notlike '#*' })) {
    $catalog[(GetField $row 'asset_id')] = $row
}
$npcText = ReadText $npcPath
$generatedWearableText = ReadText $generatedWearablePath
$generatedComponentText = ReadText $generatedComponentPath

Check ($stages.Count -eq 21) "NATIVE_STAGE_COUNT_INVALID: $($stages.Count)"
Check (($stages | Select-Object -ExpandProperty asset_id -Unique).Count -eq 21) 'NATIVE_STAGE_ASSET_IDS_NOT_UNIQUE'

foreach ($stage in $stages) {
    $assetId = GetField $stage 'asset_id'
    $asset = $catalog[$assetId]
    Check ($null -ne $asset) "CATALOG_ASSET_MISSING: $assetId"
    $proxyName = GetField $asset 'async_unit_name'
    $bodyModel = GetField $stage 'body_model'
    Check (-not [string]::IsNullOrWhiteSpace($proxyName)) "PRELOAD_PROXY_UNIT_MISSING: $assetId"
    Check ((GetField $asset 'primary_model') -eq $bodyModel) "BODY_MODEL_CSV_MISMATCH: $assetId"

    $proxy = GetBalancedBlock $npcText $proxyName
    Check ($proxy -match '"BaseClass"\s+"npc_dota_creature"') "PROXY_BASE_CLASS_INVALID: $assetId"
    $modelMatch = [regex]::Match($proxy, '"Model"\s+"([^"]+)"')
    Check ($modelMatch.Success -and $modelMatch.Groups[1].Value -eq $bodyModel) "PROXY_BODY_MODEL_INVALID: $assetId"

    $expectedRows = @($wearables |
        Where-Object {
            $_.asset_id -eq $assetId -and
            $_.enabled -ne '0'
        } |
        Sort-Object @{ Expression = { [int]$_.sort_order } }, wearable_key)
    Check (-not $proxy.Contains('"AttachWearables"')) "PROXY_AUTO_ATTACH_FORBIDDEN: $assetId"
    $precache = $null
    if ($proxy.Contains('"precache"')) {
        $precache = GetNestedBlock $proxy 'precache'
    }
    $expectedModels = @($expectedRows |
        Where-Object { -not [string]::IsNullOrWhiteSpace((GetField $_ 'model_path')) } |
        ForEach-Object { GetField $_ 'model_path' })
    $actualModels = @()
    if ($null -ne $precache) {
        $actualModels = @([regex]::Matches($precache, '"model"\s+"([^"]+)"') |
            ForEach-Object { $_.Groups[1].Value })
    }
    Check ($actualModels.Count -eq $expectedModels.Count) "PROXY_PRECACHE_MODEL_COUNT_INVALID: $assetId"
    for ($index = 0; $index -lt $expectedModels.Count; $index++) {
        Check ($actualModels[$index] -eq $expectedModels[$index]) "PROXY_PRECACHE_MODEL_INVALID: $assetId index=$index"
    }
    foreach ($row in $expectedRows) {
        $itemDef = GetField $row 'item_def'
        $modelPath = GetField $row 'model_path'
        Check ((GetField $row 'entity_class') -eq 'prop_dynamic') "WEARABLE_ENTITY_CLASS_INVALID: $($row.wearable_key)"
        Check ((GetField $row 'attach_mode') -eq 'bone_merge') "WEARABLE_ATTACH_MODE_INVALID: $($row.wearable_key)"
        Check (([string]::IsNullOrWhiteSpace($itemDef)) -eq ([string]::IsNullOrWhiteSpace($modelPath))) "WEARABLE_ITEM_MODEL_PAIR_INVALID: $($row.wearable_key)"
        if (-not [string]::IsNullOrWhiteSpace($itemDef)) {
            Check ($itemDef -match '^\d+$') "WEARABLE_ITEMDEF_NOT_NUMERIC: $($row.wearable_key)"
            $componentKey = $assetId + ':' + (GetField $row 'wearable_key')
            $component = $componentsByKey[$componentKey]
            Check ($null -ne $component) "WORLD_COMPONENT_MISSING: $componentKey"
            Check ((GetField $component 'component_id') -eq (GetField $row 'wearable_key')) "WORLD_COMPONENT_ID_INVALID: $componentKey"
            Check ((GetField $component 'model_path') -eq $modelPath) "WORLD_COMPONENT_MODEL_INVALID: $componentKey"
            Check ((GetField $component 'entity_class') -eq 'prop_dynamic') "WORLD_COMPONENT_CLASS_INVALID: $componentKey"
            Check ((GetField $component 'attach_mode') -eq 'bone_merge') "WORLD_COMPONENT_ATTACH_INVALID: $componentKey"
            Check ((GetField $component 'sort_order') -eq (GetField $row 'sort_order')) "WORLD_COMPONENT_ORDER_INVALID: $componentKey"
            Check ($generatedComponentText.Contains('component_key = "' + $componentKey + '"')) "GENERATED_WORLD_COMPONENT_MISSING: $componentKey"
        }
    }
    $expectedItemDefs = @($expectedRows |
        Where-Object { -not [string]::IsNullOrWhiteSpace((GetField $_ 'item_def')) } |
        ForEach-Object { GetField $_ 'item_def' })
    $generatedRows = @([regex]::Matches(
        $generatedWearableText,
        ('\{ wearable_key = "[^"]+", asset_id = "' +
            [regex]::Escape($assetId) + '"[^\r\n]*\}')
    ) | ForEach-Object { $_.Value })
    $generatedItemDefs = @($generatedRows |
        ForEach-Object {
            $match = [regex]::Match($_, 'item_def = "([^"]*)"')
            if ($match.Success -and $match.Groups[1].Value -ne '') {
                $match.Groups[1].Value
            }
        })
    Check ($generatedItemDefs.Count -eq $expectedItemDefs.Count) "GENERATED_ITEMDEF_COUNT_INVALID: $assetId"
    for ($index = 0; $index -lt $expectedItemDefs.Count; $index++) {
        Check ($generatedItemDefs[$index] -eq $expectedItemDefs[$index]) "GENERATED_ITEMDEF_ORDER_INVALID: $assetId index=$index"
    }
}

$towerComponents = @($components | Where-Object { $catalog.ContainsKey((GetField $_ 'asset_id')) -and (GetField $_ 'asset_id') -like 'tower_*' })
Check ($towerComponents.Count -eq 97) "WORLD_COMPONENT_COUNT_INVALID: $($towerComponents.Count)"
Check (@($towerComponents | Where-Object { (GetField $_ 'asset_id') -eq 'tower_laser_od_blackgate' }).Count -eq 0) 'IO_WORLD_COMPONENTS_MUST_BE_ZERO'
Write-Output "HERO_BODY_STAGE_CONTRACT_PASS stages=$($stages.Count) wearables=$($wearables.Count) components=$($towerComponents.Count)"
