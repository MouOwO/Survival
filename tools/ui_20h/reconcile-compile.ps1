$ErrorActionPreference='Stop'
$reconcileRoot=(Get-Location).Path
$reconcileEngine=[IO.Path]::GetFullPath((Join-Path $reconcileRoot '../../..'))
$reconcilePlan=Get-Content design_refs/ui_20h/work/feedback10/content_reconciliation.json -Raw|ConvertFrom-Json
foreach($reconcileItem in $reconcilePlan.records){
 $reconcileSource=Join-Path $reconcileEngine ('content/dota_addons/Survival/'+$reconcileItem.file)
 & (Join-Path $reconcileEngine 'game/bin/win64/resourcecompiler.exe') -i $reconcileSource -fshallow -nop4 *> (Join-Path $reconcileRoot ('output/ui_20h/reconcile_compile_'+[IO.Path]::GetFileName($reconcileSource)+'.log'))
 if($LASTEXITCODE -ne 0){throw ('Compile failed: '+$reconcileItem.file)}
}
Write-Output ('UPSTREAM_NATIVE_COMPILE_PASS '+$reconcilePlan.records.Count+' proven sources')
