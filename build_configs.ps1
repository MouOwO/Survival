param([switch]$CheckOnly)
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8
chcp 65001 | Out-Null

$AddonRoot = $PSScriptRoot
$Builder = Join-Path $AddonRoot 'tools\build_configs.py'
$Generated = Join-Path $AddonRoot 'scripts\vscripts\config\generated'

Push-Location $AddonRoot
try {
    if (-not $CheckOnly) {
        python $Builder
        if ($LASTEXITCODE -ne 0) { throw "CSV to Lua failed: $LASTEXITCODE" }
    }

    python -c "from pathlib import Path; import sys; r=Path(r'$Generated'); fs=list(r.glob('*.lua')); bad=[str(p) for p in fs if chr(0xfffd) in p.read_text(encoding='utf-8-sig')]; print(f'CONFIG_VERIFY files={len(fs)} bad_utf8={len(bad)}'); sys.exit(1 if len(fs)<47 or bad else 0)"
    if ($LASTEXITCODE -ne 0) { throw 'Generated Lua verification failed.' }

    Write-Host 'CONFIG_BUILD_PASS' -ForegroundColor Green
    Write-Host "Output: $Generated"
    Write-Host 'Close the current test session and Run the map again. Required Lua modules are cached inside a running VM.' -ForegroundColor Yellow
}
finally { Pop-Location }
