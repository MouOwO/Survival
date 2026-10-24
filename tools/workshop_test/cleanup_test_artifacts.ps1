[CmdletBinding()]
param(
    [switch]$Apply,
    [switch]$ScopeIncludeRetiredGuest
)

# This allowlist contains generated copies and old test output only. Never use
# wildcard deletion or turn output/tmp themselves into cleanup targets.
function Get-CleanupAllowlist {
    param([switch]$IncludeRetiredGuest)
    $paths = @(
        'output/ws4_remote_client_20261023.zip',
        'output/ws4_remote_client_20261023_v2.zip',
        'output/ws4_remote_client_20261023_v3.zip',
        'output/ws4_remote_client_20261023_v4.zip',
        'output/ws4_remote_client_20261023_v5.zip',
        'output/ws4_remote_client_20261023_v6.zip',
        'output/ws4_bulk_patch_validation_20261023',
        'output/ws4_long_install_validation_20261023',
        'output/ws4_bulk_resource_repair_20261023_v6.zip',
        'output/mode_spawn_cleanup_20261021',
        'output/map_build_c6',
        'output/wall_native_redesign_20261015/preserved_temp',
        'output/spawn_cleanup',
        'tmp/exit_dark_squares_20261008',
        'tmp/portal_hammer_audit_20261022',
        'tmp/rich_mode_20261017'
    )
    if ($IncludeRetiredGuest) { $paths += 'output/ws4_remote_client_20261023' }
    return $paths
}

function Get-CleanupProtectedDependencies {
    # These paths hold current auth/relay receipts, interpreters, test tools,
    # database fixtures and publication baselines; they are not disposable.
    return @(
        'output/test_entry_cleanup_20261024',
        'output/test_entry_runtime',
        'output/ws4_web_auth_20261024',
        'output/workshop_web_auth_20261024',
        'output/workshop_web_auth_browser',
        'output/ecs_backend_work',
        'output/video_shop_20261015/deps',
        'output/video_shop_20261015/postgres_test/portable',
        'output/video_shop_20261015/release',
        'output/video_shop_20261015/deployed_baseline',
        'output/valley_decor_v2/source2viewer',
        'output/mode_spawn_progression_20261020/live_caps/baseline'
    )
}

function ConvertTo-CleanupFullPath {
    param([Parameter(Mandatory=$true)][string]$Path)
    return [IO.Path]::GetFullPath($Path).TrimEnd([char[]]@('\', '/'))
}

function Test-CleanupRelativeOverlap {
    param([string]$First, [string]$Second)
    $a = $First.Replace('\', '/').TrimEnd('/').ToLowerInvariant()
    $b = $Second.Replace('\', '/').TrimEnd('/').ToLowerInvariant()
    return ($a -eq $b -or $a.StartsWith($b + '/') -or $b.StartsWith($a + '/'))
}

function Assert-CleanupNoReparseChain {
    param([Parameter(Mandatory=$true)][string]$Path)
    $full = [IO.Path]::GetFullPath($Path)
    $drive = [IO.Path]::GetPathRoot($full)
    $cursor = $drive
    $parts = $full.Substring($drive.Length).Split([char[]]@('\', '/'), [StringSplitOptions]::RemoveEmptyEntries)
    foreach ($part in @('') + $parts) {
        if ($part) { $cursor = Join-Path $cursor $part }
        $item = Get-Item -LiteralPath $cursor -Force -ErrorAction SilentlyContinue
        if ($null -eq $item) { break }
        if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw 'cleanup_reparse_point_rejected'
        }
    }
}

function Get-CleanupTrackedPaths {
    param([Parameter(Mandatory=$true)][string]$RepositoryRoot)
    $info = New-Object Diagnostics.ProcessStartInfo
    $info.FileName = (Get-Command git -CommandType Application -ErrorAction Stop).Source
    $info.Arguments = '-c core.quotepath=false ls-files -z -- output tmp'
    $info.WorkingDirectory = $RepositoryRoot
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $info.StandardOutputEncoding = New-Object Text.UTF8Encoding($false)
    $process = New-Object Diagnostics.Process
    $process.StartInfo = $info
    try {
        if (-not $process.Start()) { throw 'cleanup_git_start_failed' }
        $stdout = $process.StandardOutput.ReadToEnd()
        $stderr = $process.StandardError.ReadToEnd()
        $process.WaitForExit()
        if ($process.ExitCode -ne 0) { throw 'cleanup_git_listing_failed' }
        return @($stdout.Split([char]0) | Where-Object { $_ })
    } finally { $process.Dispose() }
}

function Get-CleanupContext {
    param([Parameter(Mandatory=$true)][string]$RepositoryRoot)
    $original = Join-Path $RepositoryRoot 'output/ws4_web_auth_20261024/original_game_state.json'
    Assert-CleanupNoReparseChain $original
    if (-not (Test-Path -LiteralPath $original -PathType Leaf)) {
        throw 'cleanup_original_change_proof_missing'
    }
    $data = [IO.File]::ReadAllText($original, [Text.Encoding]::UTF8) | ConvertFrom-Json
    if (@($data.files).Count -ne 102) { throw 'cleanup_original_change_proof_invalid' }
    $originalPaths = @($data.files | ForEach-Object {
        $name = [string]$_.path
        if (-not $name -or $name.Contains('\') -or $name.Contains(':') -or
            $name.StartsWith('/') -or $name.Split('/') -contains '..' -or
            $name.Split('/') -contains '.' -or $name.Split('/') -contains '') {
            throw 'cleanup_original_change_path_invalid'
        }
        $name
    })
    # Failure to inspect processes aborts the operation. Their command lines
    # are used in memory only and must never be included in the audit JSON.
    try {
        $processes = @(Get-CimInstance -ClassName Win32_Process -ErrorAction Stop |
            Select-Object ProcessId, ExecutablePath, CommandLine)
    } catch { throw 'cleanup_active_process_inspection_failed' }
    if ($processes.Count -eq 0) { throw 'cleanup_active_process_inspection_failed' }
    return [pscustomobject]@{
        TrackedPaths = @(Get-CleanupTrackedPaths $RepositoryRoot)
        OriginalPaths = $originalPaths
        Processes = $processes
    }
}

function Assert-CleanupTarget {
    param(
        [Parameter(Mandatory=$true)][string]$RepositoryRoot,
        [Parameter(Mandatory=$true)][string]$RelativePath,
        [Parameter(Mandatory=$true)]$Context,
        [switch]$IncludeRetiredGuest
    )
    if ((Get-CleanupAllowlist -IncludeRetiredGuest:$IncludeRetiredGuest) -cnotcontains $RelativePath) {
        throw 'cleanup_target_not_allowlisted'
    }
    if ($RelativePath -notmatch '^(output|tmp)/[^/].+') { throw 'cleanup_target_scope_invalid' }
    $root = ConvertTo-CleanupFullPath $RepositoryRoot
    $target = ConvertTo-CleanupFullPath (Join-Path $root $RelativePath)
    if (-not $target.StartsWith($root + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'cleanup_target_outside_repository'
    }
    Assert-CleanupNoReparseChain $target
    if (Test-Path -LiteralPath $target) {
        # Resolve the actual target immediately before every possible removal.
        $resolved = ConvertTo-CleanupFullPath (Resolve-Path -LiteralPath $target -ErrorAction Stop).ProviderPath
        if (-not $resolved.Equals($target, [StringComparison]::OrdinalIgnoreCase)) {
            throw 'cleanup_resolved_target_changed'
        }
    }
    foreach ($path in @($Context.TrackedPaths)) {
        if (Test-CleanupRelativeOverlap $RelativePath ([string]$path)) { throw 'cleanup_tracked_file_protected' }
    }
    foreach ($path in @($Context.OriginalPaths)) {
        if (Test-CleanupRelativeOverlap $RelativePath ([string]$path)) { throw 'cleanup_original_change_protected' }
    }
    foreach ($path in @(Get-CleanupProtectedDependencies)) {
        if (Test-CleanupRelativeOverlap $RelativePath $path) { throw 'cleanup_dependency_protected' }
    }
    if ($RelativePath -eq 'output/ws4_remote_client_20261023' -and
        (Test-Path -LiteralPath (Join-Path $root 'tools/workshop_test/launch_guest.ps1'))) {
        throw 'cleanup_guest_entry_not_retired'
    }
    $targetSearch = $target.Replace('\', '/').ToLowerInvariant()
    $relativeSearch = $RelativePath.ToLowerInvariant()
    foreach ($process in @($Context.Processes)) {
        $exe = ([string]$process.ExecutablePath).Replace('\', '/').ToLowerInvariant()
        $command = ([string]$process.CommandLine).Replace('\', '/').ToLowerInvariant()
        if (($exe -and ($exe -eq $targetSearch -or $exe.StartsWith($targetSearch + '/'))) -or
            ($command -and ($command.Contains($targetSearch) -or $command.Contains($relativeSearch)))) {
            throw 'cleanup_active_process_path_protected'
        }
    }
    return $target
}

function Get-CleanupTree {
    param([Parameter(Mandatory=$true)][string]$Path)
    Assert-CleanupNoReparseChain $Path
    if (-not (Test-Path -LiteralPath $Path)) {
        return [pscustomobject]@{ Bytes=[long]0; Files=[long]0; Fingerprint=$null; Exists=$false }
    }
    $pending = New-Object 'Collections.Generic.Stack[string]'
    $rows = New-Object 'Collections.Generic.List[string]'
    $pending.Push($Path)
    [long]$bytes = 0
    [long]$files = 0
    while ($pending.Count -gt 0) {
        $current = $pending.Pop()
        $item = Get-Item -LiteralPath $current -Force -ErrorAction Stop
        if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw 'cleanup_reparse_point_rejected'
        }
        if ($item.PSIsContainer) {
            $rows.Add('D|' + $item.FullName)
            foreach ($child in @(Get-ChildItem -LiteralPath $current -Force -ErrorAction Stop)) {
                if (($child.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                    throw 'cleanup_reparse_point_rejected'
                }
                $pending.Push($child.FullName)
            }
        } else {
            $bytes += [long]$item.Length
            $files++
            $rows.Add('F|' + $item.FullName + '|' + $item.Length + '|' + $item.LastWriteTimeUtc.Ticks)
        }
    }
    $rows.Sort([StringComparer]::Ordinal)
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $fingerprint = [BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes(
            [string]::Join("`n", $rows)))).Replace('-', '').ToLowerInvariant()
    } finally { $sha.Dispose() }
    return [pscustomobject]@{ Bytes=$bytes; Files=$files; Fingerprint=$fingerprint; Exists=$true }
}

function Remove-CleanupTarget {
    param(
        [Parameter(Mandatory=$true)][string]$RepositoryRoot,
        [Parameter(Mandatory=$true)][string]$RelativePath,
        [Parameter(Mandatory=$true)]$Context,
        [Parameter(Mandatory=$true)][string]$ExpectedFingerprint,
        [switch]$IncludeRetiredGuest
    )
    $target = Assert-CleanupTarget -RepositoryRoot $RepositoryRoot -RelativePath $RelativePath `
        -Context $Context -IncludeRetiredGuest:$IncludeRetiredGuest
    $fresh = Get-CleanupTree $target
    if (-not $fresh.Exists -or $fresh.Fingerprint -cne $ExpectedFingerprint) {
        throw 'cleanup_tree_changed_since_audit'
    }
    # Keep Windows deletion within PowerShell, using the previously resolved
    # absolute literal target. No path is ever sent to cmd.exe or another shell.
    Assert-CleanupNoReparseChain $target
    Remove-Item -LiteralPath $target -Recurse -Force -ErrorAction Stop
    if (Test-Path -LiteralPath $target) { throw 'cleanup_delete_not_complete' }
    return $fresh
}

function Write-CleanupReport {
    param([string]$RepositoryRoot, [string]$FileName, $Report)
    $folder = Join-Path $RepositoryRoot 'output/test_entry_cleanup_20261024'
    Assert-CleanupNoReparseChain $folder
    if (-not (Test-Path -LiteralPath $folder)) { New-Item -ItemType Directory -Path $folder -ErrorAction Stop | Out-Null }
    Assert-CleanupNoReparseChain $folder
    $path = Join-Path $folder $FileName
    Assert-CleanupNoReparseChain $path
    [IO.File]::WriteAllText($path, ($Report | ConvertTo-Json -Depth 8), (New-Object Text.UTF8Encoding($false)))
}

function Invoke-TestArtifactCleanup {
    param([switch]$DoApply, [switch]$IncludeRetiredGuest)
    $ErrorActionPreference = 'Stop'
    $root = ConvertTo-CleanupFullPath (Join-Path $PSScriptRoot '../..')
    $reportName = 'cleanup_' + [DateTime]::UtcNow.ToString('yyyyMMdd_HHmmss_fff') + '_' + $PID + '.json'
    $report = [ordered]@{
        schema=1; kind='allowlisted_test_artifact_cleanup'; apply=[bool]$DoApply
        include_retired_guest=[bool]$IncludeRetiredGuest; repository=$root
        utc=[DateTime]::UtcNow.ToString('o'); ok=$false
        planned_bytes=[long]0; planned_files=[long]0; deleted_bytes=[long]0; deleted_files=[long]0
        targets=@(); error=$null
        protected_original_changes=102; process_commands_recorded=$false
    }
    try {
        $context = Get-CleanupContext $root
        $blocked = $false
        foreach ($relative in @(Get-CleanupAllowlist -IncludeRetiredGuest:$IncludeRetiredGuest)) {
            $row = [ordered]@{ path=$relative; status='pending'; bytes=[long]0; files=[long]0; fingerprint=$null; error=$null }
            try {
                $target = Assert-CleanupTarget -RepositoryRoot $root -RelativePath $relative `
                    -Context $context -IncludeRetiredGuest:$IncludeRetiredGuest
                $tree = Get-CleanupTree $target
                $row.bytes = $tree.Bytes
                $row.files = $tree.Files
                $row.fingerprint = $tree.Fingerprint
                $row.status = if ($tree.Exists) { 'audited' } else { 'missing' }
                $report.planned_bytes += $tree.Bytes
                $report.planned_files += $tree.Files
            } catch {
                $row.status = 'blocked'
                $row.error = $_.Exception.Message
                $blocked = $true
            }
            $report.targets += $row
        }
        Write-CleanupReport $root $reportName $report
        if ($blocked) { throw 'cleanup_preflight_blocked_no_deletions' }
        if ($DoApply) {
            foreach ($row in $report.targets) {
                if ($row.status -ne 'audited') { continue }
                # Recheck Git, original-change proof, active process paths,
                # actual absolute path, every directory and tree contents.
                $freshContext = Get-CleanupContext $root
                $deleted = Remove-CleanupTarget -RepositoryRoot $root -RelativePath $row.path `
                    -Context $freshContext -ExpectedFingerprint $row.fingerprint `
                    -IncludeRetiredGuest:$IncludeRetiredGuest
                $row.status = 'deleted'
                $report.deleted_bytes += $deleted.Bytes
                $report.deleted_files += $deleted.Files
                Write-CleanupReport $root $reportName $report
            }
        }
        $report.ok = $true
    } catch { $report.error = $_.Exception.Message }
    Write-CleanupReport $root $reportName $report
    [pscustomobject]@{
        ok=$report.ok; apply=$report.apply; planned_bytes=$report.planned_bytes
        planned_files=$report.planned_files; deleted_bytes=$report.deleted_bytes
        deleted_files=$report.deleted_files; error=$report.error
        report=('output/test_entry_cleanup_20261024/' + $reportName)
    } | ConvertTo-Json -Compress
    if ($report.ok) { return 0 }
    return 1
}

if ($MyInvocation.InvocationName -ne '.') {
    $result = @(Invoke-TestArtifactCleanup -DoApply:$Apply -IncludeRetiredGuest:$ScopeIncludeRetiredGuest)
    if ($result.Count -gt 1) { $result[0..($result.Count - 2)] | Write-Output }
    exit [int]$result[-1]
}
