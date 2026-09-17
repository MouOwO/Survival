$ErrorActionPreference='Stop'
$root=Join-Path (Split-Path -Parent $PSScriptRoot) 'data/csv/存档系统'
function Read-Table($name){ @(Import-Csv (Join-Path $root $name) | Where-Object { -not ([string]@($_.PSObject.Properties)[0].Value).StartsWith('#') }) }
function Write-Table($name,$rows){
 $path=Join-Path $root $name
 $header=@(Get-Content $path -TotalCount 3)
 $csv=@($rows | ConvertTo-Csv -NoTypeInformation)
 [IO.File]::WriteAllText($path,(($header+$csv[1..($csv.Count-1)]) -join "`n")+"`n",[Text.UTF8Encoding]::new($false))
}
$defs=@(Read-Table 'archive_challenge_definitions.csv' | Where-Object { $_.challenge_id -notin @('social_friend','social_ex','social_beast') })
$stats=@(Read-Table 'archive_challenge_stats.csv' | Where-Object { $_.challenge_id -notin @('social_friend','social_ex','social_beast') })
$cats=@(Read-Table 'archive_categories.csv' | Where-Object { $_.category_id -notin @('friend','ex','beast') })
$i=0
foreach($pool in @('friend','ex','beast')){
 $i++
 $name=if($pool -eq 'friend'){'好基友挑战'}elseif($pool -eq 'ex'){'前女友挑战'}else{'瑞兽赐福挑战'}
 $display=if($pool -eq 'friend'){'我的好基友'}elseif($pool -eq 'ex'){'我的前女友'}else{'瑞兽赐福'}
 $ticket=if($pool -eq 'friend'){'义帖'}elseif($pool -eq 'ex'){'邀请函'}else{'福签'}
 $id='social_'+$pool
 $defs += [pscustomobject][ordered]@{challenge_id=$id;building_id=3;slot_order=7+$i;display_name=$name;min_difficulty=1;reward_kind='social_ticket';reward_key=$pool;model_path='models/heroes/ogre_magi/ogre_magi.vmdl';model_scale=1.2;ability_icon='ogre_magi_multicast';cooldown_seconds=3;enabled=1;description=('召唤1只怪物，击杀获得1张'+$ticket+'；本挑战每日最多获得10张，每局仅限一次。')}
 foreach($n in 1..10){
  $stats += [pscustomobject][ordered]@{stats_id="${id}_N$n";challenge_id=$id;difficulty_id="N$n";health=32000000;attack=1980002;war3_armor=7992;attack_speed=1;move_speed=280;attack_range=160;magic_resistance=0;enabled=1;notes='工作簿社交存档挑战属性，N1-N10一致。'}
 }
 $cats += [pscustomobject][ordered]@{category_id=$pool;display_name=$display;renderer='collection';sort_order=60+$i;enabled=1}
}
Write-Table 'archive_challenge_definitions.csv' $defs
Write-Table 'archive_challenge_stats.csv' $stats
Write-Table 'archive_categories.csv' $cats
& (Join-Path $PSScriptRoot 'build_archive_configs.ps1')
