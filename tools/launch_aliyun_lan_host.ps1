param(
    [ValidateRange(2,4)][int]$ExpectedPlayers = 2,
    [ValidateRange(10,1800)][int]$JoinWaitSeconds = 600
)
$ErrorActionPreference = 'Stop'
& (Join-Path $PSScriptRoot 'launch_aliyun_test_game.ps1') -ExpectedPlayers $ExpectedPlayers -JoinWaitSeconds $JoinWaitSeconds
