$ErrorActionPreference='Stop'
$guardWorkspace=(Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
$guardBase=Join-Path $guardWorkspace 'output\payment_release'
$guardBaseline=Join-Path $guardBase '20261016-shop-functional-v2'
$guardCurrent=Join-Path $guardBase 'current'
if (Test-Path -LiteralPath $guardCurrent) { throw 'Do not replace an existing local current pointer.' }
if (-not $guardCurrent.StartsWith($guardWorkspace+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)) { throw 'Guard pointer outside workspace.' }
if (-not $guardBaseline.StartsWith($guardWorkspace+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)) { throw 'Guard baseline outside workspace.' }
New-Item -ItemType Junction -Path $guardCurrent -Target $guardBaseline | Out-Null
$guardExit=1
try {
    & py -3 -B -X utf8 (Join-Path $PSScriptRoot 'guard_contract.py')
    $guardExit=$LASTEXITCODE
} finally {
    $guardLink=Get-Item -LiteralPath $guardCurrent -Force
    if ($guardLink.LinkType -ne 'Junction' -or [string]$guardLink.Target -ne $guardBaseline) { throw 'Unexpected local guard junction; leave it untouched.' }
    # Remove only this exact junction. No recursion and no target-file deletion.
    [IO.Directory]::Delete($guardCurrent,$false)
}
exit $guardExit
