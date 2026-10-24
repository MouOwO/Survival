param([string]$PackagePath, [string]$Server, [string]$GamePath, [switch]$CheckOnly)
$ErrorActionPreference = 'Stop'
try {
    if (-not $PackagePath) { throw 'guest_package_missing' }
    if (-not (Test-Path -LiteralPath $PackagePath -PathType Container)) { throw 'guest_package_missing' }
    $package = (Resolve-Path -LiteralPath $PackagePath).Path
    $script = Join-Path $package 'join_client.ps1'
    if (-not (Test-Path -LiteralPath $script -PathType Leaf)) { throw 'guest_package_missing' }
    # Only dispatch our generated guest script. Its pinned manifest and full
    # runtime verification still run before installing or starting Dota.
    $manifestHash = '2be968c893f4584fc65438fff696e541fc92f86f2ccd66d50bd48641c365ceda'
    $expected = [IO.File]::ReadAllText((Join-Path $PSScriptRoot '../join_client.ps1')).Replace('__MANIFEST_SHA256__',$manifestHash).Replace("`r`n","`n")
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
        Write-Output '请从主机复制完整 ws4_remote_client 客户端 ZIP，完整解压并应用最新启动修复包，再运行 join_game.cmd。'
        Write-Output '此为历史客户端维护工具，必须显式提供完整的客户端路径。当前主机测试请使用根目录的两个测试入口。'
    } elseif ($code -eq 'guest_entrypoint_changed') {
        Write-Output '客户端入口版本不一致或已被修改，请使用主机提供的完整客户端并应用最新启动修复包。'
    } else { $code = 'guest_launcher_failed' }
    Write-Output $code
    exit 1
}
