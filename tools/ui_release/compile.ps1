$ErrorActionPreference='Stop'
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$engine=[IO.Path]::GetFullPath((Join-Path $repo '../../..'))
$content=Join-Path $engine 'content/dota_addons/Survival/panorama'
$plan=Get-Content (Join-Path $PSScriptRoot 'plan.json') -Raw | ConvertFrom-Json
$compiler=Join-Path $engine 'game/bin/win64/resourcecompiler.exe'
foreach($rel in @($plan.sources.PSObject.Properties.Name | Where-Object { $_.EndsWith('.xml') })){
 $out=& $compiler -i (Join-Path $content $rel) -game (Join-Path $engine 'game/dota') -f -nop4 2>&1
 $code=$LASTEXITCODE
 $log=Join-Path $PSScriptRoot ('compile_'+[IO.Path]::GetFileName($rel)+'.log')
 $out | Out-File $log -Encoding utf8
 if($code -ne 0 -or -not($out -match '0 failed')){throw "Formal compile failed: $rel"}
 $out | Select-String 'OK:' | ForEach-Object {$_.Line}
}
@{version=$plan.version;compiled=$true;time=(Get-Date -Format o)} | ConvertTo-Json | Set-Content (Join-Path $PSScriptRoot 'compiled.json')
