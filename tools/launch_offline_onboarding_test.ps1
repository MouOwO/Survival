param([switch]$CheckOnly)
$ErrorActionPreference = 'Stop'
& (Join-Path $PSScriptRoot 'workshop_test/launch_test.ps1') -Mode Offline -Onboarding -CheckOnly:$CheckOnly
