param([string]$Server, [string]$GamePath, [switch]$CheckOnly)
$ErrorActionPreference = 'Stop'
$expectedManifestHash = '__MANIFEST_SHA256__'
$addonName = 'survival_ws4_local'
$descriptorName = '_ws4_local_install.json'
$cacheNames = @('tools_asset_info.bin','tools_thumbnail_cache.sqlite3','tools_thumbnail_cache.sqlite3-journal','tools_thumbnail_cache.sqlite3-wal','tools_thumbnail_cache.sqlite3-shm')
function Assert-PlainPath([string]$Path) {
    $entry = Get-Item -LiteralPath $Path -Force
    while ($entry) {
        if (($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'linked_path_not_allowed' }
        if ($entry -is [IO.FileInfo]) { $entry = $entry.Directory }
        else { $entry = $entry.Parent }
    }
}
function Assert-File([string]$Path, $Row) {
    Assert-PlainPath $Path
    if ((Get-Item -LiteralPath $Path).Length -ne $Row.bytes -or (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant() -ne $Row.sha256) { throw 'client_runtime_bytes_changed' }
}
function Assert-Layout([string]$Folder, $Rows, [bool]$PermitCaches) {
    Assert-PlainPath $Folder
    $known = @{}
    foreach ($row in $Rows) { $known[$row.path] = $true }
    foreach ($entry in Get-ChildItem -LiteralPath $Folder -Force -Recurse) {
        Assert-PlainPath $entry.FullName
        if ($entry.PSIsContainer) { continue }
        $relative = $entry.FullName.Substring($Folder.Length + 1).Replace('\','/')
        if ($relative -eq $descriptorName) { continue }
        if ($PermitCaches -and $cacheNames -contains $relative) { continue }
        if (-not $known.ContainsKey($relative)) { throw 'client_unexpected_file' }
    }
}
function Resolve-DotaGame {
    if ($GamePath) { return (Resolve-Path -LiteralPath $GamePath).Path }
    $steam = (Get-ItemProperty -LiteralPath 'HKCU:/Software/Valve/Steam' -ErrorAction SilentlyContinue).SteamPath
    $libraries = @(@($steam, (Join-Path ${env:ProgramFiles(x86)} 'Steam')) | Where-Object { $_ })
    foreach ($library in @($libraries)) {
        $config = Join-Path $library 'steamapps/libraryfolders.vdf'
        if (Test-Path -LiteralPath $config) {
            foreach ($match in [regex]::Matches((Get-Content -LiteralPath $config -Raw),'"path"\s+"([^"]+)"')) { $libraries += $match.Groups[1].Value.Replace('\\','\') }
        }
    }
    foreach ($library in $libraries | Select-Object -Unique) {
        $candidate = Join-Path $library 'steamapps/common/dota 2 beta/game'
        if (Test-Path -LiteralPath (Join-Path $candidate 'bin/win64/dota2.exe')) { return (Resolve-Path -LiteralPath $candidate).Path }
    }
    $entered = Read-Host '请输入 Dota 2 的 game 文件夹完整路径'
    return (Resolve-Path -LiteralPath $entered).Path
}
try {
    if (-not $Server) {
        $addressFile = Join-Path $PSScriptRoot 'server_address.txt'
        if (Test-Path -LiteralPath $addressFile) { $Server = (Get-Content -LiteralPath $addressFile -Raw).Trim() }
        else { $Server = Read-Host '请输入主机的虚拟 IPv4 和端口，例如 26.1.2.3:27015' }
    }
    if ($Server -notmatch '^(\d{1,3}(?:\.\d{1,3}){3}):(\d{1,5})$') { throw 'join_address_invalid' }
    $ipText = $Matches[1]; $port = [int]$Matches[2]
    $address = [Net.IPAddress]::None
    if (-not [Net.IPAddress]::TryParse($ipText,[ref]$address) -or $address.ToString() -ne $ipText -or $address.AddressFamily -ne [Net.Sockets.AddressFamily]::InterNetwork -or $port -ne 27015) { throw 'join_address_invalid' }
    if (-not $CheckOnly -and (Get-Process -Name dota2 -ErrorAction SilentlyContinue)) { throw 'close_dota_first' }
    $manifestPath = Join-Path $PSScriptRoot 'client_manifest.json'
    Assert-PlainPath $manifestPath
    if ($expectedManifestHash -notmatch '^[a-f0-9]{64}$' -or (Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash.ToLowerInvariant() -ne $expectedManifestHash) { throw 'use_generated_client_package' }
    $manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($manifest.kind -ne 'WS4-LOCAL-1' -or $manifest.base_content_sha256 -ne 'a8ad3b474799bbc07821b568120ec442a2c25a74826fe2e0e92696a09ca36335') { throw 'client_identity_invalid' }
    $rows = @($manifest.runtime.files)
    foreach ($row in $rows) { if ($row.path -notmatch '^[A-Za-z0-9_./ -]+$' -or $row.path -match '(^|/)\.\.?(/|$)' -or $row.path.StartsWith('/') -or $row.sha256 -notmatch '^[a-f0-9]{64}$') { throw 'client_manifest_path_invalid' } }
    $source = Join-Path $PSScriptRoot $addonName
    Assert-Layout $source $rows $false
    Write-Host '正在校验加入方测试资源……'
    foreach ($row in $rows) { Assert-File (Join-Path $source $row.path) $row }
    $game = Resolve-DotaGame
    Assert-PlainPath $game
    $exe = Join-Path $game 'bin/win64/dota2.exe'
    if (-not (Test-Path -LiteralPath $exe)) { throw 'dota_game_path_invalid' }
    $target = Join-Path $game ('dota_addons/' + $addonName)
    if ($CheckOnly) {
        @{ok=$true;status='CLIENT_PACKAGE_CHECKED_NO_GAME_STARTED';server=$Server;files=$rows.Count;game_path=$game;target_exists=(Test-Path -LiteralPath $target)} | ConvertTo-Json -Compress
        exit 0
    }
    if (Get-Process -Name dota2 -ErrorAction SilentlyContinue) { throw 'close_dota_first' }
    $content = Join-Path (Split-Path $game) ('content/dota_addons/' + $addonName)
    $contentMarker = Join-Path $content 'ws4_local_owner.txt'
    $existingParent = Split-Path $content
    while (-not (Test-Path -LiteralPath $existingParent)) { $existingParent = Split-Path $existingParent }
    Assert-PlainPath $existingParent
    if (Test-Path -LiteralPath $content) {
        Assert-PlainPath $content
        if (-not (Test-Path -LiteralPath $contentMarker)) { throw 'existing_content_directory_unowned' }
        Assert-PlainPath $contentMarker
        if ((Get-Content -LiteralPath $contentMarker -Raw) -ne "WS4-LOCAL-1`n") { throw 'existing_content_directory_unowned' }
    } else {
        New-Item -ItemType Directory -Path $content -Force | Out-Null
        [IO.File]::WriteAllText($contentMarker,"WS4-LOCAL-1`n",(New-Object Text.UTF8Encoding($false)))
    }
    $addons = Join-Path $game 'dota_addons'
    if (-not (Test-Path -LiteralPath $addons)) { New-Item -ItemType Directory -Path $addons | Out-Null }
    Assert-PlainPath $addons
    if (Test-Path -LiteralPath $target) {
        $existing = Join-Path $target $descriptorName
        Assert-PlainPath $existing
        if ((Get-FileHash -LiteralPath $existing -Algorithm SHA256).Hash.ToLowerInvariant() -ne $expectedManifestHash) { throw 'existing_addon_version_differs' }
        Assert-Layout $target $rows $true
    } else {
        New-Item -ItemType Directory -Path $target | Out-Null
        Copy-Item -LiteralPath $manifestPath -Destination (Join-Path $target $descriptorName)
    }
    foreach ($row in $rows) {
        $destination = Join-Path $target $row.path
        if (Test-Path -LiteralPath $destination) { Assert-File $destination $row }
        else {
            $parent = Split-Path -Parent $destination
            if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
            Assert-PlainPath $parent
            Copy-Item -LiteralPath (Join-Path $source $row.path) -Destination $destination
            Assert-File $destination $row
        }
    }
    if (Get-Process -Name dota2 -ErrorAction SilentlyContinue) { throw 'close_dota_first' }
    Write-Host ('正在连接测试主机 ' + $Server + '。请保持 Steam 和 Radmin VPN 在线。')
    Start-Process -FilePath $exe -ArgumentList @('-steam','-tools','-noassetbrowser','-addon',$addonName,'-novid','+connect',$Server) -WorkingDirectory (Join-Path $game 'dota') | Out-Null
} catch {
    $message = $_.Exception.Message
    if ($message -eq 'close_dota_first') { Write-Host '请先退出这台电脑上的 Dota 2，保留 Steam，再运行加入入口。' }
    elseif ($message -eq 'existing_addon_version_differs') { Write-Host '这台电脑已存在不同版本测试副本，已保留原文件；请联系作者处理版本。' }
    else { Write-Host '加入准备未完成，请把下方固定错误码发给作者。' }
    if ($message -notmatch '^[a-z_]{1,100}$') { $message = 'guest_join_failed' }
    @{ok=$false;error=$message} | ConvertTo-Json -Compress
    exit 1
}
