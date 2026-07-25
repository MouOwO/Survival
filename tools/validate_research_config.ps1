param(
    [Parameter(Mandatory = $true)]
    [string]$ConfigPath,

    [Parameter(Mandatory = $true)]
    [string]$AllLevelCostsPath
)

$ErrorActionPreference = "Stop"
$text = Get-Content -LiteralPath $ConfigPath -Raw -Encoding UTF8
$pattern = 'technology\("(?<id>[A-Z]+-\d+)",\s*"(?<name>[^"]+)",\s*"(?<building>[^"]+)",\s*(?<max>\d+),\s*"(?<legacy>[^"]+)",\s*(?<gb>\d+),\s*(?<gs>\d+),\s*(?<wb>\d+),\s*(?<ws>\d+)'
$definitions = @{}
foreach ($match in [regex]::Matches(
    $text,
    $pattern,
    [Text.RegularExpressions.RegexOptions]::Singleline
)) {
    $definitions[$match.Groups['id'].Value] = @{
        name = $match.Groups['name'].Value
        max = [int]$match.Groups['max'].Value
        gold_base = [int64]$match.Groups['gb'].Value
        gold_step = [int64]$match.Groups['gs'].Value
        wood_base = [int64]$match.Groups['wb'].Value
        wood_step = [int64]$match.Groups['ws'].Value
    }
}

if ($definitions.Count -ne 19) {
    throw "Expected 19 Lua definitions, found $($definitions.Count)"
}

$lines = Get-Content -LiteralPath $AllLevelCostsPath -Encoding UTF8
$errors = New-Object System.Collections.ArrayList
$levelCount = 0
$seenMax = @{}
for ($index = 3; $index -lt $lines.Count; $index++) {
    if ([string]::IsNullOrWhiteSpace($lines[$index])) { continue }
    $columns = $lines[$index] -split "`t", -1
    if ($columns.Count -lt 7) { continue }
    $techId = $columns[0]
    $definition = $definitions[$techId]
    if ($null -eq $definition) {
        [void]$errors.Add("Unknown Excel tech_id: $techId")
        continue
    }
    $level = [int]$columns[3]
    $maxLevel = [int]$columns[4]
    $gold = [int64]$columns[5]
    $wood = [int64]$columns[6]
    $expectedGold = $definition.gold_base + (($level - 1) * $definition.gold_step)
    $expectedWood = $definition.wood_base + (($level - 1) * $definition.wood_step)
    if ($maxLevel -ne $definition.max) {
        [void]$errors.Add(
            "$techId max mismatch Lua=$($definition.max) Excel=$maxLevel"
        )
    }
    if ($gold -ne $expectedGold -or $wood -ne $expectedWood) {
        [void]$errors.Add(
            "$techId LV$level cost mismatch Lua=$expectedGold/$expectedWood Excel=$gold/$wood"
        )
    }
    $seenMax[$techId] = [Math]::Max(
        [int]($seenMax[$techId] -as [int]),
        $level
    )
    $levelCount++
}

foreach ($techId in $definitions.Keys) {
    if ([int]$seenMax[$techId] -ne $definitions[$techId].max) {
        [void]$errors.Add(
            "$techId level coverage mismatch Lua=$($definitions[$techId].max) Excel=$($seenMax[$techId])"
        )
    }
}

if ($levelCount -ne 420) {
    [void]$errors.Add("Expected 420 Excel levels, found $levelCount")
}
if ($errors.Count -gt 0) {
    throw ($errors -join [Environment]::NewLine)
}

Write-Output "PASS technologies=$($definitions.Count) levels=$levelCount"