$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'cleanup_test_artifacts.ps1')

function Assert-Fixture {
    param([bool]$Condition, [string]$Name)
    if (-not $Condition) { throw ('FAIL: ' + $Name) }
    Write-Output ('PASS: ' + $Name)
}

function Assert-Rejected {
    param([scriptblock]$Action, [string]$Expected, [string]$Name)
    $found = $false
    try { & $Action | Out-Null } catch {
        if ($_.Exception.Message -ne $Expected) { throw }
        $found = $true
    }
    Assert-Fixture $found $Name
}

function New-FixtureContext {
    return [pscustomobject]@{ TrackedPaths=@(); OriginalPaths=@(); Processes=@() }
}

$fixtureRoot = Join-Path ([IO.Path]::GetTempPath()) ('ws4-cleanup-fixture-' + [Guid]::NewGuid().ToString('N'))
$fixtureCanonical = ConvertTo-CleanupFullPath $fixtureRoot
$temporaryCanonical = ConvertTo-CleanupFullPath ([IO.Path]::GetTempPath())
if (-not $fixtureCanonical.StartsWith($temporaryCanonical + [IO.Path]::DirectorySeparatorChar,
    [StringComparison]::OrdinalIgnoreCase)) { throw 'fixture_outside_temporary_directory' }
Assert-CleanupNoReparseChain $fixtureRoot
New-Item -ItemType Directory -Path $fixtureRoot | Out-Null
$targetRelative = 'output/map_build_c6'
$target = Join-Path $fixtureRoot $targetRelative
$link = $null
try {
    New-Item -ItemType Directory -Path $target -Force | Out-Null
    $image = Join-Path $target 'fixture.png'
    [IO.File]::WriteAllBytes($image, [byte[]]@(1, 2, 3, 4, 5))
    $context = New-FixtureContext

    Assert-Fixture ((Get-CleanupAllowlist).Count -eq 16) 'default scope is exactly 16 audited targets'
    Assert-Fixture ((Get-CleanupAllowlist -IncludeRetiredGuest).Count -eq 17) 'retired guest is separate opt-in'
    $resolved = Assert-CleanupTarget -RepositoryRoot $fixtureRoot -RelativePath $targetRelative -Context $context
    Assert-Fixture ($resolved -eq (ConvertTo-CleanupFullPath $target)) 'allowed target resolves inside fixture root'
    $initial = Get-CleanupTree $target
    Assert-Fixture ($initial.Bytes -eq 5 -and $initial.Files -eq 1) 'audit records exact bytes and files'
    Assert-Fixture ((Get-CleanupTree $target).Fingerprint -eq $initial.Fingerprint) 'stable tree yields stable fingerprint'

    foreach ($outside in @('output', 'tmp', 'art/ui/sources', 'output/../maps', 'output/map_build_c6_extra')) {
        Assert-Rejected { Assert-CleanupTarget -RepositoryRoot $fixtureRoot -RelativePath $outside -Context $context } `
            'cleanup_target_not_allowlisted' ('reject non-allowlisted path: ' + $outside)
    }
    Assert-Fixture (-not (Test-CleanupRelativeOverlap 'output/map_build_c6' 'output/map_build_c6_extra/file')) `
        'sibling names are not treated as descendants'
    Assert-Fixture (Test-CleanupRelativeOverlap 'output/map_build_c6' 'OUTPUT/MAP_BUILD_C6/fixture.png') `
        'overlap guards compare Windows paths without case sensitivity'

    $tracked = New-FixtureContext
    $tracked.TrackedPaths = @('output/map_build_c6/fixture.png')
    Assert-Rejected { Assert-CleanupTarget -RepositoryRoot $fixtureRoot -RelativePath $targetRelative -Context $tracked } `
        'cleanup_tracked_file_protected' 'tracked child prevents deletion'
    $original = New-FixtureContext
    $original.OriginalPaths = @('output/map_build_c6/fixture.png')
    Assert-Rejected { Assert-CleanupTarget -RepositoryRoot $fixtureRoot -RelativePath $targetRelative -Context $original } `
        'cleanup_original_change_protected' 'original user change prevents deletion'

    foreach ($process in @(
        [pscustomobject]@{ ProcessId=10; ExecutablePath=(Join-Path $target 'tool.exe'); CommandLine='' },
        [pscustomobject]@{ ProcessId=11; ExecutablePath='C:\Windows\tool.exe'; CommandLine=('game.exe -con_logfile "' + $image + '"') },
        [pscustomobject]@{ ProcessId=12; ExecutablePath='C:\Windows\tool.exe'; CommandLine='python.exe OUTPUT\MAP_BUILD_C6\runner.py' }
    )) {
        $active = New-FixtureContext
        $active.Processes = @($process)
        Assert-Rejected { Assert-CleanupTarget -RepositoryRoot $fixtureRoot -RelativePath $targetRelative -Context $active } `
            'cleanup_active_process_path_protected' ('active process reference protected: ' + $process.ProcessId)
    }
    foreach ($dependency in @(Get-CleanupProtectedDependencies)) {
        foreach ($candidate in @(Get-CleanupAllowlist -IncludeRetiredGuest)) {
            if (Test-CleanupRelativeOverlap $candidate $dependency) { throw 'allowlist_overlaps_protected_dependency' }
        }
    }
    Assert-Fixture $true 'all cleanup targets avoid retained runtime and test dependencies'

    $guest = 'output/ws4_remote_client_20261023'
    Assert-Rejected { Assert-CleanupTarget -RepositoryRoot $fixtureRoot -RelativePath $guest -Context $context } `
        'cleanup_target_not_allowlisted' 'guest cannot enter default scope'
    $entryFolder = Join-Path $fixtureRoot 'tools/workshop_test'
    New-Item -ItemType Directory -Path $entryFolder -Force | Out-Null
    $entry = Join-Path $entryFolder 'launch_guest.ps1'
    [IO.File]::WriteAllText($entry, '# old guest entry')
    Assert-Rejected { Assert-CleanupTarget -RepositoryRoot $fixtureRoot -RelativePath $guest -Context $context -IncludeRetiredGuest } `
        'cleanup_guest_entry_not_retired' 'guest cannot be deleted while old entry exists'
    Remove-Item -LiteralPath $entry -Force
    Assert-CleanupTarget -RepositoryRoot $fixtureRoot -RelativePath $guest -Context $context -IncludeRetiredGuest | Out-Null
    Assert-Fixture $true 'guest opt-in succeeds after old entry retires'

    $linkDestination = Join-Path $fixtureRoot 'art_source'
    New-Item -ItemType Directory -Path $linkDestination | Out-Null
    [IO.File]::WriteAllText((Join-Path $linkDestination 'keep.txt'), 'preserved source')
    $link = Join-Path $target 'source_link'
    New-Item -ItemType Junction -Path $link -Target $linkDestination -ErrorAction Stop | Out-Null
    Assert-Rejected { Get-CleanupTree $target } 'cleanup_reparse_point_rejected' 'nested junction prevents tree deletion'
    Assert-Rejected { Assert-CleanupNoReparseChain (Join-Path $link 'keep.txt') } `
        'cleanup_reparse_point_rejected' 'ancestor junction is rejected before resolving target'
    # Remove only the fixture junction itself; do not recursively follow it.
    # Windows PowerShell 5.1 Remove-Item has a junction null-reference bug;
    # Directory.Delete(false) removes only this link, never its destination.
    [IO.Directory]::Delete($link, $false)
    $link = $null
    Assert-Fixture (Test-Path -LiteralPath (Join-Path $linkDestination 'keep.txt')) 'junction destination remains intact'

    [IO.File]::WriteAllBytes($image, [byte[]]@(1, 2, 3, 4, 5, 6))
    Assert-Rejected { Remove-CleanupTarget -RepositoryRoot $fixtureRoot -RelativePath $targetRelative `
        -Context $context -ExpectedFingerprint $initial.Fingerprint } 'cleanup_tree_changed_since_audit' `
        'changed tree cannot be deleted using stale audit'
    Assert-Fixture (Test-Path -LiteralPath $image) 'failed validation preserves artifact'
    $current = Get-CleanupTree $target
    $deleted = Remove-CleanupTarget -RepositoryRoot $fixtureRoot -RelativePath $targetRelative `
        -Context $context -ExpectedFingerprint $current.Fingerprint
    Assert-Fixture ($deleted.Bytes -eq 6 -and -not (Test-Path -LiteralPath $target)) `
        'validated removal touches only explicitly allowlisted fixture target'
    Assert-Fixture (Test-Path -LiteralPath (Join-Path $linkDestination 'keep.txt')) 'unlisted source survives cleanup'
    Write-Output 'CLEANUP_FIXTURE_PASS'
} finally {
    if ($link -and (Test-Path -LiteralPath $link)) { [IO.Directory]::Delete($link, $false) }
    # This is the unique fixture path checked above, never project output.
    if ((ConvertTo-CleanupFullPath $fixtureRoot) -ne $fixtureCanonical -or
        -not $fixtureCanonical.StartsWith($temporaryCanonical + [IO.Path]::DirectorySeparatorChar,
            [StringComparison]::OrdinalIgnoreCase)) { throw 'fixture_cleanup_path_changed' }
    Assert-CleanupNoReparseChain $fixtureRoot
    # Directory removal can briefly race the filesystem's junction teardown.
    # Retry only this previously verified, unique temporary fixture path.
    for ($attempt = 0; $attempt -lt 5 -and (Test-Path -LiteralPath $fixtureRoot); $attempt++) {
        try {
            Assert-CleanupNoReparseChain $fixtureRoot
            Remove-Item -LiteralPath $fixtureRoot -Recurse -Force -ErrorAction Stop
        } catch {
            if ($attempt -eq 4) { throw }
            Start-Sleep -Milliseconds 100
        }
    }
}
