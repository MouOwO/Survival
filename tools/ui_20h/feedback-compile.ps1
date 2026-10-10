param([switch]$ArchiveOnly)
$ErrorActionPreference='Stop'
$feedbackRepo=(Get-Location).Path
$feedbackEngine=[IO.Path]::GetFullPath((Join-Path $feedbackRepo '../../..'))
$feedbackContent=Join-Path $feedbackEngine 'content/dota_addons/Survival/panorama'
$feedbackBackup=Join-Path $feedbackRepo ('output/ui_20h/feedback_compile_'+(Get-Date -Format yyyyMMdd_HHmmss))
$feedbackFiles=@('scripts/custom_game/archive_jade.js','styles/custom_game/common/jade_ui.css')
if(-not $ArchiveOnly){$feedbackFiles+=@('scripts/custom_game/production_progress.js','styles/custom_game/production_progress.css')}
foreach($feedbackRel in $feedbackFiles){
 $feedbackSource=Join-Path $feedbackRepo ('panorama/src/'+$feedbackRel)
 $feedbackTarget=Join-Path $feedbackContent $feedbackRel
 $feedbackSaved=Join-Path $feedbackBackup $feedbackRel
 New-Item -ItemType Directory -Path (Split-Path $feedbackSaved -Parent) -Force|Out-Null
 if(Test-Path -LiteralPath $feedbackTarget){Copy-Item -LiteralPath $feedbackTarget -Destination $feedbackSaved -Force}
 Copy-Item -LiteralPath $feedbackSource -Destination $feedbackTarget -Force
 & (Join-Path $feedbackEngine 'game/bin/win64/resourcecompiler.exe') -i $feedbackTarget -fshallow -nop4 *> (Join-Path $feedbackBackup (($feedbackRel -replace '/','_')+'.log'))
 if($LASTEXITCODE -ne 0){throw "Compile failed: $feedbackRel"}
 Write-Output "FEEDBACK_NATIVE_COMPILE_PASS $feedbackRel"
}
Write-Output 'Content archive.xml/title references preserved; existing game manifest used.'
