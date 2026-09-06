$ErrorActionPreference='Stop'
$repo=Split-Path -Parent $PSScriptRoot
$root=Join-Path $repo 'data/csv/存档系统'
$defs=@(Import-Csv (Join-Path $root 'archive_challenge_definitions.csv') | Where-Object {$_.challenge_id -and -not $_.challenge_id.StartsWith('#')})
$rule=Import-Csv (Join-Path $root 'archive_challenge_rules.csv') | Where-Object rule_id -eq 'default'
$utf8=[Text.UTF8Encoding]::new($false)
$abilities=[Collections.Generic.List[string]]::new()
$abilities.Add('"DOTAAbilities"');$abilities.Add('{')
$tokens=[Collections.Generic.List[string]]::new()
foreach($def in $defs){
    $name='ability_archive_'+$def.challenge_id
    $abilities.Add('    "'+$name+'"');$abilities.Add('    {')
    $values=[ordered]@{BaseClass='ability_lua';ScriptFile='abilities/archive_challenge_abilities';AbilityBehavior='DOTA_ABILITY_BEHAVIOR_NO_TARGET';AbilityTextureName=$def.ability_icon;MaxLevel='1';AbilityCastPoint='0';AbilityManaCost='0';AbilityCooldown=$def.cooldown_seconds}
    foreach($key in $values.Keys){$abilities.Add('        "'+$key+'" "'+$values[$key]+'"')}
    $abilities.Add('    }')
    $tokens.Add('        "DOTA_Tooltip_ability_'+$name+'" "'+$def.display_name+'"')
    $tokens.Add('        "DOTA_Tooltip_ability_'+$name+'_Description" "当前关卡≥N'+$def.min_difficulty+'。'+$def.description+'"')
}
$abilities.Add('    "ability_archive_finish" { "BaseClass" "ability_lua" "ScriptFile" "abilities/archive_challenge_abilities" "AbilityBehavior" "DOTA_ABILITY_BEHAVIOR_NO_TARGET" "AbilityTextureName" "chen_hand_of_god" "MaxLevel" "1" "AbilityCastPoint" "0" "AbilityCooldown" "0" "AbilityManaCost" "0" }')
$abilities.Add('}')
$abilities.Insert($abilities.Count-1, '    "ability_archive_endless" { "BaseClass" "ability_lua" "ScriptFile" "abilities/archive_challenge_abilities" "AbilityBehavior" "DOTA_ABILITY_BEHAVIOR_NO_TARGET" "AbilityTextureName" "nevermore_requiem" "MaxLevel" "1" "AbilityCastPoint" "0" "AbilityCooldown" "0" "AbilityManaCost" "0" }')
$tokens.Add('        "DOTA_Tooltip_ability_ability_archive_endless" "开启无尽模式"')
$tokens.Add('        "DOTA_Tooltip_ability_ability_archive_endless_Description" "每波5只小怪，限时60秒，全部击杀立即进入下一波并获得积分。每10波为一档，每波积分为7n-6。每局仅能开启一次，超时结束本次无尽挑战。"')
[IO.File]::WriteAllText((Join-Path $repo 'scripts/npc/npc_archive_challenges_abilities.txt'),($abilities -join "`n")+"`n",$utf8)
$units=@('"DOTAUnits"','{')
for($i=1;$i -le 3;$i++){
    $units += '    "npc_archive_challenge_'+$i+'"'
    $units += '    {'
    $values=[ordered]@{BaseClass='npc_dota_creature';Model=$rule.building_model;ModelScale=$rule.building_model_scale;Level='1';ConsideredHero='0';HasInventory='0';AbilityLayout='12';HealthBarOffset='-1';StatusHealth='2500';StatusMana='0';MovementCapabilities='DOTA_UNIT_CAP_MOVE_NONE';AttackCapabilities='DOTA_UNIT_CAP_NO_ATTACK';ArmorPhysical='0';BoundsHullName='DOTA_HULL_SIZE_BARRACKS';VisionDaytimeRange='1000';VisionNighttimeRange='1000'}
    foreach($key in $values.Keys){$units += '        "'+$key+'" "'+$values[$key]+'"'}
    $units += '    }'
    $tokens.Add('        "npc_archive_challenge_'+$i+'" "存档挑战'+$i+'"')
}
$units += '}'
[IO.File]::WriteAllText((Join-Path $repo 'scripts/npc/npc_archive_challenges_units.txt'),($units -join "`n")+"`n",$utf8)
$tokens.Add('        "DOTA_Tooltip_ability_ability_archive_finish" "结束存档挑战"')
$tokens.Add('        "DOTA_Tooltip_ability_ability_archive_finish_Description" "结束自己的存档挑战；全部玩家结束后以胜利结算本局。未击败的挑战BOSS会被移除，不获得奖励。"')
$path=Join-Path $repo 'resource/addon_schinese.txt'
$text=[IO.File]::ReadAllText($path)
$startMarker='        // BEGIN ARCHIVE_CHALLENGE_LOCALIZATION'
$endMarker='        // END ARCHIVE_CHALLENGE_LOCALIZATION'
$block=$startMarker+"`n"+($tokens -join "`n")+"`n"+$endMarker+"`n"
$start=$text.IndexOf($startMarker)
if($start -ge 0){
    $start=$text.LastIndexOf("`n",$start)+1
    $end=$text.IndexOf($endMarker,$start)+$endMarker.Length
    $text=$text.Substring(0,$start)+$block.TrimEnd()+$text.Substring($end)
    $text=$text.Replace($endMarker+"`n}",$endMarker+"`n    }")
}else{
    $outer=$text.LastIndexOf('}');$inner=$text.LastIndexOf('}',$outer-1)
    $lineStart=$text.LastIndexOf("`n",$inner)+1
    $text=$text.Insert($lineStart,$block)
}
[IO.File]::WriteAllText($path,$text,[Text.UTF8Encoding]::new($true))
Write-Host 'ARCHIVE_CHALLENGE_ASSETS_PASS'
