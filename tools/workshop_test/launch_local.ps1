param([ValidateRange(1,4)][int]$ExpectedPlayers = 1, [switch]$DirectJoin)
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
if (-not (Test-Path -LiteralPath 'D:/Survival_发布候选/20261023_ws4_auth_v03/_release_manifest.json' -PathType Leaf)) {
    Write-Output '这是创建房间的主机入口；本电脑缺少主机专用冻结测试包。仅拉取 Git 代码不会安装该资源。'
    Write-Output '加入另一台主机：请完整解压 ws4_remote_client_20261023_v2.zip，运行包内“加入测试.cmd”。'
    Write-Output '也可将解压目录拖到项目根目录 join_ws4_game.cmd 上，无需 Python、Node 或主机凭据。'
    Write-Output 'host_frozen_release_missing'
    exit 1
}
. (Join-Path $repo 'tools/backend_python.ps1')
$python = Resolve-SurvivalBackendPython -RepoRoot $repo
Push-Location $repo
try {
    $launchArgs = @('-B','-X','utf8',(Join-Path $PSScriptRoot 'local_host.py'),'run','--expected-players',"$ExpectedPlayers")
    if ($DirectJoin) { $launchArgs += '--direct-join' }
    & $python @launchArgs
    exit $LASTEXITCODE
} finally { Pop-Location }
