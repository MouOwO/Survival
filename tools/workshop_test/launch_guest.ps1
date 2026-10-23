param([string]$PackagePath, [string]$Server, [string]$GamePath, [switch]$CheckOnly)
$ErrorActionPreference = 'Stop'
try {
    if (-not $PackagePath) { $PackagePath = Join-Path $PSScriptRoot '../../output/ws4_remote_client_20261023' }
    if (-not (Test-Path -LiteralPath $PackagePath -PathType Container)) { throw 'guest_package_missing' }
    $package = (Resolve-Path -LiteralPath $PackagePath).Path
    $script = Join-Path $package 'join_client.ps1'
    if (-not (Test-Path -LiteralPath $script -PathType Leaf)) { throw 'guest_package_missing' }
    # Only dispatch our generated guest script. Its pinned manifest and full
    # runtime verification still run before installing or starting Dota.
    $manifestHash = '2be968c893f4584fc65438fff696e541fc92f86f2ccd66d50bd48641c365ceda'
    $expected = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'join_client.ps1')).Replace('__MANIFEST_SHA256__',$manifestHash).Replace("`r`n","`n")
    $actual = [IO.File]::ReadAllText($script).Replace("`r`n","`n")
    if ($actual -cne $expected) { throw 'guest_entrypoint_changed' }
    $joinArgs = @{}
    if ($Server) { $joinArgs.Server = $Server }
    if ($GamePath) { $joinArgs.GamePath = $GamePath }
    if ($CheckOnly) { $joinArgs.CheckOnly = $true }
    $global:LASTEXITCODE = 0
    & $script @joinArgs
    exit $LASTEXITCODE
} catch {
    $code = $_.Exception.Message
    if ($code -eq 'guest_package_missing') {
        Write-Output '加入方需要完整客户端包，Git 源码不含冻结测试资源。'
        Write-Output '请从主机复制 ws4_remote_client_20261023_v2.zip，完整解压后双击包内“加入测试.cmd”。'
        Write-Output '也可将解压目录拖到 join_ws4_game.cmd 上；直接双击该入口默认使用 output/ws4_remote_client_20261023。'
    } elseif ($code -eq 'guest_entrypoint_changed') {
        Write-Output '客户端入口版本不一致或已被修改，请使用主机提供的原始完整客户端包。'
    } else { $code = 'guest_launcher_failed' }
    Write-Output $code
    exit 1
}
