$ErrorActionPreference='Stop'
$repo=Split-Path -Parent $PSScriptRoot
$waveCsv=Join-Path $repo 'data/csv/怪物与波次系统/wave_definitions.csv'
$original=[IO.File]::ReadAllText($waveCsv)
$rows=@(Import-Csv $waveCsv | Where-Object {$_.wave_id -and -not $_.wave_id.StartsWith('#')})
$template=@($rows | Where-Object difficulty_id -eq 'N5')
if(-not $template.Count){throw 'N5 wave template missing'}
$new=@()
for($n=6;$n -le 10;$n++){
    if($rows | Where-Object difficulty_id -eq "N$n"){continue}
    foreach($row in $template){
        $next=[ordered]@{};foreach($property in $row.PSObject.Properties){$next[$property.Name]=$property.Value}
        $next.wave_id=([string]$next.wave_id -replace '^n5',"n$n" -replace '^N5',"N$n")
        $next.difficulty_id="N$n"
        $new += [pscustomobject]$next
    }
}
if($new.Count){
    $csv=@($new | ConvertTo-Csv -NoTypeInformation)
    [IO.File]::WriteAllText($waveCsv,$original.TrimEnd()+"`n"+($csv[1..($csv.Count-1)] -join "`n")+"`n",[Text.UTF8Encoding]::new($false))
}
$builder=Get-Content (Join-Path $PSScriptRoot 'build_lottery_configs.ps1') -Raw
$start=$builder.IndexOf('function Escape-Lua')
$functions=$builder.Substring($start,$builder.LastIndexOf('Get-ChildItem $sourceRoot')-$start)
$functions=$functions.Replace('$($headers[$index]) = $converted','$(if($headers[$index] -eq ''armor''){''war3_armor''}else{$headers[$index]}) = $converted')
Invoke-Expression $functions
$outputRoot=Join-Path $repo 'scripts/vscripts/config/generated'
$utf8NoBom=[Text.UTF8Encoding]::new($false)
Build-One (Get-Item $waveCsv)
Write-Host 'ARCHIVE_N6_N10_WAVES_PASS'
