param([string]$RepoRoot = '')
$ErrorActionPreference='Stop'
$repo=if($RepoRoot){[IO.Path]::GetFullPath($RepoRoot)}else{Split-Path -Parent $PSScriptRoot}
$root=Join-Path $repo 'data/csv/存档系统'
$defs=@(Import-Csv (Join-Path $root 'archive_challenge_definitions.csv') | Where-Object {$_.challenge_id -and -not $_.challenge_id.StartsWith('#')})
$rule=Import-Csv (Join-Path $root 'archive_challenge_rules.csv') | Where-Object rule_id -eq 'default'
$actionsPath=Join-Path $root 'archive_challenge_actions.csv'
$actions=@(if(Test-Path -LiteralPath $actionsPath){Import-Csv -LiteralPath $actionsPath | Where-Object {$_.action_id -and -not $_.action_id.StartsWith('#')}})
$buildingCount=4
if($rule.building_count){
    $buildingCount=[int]$rule.building_count
    if($buildingCount -lt 1 -or $buildingCount -gt 32){throw 'archive building_count must be between 1 and 32'}
}
$utf8=[Text.UTF8Encoding]::new($false)
$abilities=[Collections.Generic.List[string]]::new()
$abilities.Add('"DOTAAbilities"');$abilities.Add('{')
$tokens=[Collections.Generic.List[string]]::new()
$abilityNames=[Collections.Generic.HashSet[string]]::new()
function ConvertTo-ArchiveKvText($value){
    # Localization bodies may contain complete multiline video tooltips.
    return ([string]$value).Replace('\','\\').Replace('"','\"').Replace("`r`n",'<br>').Replace("`n",'<br>').Replace("`r",'<br>')
}
function Add-ArchiveAbility($name,$icon,$cooldown){
    if($name -notmatch '^ability_archive_[a-z0-9_]+$'){throw "Invalid archive ability name: $name"}
    if(-not $abilityNames.Add($name)){throw "Duplicate archive ability: $name"}
    $abilities.Add('    "'+$name+'"');$abilities.Add('    {')
    if(-not $cooldown){$cooldown='0'}
    $values=[ordered]@{BaseClass='ability_lua';ScriptFile='abilities/archive_challenge_abilities';AbilityBehavior='DOTA_ABILITY_BEHAVIOR_NO_TARGET';AbilityTextureName=$icon;MaxLevel='1';AbilityCastPoint='0';AbilityManaCost='0';AbilityCooldown=$cooldown}
    foreach($key in $values.Keys){$abilities.Add('        "'+$key+'" "'+(ConvertTo-ArchiveKvText $values[$key])+'"')}
    $abilities.Add('    }')
}
function Add-ArchiveLocalization($name,$title,$description){
    $tokens.Add('        "DOTA_Tooltip_ability_'+$name+'" "'+(ConvertTo-ArchiveKvText $title)+'"')
    # description is the authoritative full body. unlock_text is published by
    # the runtime service; never add a second, invented difficulty prefix here.
    $tokens.Add('        "DOTA_Tooltip_ability_'+$name+'_Description" "'+(ConvertTo-ArchiveKvText $description)+'"')
}
foreach($def in $defs){
    $name='ability_archive_'+$def.challenge_id
    Add-ArchiveAbility $name $def.ability_icon $def.cooldown_seconds
    Add-ArchiveLocalization $name $def.display_name $def.description
}
foreach($action in $actions){
    $name=if($action.ability_name){$action.ability_name}else{'ability_archive_'+$action.action_id}
    Add-ArchiveAbility $name $action.ability_icon $action.cooldown_seconds
    Add-ArchiveLocalization $name $action.display_name $action.description
}
# Keep legacy callable declarations for existing games; these do not allocate
# grid slots. The service owns the configured action building_id/slot_order.
if(-not $abilityNames.Contains('ability_archive_endless')){
    Add-ArchiveAbility 'ability_archive_endless' 'nevermore_requiem' '0'
    Add-ArchiveLocalization 'ability_archive_endless' '开启无尽模式' '每波5只小怪，限时60秒，全部击杀立即进入下一波并获得积分。每10波为一档，每波积分为7n-6。每局仅能开启一次，超时结束本次无尽挑战。'
}
if(-not $abilityNames.Contains('ability_archive_finish')){
    Add-ArchiveAbility 'ability_archive_finish' 'chen_hand_of_god' '0'
    Add-ArchiveLocalization 'ability_archive_finish' '结束存档挑战' '结束自己的存档挑战；全部玩家结束后以胜利结算本局。未击败的挑战BOSS会被移除，不获得奖励。'
}
$abilities.Add('}')
[IO.File]::WriteAllText((Join-Path $repo 'scripts/npc/npc_archive_challenges_abilities.txt'),($abilities -join "`n")+"`n",$utf8)
$units=@('"DOTAUnits"','{')
for($i=1;$i -le $buildingCount;$i++){
    $units += '    "npc_archive_challenge_'+$i+'"'
    $units += '    {'
    $hubModel=$rule.('building_model_'+$i)
    if(-not $hubModel -and $i -eq 4){$hubModel=$rule.building_model_3}
    if(-not $hubModel){$hubModel=$rule.building_model}
    $values=[ordered]@{BaseClass='npc_dota_creature';Model=$hubModel;ModelScale=$rule.building_model_scale;Level='1';ConsideredHero='0';HasInventory='0';AbilityLayout='12';HealthBarOffset='-1';StatusHealth='2500';StatusMana='0';MovementCapabilities='DOTA_UNIT_CAP_MOVE_NONE';AttackCapabilities='DOTA_UNIT_CAP_NO_ATTACK';ArmorPhysical='0';BoundsHullName='DOTA_HULL_SIZE_BARRACKS';VisionDaytimeRange='1000';VisionNighttimeRange='1000'}
    foreach($key in $values.Keys){$units += '        "'+$key+'" "'+(ConvertTo-ArchiveKvText $values[$key])+'"'}
    $units += '    }'
    $tokens.Add('        "npc_archive_challenge_'+$i+'" "存档挑战'+$i+'"')
}
$units += '}'
[IO.File]::WriteAllText((Join-Path $repo 'scripts/npc/npc_archive_challenges_units.txt'),($units -join "`n")+"`n",$utf8)
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
