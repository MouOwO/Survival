$ErrorActionPreference = "Stop"

$gameRoot = Split-Path -Parent $PSScriptRoot
$dotaRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $gameRoot))
$gameAddonParent = Join-Path $dotaRoot "game\dota_addons"
$contentAddonParent = Join-Path $dotaRoot "content\dota_addons"
$gameTemp = Join-Path $gameAddonParent "__survival_case_migration__"
$contentTemp = Join-Path $contentAddonParent "__survival_case_migration__"
$gameRollbackTemp = Join-Path $gameAddonParent "__survival_case_rollback__"
$contentRollbackTemp = Join-Path $contentAddonParent "__survival_case_rollback__"
$resourceCompiler = Join-Path $dotaRoot "game\bin\win64\resourcecompiler.exe"
$dotaGame = Join-Path $dotaRoot "game\dota"

function Get-SurvivalAddonPath($parent) {
    $matches = @(Get-ChildItem -LiteralPath $parent -Directory -Force |
        Where-Object { $_.Name -ieq "survival" })
    if ($matches.Count -ne 1) {
        throw "SURVIVAL_ADDON_DIRECTORY_COUNT_INVALID_$($matches.Count)"
    }
    $matches[0].FullName
}

function Check($condition, $message) {
    if (-not $condition) { throw $message }
}

function Rename-AddonCase($path, $temporaryName, $targetName) {
    $originalName = Split-Path -Leaf $path
    if ($originalName -ceq $targetName) { return }
    $parent = Split-Path -Parent $path
    $temporaryPath = Join-Path $parent $temporaryName
    Check (-not (Test-Path -LiteralPath $temporaryPath)) `
        "CASE_MIGRATION_TEMP_EXISTS_$temporaryName"
    Rename-Item -LiteralPath $path -NewName $temporaryName
    try {
        Rename-Item -LiteralPath $temporaryPath -NewName $targetName
    } catch {
        Rename-Item -LiteralPath $temporaryPath -NewName $originalName
        throw
    }
}

$activeTools = @(Get-CimInstance Win32_Process | Where-Object {
    $_.Name -match '^(dota2|vconsole2|resourcecompiler|assetbrowser|hammer|dota2cfg|vpk)[.]exe$'
})
Check ($activeTools.Count -eq 0) "WORKSHOP_PROCESS_STILL_RUNNING"
Check (Test-Path -LiteralPath $resourceCompiler) "RESOURCECOMPILER_TOOL_MISSING"
Check (-not (Test-Path -LiteralPath $gameTemp)) "GAME_CASE_MIGRATION_TEMP_EXISTS"
Check (-not (Test-Path -LiteralPath $contentTemp)) "CONTENT_CASE_MIGRATION_TEMP_EXISTS"
Check (-not (Test-Path -LiteralPath $gameRollbackTemp)) "GAME_CASE_ROLLBACK_TEMP_EXISTS"
Check (-not (Test-Path -LiteralPath $contentRollbackTemp)) "CONTENT_CASE_ROLLBACK_TEMP_EXISTS"

$gameCurrent = Get-SurvivalAddonPath $gameAddonParent
$contentCurrent = Get-SurvivalAddonPath $contentAddonParent
$assetIndex = Join-Path $gameCurrent "tools_asset_info.bin"
if (Test-Path -LiteralPath $assetIndex) {
    $backupDir = Join-Path $env:TEMP `
        ("survival_file_mod_backup_" + (Get-Date -Format "yyyyMMdd_HHmmss"))
    New-Item -ItemType Directory -Path $backupDir | Out-Null
    Move-Item -LiteralPath $assetIndex -Destination `
        (Join-Path $backupDir "tools_asset_info.bin")
    Write-Host "ASSET_INDEX_BACKUP=$backupDir"
}

Set-Location -LiteralPath $dotaRoot
$gameOriginalName = Split-Path -Leaf $gameCurrent
$contentOriginalName = Split-Path -Leaf $contentCurrent
$gameChanged = $false
$contentChanged = $false
try {
    if ($gameOriginalName -cne "survival") {
        Rename-AddonCase $gameCurrent "__survival_case_migration__" "survival"
        $gameChanged = $true
    }
    if ($contentOriginalName -cne "survival") {
        Rename-AddonCase $contentCurrent "__survival_case_migration__" "survival"
        $contentChanged = $true
    }
} catch {
    if ($contentChanged) {
        Rename-AddonCase (Get-SurvivalAddonPath $contentAddonParent) `
            "__survival_case_rollback__" $contentOriginalName
    }
    if ($gameChanged) {
        Rename-AddonCase (Get-SurvivalAddonPath $gameAddonParent) `
            "__survival_case_rollback__" $gameOriginalName
    }
    throw
}

$gameCanonical = Get-SurvivalAddonPath $gameAddonParent
$contentCanonical = Get-SurvivalAddonPath $contentAddonParent
Check ((Split-Path -Leaf $gameCanonical) -ceq "survival") `
    "GAME_ADDON_DIRECTORY_NOT_CANONICAL_LOWERCASE"
Check ((Split-Path -Leaf $contentCanonical) -ceq "survival") `
    "CONTENT_ADDON_DIRECTORY_NOT_CANONICAL_LOWERCASE"

$sourceVtex = Join-Path $contentCanonical "materials\overviews\template_map.vtex"
$sourceVmat = Join-Path $contentCanonical "materials\overviews\template_map.vmat"
foreach ($source in @($sourceVtex, $sourceVmat)) {
    & $resourceCompiler -f -nop4 -game $dotaGame -i $source
    Check ($LASTEXITCODE -eq 0) "MINIMAP_RESOURCE_COMPILE_FAILED_$source"
}

$contract = Join-Path $gameCanonical "tools\test_minimap_texture_resource_contract.ps1"
& $contract
Check ($LASTEXITCODE -eq 0) "MINIMAP_TEXTURE_RESOURCE_CONTRACT_FAILED"

Write-Host "ADDON_FILE_MOD_CASE_FINALIZE_PASS"