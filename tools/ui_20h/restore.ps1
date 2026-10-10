param([ValidateSet('best','baseline_full')][string]$Version='best',[switch]$Apply,[switch]$AllowChanged)
$ErrorActionPreference='Stop'
$uiRepo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$uiCheck=Join-Path $uiRepo 'design_refs/ui_20h/work/checkpoints'
$uiTarget=Get-Content -LiteralPath (Join-Path $uiCheck ($Version+'/manifest.json')) -Raw|ConvertFrom-Json
$uiBest=Get-Content -LiteralPath (Join-Path $uiCheck 'best/manifest.json') -Raw|ConvertFrom-Json
$uiExpected=@{};foreach($uiFile in $uiBest.files){$uiExpected[$uiFile.path]=$uiFile.sha256}
$uiOperations=@()
foreach($uiFile in $uiTarget.files){
    $uiDest=[IO.Path]::GetFullPath((Join-Path $uiRepo $uiFile.path))
    $uiObj=[IO.Path]::GetFullPath((Join-Path $uiCheck $uiFile.object))
    if(-not $uiDest.StartsWith($uiRepo+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase) -or -not $uiObj.StartsWith($uiCheck+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw 'Checkpoint path escapes workspace'}
    if((Get-FileHash -LiteralPath $uiObj).Hash.ToLowerInvariant() -ne $uiFile.sha256){throw "Damaged checkpoint: $($uiFile.path)"}
    if(Test-Path -LiteralPath $uiDest){$uiCurrent=(Get-FileHash -LiteralPath $uiDest).Hash.ToLowerInvariant();if($uiCurrent -eq $uiFile.sha256){continue};if(-not $AllowChanged -and $uiCurrent -ne $uiExpected[$uiFile.path]){throw "Later edits detected: $($uiFile.path). Review before explicitly using -AllowChanged."}}
    $uiOperations+=@{source=$uiObj;destination=$uiDest;path=$uiFile.path}
}
Write-Output "Checkpoint ${Version}: $($uiOperations.Count) replacements. No files are deleted."
if(-not $Apply){$uiOperations|ForEach-Object {Write-Output $_.path};Write-Output 'Inspection only. Add -Apply to restore.';return}
foreach($uiOperation in $uiOperations){New-Item -ItemType Directory -Path (Split-Path $uiOperation.destination -Parent) -Force|Out-Null;Copy-Item -LiteralPath $uiOperation.source -Destination $uiOperation.destination -Force}
Write-Output 'Checkpoint restored. Recompile the reference graph before native validation.'
