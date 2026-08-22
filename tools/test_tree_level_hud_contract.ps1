$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$dotaRoot = Split-Path -Parent `
    (Split-Path -Parent (Split-Path -Parent $root))
$contentRoot = Join-Path $dotaRoot `
    "content\dota_addons\survival"

$router = Get-Content -LiteralPath (Join-Path $root `
    "scripts\vscripts\ui\ui_request_router.lua") -Raw
$client = Get-Content -LiteralPath (Join-Path $contentRoot `
    "panorama\scripts\custom_game\combat_stats.js") -Raw

function Check([bool] $condition, [string] $message) {
    if (-not $condition) { throw $message }
}

Check ($router.Contains('require("config/tree_config")')) `
    "TREE_LEVEL_CONFIG_MISSING"
Check ($router.Contains("is_resource_tree")) `
    "TREE_LEVEL_MARKER_MISSING"
Check ($router.Contains("max_level")) `
    "TREE_MAX_LEVEL_SNAPSHOT_MISSING"
Check ($router.Contains("event_bus.subscribe(events.TREE_CHANGED")) `
    "TREE_CHANGED_SELECTED_SNAPSHOT_MISSING"
Check ($client.Contains("displayNameWithTreeLevel")) `
    "TREE_LEVEL_RENDERER_MISSING"
Check ($client.Contains('return "大树等级 "')) `
    "TREE_LEVEL_HUD_TEXT_MISSING"

Write-Output "TREE_LEVEL_HUD_CONTRACT_PASS"