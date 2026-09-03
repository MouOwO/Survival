param(
    [string]$Template = (Join-Path $PSScriptRoot 'jugg_portrait_template.vmap'),
    [string]$Output = 'D:\SteamLibrary\steamapps\common\dota 2 beta\content\dota_addons\Survival\maps\portraits\juggernaut_arcana_origins_v4.vmap'
)

$ErrorActionPreference = 'Stop'
$utf8 = New-Object System.Text.UTF8Encoding($false)

function Find-Balanced([string]$text, [int]$open, [char]$left, [char]$right) {
    $depth = 0; $quoted = $false; $escaped = $false
    for ($i = $open; $i -lt $text.Length; $i++) {
        $c = $text[$i]
        if ($quoted) {
            if ($escaped) { $escaped = $false }
            elseif ($c -eq '\') { $escaped = $true }
            elseif ($c -eq '"') { $quoted = $false }
            continue
        }
        if ($c -eq '"') { $quoted = $true }
        elseif ($c -eq $left) { $depth++ }
        elseif ($c -eq $right) { $depth--; if ($depth -eq 0) { return $i } }
    }
    throw 'BALANCED_DELIMITER_NOT_FOUND'
}

function Get-WorldBlocks([string]$text) {
    $anchor = $text.IndexOf('"children" "element_array"')
    if ($anchor -lt 0) { throw 'WORLD_CHILDREN_MISSING' }
    $open = $text.IndexOf('[', $anchor)
    $close = Find-Balanced $text $open '[' ']'
    $cursor = $open + 1; $result = @()
    while ($cursor -lt $close) {
        $entity = $text.IndexOf('"CMapEntity"', $cursor)
        if ($entity -lt 0 -or $entity -ge $close) { break }
        $brace = $text.IndexOf('{', $entity)
        $entityClose = Find-Balanced $text $brace '{' '}'
        $result += $text.Substring($entity, $entityClose - $entity + 1)
        $cursor = $entityClose + 1
    }
    return [pscustomobject]@{ Open = $open; Close = $close; Blocks = $result }
}

function Value([string]$block, [string]$property) {
    $m = [regex]::Match($block, '"' + [regex]::Escape($property) + '" "(?:string|vector3|qangle|int|bool)" "([^"]*)"')
    if ($m.Success) { return $m.Groups[1].Value }
    return ''
}

function Set-Value([string]$block, [string]$property, [string]$value) {
    $pattern = '("' + [regex]::Escape($property) + '" "(?:string|vector3|qangle|int|bool)" ")[^"]*(")'
    $m = [regex]::Match($block, $pattern)
    if (-not $m.Success) { throw "PROPERTY_MISSING: $property" }
    return [regex]::Replace($block, $pattern, {
        param($match)
        $match.Groups[1].Value + $value + $match.Groups[2].Value
    }, 1)
}

function New-Id([string]$block) {
    return [regex]::Replace($block, '"id" "elementid" "[^"]+"', {
        param($match)
        '"id" "elementid" "' + ([guid]::NewGuid().ToString()) + '"'
    })
}

$text = [IO.File]::ReadAllText($Template)
$world = Get-WorldBlocks $text
$blocks = $world.Blocks
$bodySource = $blocks | Where-Object { (Value $_ 'classname') -eq 'prop_dynamic' -and (Value $_ 'targetname') -eq 'grass_cyclone' } | Select-Object -First 1
$light = $blocks | Where-Object { (Value $_ 'classname') -eq 'env_global_light' } | Select-Object -First 1
$camera = $blocks | Where-Object { (Value $_ 'classname') -eq 'point_camera' } | Select-Object -First 1
$cameraRig = $blocks | Where-Object { (Value $_ 'classname') -eq 'prop_dynamic_clientside' -and (Value $_ 'targetname') -eq 'debut_camera' } | Select-Object -First 1
if (-not $bodySource -or -not $light -or -not $camera -or -not $cameraRig) { throw 'OFFICIAL_PREFAB_ENTITIES_MISSING' }

$body = $bodySource
$body = Set-Value $body 'targetname' 'jugg_arcana_body'
$body = Set-Value $body 'parentname' ''
$body = Set-Value $body 'parentAttachmentName' ''
$body = Set-Value $body 'model' 'models/heroes/juggernaut/juggernaut_arcana.vmdl'
$body = Set-Value $body 'skin' 'default'
$body = Set-Value $body 'StartingAnim' 'idle'
$body = Set-Value $body 'IdleAnim' 'idle'
$body = Set-Value $body 'origin' '-195.000000 457.000000 71.000000'
$body = Set-Value $body 'angles' '0 203.000000 0'
$body = Set-Value $body 'scales' '1 1 1'
$body = Set-Value $body 'force_hidden' '0'
$body = Set-Value $body 'editorOnly' '0'
$body = New-Id $body

$wearableModels = @(
    @{ Name = 'arms'; Model = 'models/items/juggernaut/armor_for_the_favorite_arms/armor_for_the_favorite_arms.vmdl'; Skin = 'default' },
    @{ Name = 'back'; Model = 'models/items/juggernaut/armor_for_the_favorite_back/armor_for_the_favorite_back.vmdl'; Skin = 'default' },
    @{ Name = 'head'; Model = 'models/items/juggernaut/armor_for_the_favorite_head/armor_for_the_favorite_head.vmdl'; Skin = 'default' },
    @{ Name = 'legs'; Model = 'models/items/juggernaut/armor_for_the_favorite_legs/armor_for_the_favorite_legs.vmdl'; Skin = 'default' },
    @{ Name = 'weapon'; Model = 'models/items/juggernaut/fall20_juggernaut_katz_weapon/fall20_juggernaut_katz_weapon.vmdl'; Skin = '1' }
)
$wearables = @()
foreach ($entry in $wearableModels) {
    $w = $body
    $w = Set-Value $w 'targetname' ('jugg_arcana_' + $entry.Name)
    $w = Set-Value $w 'parentname' 'jugg_arcana_body'
    $w = Set-Value $w 'parentAttachmentName' '!bonemerge'
    $w = Set-Value $w 'model' $entry.Model
    $w = Set-Value $w 'skin' $entry.Skin
    $w = New-Id $w
    $wearables += $w
}

$light = Set-Value $light 'targetname' 'jugg_portrait_light'
$light = Set-Value $light 'origin' '-408.153503 147.133240 255.204865'
$light = Set-Value $light 'angles' '29.544004 17.475599 80.844284'
$light = Set-Value $light 'StartDisabled' '0'
$light = Set-Value $light 'background_clear_not_required' '1'
$light = New-Id $light
$cameraRig = Set-Value $cameraRig 'targetname' 'jugg_portrait_camera_rig'
$cameraRig = Set-Value $cameraRig 'parentname' ''
$cameraRig = Set-Value $cameraRig 'parentAttachmentName' ''
$cameraRig = Set-Value $cameraRig 'origin' '-450.000000 442.977997 158.841003'
$cameraRig = Set-Value $cameraRig 'angles' '0 355.000000 0'
$cameraRig = Set-Value $cameraRig 'force_hidden' '1'
$cameraRig = Set-Value $cameraRig 'editorOnly' '0'
$cameraRig = New-Id $cameraRig
$camera = Set-Value $camera 'targetname' 'jugg_portrait_camera'
$camera = Set-Value $camera 'parentname' 'jugg_portrait_camera_rig'
$camera = Set-Value $camera 'parentAttachmentName' ''
$camera = Set-Value $camera 'origin' '0 0 0'
$camera = Set-Value $camera 'angles' '0 0 0'
$camera = Set-Value $camera 'dof_enabled' '0'
$camera = New-Id $camera

$keep = @($body) + $wearables + @($cameraRig, $light, $camera)
$newChildren = "`r`n" + (($keep -join ",`r`n") -replace '^', "`t`t`t") + "`r`n`t`t"
$text = $text.Substring(0, $world.Open + 1) + $newChildren + $text.Substring($world.Close)
$text = Set-Value $text 'mapUsageType' 'background'
[IO.Directory]::CreateDirectory((Split-Path -Parent $Output)) | Out-Null
[IO.File]::WriteAllText($Output, $text, $utf8)
Write-Host 'JUGGERNAUT_STATIC_PORTRAIT_MAP_PASS'
