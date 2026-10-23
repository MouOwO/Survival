param([string]$Server, [string]$GamePath, [switch]$CheckOnly, [switch]$AuditAll)
$ErrorActionPreference = 'Stop'
$expectedManifestHash = '__MANIFEST_SHA256__'
$addonName = 'survival_ws4_local'
$descriptorName = '_ws4_local_install.json'
$stage = 'read_address'
$currentFile = ''
$revision = 'WS4-JOIN-06'
$pathLength = 0
$actualBytes = $null
$actualSha = $null
$cacheNames = @('tools_asset_info.bin','tools_thumbnail_cache.sqlite3','tools_thumbnail_cache.sqlite3-journal','tools_thumbnail_cache.sqlite3-wal','tools_thumbnail_cache.sqlite3-shm')
function Assert-PlainPath([string]$Path) {
    $script:pathLength = $Path.Length
    try { $entry = Get-Item -LiteralPath $Path -Force -ErrorAction Stop }
    catch {
        $kind = $_.Exception.GetBaseException().GetType().FullName
        if ($kind -match 'PathTooLongException$' -or ($Path.Length -ge 260 -and $_.CategoryInfo.Category -eq 'ObjectNotFound')) { throw 'guest_path_too_long' }
        if ($_.CategoryInfo.Category -eq 'ObjectNotFound') { throw 'guest_file_missing' }
        throw
    }
    while ($entry) {
        if (($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'linked_path_not_allowed' }
        if ($entry -is [IO.FileInfo]) { $entry = $entry.Directory }
        else { $entry = $entry.Parent }
    }
}
function Assert-File([string]$Path, $Row) {
    $script:currentFile = $Row.path
    $script:actualBytes = $null; $script:actualSha = $null
    Assert-PlainPath $Path
    $script:actualBytes = (Get-Item -LiteralPath $Path -Force).Length
    if ($actualBytes -ne $Row.bytes) { throw 'client_runtime_bytes_changed' }
    $script:actualSha = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actualSha -ne $Row.sha256) { throw 'client_runtime_bytes_changed' }
}
function Assert-Layout([string]$Folder, $Rows, [bool]$PermitCaches) {
    Assert-PlainPath $Folder
    $known = @{}
    foreach ($row in $Rows) { $known[$row.path] = $true }
    foreach ($entry in Get-ChildItem -LiteralPath $Folder -Force -Recurse) {
        $relative = $entry.FullName.Substring($Folder.Length + 1).Replace('\','/')
        $script:currentFile = $relative
        Assert-PlainPath $entry.FullName
        if ($entry.PSIsContainer) { continue }
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
    Write-Host ('加入器版本：' + $revision)
    if ($AuditAll -and -not $CheckOnly) { throw 'audit_requires_check_only' }
    # Auditing assets never needs a server address, game installation or VPN.
    if ($AuditAll -and -not $Server) { $Server = '127.0.0.1:27015' }
    if (-not $Server) {
        $addressFile = Join-Path $PSScriptRoot 'server_address.txt'
        if (Test-Path -LiteralPath $addressFile) { $Server = (Get-Content -LiteralPath $addressFile -Raw).Trim() }
        else { $Server = Read-Host '请输入主机的虚拟 IPv4 和端口，例如 26.1.2.3:27015' }
    }
    if ($Server -notmatch '^(\d{1,3}(?:\.\d{1,3}){3}):(\d{1,5})$') { throw 'join_address_invalid' }
    $ipText = $Matches[1]; $port = [int]$Matches[2]
    $address = [Net.IPAddress]::None
    if (-not [Net.IPAddress]::TryParse($ipText,[ref]$address) -or $address.ToString() -ne $ipText -or $address.AddressFamily -ne [Net.Sockets.AddressFamily]::InterNetwork -or $port -ne 27015) { throw 'join_address_invalid' }
    $stage = 'check_running_game'
    if (-not $CheckOnly -and (Get-Process -Name dota2 -ErrorAction SilentlyContinue)) { throw 'close_dota_first' }
    $stage = 'check_manifest'; $currentFile = 'client_manifest.json'
    $manifestPath = Join-Path $PSScriptRoot 'client_manifest.json'
    Assert-PlainPath $manifestPath
    if ($expectedManifestHash -notmatch '^[a-f0-9]{64}$' -or (Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash.ToLowerInvariant() -ne $expectedManifestHash) { throw 'use_generated_client_package' }
    $stage = 'read_manifest'
    $manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($manifest.kind -ne 'WS4-LOCAL-1' -or $manifest.base_content_sha256 -ne 'a8ad3b474799bbc07821b568120ec442a2c25a74826fe2e0e92696a09ca36335') { throw 'client_identity_invalid' }
    $rows = @($manifest.runtime.files)
    foreach ($row in $rows) { if ($row.path -notmatch '^[A-Za-z0-9_./ -]+$' -or $row.path -match '(^|/)\.\.?(/|$)' -or $row.path.StartsWith('/') -or $row.sha256 -notmatch '^[a-f0-9]{64}$') { throw 'client_manifest_path_invalid' } }
    $source = Join-Path $PSScriptRoot $addonName
    $stage = 'check_layout'; $currentFile = $addonName
    if (-not (Test-Path -LiteralPath $source -PathType Container)) { throw 'guest_runtime_folder_missing' }
    if ($AuditAll) {
        Assert-PlainPath $source
        $stage = 'check_resources'
        $issues = New-Object 'System.Collections.Generic.List[object]'
        Write-Host '正在逐一校验全部资源；此操作不会启动游戏或连接主机。'
        foreach ($row in $rows) {
            try { Assert-File (Join-Path $source $row.path) $row }
            catch {
                $code = $_.Exception.Message
                if ($code -notmatch '^[a-z_]{1,100}$') { $code = 'guest_asset_read_failed' }
                $issues.Add(@{path=$row.path;error=$code;expected_bytes=$row.bytes;actual_bytes=$actualBytes;
                    expected_sha256=$row.sha256;actual_sha256=$actualSha})
            }
        }
        $audit = @{ok=($issues.Count -eq 0);revision=$revision;status='CLIENT_RESOURCE_AUDIT_COMPLETE';
            files=$rows.Count;issue_count=$issues.Count;issues=@($issues.ToArray());game_started=$false}
        $auditPath = Join-Path $PSScriptRoot 'client_resource_audit.json'
        if (Test-Path -LiteralPath $auditPath) { Assert-PlainPath $auditPath }
        [IO.File]::WriteAllText($auditPath,($audit | ConvertTo-Json -Depth 6),(New-Object Text.UTF8Encoding($false)))
        Write-Host ('资源校验完成：' + $rows.Count + ' 份文件，异常 ' + $issues.Count + ' 份。完整报告：client_resource_audit.json')
        $audit.issues = @($issues.ToArray() | Select-Object -First 25)
        $audit | ConvertTo-Json -Depth 6 -Compress
        if ($issues.Count -gt 0) { exit 1 }
        exit 0
    }
    Assert-Layout $source $rows $false
    $stage = 'check_resources'
    Write-Host '正在校验加入方测试资源……'
    foreach ($row in $rows) { Assert-File (Join-Path $source $row.path) $row }
    $stage = 'locate_game'; $currentFile = ''
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
    $stage = 'prepare_content'
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
    $stage = 'prepare_target'
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
    $stage = 'install_runtime'
    foreach ($row in $rows) {
        $currentFile = $row.path
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
    $stage = 'start_game'; $currentFile = ''
    Write-Host ('正在连接测试主机 ' + $Server + '。请保持 Steam 和 Radmin VPN 在线。')
    Start-Process -FilePath $exe -ArgumentList @('-steam','-tools','-noassetbrowser','-addon',$addonName,'-novid','+connect',$Server) -WorkingDirectory (Join-Path $game 'dota') | Out-Null
} catch {
    $message = $_.Exception.Message
    $category = $_.CategoryInfo.Category.ToString()
    $exceptionType = $_.Exception.GetBaseException().GetType().FullName
    if ($message -notmatch '^[a-z_]{1,100}$') {
        if ($exceptionType -match 'CommandNotFoundException$') { $message = 'guest_powershell_command_missing' }
        elseif ($exceptionType -match 'PathTooLongException$') { $message = 'guest_path_too_long' }
        elseif ($category -eq 'PermissionDenied' -or $exceptionType -match 'UnauthorizedAccessException$') { $message = 'guest_access_denied' }
        elseif ($category -eq 'ObjectNotFound' -or $exceptionType -match '(File|Directory)NotFoundException$') { $message = 'guest_file_missing' }
        else { $message = 'guest_' + $stage + '_failed' }
    }
    if ($message -eq 'close_dota_first') { Write-Host '请先退出这台电脑上的 Dota 2，保留 Steam，再运行加入入口。' }
    elseif ($message -eq 'existing_addon_version_differs') { Write-Host '这台电脑已存在不同版本测试副本，已保留原文件；请联系作者处理版本。' }
    elseif ($message -eq 'guest_file_missing' -or $message -eq 'guest_runtime_folder_missing') { Write-Host '发现缺少文件，请完整解压客户端；不要只复制启动文件或小修复包。' }
    elseif ($message -eq 'guest_access_denied') { Write-Host '读取或写入测试文件被拒绝，请将完整客户端解压到自己可访问的普通文件夹。' }
    elseif ($message -eq 'guest_path_too_long') { Write-Host '文件路径过长，请将完整客户端移动到较短路径，例如 D:\WS4，再重试。' }
    else { Write-Host '加入准备未完成，请把下方诊断 JSON 发给作者。此时尚不能据此判断 VPN 连通性。' }
    $diagnostic = @{ok=$false;revision=$revision;error=$message;stage=$stage;category=$category;
        exception_type=$exceptionType;line=$_.InvocationInfo.ScriptLineNumber;powershell=$PSVersionTable.PSVersion.ToString();path_chars=$pathLength}
    if ($currentFile -match '^[A-Za-z0-9_./ -]{1,220}$') { $diagnostic.file = $currentFile }
    if ($message -eq 'client_runtime_bytes_changed') {
        $row = $rows | Where-Object path -eq $currentFile | Select-Object -First 1
        $diagnostic.expected_bytes = $row.bytes; $diagnostic.actual_bytes = $actualBytes
        $diagnostic.expected_sha256 = $row.sha256; $diagnostic.actual_sha256 = $actualSha
    }
    $encoded = $diagnostic | ConvertTo-Json -Compress
    try {
        Assert-PlainPath $PSScriptRoot
        $diagnosticPath = Join-Path $PSScriptRoot 'join_diagnostic.json'
        if (Test-Path -LiteralPath $diagnosticPath) { Assert-PlainPath $diagnosticPath }
        [IO.File]::WriteAllText($diagnosticPath,$encoded,(New-Object Text.UTF8Encoding($false)))
    } catch { }
    Write-Host ('失败阶段：' + $stage)
    $encoded
    exit 1
}
