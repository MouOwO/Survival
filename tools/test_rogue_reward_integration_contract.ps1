$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot

function Read-Utf8([string]$Path) {
    return [IO.File]::ReadAllText(
        $Path,
        [Text.UTF8Encoding]::new($false, $true)
    )
}

function Check($Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}

$events = Read-Utf8 (Join-Path $root 'scripts\vscripts\core\events.lua')
$addon = Read-Utf8 (Join-Path $root 'scripts\vscripts\addon_game_mode.lua')
$ability = Read-Utf8 (Join-Path $root 'scripts\vscripts\abilities\ability_survival_rogue_reward.lua')
$progression = Read-Utf8 (Join-Path $root 'scripts\vscripts\systems\builder_progression_system.lua')
$runtime = Read-Utf8 (Join-Path $root 'scripts\vscripts\ui\ability_runtime_service.lua')
$wave = Read-Utf8 (Join-Path $root 'scripts\vscripts\systems\wave_system.lua')
$router = Read-Utf8 (Join-Path $root 'scripts\vscripts\ui\ui_request_router.lua')
$runtimeBuilder = Read-Utf8 (Join-Path $root 'scripts\vscripts\ui\ability_runtime_builder.lua')
$tooltipCsvPath = [IO.Directory]::GetFiles(
    (Join-Path $root 'data\csv'), 'tooltip_definitions.csv',
    [IO.SearchOption]::AllDirectories
) | Select-Object -First 1
$tooltipCsv = Read-Utf8 $tooltipCsvPath
$contentRoot = Join-Path $root '..\..\..\content\dota_addons\survival'
$combat = Read-Utf8 (Join-Path $contentRoot 'panorama\scripts\custom_game\combat_stats.js')
$tooltip = Read-Utf8 (Join-Path $contentRoot 'panorama\scripts\custom_game\ability_tooltip.js')
$stagesPath = [IO.Directory]::GetFiles(
    (Join-Path $root 'data\csv'), 'builder_ability_stages.csv',
    [IO.SearchOption]::AllDirectories
) | Select-Object -First 1
$stages = Import-Csv -LiteralPath $stagesPath

$eventNames = @(
    'ROGUE_REWARD_OPEN_REQUEST',
    'ROGUE_REWARD_SELECT_REQUEST',
    'ROGUE_REWARD_REROLL_REQUEST',
    'ROGUE_REWARD_GRANT_RANDOM_REQUEST',
    'ROGUE_REWARD_CONSUMED_GET_REQUEST',
    'ROGUE_REWARD_CHANGED'
)
foreach ($name in $eventNames) {
    Check ($events -match ("(?m)^\s+{0}\s*=\s*`"[^`"]+`",$" -f $name)) `
        ("ROGUE_EVENT_MISSING_{0}" -f $name)
}

$builderReward = @($stages | Where-Object {
    $_.stage_id -eq 'wall_pending' -and
    $_.ability_name -eq 'ability_survival_rogue_reward'
})
Check ($builderReward.Count -eq 1) 'BUILDER_ROGUE_STAGE_MISSING_OR_DUPLICATED'
Check ([int]$builderReward[0].slot_order -eq 7) 'BUILDER_ROGUE_NOT_IN_G_SLOT'
Check ($addon.Contains('require("systems/rogue_reward_service").init()')) `
    'ROGUE_REWARD_SERVICE_NOT_INITIALIZED'
Check ($ability.Contains('events.ROGUE_REWARD_OPEN_REQUEST') -and
    $ability.Contains('source = "builder"') -and
    -not $ability.Contains('RemoveAbility')) `
    'BUILDER_ROGUE_ABILITY_FLOW_INCOMPLETE'
Check ($progression.Contains('events.ROGUE_REWARD_CONSUMED_GET_REQUEST') -and
    $progression.Contains('events.ROGUE_REWARD_CHANGED') -and
    $progression.Contains('ensure_rogue_ability') -and
    $progression.Contains('BUILDER_ROGUE_SLOT_ORDER')) `
    'BUILDER_ROGUE_CONSUMPTION_SYNC_MISSING'
Check ($runtime.Contains('runtime.builder_slot_order = builder_slot_order_by_ability[ability_name]')) `
    'BUILDER_SLOT_RUNTIME_PROJECTION_MISSING'
Check ($runtimeBuilder.Contains('ability_survival_rogue_reward') -and
    $runtimeBuilder.Contains('display_name = row.name') -and
    $runtimeBuilder.Contains('value = "G"')) 'BUILDER_ROGUE_TOOLTIP_RUNTIME_MISSING'
Check (($tooltipCsv -split "`n" | Where-Object { $_ -match '^ability:ability_survival_rogue_reward,' }).Count -eq 1) `
    'BUILDER_ROGUE_TOOLTIP_CSV_MISSING'
Check ($combat.Contains('6: "A", 7: "G"') -and
    $combat.Contains('abilityName === "ability_survival_rogue_reward"') -and
    $combat.Contains('"builder_key_dispatch"')) 'BUILDER_ROGUE_G_INPUT_MISSING'
Check ($tooltip.Contains('abilityName === "ability_survival_rogue_reward"')) `
    'BUILDER_ROGUE_CLICK_PROXY_MISSING'
Check ($router.Contains('events.ROGUE_REWARD_OPEN_REQUEST') -and
    -not $router.Contains('unit:RemoveAbility(ability_name)')) 'BUILDER_ROGUE_ROUTER_MISSING'
Check ($wave.Contains('if meta.is_boss then') -and
    $wave.Contains('player_context.active_player_ids()') -and
    $wave.Contains('events.ROGUE_REWARD_OPEN_REQUEST') -and
    $wave.Contains('source = "boss"')) `
    'BOSS_ROGUE_REWARD_DISPATCH_MISSING'

Write-Output 'ROGUE_REWARD_INTEGRATION_CONTRACT_PASS'