param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('A', 'B', 'C')]
    [string]$Preset
)
$ErrorActionPreference = 'Stop'
$towerRepo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$towerLogDirectory = Join-Path $towerRepo 'output/tower_skin_trial'
New-Item -ItemType Directory -Force -Path $towerLogDirectory | Out-Null
$towerLog = Join-Path $towerLogDirectory ('switch_' + $Preset + '.log')
Set-Content -LiteralPath $towerLog -Encoding UTF8 -Value ('Preset ' + $Preset + ' | ' + (Get-Date -Format o))

function Write-TowerLog([string]$Message) {
    Write-Host $Message
    Add-Content -LiteralPath $towerLog -Encoding UTF8 -Value $Message
}

try {
    $towerCandidates = @()
    # Prefer actual per-user/program installations over Windows Store aliases.
    $towerInstallRoots = @(
        (Join-Path $env:LOCALAPPDATA 'Programs/Python'),
        $env:ProgramFiles
    )
    foreach ($towerInstallRoot in $towerInstallRoots) {
        if (-not $towerInstallRoot -or -not (Test-Path -LiteralPath $towerInstallRoot)) { continue }
        foreach ($towerDirectory in @(Get-ChildItem -LiteralPath $towerInstallRoot -Directory -Filter 'Python*' | Sort-Object Name -Descending)) {
            $towerExecutable = Join-Path $towerDirectory.FullName 'python.exe'
            if (Test-Path -LiteralPath $towerExecutable -PathType Leaf) { $towerCandidates += $towerExecutable }
        }
    }
    foreach ($towerCommand in @(Get-Command python,python3 -CommandType Application -All -ErrorAction SilentlyContinue)) {
        if ($towerCommand.Source -notmatch '\\Microsoft\\WindowsApps\\') {
            $towerCandidates += $towerCommand.Source
        }
    }
    $towerPython = $null
    foreach ($towerCandidate in @($towerCandidates | Select-Object -Unique)) {
        $towerVersion = & $towerCandidate -I -c 'import sys; print(sys.version.split()[0]); sys.exit(0 if sys.version_info >= (3, 10) else 1)' 2>$null
        if ($LASTEXITCODE -eq 0) {
            $towerPython = $towerCandidate
            Write-TowerLog ('Python ' + $towerVersion + ': ' + $towerPython)
            break
        }
    }
    if (-not $towerPython) { throw 'No working Python 3.10+ installation found. Windows Store aliases are ignored.' }

    Push-Location -LiteralPath $towerRepo
    try {
        # Capture stderr too; the builder reports whether its transaction failed.
        # Native nonzero exits are inspected explicitly, including in PowerShell 5.1.
        $towerOldPreference = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        try {
            & $towerPython -X utf8 (Join-Path $PSScriptRoot 'tower_skin_presets.py') --preset $Preset 2>&1 |
                ForEach-Object { Write-TowerLog ([string]$_) }
            $towerExitCode = $LASTEXITCODE
        } finally { $ErrorActionPreference = $towerOldPreference }
    } finally { Pop-Location }
    if ($towerExitCode -ne 0) {
        Write-TowerLog ('Switch failed (exit ' + $towerExitCode + '). Read the specific error above. Log: ' + $towerLog)
        exit 1
    }
    Write-TowerLog ('Preset ' + $Preset + ' is ready. Reload the survival map to view it.')
    Write-TowerLog ('Log: ' + $towerLog)
    exit 0
} catch {
    Write-TowerLog ('Switch failed: ' + $_.Exception.Message)
    Write-TowerLog ('Log: ' + $towerLog)
    exit 1
}
