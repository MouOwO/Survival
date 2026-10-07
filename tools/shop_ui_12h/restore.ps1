[CmdletBinding(SupportsShouldProcess=$true)]
param([ValidateSet('Best','Baseline')][string]$Mode='Best')
$ErrorActionPreference='Stop'
$shopRepo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$shopCheckpoints=Join-Path $shopRepo 'design_refs/shop_ui_12h/work/checkpoints'
$shopBest=Join-Path $shopCheckpoints 'production_best'
$shopBaseline=Join-Path $shopCheckpoints 'baseline'
$shopManifest=Get-Content -Raw -LiteralPath (Join-Path $shopBest 'manifest.json')|ConvertFrom-Json
$shopOriginal=Get-Content -Raw -LiteralPath (Join-Path $shopBaseline 'manifest.json')|ConvertFrom-Json
$shopTargets=if($Mode -eq 'Best'){@($shopManifest.files)}else{@($shopManifest.files|Where-Object {$_.path -in @('panorama/src/scripts/custom_game/commerce_remaining_5d5c1152eb.js','panorama/src/layout/custom_game/survival_hud.xml')})}
foreach($shopEntry in $shopTargets){
 $shopLive=Join-Path $shopRepo $shopEntry.path
 if(Test-Path -LiteralPath $shopLive){
  $shopHash=(Get-FileHash -LiteralPath $shopLive).Hash.ToLowerInvariant()
  $shopOriginalHash=$shopOriginal.files.($shopEntry.path)
  if($shopHash -ne $shopEntry.sha256 -and $shopHash -ne $shopOriginalHash){throw ('文件在检查点之后又被修改，请人工合并，恢复脚本不会覆盖：'+$shopEntry.path)}
 }
}
$shopAssetOperations=@()
if($Mode -eq 'Best'){
 $shopAssets=Join-Path $shopBest 'art/ui/sources/custom_game/commerce_jade_v1'
 $shopLiveAssets=Join-Path $shopRepo 'art/ui/sources/custom_game/commerce_jade_v1'
 foreach($shopFile in Get-ChildItem -LiteralPath $shopAssets -Recurse -File){
  $shopRel=$shopFile.FullName.Substring($shopAssets.Length).TrimStart('\')
  $shopLive=Join-Path $shopLiveAssets $shopRel
  if(Test-Path -LiteralPath $shopLive){
   if((Get-FileHash -LiteralPath $shopLive).Hash -ne (Get-FileHash -LiteralPath $shopFile.FullName).Hash){throw ('素材在检查点之后又被修改，请人工比较：'+$shopRel)}
  }else{$shopAssetOperations+=@{source=$shopFile.FullName;target=$shopLive}}
 }
}
# Validate every source and asset before the first write, so a conflict does not cause partial restoration.
foreach($shopEntry in $shopTargets){
 $shopLive=Join-Path $shopRepo $shopEntry.path
 $shopSaved=if($Mode -eq 'Best'){Join-Path $shopBest $shopEntry.path}else{Join-Path $shopBaseline ([IO.Path]::GetFileName($shopEntry.path))}
 if($PSCmdlet.ShouldProcess($shopLive,'恢复 '+$Mode+' 检查点')){
  New-Item -ItemType Directory -Path (Split-Path -Parent $shopLive) -Force|Out-Null
  Copy-Item -LiteralPath $shopSaved -Destination $shopLive -Force
 }
}
foreach($shopOperation in $shopAssetOperations){
 if($PSCmdlet.ShouldProcess($shopOperation.target,'恢复最佳版缺失素材')){
  New-Item -ItemType Directory -Path (Split-Path -Parent $shopOperation.target) -Force|Out-Null
  Copy-Item -LiteralPath $shopOperation.source -Destination $shopOperation.target
 }
}
Write-Output ('检查点恢复流程完成：'+$Mode+'。使用 -WhatIf 可只检查；实际恢复后运行 compile.ps1 更新游戏资源。')
