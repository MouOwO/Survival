param([string]$Workbook='C:\Users\Administrator\Desktop\通关存档效果.xlsx')
$ErrorActionPreference='Stop'
$repo=Split-Path -Parent $PSScriptRoot
$source=Get-Content (Join-Path $PSScriptRoot 'import_lottery_points_items.ps1') -Raw
$start=$source.IndexOf('function Read-WorksheetRows')
Invoke-Expression $source.Substring($start,$source.IndexOf('function Icon-For')-$start)
$sheet=Read-WorksheetRows $Workbook '钓鱼存档'
$definitions=Import-Csv (Join-Path $repo 'data/csv/玩家档案系统/star_blessing_reward_definitions.csv')
$rows=foreach($i in 1..26){
 $r=$sheet[$i+4];$id='star_blessing_{0:d3}' -f $i
 $existing=$definitions|Where-Object reward_id -eq $id
 if(-not $existing -or [int]$r.A -ne $i -or [int]$r.C -le 0){throw "Invalid fishing item $id"}
 $description=$r.D
 # Keep the two existing backend effects accurately described; this task is presentation only.
 if($i -eq 15){$description='墙护甲加成+2%'}
 if($i -eq 25){$description='箭塔造成伤害攻击+1'}
 [pscustomobject][ordered]@{reward_id=$id;display_name=($r.B -replace '（疑似）','');max_owned=[int]$r.C;description=$description;workbook_description=$r.D;quality='N';enabled=1}
}
$csv=@($rows|ConvertTo-Csv -NoTypeInformation)
$lines=@($csv[0].Replace('"',''),'#types:string,string,number,string,string,string,boolean')+$csv[1..($csv.Count-1)]
[IO.File]::WriteAllText((Join-Path $repo 'data/csv/存档系统/archive_fishing_items.csv'),($lines -join "`n")+"`n",[Text.UTF8Encoding]::new($false))
Write-Host 'ARCHIVE_FISHING_IMPORTED: 26 existing reward IDs'
